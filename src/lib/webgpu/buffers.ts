// Buffer creation and management

import type { SimulationBuffers, SimulationParams, CursorState } from './types';
import { WORKGROUP_SIZE } from './types';

export interface BufferConfig {
	boidCount: number;
	trailLength: number;
	gridWidth: number;
	gridHeight: number;
	canvasWidth: number;
	canvasHeight: number;
}

export function createBuffers(device: GPUDevice, config: BufferConfig): SimulationBuffers {
	const { boidCount, trailLength, canvasWidth, canvasHeight } = config;
	
	// Use max grid size for grid buffers to avoid reallocation when perception changes
	const { maxTotalCells } = calculateMaxGridDimensions(canvasWidth, canvasHeight);

	// Position buffers (ping-pong): vec2<f32> per boid
	const positionA = device.createBuffer({
		size: boidCount * 2 * 4, // 2 floats × 4 bytes
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	const positionB = device.createBuffer({
		size: boidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Velocity buffers (ping-pong): vec2<f32> per boid
	const velocityA = device.createBuffer({
		size: boidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	const velocityB = device.createBuffer({
		size: boidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Trail buffer: vec2<f32> × MAX_TRAIL_LENGTH per boid (pre-allocated for max)
	const trails = device.createBuffer({
		size: boidCount * MAX_TRAIL_LENGTH * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Cell counts: u32 per cell (pre-allocated for max grid size)
	const cellCounts = device.createBuffer({
		size: maxTotalCells * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Cell offsets (for scatter atomics): u32 per cell (pre-allocated for max grid size)
	const cellOffsets = device.createBuffer({
		size: maxTotalCells * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Prefix sums: u32 per cell (pre-allocated for max grid size)
	const prefixSums = device.createBuffer({
		size: maxTotalCells * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Sorted indices: u32 per boid
	const sortedIndices = device.createBuffer({
		size: boidCount * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Boid cell indices: u32 per boid
	const boidCellIndices = device.createBuffer({
		size: boidCount * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Uniform buffer (256 bytes, padded for alignment)
	const uniforms = device.createBuffer({
		size: 256,
		usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
	});

	// Trail head index buffer
	const trailHead = device.createBuffer({
		size: 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	return {
		positionA,
		positionB,
		velocityA,
		velocityB,
		trails,
		cellCounts,
		cellOffsets,
		prefixSums,
		sortedIndices,
		boidCellIndices,
		uniforms,
		trailHead
	};
}

export function destroyBuffers(buffers: SimulationBuffers): void {
	buffers.positionA.destroy();
	buffers.positionB.destroy();
	buffers.velocityA.destroy();
	buffers.velocityB.destroy();
	buffers.trails.destroy();
	buffers.cellCounts.destroy();
	buffers.cellOffsets.destroy();
	buffers.prefixSums.destroy();
	buffers.sortedIndices.destroy();
	buffers.boidCellIndices.destroy();
	buffers.uniforms.destroy();
	buffers.trailHead.destroy();
}

export function initializeBoids(
	device: GPUDevice,
	buffers: SimulationBuffers,
	boidCount: number,
	canvasWidth: number,
	canvasHeight: number
): void {
	// Safe spawn margin - keep boids away from edges and corners
	// This matches the boundary force margin in simulate.wgsl
	const safeMargin = 60; // Slightly larger than shader's 50px margin
	
	// Calculate safe spawn area
	const safeMinX = safeMargin;
	const safeMaxX = canvasWidth - safeMargin;
	const safeMinY = safeMargin;
	const safeMaxY = canvasHeight - safeMargin;
	const safeWidth = safeMaxX - safeMinX;
	const safeHeight = safeMaxY - safeMinY;
	
	// Create initial positions (random within safe area)
	const positions = new Float32Array(boidCount * 2);
	for (let i = 0; i < boidCount; i++) {
		positions[i * 2] = safeMinX + Math.random() * safeWidth;
		positions[i * 2 + 1] = safeMinY + Math.random() * safeHeight;
	}

	// Create initial velocities (random directions, moderate speed)
	const velocities = new Float32Array(boidCount * 2);
	for (let i = 0; i < boidCount; i++) {
		const angle = Math.random() * Math.PI * 2;
		const speed = 1 + Math.random() * 2;
		velocities[i * 2] = Math.cos(angle) * speed;
		velocities[i * 2 + 1] = Math.sin(angle) * speed;
	}

	// Upload to GPU
	device.queue.writeBuffer(buffers.positionA, 0, positions);
	device.queue.writeBuffer(buffers.positionB, 0, positions);
	device.queue.writeBuffer(buffers.velocityA, 0, velocities);
	device.queue.writeBuffer(buffers.velocityB, 0, velocities);
}

export function clearTrails(
	device: GPUDevice,
	buffers: SimulationBuffers,
	boidCount: number,
	_trailLength?: number // Unused - always clears full pre-allocated buffer
): void {
	// Zero out trail buffer (full pre-allocated size)
	const zeros = new Float32Array(boidCount * MAX_TRAIL_LENGTH * 2);
	device.queue.writeBuffer(buffers.trails, 0, zeros);

	// Reset trail head
	const headData = new Uint32Array([0]);
	device.queue.writeBuffer(buffers.trailHead, 0, headData);
}

export interface UniformData {
	canvasWidth: number;
	canvasHeight: number;
	cellSize: number;
	gridWidth: number;
	gridHeight: number;
	boidCount: number;
	trailLength: number;
	trailHead: number;
	params: SimulationParams;
	cursor: CursorState;
	deltaTime: number;
	time: number;
	frameCount: number;
}

export function updateUniforms(device: GPUDevice, buffer: GPUBuffer, data: UniformData): void {
	// Pack uniforms according to WGSL struct layout
	const uniformArray = new ArrayBuffer(256);
	const f32View = new Float32Array(uniformArray);
	const u32View = new Uint32Array(uniformArray);

	// Layout matches the Uniforms struct in WGSL
	let offset = 0;

	f32View[offset++] = data.canvasWidth;
	f32View[offset++] = data.canvasHeight;
	f32View[offset++] = data.cellSize;
	u32View[offset++] = data.gridWidth;
	u32View[offset++] = data.gridHeight;
	u32View[offset++] = data.boidCount;
	u32View[offset++] = data.trailLength;
	u32View[offset++] = data.trailHead;
	f32View[offset++] = data.params.alignment;
	f32View[offset++] = data.params.cohesion;
	f32View[offset++] = data.params.separation;
	f32View[offset++] = data.params.perception;
	f32View[offset++] = data.params.maxSpeed;
	f32View[offset++] = data.params.maxForce;
	f32View[offset++] = data.params.noise;
	f32View[offset++] = data.params.rebels;
	u32View[offset++] = data.params.boundaryMode;
	u32View[offset++] = data.params.cursorMode;
	u32View[offset++] = data.params.cursorShape;
	f32View[offset++] = data.params.cursorForce;
	f32View[offset++] = data.params.cursorRadius;
	// When cursor is not active, place it far off-screen so it can't affect any boids
	f32View[offset++] = data.cursor.isActive ? data.cursor.x : -99999;
	f32View[offset++] = data.cursor.isActive ? data.cursor.y : -99999;
	u32View[offset++] = data.cursor.isPressed ? 1 : 0;
	u32View[offset++] = data.cursor.isActive ? 1 : 0;
	f32View[offset++] = data.params.boidSize;
	u32View[offset++] = data.params.colorMode;
	u32View[offset++] = data.params.colorSpectrum;
	f32View[offset++] = data.params.sensitivity;
	f32View[offset++] = data.deltaTime;
	f32View[offset++] = data.time;
	u32View[offset++] = data.frameCount;
	u32View[offset++] = data.params.algorithmMode;

	device.queue.writeBuffer(buffer, 0, uniformArray);
}

// Minimum perception for buffer pre-allocation (matches UI min)
const MIN_PERCEPTION_FOR_ALLOCATION = 20;

// Maximum trail length for buffer pre-allocation (matches UI max)
const MAX_TRAIL_LENGTH = 100;

// Calculate grid dimensions based on canvas size and perception radius
export function calculateGridDimensions(
	canvasWidth: number,
	canvasHeight: number,
	perception: number
): { gridWidth: number; gridHeight: number; cellSize: number } {
	const cellSize = perception;
	const gridWidth = Math.ceil(canvasWidth / cellSize);
	const gridHeight = Math.ceil(canvasHeight / cellSize);
	return { gridWidth, gridHeight, cellSize };
}

// Calculate maximum grid dimensions for buffer pre-allocation
// Uses minimum perception to ensure buffers are large enough for any perception value
export function calculateMaxGridDimensions(
	canvasWidth: number,
	canvasHeight: number
): { maxGridWidth: number; maxGridHeight: number; maxTotalCells: number } {
	const maxGridWidth = Math.ceil(canvasWidth / MIN_PERCEPTION_FOR_ALLOCATION);
	const maxGridHeight = Math.ceil(canvasHeight / MIN_PERCEPTION_FOR_ALLOCATION);
	return { maxGridWidth, maxGridHeight, maxTotalCells: maxGridWidth * maxGridHeight };
}

// Calculate number of workgroups needed
export function calculateWorkgroups(count: number): number {
	return Math.ceil(count / WORKGROUP_SIZE);
}

// Block sums buffer for prefix sum (needed for large grids)
// Now takes canvas dimensions to pre-allocate for max grid size
export function createBlockSumsBuffer(
	device: GPUDevice,
	canvasWidth: number,
	canvasHeight: number
): GPUBuffer {
	const { maxTotalCells } = calculateMaxGridDimensions(canvasWidth, canvasHeight);
	const numBlocks = Math.ceil(maxTotalCells / (WORKGROUP_SIZE * 2));
	return device.createBuffer({
		size: Math.max(numBlocks * 4, 4),
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});
}
