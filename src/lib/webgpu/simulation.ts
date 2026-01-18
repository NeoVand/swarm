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
	type BufferConfig
} from './buffers';
import { createComputePipelines, encodeComputePasses, type ComputeResources } from './compute';
import { createRenderPipelines, encodeRenderPass, destroyRenderResources, type RenderResources } from './render';

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
	initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight);
	clearTrails(device, buffers, params.population, params.trailLength);

	// Create pipelines
	let computeResources: ComputeResources = createComputePipelines(device, buffers, blockSumsBuffer);
	let renderResources: RenderResources = createRenderPipelines(device, format, buffers);

	// Animation state
	let running = false;
	let animationFrameId: number | null = null;
	let readFromA = true;
	let frameCount = 0;
	let trailHead = 0;
	let lastTime = 0;
	let fpsFrames = 0;
	let fpsTime = 0;

	function frame(time: number): void {
		if (!running) return;

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

		// Update grid dimensions if perception changed
		const newGridInfo = calculateGridDimensions(canvasWidth, canvasHeight, params.perception);
		if (newGridInfo.gridWidth !== gridInfo.gridWidth || newGridInfo.gridHeight !== gridInfo.gridHeight) {
			gridInfo = newGridInfo;
			// Grid changed, may need to recreate some buffers
		}

		// Update trail head
		trailHead = (trailHead + 1) % params.trailLength;

		// Update uniform buffer
		updateUniforms(device, buffers.uniforms, {
			canvasWidth,
			canvasHeight,
			cellSize: gridInfo.cellSize,
			gridWidth: gridInfo.gridWidth,
			gridHeight: gridInfo.gridHeight,
			boidCount: params.population,
			trailLength: params.trailLength,
			trailHead,
			params,
			cursor,
			deltaTime: Math.min(deltaTime, 0.1), // Cap to prevent huge jumps
			time: time / 1000,
			frameCount
		});

		// Create command encoder
		const encoder = device.createCommandEncoder();

		// Encode compute passes
		encodeComputePasses(
			encoder,
			computeResources,
			params.population,
			gridInfo.gridWidth * gridInfo.gridHeight,
			readFromA
		);

		// Encode render pass
		const textureView = context.getCurrentTexture().createView();
		encodeRenderPass(
			encoder,
			textureView,
			renderResources,
			params.population,
			params.trailLength,
			readFromA
		);

		// Submit commands
		device.queue.submit([encoder.finish()]);

		// Swap buffers for next frame
		readFromA = !readFromA;
		frameCount++;

		// Schedule next frame
		animationFrameId = requestAnimationFrame(frame);
	}

	function start(): void {
		if (running) return;
		running = true;
		lastTime = 0;
		animationFrameId = requestAnimationFrame(frame);
	}

	function stop(): void {
		running = false;
		if (animationFrameId !== null) {
			cancelAnimationFrame(animationFrameId);
			animationFrameId = null;
		}
	}

	function destroy(): void {
		stop();
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

		// Clear trails on resize
		clearTrails(device, buffers, params.population, params.trailLength);
		trailHead = 0;
	}

	function reallocateBuffers(): void {
		const wasRunning = running;
		stop();

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

		// Reinitialize boids
		initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight);
		clearTrails(device, buffers, params.population, params.trailLength);

		// Recreate pipelines with new buffers
		computeResources = createComputePipelines(device, buffers, blockSumsBuffer);
		renderResources = createRenderPipelines(device, format, buffers);

		// Reset state
		readFromA = true;
		frameCount = 0;
		trailHead = 0;

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
		initializeBoids(device, buffers, params.population, canvasWidth, canvasHeight);
		clearTrails(device, buffers, params.population, params.trailLength);
		
		// Reset state
		readFromA = true;
		frameCount = 0;
		trailHead = 0;
	}

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
		isRunning: () => running
	};
}
