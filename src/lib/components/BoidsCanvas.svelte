<script lang="ts">
	import { onDestroy } from 'svelte';
	import { get } from 'svelte/store';
	import { initWebGPU, resizeCanvas, destroyWebGPU } from '$lib/webgpu/context';
	import { createSimulation, type Simulation } from '$lib/webgpu/simulation';
	import {
		initializeScenes,
		loadSceneFromHash,
		registerSceneCameraHandlers
	} from '$lib/stores/scenes';
	import type { GPUContext, SimulationParams, CursorState } from '$lib/webgpu/types';
	import {
		CursorMode,
		CursorResponse,
		CursorShape,
		VortexDirection,
		WallTool,
		WallBrushShape,
		calculateOptimalSpeciesPopulations
	} from '$lib/webgpu/types';
	import {
		params,
		cursor,
		dimensions,
		isWebGPUAvailable,
		isRunning,
		fps,
		needsBufferReallocation,
		needsTrailClear,
		needsSimulationReset,
		canvasElement,
		wallTool,
		paintWall,
		beginStroke,
		endStrokeWithHollow,
		wallsDirty,
		speciesDirty,
		needsCameraReset
	} from '$lib/stores/simulation';

	let canvas: HTMLCanvasElement;
	let container: HTMLDivElement;
	let gpuContext: GPUContext | null = null;
	let simulation: Simulation | null = null;
	let unregisterSceneCamera: (() => void) | undefined;

	// Track cursor CSS position (not DPR scaled)
	let cursorCssX = $state(0);
	let cursorCssY = $state(0);

	// Subscribe to stores
	let currentParams = $state.raw<SimulationParams>(get(params));
	let currentCursor = $state.raw<CursorState>(get(cursor));
	let currentWallTool = $state<WallTool>(WallTool.None);
	let isPaintingWall = $state(false);

	const unsubParams = params.subscribe((p) => {
		currentParams = p;
		simulation?.updateParams(p);
	});

	const unsubCursor = cursor.subscribe((c) => {
		currentCursor = c;
		simulation?.updateCursor(c);
	});

	const unsubWallTool = wallTool.subscribe((t) => {
		currentWallTool = t;
	});

	const unsubWallsDirty = wallsDirty.subscribe((dirty) => {
		if (dirty && simulation) {
			simulation.updateWalls();
		}
	});

	// Reactive cursor state based on active species
	const activeSpeciesForCursor = $derived(
		currentParams.species.find((s) => s.id === currentParams.activeSpeciesId)
	);
	const speciesCursorResponse = $derived(
		activeSpeciesForCursor?.cursorResponse ?? CursorResponse.Ignore
	);
	const speciesVortexDirection = $derived(
		activeSpeciesForCursor?.cursorVortex ?? VortexDirection.Off
	);
	const hasVortexActive = $derived(speciesVortexDirection !== VortexDirection.Off);
	const hasCursorInteraction = $derived(
		speciesCursorResponse !== CursorResponse.Ignore || hasVortexActive
	);

	const unsubCameraReset = needsCameraReset.subscribe((needs) => {
		if (needs && simulation) {
			simulation.resetCamera();
			needsCameraReset.set(false);
		}
	});

	const unsubSpeciesDirty = speciesDirty.subscribe((dirty) => {
		if (dirty && simulation) {
			simulation.updateSpecies();
			speciesDirty.set(false);
		}
	});

	const unsubRealloc = needsBufferReallocation.subscribe((needs) => {
		if (needs && simulation) {
			simulation.reallocateBuffers();
			needsBufferReallocation.set(false);
		}
	});

	const unsubTrailClear = needsTrailClear.subscribe((needs) => {
		if (needs && simulation) {
			simulation.clearTrails();
			needsTrailClear.set(false);
		}
	});

	const unsubSimulationReset = needsSimulationReset.subscribe((needs) => {
		if (needs && simulation) {
			simulation.resetBoids();
			needsSimulationReset.set(false);
		}
	});

	// Play/pause subscription
	const unsubRunning = isRunning.subscribe((running) => {
		if (simulation) {
			if (running) {
				simulation.start();
			} else {
				simulation.stop();
			}
		}
	});

	function updateDimensions(): void {
		if (!container || !canvas || !gpuContext) return;

		// Use visualViewport for accurate dimensions on mobile
		const vv = window.visualViewport;
		const width = vv ? vv.width : window.innerWidth;
		const height = vv ? vv.height : window.innerHeight;

		// Get device pixel ratio for sharp rendering
		const dpr = Math.min(window.devicePixelRatio || 1, 2);

		const canvasWidth = Math.floor(width * dpr);
		const canvasHeight = Math.floor(height * dpr);

		if (canvas.width !== canvasWidth || canvas.height !== canvasHeight) {
			canvas.width = canvasWidth;
			canvas.height = canvasHeight;
			canvas.style.width = `${width}px`;
			canvas.style.height = `${height}px`;

			resizeCanvas(gpuContext, canvasWidth, canvasHeight);
			dimensions.set({ width: canvasWidth, height: canvasHeight });
			simulation?.resize(canvasWidth, canvasHeight);
		}
	}

	// --- Embedded 3D camera control ---
	// While embedded, the pointer drives the camera instead of the flock: cursor
	// forces and wall painting are suspended until the view is flattened again.
	// Left-drag orbits, right-drag pans, and simply hovering pushes boids around
	// on the surface - the same thing the cursor does in the flat view.
	let isOrbiting = $state(false);
	let isPanning = $state(false);
	let isPushing = false;
	let lastOrbitX = 0;
	let lastOrbitY = 0;
	let pinchDistance = 0;

	const ORBIT_SENSITIVITY = 0.006; // radians per pixel

	function isEmbeddedMode(): boolean {
		return currentParams?.embedded3D === true;
	}

	function beginOrbit(clientX: number, clientY: number, pan = false): void {
		isOrbiting = !pan;
		isPanning = pan;
		lastOrbitX = clientX;
		lastOrbitY = clientY;
	}

	function moveOrbit(clientX: number, clientY: number): void {
		if (!isOrbiting && !isPanning) return;
		const rawX = clientX - lastOrbitX;
		const rawY = clientY - lastOrbitY;
		lastOrbitX = clientX;
		lastOrbitY = clientY;
		if (isPanning) {
			// Pan deltas are fractions of viewport height
			const h = Math.max(canvas?.clientHeight ?? window.innerHeight, 1);
			simulation?.panCamera(rawX / h, rawY / h);
		} else {
			simulation?.orbitCamera(rawX * ORBIT_SENSITIVITY, rawY * ORBIT_SENSITIVITY);
		}
	}

	/**
	 * Project the pointer onto the embedded surface and feed the result back as
	 * a domain-space cursor, so cursor forces and vortices work in 3D exactly as
	 * they do flat. Skipped while dragging the camera.
	 */
	function pickDomainAt(clientX: number, clientY: number): { x: number; y: number } | null {
		if (!canvas || !simulation) return null;
		const rect = canvas.getBoundingClientRect();
		cursorCssX = clientX - rect.left;
		cursorCssY = clientY - rect.top;
		const ndcX = (cursorCssX / Math.max(rect.width, 1)) * 2 - 1;
		const ndcY = 1 - (cursorCssY / Math.max(rect.height, 1)) * 2;
		return simulation.pickDomainPosition(ndcX, ndcY);
	}

	function updateEmbeddedCursor(clientX: number, clientY: number, pressed?: boolean): void {
		const hit = pickDomainAt(clientX, clientY);
		if (!hit) {
			cursor.update((c) => ({ ...c, isActive: false }));
			return;
		}
		cursor.update((c) => ({
			...c,
			x: hit.x,
			y: hit.y,
			isActive: true,
			isPressed: pressed ?? c.isPressed
		}));
	}

	function handleWheel(e: WheelEvent): void {
		if (!isEmbeddedMode()) return;
		e.preventDefault();
		// Exponential so each notch feels the same at any distance
		simulation?.zoomCamera(Math.exp(e.deltaY * 0.0015));
	}

	function touchDistance(a: Touch, b: Touch): number {
		return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
	}

	function handleMouseMove(e: MouseEvent): void {
		if (isEmbeddedMode()) {
			if (isOrbiting || isPanning) {
				moveOrbit(e.clientX, e.clientY);
			} else {
				updateEmbeddedCursor(e.clientX, e.clientY, isPushing ? true : undefined);
			}
			return;
		}
		if (!canvas) return;
		const rect = canvas.getBoundingClientRect();
		const dpr = Math.min(window.devicePixelRatio || 1, 2);
		// Track CSS position for visual cursor
		cursorCssX = e.clientX - rect.left;
		cursorCssY = e.clientY - rect.top;
		const canvasX = cursorCssX * dpr;
		const canvasY = cursorCssY * dpr;

		// Paint walls if wall tool is active and mouse is pressed
		if (isPaintingWall && currentWallTool !== WallTool.None) {
			paintWall(
				canvasX,
				canvasY,
				currentParams.wallBrushSize * dpr,
				currentWallTool === WallTool.Eraser
			);
		}

		cursor.update((c) => ({
			...c,
			x: canvasX,
			y: canvasY,
			isActive: true
		}));
	}

	function handleMouseDown(e: MouseEvent): void {
		if (isEmbeddedMode()) {
			// Right (or middle) button always pans
			if (e.button === 2 || e.button === 1) {
				beginOrbit(e.clientX, e.clientY, true);
				cursor.update((c) => ({ ...c, isActive: false, isPressed: false }));
				return;
			}
			// Left button: pressing on the surface pushes boids, pressing empty
			// space orbits. Grabbing the object to spin it and grabbing the flock
			// to shove it are different intents.
			const hit = pickDomainAt(e.clientX, e.clientY);
			if (hit) {
				isPushing = true;
				cursor.update((c) => ({ ...c, x: hit.x, y: hit.y, isActive: true, isPressed: true }));
			} else {
				beginOrbit(e.clientX, e.clientY);
				cursor.update((c) => ({ ...c, isActive: false, isPressed: false }));
			}
			return;
		}
		if (currentWallTool !== WallTool.None) {
			isPaintingWall = true;
			// Begin stroke tracking if using ring brush with pencil
			if (
				currentWallTool === WallTool.Pencil &&
				currentParams.wallBrushShape === WallBrushShape.Ring
			) {
				beginStroke();
			}
			// Paint at current position immediately
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;
			paintWall(
				canvasX,
				canvasY,
				currentParams.wallBrushSize * dpr,
				currentWallTool === WallTool.Eraser
			);
		}
		cursor.update((c) => ({ ...c, isPressed: true }));
	}

	function handleMouseUp(): void {
		if (isPushing) {
			isPushing = false;
			cursor.update((c) => ({ ...c, isPressed: false }));
			return;
		}
		if (isOrbiting || isPanning) {
			isOrbiting = false;
			isPanning = false;
			return;
		}
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
		cursor.update((c) => ({ ...c, isPressed: false }));
	}

	function handleMouseLeave(): void {
		isOrbiting = false;
		isPanning = false;
		isPushing = false;
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
		cursor.update((c) => ({ ...c, isActive: false, isPressed: false }));
	}

	function handleTouchStart(e: TouchEvent): void {
		e.preventDefault();
		if (isEmbeddedMode()) {
			if (e.touches.length === 2) {
				isOrbiting = false;
				isPanning = false; // set on the first move, once there is a delta
				pinchDistance = touchDistance(e.touches[0], e.touches[1]);
				lastOrbitX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
				lastOrbitY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
			} else if (e.touches.length === 1) {
				beginOrbit(e.touches[0].clientX, e.touches[0].clientY);
			}
			return;
		}
		if (e.touches.length > 0) {
			const touch = e.touches[0];
			const rect = canvas.getBoundingClientRect();
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			cursorCssX = touch.clientX - rect.left;
			cursorCssY = touch.clientY - rect.top;
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;

			// Paint walls if wall tool is active
			if (currentWallTool !== WallTool.None) {
				isPaintingWall = true;
				// Begin stroke tracking if using ring brush with pencil
				if (
					currentWallTool === WallTool.Pencil &&
					currentParams.wallBrushShape === WallBrushShape.Ring
				) {
					beginStroke();
				}
				paintWall(
					canvasX,
					canvasY,
					currentParams.wallBrushSize * dpr,
					currentWallTool === WallTool.Eraser
				);
			}

			cursor.set({
				x: canvasX,
				y: canvasY,
				isPressed: true,
				isActive: true
			});
		}
	}

	function handleTouchMove(e: TouchEvent): void {
		e.preventDefault();
		if (isEmbeddedMode()) {
			if (e.touches.length === 2) {
				// Two fingers pinch to zoom and drag to pan at the same time
				const dist = touchDistance(e.touches[0], e.touches[1]);
				if (pinchDistance > 0 && dist > 0) {
					simulation?.zoomCamera(pinchDistance / dist);
				}
				pinchDistance = dist;

				const cx = (e.touches[0].clientX + e.touches[1].clientX) / 2;
				const cy = (e.touches[0].clientY + e.touches[1].clientY) / 2;
				if (isPanning) {
					const h = Math.max(canvas?.clientHeight ?? window.innerHeight, 1);
					simulation?.panCamera((cx - lastOrbitX) / h, (cy - lastOrbitY) / h);
				}
				isPanning = true;
				isOrbiting = false;
				lastOrbitX = cx;
				lastOrbitY = cy;
			} else if (e.touches.length === 1) {
				moveOrbit(e.touches[0].clientX, e.touches[0].clientY);
			}
			return;
		}
		if (e.touches.length > 0) {
			const touch = e.touches[0];
			const rect = canvas.getBoundingClientRect();
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			cursorCssX = touch.clientX - rect.left;
			cursorCssY = touch.clientY - rect.top;
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;

			// Paint walls if wall tool is active
			if (isPaintingWall && currentWallTool !== WallTool.None) {
				paintWall(
					canvasX,
					canvasY,
					currentParams.wallBrushSize * dpr,
					currentWallTool === WallTool.Eraser
				);
			}

			cursor.update((c) => ({
				...c,
				x: canvasX,
				y: canvasY
			}));
		}
	}

	function handleTouchEnd(e: TouchEvent): void {
		e.preventDefault();
		isOrbiting = false;
		isPanning = false;
		pinchDistance = 0;
		if (isEmbeddedMode()) return;
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
		// Fully reset cursor state when touch ends
		cursor.set({ x: -9999, y: -9999, isPressed: false, isActive: false });
	}

	let resizeObserver: ResizeObserver | null = null;

	function mountCanvas(element: HTMLCanvasElement) {
		canvas = element;
		container = element.parentElement as HTMLDivElement;
		let disposed = false;
		// Expose canvas element for screenshot/recording
		canvasElement.set(canvas);

		// Initialize WebGPU (async but we don't return the promise)
		initWebGPU(canvas).then((ctx) => {
			if (disposed) {
				destroyWebGPU(ctx);
				return;
			}
			gpuContext = ctx;

			if (!gpuContext) {
				isWebGPUAvailable.set(false);
				return;
			}

			// Set initial dimensions
			updateDimensions();

			// Calculate optimal populations for all four species based on screen size
			const optimalPops = calculateOptimalSpeciesPopulations(canvas.width, canvas.height);

			// Update params with optimal populations for all species
			params.update((p) => ({
				...p,
				population: optimalPops.total,
				species: p.species.map((s) => {
					if (s.id === 0) return { ...s, population: optimalPops.species1 };
					if (s.id === 1) return { ...s, population: optimalPops.species2 };
					if (s.id === 2) return { ...s, population: optimalPops.species3 };
					if (s.id === 3) return { ...s, population: optimalPops.species4 };
					return s;
				})
			}));

			// Get params for simulation init
			let initParams: SimulationParams;
			const unsub0 = params.subscribe((p) => (initParams = p));
			unsub0();

			// Create simulation
			simulation = createSimulation(gpuContext, initParams!, (newFps) => {
				fps.set(newFps);
			});
			unregisterSceneCamera = registerSceneCameraHandlers({
				capture: () => simulation?.getCameraState(),
				restore: (camera) => simulation?.restoreCameraState(camera)
			});

			// Ensure reallocation flag is clean after init
			needsBufferReallocation.set(false);
			isWebGPUAvailable.set(true);
			initializeScenes();
			loadSceneFromHash();
			window.addEventListener('hashchange', loadSceneFromHash);

			// Start simulation (respects current isRunning state)
			let currentRunning = true;
			const unsub = isRunning.subscribe((v) => (currentRunning = v));
			unsub();
			if (currentRunning) {
				simulation.start();
			}

			// Setup resize observers
			resizeObserver = new ResizeObserver(() => {
				updateDimensions();
			});
			resizeObserver.observe(container);

			// Visual viewport listener for mobile
			if (window.visualViewport) {
				window.visualViewport.addEventListener('resize', updateDimensions);
			}

			window.addEventListener('resize', updateDimensions);
			window.addEventListener('orientationchange', updateDimensions);
		});

		// Return cleanup function
		return () => {
			disposed = true;
			window.removeEventListener('hashchange', loadSceneFromHash);
			resizeObserver?.disconnect();
			if (window.visualViewport) {
				window.visualViewport.removeEventListener('resize', updateDimensions);
			}
			window.removeEventListener('resize', updateDimensions);
			window.removeEventListener('orientationchange', updateDimensions);
		};
	}

	onDestroy(() => {
		unsubParams();
		unsubCursor();
		unsubRealloc();
		unsubTrailClear();
		unsubSimulationReset();
		unsubRunning();
		unsubWallTool();
		unsubWallsDirty();
		unsubSpeciesDirty();
		unsubCameraReset();
		unregisterSceneCamera?.();
		canvasElement.set(null);
		simulation?.destroy();
		destroyWebGPU(gpuContext);
		gpuContext = null;
	});
</script>

<div class="fixed relative inset-0 overflow-hidden bg-[#0a0b0d]">
	<canvas
		{@attach mountCanvas}
		class="block touch-none select-none {currentParams?.embedded3D
			? isOrbiting
				? 'cursor-grabbing'
				: 'cursor-grab'
			: currentParams?.cursorMode !== CursorMode.Off ||
				  hasVortexActive ||
				  currentWallTool !== WallTool.None
				? 'cursor-none'
				: ''}"
		onmousemove={handleMouseMove}
		onmousedown={handleMouseDown}
		onmouseup={handleMouseUp}
		onmouseleave={handleMouseLeave}
		onwheel={handleWheel}
		ontouchstart={handleTouchStart}
		ontouchmove={handleTouchMove}
		ontouchend={(e) => handleTouchEnd(e)}
		ontouchcancel={(e) => handleTouchEnd(e)}
		oncontextmenu={(e) => e.preventDefault()}
	></canvas>

	<!-- Wall tool cursor overlay -->
	{#if currentCursor?.isActive && currentWallTool !== WallTool.None && !currentParams?.embedded3D}
		{@const brushSize = currentParams?.wallBrushSize ?? 30}
		{@const isPencil = currentWallTool === WallTool.Pencil}
		{@const brushColor = isPencil ? '100, 116, 139' : '239, 68, 68'}

		<div
			class="pointer-events-none absolute"
			style="left: {cursorCssX}px; top: {cursorCssY}px; transform: translate(-50%, -50%);"
		>
			<svg width={brushSize * 2} height={brushSize * 2}>
				<circle
					cx={brushSize}
					cy={brushSize}
					r={brushSize - 1}
					fill={isPaintingWall ? `rgba(${brushColor}, 0.3)` : 'none'}
					stroke="rgba({brushColor}, {isPaintingWall ? 0.9 : 0.6})"
					stroke-width={isPaintingWall ? 2 : 1.5}
					stroke-dasharray={isPencil ? 'none' : '6 4'}
				/>
				<!-- Center crosshair -->
				<line
					x1={brushSize - 6}
					y1={brushSize}
					x2={brushSize + 6}
					y2={brushSize}
					stroke="rgba({brushColor}, 0.8)"
					stroke-width="1"
				/>
				<line
					x1={brushSize}
					y1={brushSize - 6}
					x2={brushSize}
					y2={brushSize + 6}
					stroke="rgba({brushColor}, 0.8)"
					stroke-width="1"
				/>
			</svg>
		</div>
	{/if}

	<!-- Custom cursor overlay for boid interaction (shows alongside wall tool cursor) -->
	<!-- Shown in embedded mode too: the pointer is projected onto the surface, so
	     cursor forces work there and the ring should follow them. -->
	{#if currentCursor?.isActive && hasCursorInteraction && !isOrbiting && !isPanning}
		{@const radius = currentParams?.cursorRadius ?? 50}
		{@const isAttract = speciesCursorResponse === CursorResponse.Attract}
		{@const isVortexOnly = speciesCursorResponse === CursorResponse.Ignore && hasVortexActive}
		{@const shape = currentParams?.cursorShape ?? CursorShape.Disk}
		{@const hasVortex = hasVortexActive}
		{@const isClockwise = speciesVortexDirection === VortexDirection.Clockwise}
		{@const isCounterClockwise = speciesVortexDirection === VortexDirection.CounterClockwise}
		{@const vortexOnlyColor = isClockwise ? '234, 179, 8' : '168, 85, 247'}
		{@const color = isVortexOnly ? vortexOnlyColor : isAttract ? '6, 182, 212' : '244, 63, 94'}
		{@const baseOpacity = currentCursor.isPressed ? 0.9 : 0.6}
		{@const spinClass = hasVortex
			? isCounterClockwise
				? 'animate-spin-vortex-reverse'
				: 'animate-spin-vortex'
			: ''}

		<div
			class="pointer-events-none absolute"
			style="left: {cursorCssX}px; top: {cursorCssY}px; transform: translate(-50%, -50%);"
		>
			<!-- Ring Shape -->
			{#if shape === CursorShape.Ring}
				<svg width={radius * 2} height={radius * 2} class={spinClass}>
					<circle
						cx={radius}
						cy={radius}
						r={radius - 2}
						fill="none"
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2.5 : 1.5}
						stroke-dasharray={hasVortex || isVortexOnly ? '10 8' : 'none'}
					/>
				</svg>

				<!-- Disk Shape (default) -->
			{:else}
				<svg width={radius * 2} height={radius * 2} class={spinClass}>
					<circle
						cx={radius}
						cy={radius}
						r={radius - 1}
						fill={isVortexOnly ? 'none' : `rgba(${color}, ${baseOpacity * 0.15})`}
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2 : 1.5}
						stroke-dasharray={hasVortex || isVortexOnly ? '10 8' : 'none'}
					/>
					<!-- Center dot (not shown for vortex-only) -->
					{#if !isVortexOnly}
						<circle cx={radius} cy={radius} r="3" fill="rgba({color}, {baseOpacity})" />
					{/if}
				</svg>
			{/if}
		</div>
	{/if}
</div>

<style>
	.cursor-none {
		cursor: none;
	}

	@keyframes spin-vortex {
		from {
			transform: rotate(0deg);
		}
		to {
			transform: rotate(360deg);
		}
	}
	.animate-spin-vortex {
		animation: spin-vortex 2s linear infinite;
		will-change: transform;
	}

	@keyframes spin-vortex-reverse {
		from {
			transform: rotate(0deg);
		}
		to {
			transform: rotate(-360deg);
		}
	}
	.animate-spin-vortex-reverse {
		animation: spin-vortex-reverse 2s linear infinite;
		will-change: transform;
	}
</style>
