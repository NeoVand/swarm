// Main simulation loop orchestration

import type { GPUContext, SimulationBuffers, SimulationParams, CursorState } from './types';
import {
	createBuffers,
	destroyBuffers,
	initializeBoids,
	clearTrails,
	updateUniforms,
	calculateGridDimensions,
	createBlockSumsBuffer,
	updateWallTexture,
	createWallTexture,
	updateSpeciesParams,
	updateInteractionMatrix,
	updateMetricRules,
	updateCurveSamples,
	MAX_TRAIL_LENGTH,
	type BufferConfig
} from './buffers';
import {
	createComputePipelines,
	encodeComputePasses,
	type ComputeResources,
	type IterativeMetricsConfig
} from './compute';
import {
	createRenderPipelines,
	encodeRenderPass,
	destroyRenderResources,
	recreateWallBindGroup,
	type RenderResources
} from './render';
import {
	createOrbitCamera,
	viewProjectionMatrix,
	cameraEye,
	planeHalfExtents,
	fitDistance,
	fitDistanceForRadius,
	SHAPE_BOUNDING_RADIUS,
	orbit,
	zoom,
	pan,
	rayThrough,
	type OrbitCamera
} from './camera';
import { pickSurfaceUV, type EmbedView } from './embedding';
import {
	getWallData,
	getWallTextureDimensions,
	initWallData,
	wallsDirty,
	curvesDirty,
	metricRulesDirty,
	sampleAllCurves,
	sampleCurve,
	params as paramsStore
} from '$lib/stores/simulation';
import { get } from 'svelte/store';

export interface Simulation {
	start: () => void;
	stop: () => void;
	destroy: () => void;
	updateParams: (params: SimulationParams) => void;
	updateCursor: (cursor: CursorState) => void;
	resize: (width: number, height: number) => void;
	reallocateBuffers: () => void;
	clearTrails: () => void;
	resetBoids: () => void;
	isRunning: () => boolean;
	updateWalls: () => void;
	updateSpecies: () => void;
	/** Orbit the embedded-mode camera. Deltas are in radians. */
	orbitCamera: (deltaAzimuth: number, deltaElevation: number) => void;
	/** Zoom the embedded-mode camera. factor < 1 moves closer. */
	zoomCamera: (factor: number) => void;
	/** Pan the embedded-mode camera. Deltas are fractions of viewport height. */
	panCamera: (deltaX: number, deltaY: number) => void;
	/** Return the camera to its default framing for the current canvas. */
	resetCamera: () => void;
	/**
	 * Map a screen position to the domain point on the embedded surface beneath
	 * it, so the cursor can push boids around in 3D. Null when off the surface.
	 */
	pickDomainPosition: (ndcX: number, ndcY: number) => { x: number; y: number } | null;
}

// The shell is opaque, so the far side of the flock is hidden behind the near
// wall - only the parameter grid drawn over it is blended. Kept strong enough
// to actually read against the flock rather than hinting at it.
const GRID_OPACITY = 0.55;

// Seconds for the flat <-> embedded morph
const MORPH_DURATION = 1.1;

// Seconds to cross-fade from one topology's embedding to another. Shorter than
// the flat morph - it reads as a shape change rather than an unfolding.
const TOPOLOGY_MORPH_DURATION = 0.8;

// Where the camera settles once the morph completes - offset from straight-on
// so the shape reads as three-dimensional immediately.
const REVEAL_AZIMUTH = -0.6;
const REVEAL_ELEVATION = 0.36;

// Turntable speed in radians per second
const AUTO_ROTATE_SPEED = 0.35;

// Smoothstep-style ease so the morph starts and ends gently.
function easeInOut(t: number): number {
	const c = Math.max(0, Math.min(1, t));
	return c * c * (3 - 2 * c);
}

export function createSimulation(
	gpuContext: GPUContext,
	initialParams: SimulationParams,
	onFpsUpdate: (fps: number) => void
): Simulation {
	const { device, context, format, canvas } = gpuContext;

	let params = { ...initialParams };
	let cursor: CursorState = { x: 0, y: 0, isPressed: false, isActive: false };

	let canvasWidth = canvas.width;
	let canvasHeight = canvas.height;

	// Grid dimensions
	let gridInfo = calculateGridDimensions(canvasWidth, canvasHeight, params.perception);

	// Create buffers
	let bufferConfig: BufferConfig = {
		boidCount: params.population,
		trailLength: params.trailLength,
		gridWidth: gridInfo.gridWidth,
		gridHeight: gridInfo.gridHeight,
		canvasWidth,
		canvasHeight
	};

	let buffers: SimulationBuffers = createBuffers(device, bufferConfig);
	let blockSumsBuffer = createBlockSumsBuffer(device, canvasWidth, canvasHeight);

	// Initialize boid positions and velocities
	initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight, params.species);
	clearTrails(device, buffers, params.population, params.trailLength);

	// Initialize species buffers
	updateSpeciesParams(device, buffers.speciesParams, params.species);
	updateInteractionMatrix(device, buffers.interactionMatrix, params.species);
	// Initialize metric-based interaction rules
	updateMetricRules(
		device,
		buffers.metricRules,
		buffers.metricRuleCurves,
		params.species,
		sampleCurve
	);

	// Initialize curve samples buffer
	updateCurveSamples(device, buffers.curveSamples, sampleAllCurves(params));

	// Initialize wall data
	initWallData(canvasWidth, canvasHeight);

	// Create pipelines
	let computeResources: ComputeResources = createComputePipelines(device, buffers, blockSumsBuffer);
	let renderResources: RenderResources = createRenderPipelines(device, format, buffers);

	// Animation state. `running` gates simulation stepping; `loopActive` gates the
	// render loop, which keeps going while paused so the view stays interactive.
	let running = false;
	let loopActive = false;
	let animationFrameId: number | null = null;
	let readFromA = true;
	let frameCount = 0;
	let trailHead = 0;
	let lastTime = 0;
	let fpsFrames = 0;
	let fpsTime = 0;

	// Spectral/Flow metrics state
	let needsRankInit = true;
	let lastInfluenceEnabled = params.enableInfluence;

	// Embedded 3D view state
	const camera: OrbitCamera = createOrbitCamera(canvasWidth, canvasHeight);
	let embedBlend = params.embedded3D ? 1 : 0;
	// Drives the reveal: the camera swings from straight-on to REVEAL_* in step
	// with the morph, unless the user grabs it first.
	let revealProgress = params.embedded3D ? 1 : 0;
	let userMovedCamera = false;

	// Topology cross-fade state
	let topologyPrev = params.boundaryMode;
	let topologyCurrent = params.boundaryMode;
	let topologyBlend = 1;

	/** Camera framing for the flat rectangle - the state the morph starts from. */
	function resetCameraToFit(): void {
		camera.azimuth = 0;
		camera.elevation = 0;
		camera.distance = fitDistance(canvasWidth, canvasHeight, camera.fov);
		camera.target[0] = 0;
		camera.target[1] = 0;
		camera.target[2] = 0;
		userMovedCamera = false;
	}

	/** Snapshot of the surface state, shared with the CPU-side picking mirror. */
	function currentEmbedView(): EmbedView {
		const extents = planeHalfExtents(canvasWidth, canvasHeight);
		return {
			topology: topologyCurrent,
			prevTopology: topologyPrev,
			topologyBlend: easeInOut(topologyBlend),
			embedBlend: easeInOut(embedBlend),
			planeHalfWidth: extents.halfWidth,
			planeHalfHeight: extents.halfHeight
		};
	}

	function applyReveal(): void {
		if (userMovedCamera) return;
		const t = easeInOut(revealProgress);
		// Start framed on the flat rectangle (so the morph begins exactly where
		// the 2D view left off) and pull back to frame the whole 3D shape.
		const flatDistance = fitDistance(canvasWidth, canvasHeight, camera.fov);
		const shapeDistance = fitDistanceForRadius(
			SHAPE_BOUNDING_RADIUS,
			canvasWidth,
			canvasHeight,
			camera.fov
		);
		camera.azimuth = REVEAL_AZIMUTH * t;
		camera.elevation = REVEAL_ELEVATION * t;
		camera.distance = flatDistance + (shapeDistance - flatDistance) * t;
	}

	function frame(time: number): void {
		if (!loopActive) return;

		const deltaTime = lastTime > 0 ? (time - lastTime) / 1000 : 1 / 60;
		lastTime = time;

		// FPS calculation
		fpsFrames++;
		fpsTime += deltaTime;
		if (fpsTime >= 1.0) {
			onFpsUpdate(Math.round(fpsFrames / fpsTime));
			fpsFrames = 0;
			fpsTime = 0;
		}

		// Check for curve updates
		if (get(curvesDirty)) {
			updateCurveSamples(device, buffers.curveSamples, sampleAllCurves(params));
			curvesDirty.set(false);
		}

		// Check for metric rules updates
		if (get(metricRulesDirty)) {
			updateMetricRules(
				device,
				buffers.metricRules,
				buffers.metricRuleCurves,
				params.species,
				sampleCurve
			);
			metricRulesDirty.set(false);
		}

		// Update grid dimensions if perception changed
		const newGridInfo = calculateGridDimensions(canvasWidth, canvasHeight, params.perception);
		if (
			newGridInfo.gridWidth !== gridInfo.gridWidth ||
			newGridInfo.gridHeight !== gridInfo.gridHeight
		) {
			gridInfo = newGridInfo;
			// Grid changed, may need to recreate some buffers
		}

		// Calculate actual max trail length from species for efficient rendering
		// When 0, trails are completely disabled for max performance
		const maxSpeciesTrailLength = Math.max(...params.species.map((s) => s.trailLength), 0);

		// Update trail head only if trails are enabled - skip entirely when 0 for max performance
		// Frozen while paused so the trail ring buffer holds its shape.
		if (running && maxSpeciesTrailLength > 0) {
			trailHead = (trailHead + 1) % MAX_TRAIL_LENGTH;
		}

		// Advance the flat <-> embedded morph and the accompanying camera reveal
		const morphTarget = params.embedded3D ? 1 : 0;
		const morphStep = Math.min(deltaTime, 0.1) / MORPH_DURATION;
		if (embedBlend < morphTarget) {
			embedBlend = Math.min(morphTarget, embedBlend + morphStep);
			revealProgress = Math.min(1, revealProgress + morphStep);
		} else if (embedBlend > morphTarget) {
			embedBlend = Math.max(morphTarget, embedBlend - morphStep);
			revealProgress = Math.max(0, revealProgress - morphStep);
			// Leaving embedded mode returns the camera to straight-on so the flat
			// view lands exactly where the 2D renderer would have drawn it.
			userMovedCamera = false;
		}
		applyReveal();

		// Turntable spin. Runs off wall-clock delta so it keeps turning while the
		// simulation is paused, and counts as user camera control so the reveal
		// animation does not fight it.
		if (params.embedded3D && params.embedAutoRotate) {
			userMovedCamera = true;
			orbit(camera, -AUTO_ROTATE_SPEED * Math.min(deltaTime, 0.1), 0);
		}

		// Cross-fade the embedding when the topology changes. Only meaningful
		// while embedded - flat mode has no shape to morph, so it snaps.
		if (params.boundaryMode !== topologyCurrent) {
			if (embedBlend > 0.0001) {
				// A switch mid-transition completes the previous one first, so
				// rapid cycling reads as successive morphs rather than a blur.
				topologyPrev = topologyCurrent;
				topologyBlend = 0;
			} else {
				topologyPrev = params.boundaryMode;
				topologyBlend = 1;
			}
			topologyCurrent = params.boundaryMode;
		}
		if (topologyBlend < 1) {
			topologyBlend = Math.min(
				1,
				topologyBlend + Math.min(deltaTime, 0.1) / TOPOLOGY_MORPH_DURATION
			);
		}

		const easedBlend = easeInOut(embedBlend);
		const planeExtents = planeHalfExtents(canvasWidth, canvasHeight);
		const viewProj = viewProjectionMatrix(camera, canvasWidth, canvasHeight);
		const eye = cameraEye(camera);

		// Update uniform buffer
		// Use maxSpeciesTrailLength so shader instance calculations match render instance count
		updateUniforms(device, buffers.uniforms, {
			canvasWidth,
			canvasHeight,
			cellSize: gridInfo.cellSize,
			gridWidth: gridInfo.gridWidth,
			gridHeight: gridInfo.gridHeight,
			boidCount: params.population,
			trailLength: maxSpeciesTrailLength,
			trailHead,
			params,
			cursor,
			deltaTime: Math.min(deltaTime, 0.1), // Cap to prevent huge jumps
			time: time / 1000,
			frameCount,
			// Locally perfect hashing
			reducedWidth: gridInfo.reducedWidth,
			totalSlots: gridInfo.totalSlots,
			// Embedded 3D view
			embedBlend: easedBlend,
			embedTopology: topologyCurrent,
			topologyBlend: easeInOut(topologyBlend),
			embedTopologyPrev: topologyPrev,
			viewProj,
			cameraEye: eye,
			planeHalfWidth: planeExtents.halfWidth,
			planeHalfHeight: planeExtents.halfHeight,
			shellFade: easedBlend,
			gridOpacity: GRID_OPACITY * easedBlend
		});

		// Create command encoder
		const encoder = device.createCommandEncoder();

		// Check if spectral/flow metrics need reinitialization
		if (params.enableInfluence && !lastInfluenceEnabled) {
			needsRankInit = true;
		}
		lastInfluenceEnabled = params.enableInfluence;

		// Prepare iterative metrics config
		const iterativeConfig: IterativeMetricsConfig = {
			enableInfluence: params.enableInfluence,
			influenceIterations: params.influenceIterations,
			needsRankInit
		};

		// Clear init flag after first use
		if (needsRankInit && params.enableInfluence) {
			needsRankInit = false;
		}

		// Encode compute passes
		// Use totalSlots for locally perfect hashing
		// Skipped while paused: the render below still runs, so the camera, the
		// morph and the topology cross-fade stay live on a frozen flock.
		if (running) {
			encodeComputePasses(
				encoder,
				computeResources,
				params.population,
				gridInfo.totalSlots,
				readFromA,
				iterativeConfig
			);
		}

		// Encode render pass
		const textureView = context.getCurrentTexture().createView();
		encodeRenderPass(device, encoder, textureView, renderResources, {
			boidCount: params.population,
			trailLength: maxSpeciesTrailLength,
			readFromA,
			canvasWidth,
			canvasHeight,
			embedBlend: easedBlend,
			showShell: true,
			showGrid: params.embedShowGrid
		});

		// Submit commands
		device.queue.submit([encoder.finish()]);

		// Swap buffers for next frame. Held while paused so the render above keeps
		// reading whichever buffer the last compute pass wrote.
		if (running) {
			readFromA = !readFromA;
			frameCount++;
		}

		// Schedule next frame
		animationFrameId = requestAnimationFrame(frame);
	}

	/**
	 * The render loop runs for the lifetime of the simulation, independent of
	 * whether the simulation is stepping. Pausing must not freeze the camera -
	 * you still want to orbit, pan and zoom around a stopped flock.
	 */
	function startLoop(): void {
		if (loopActive) return;
		loopActive = true;
		lastTime = 0;
		animationFrameId = requestAnimationFrame(frame);
	}

	function start(): void {
		running = true;
		startLoop();
	}

	function stop(): void {
		running = false;
	}

	function destroy(): void {
		stop();
		loopActive = false;
		if (animationFrameId !== null) {
			cancelAnimationFrame(animationFrameId);
			animationFrameId = null;
		}
		destroyBuffers(buffers);
		blockSumsBuffer.destroy();
		destroyRenderResources();
	}

	function updateParams(newParams: SimulationParams): void {
		params = { ...newParams };
	}

	function updateCursor(newCursor: CursorState): void {
		cursor = { ...newCursor };
	}

	function resize(width: number, height: number): void {
		canvasWidth = width;
		canvasHeight = height;

		// Recalculate grid
		gridInfo = calculateGridDimensions(canvasWidth, canvasHeight, params.perception);

		// Recreate wall texture for new size
		const oldWallTexture = buffers.wallTexture;
		buffers.wallTexture = createWallTexture(device, canvasWidth, canvasHeight);
		oldWallTexture.destroy();

		// Reinitialize wall data for new dimensions
		initWallData(canvasWidth, canvasHeight);

		// Recreate bind groups that reference wall texture
		renderResources.bindGroups.wall = recreateWallBindGroup(
			device,
			renderResources.wallBindGroupLayout,
			buffers.uniforms,
			buffers.wallTexture,
			buffers.wallSampler
		);

		// Note: compute bind groups also need to be recreated for wall texture
		// This is handled by recreating all compute resources
		computeResources = createComputePipelines(device, buffers, blockSumsBuffer);

		// Reframe the camera for the new aspect ratio, preserving the user's angle
		// if they have already moved it.
		if (!userMovedCamera) {
			resetCameraToFit();
			applyReveal();
		}

		// Clear trails on resize
		clearTrails(device, buffers, params.population, params.trailLength);
		trailHead = 0;
	}

	function reallocateBuffers(): void {
		const wasRunning = running;
		stop();

		// Get the latest params directly from the store to avoid race conditions
		// This ensures we have the most up-to-date species data when adding/removing species
		params = { ...get(paramsStore) };

		// Destroy old buffers
		destroyBuffers(buffers);
		blockSumsBuffer.destroy();

		// Recalculate grid
		gridInfo = calculateGridDimensions(canvasWidth, canvasHeight, params.perception);

		// Create new buffers
		bufferConfig = {
			boidCount: params.population,
			trailLength: params.trailLength,
			gridWidth: gridInfo.gridWidth,
			gridHeight: gridInfo.gridHeight,
			canvasWidth,
			canvasHeight
		};

		buffers = createBuffers(device, bufferConfig);
		blockSumsBuffer = createBlockSumsBuffer(device, canvasWidth, canvasHeight);

		// Reinitialize boids with species data
		initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight, params.species);
		clearTrails(device, buffers, params.population, params.trailLength);

		// Initialize species buffers
		updateSpeciesParams(device, buffers.speciesParams, params.species);
		updateInteractionMatrix(device, buffers.interactionMatrix, params.species);
		// Initialize metric-based interaction rules
		updateMetricRules(
			device,
			buffers.metricRules,
			buffers.metricRuleCurves,
			params.species,
			sampleCurve
		);

		// Initialize curve samples buffer (critical - curves are always active)
		updateCurveSamples(device, buffers.curveSamples, sampleAllCurves(params));

		// Restore wall data to new texture (walls are preserved in memory)
		const existingWallData = getWallData();
		if (existingWallData) {
			const dims = getWallTextureDimensions();
			updateWallTexture(device, buffers.wallTexture, existingWallData, dims.width, dims.height);
		}

		// Recreate pipelines with new buffers
		computeResources = createComputePipelines(device, buffers, blockSumsBuffer);
		renderResources = createRenderPipelines(device, format, buffers);

		// Reset state
		readFromA = true;
		frameCount = 0;
		trailHead = 0;

		// Reset spectral/flow metrics init flag - new buffers need initialization
		needsRankInit = true;

		if (wasRunning) {
			start();
		}
	}

	function doTrailClear(): void {
		clearTrails(device, buffers, params.population, params.trailLength);
		trailHead = 0;
	}

	function resetBoids(): void {
		// Reinitialize boid positions and velocities without reallocating buffers
		initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight, params.species);
		clearTrails(device, buffers, params.population, params.trailLength);

		// Update species buffers
		updateSpeciesParams(device, buffers.speciesParams, params.species);
		updateInteractionMatrix(device, buffers.interactionMatrix, params.species);
		// Update metric-based interaction rules
		updateMetricRules(
			device,
			buffers.metricRules,
			buffers.metricRuleCurves,
			params.species,
			sampleCurve
		);

		// Reset state
		readFromA = true;
		frameCount = 0;
		trailHead = 0;

		// Reset spectral/flow metrics init flag - new positions need reinitialization
		needsRankInit = true;
	}

	function doUpdateWalls(): void {
		const wallData = getWallData();
		if (!wallData) return;

		const dims = getWallTextureDimensions();
		updateWallTexture(device, buffers.wallTexture, wallData, dims.width, dims.height);
		wallsDirty.set(false);
	}

	function doUpdateSpecies(): void {
		// Get the latest params to avoid race conditions
		params = { ...get(paramsStore) };
		// Update species parameters and interaction matrix
		updateSpeciesParams(device, buffers.speciesParams, params.species);
		updateInteractionMatrix(device, buffers.interactionMatrix, params.species);
		// Update metric-based interaction rules
		updateMetricRules(
			device,
			buffers.metricRules,
			buffers.metricRuleCurves,
			params.species,
			sampleCurve
		);
	}

	// Render immediately, even if the caller never presses play - a simulation
	// that starts paused should still show its first frame and stay orbitable.
	startLoop();

	return {
		start,
		stop,
		destroy,
		updateParams,
		updateCursor,
		resize,
		reallocateBuffers,
		clearTrails: doTrailClear,
		resetBoids,
		isRunning: () => running,
		updateWalls: doUpdateWalls,
		updateSpecies: doUpdateSpecies,
		orbitCamera: (deltaAzimuth: number, deltaElevation: number) => {
			// Taking the camera cancels the scripted reveal for the rest of the session
			userMovedCamera = true;
			orbit(camera, deltaAzimuth, deltaElevation);
		},
		zoomCamera: (factor: number) => {
			userMovedCamera = true;
			zoom(camera, factor);
		},
		panCamera: (deltaX: number, deltaY: number) => {
			userMovedCamera = true;
			pan(camera, deltaX, deltaY);
		},
		resetCamera: () => {
			resetCameraToFit();
			revealProgress = embedBlend;
			applyReveal();
		},
		pickDomainPosition: (ndcX: number, ndcY: number) => {
			const view = currentEmbedView();
			if (view.embedBlend <= 0) return null;
			const aspect = canvasWidth / Math.max(canvasHeight, 1);
			const ray = rayThrough(camera, ndcX, ndcY, aspect);
			const hit = pickSurfaceUV(ray.origin, ray.dir, ray.tanHalfFov, view);
			if (!hit) return null;
			// Parametric v runs opposite to domain y (see domainToParam in embed.wgsl)
			return { x: hit.u * canvasWidth, y: (1 - hit.v) * canvasHeight };
		}
	};
}
