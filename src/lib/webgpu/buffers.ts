// Buffer creation and management

import type { SimulationBuffers, SimulationParams, CursorState, Species } from './types';
import { WORKGROUP_SIZE, WALL_TEXTURE_SCALE, MAX_SPECIES } from './types';

export interface BufferConfig {
	boidCount: number;
	trailLength: number;
	gridWidth: number;
	gridHeight: number;
	canvasWidth: number;
	canvasHeight: number;
}

export function createBuffers(device: GPUDevice, config: BufferConfig): SimulationBuffers {
	const { boidCount, canvasWidth, canvasHeight } = config;

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

	// Birth colors: f32 per boid (stores initial position-based color)
	const birthColors = device.createBuffer({
		size: boidCount * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Wall texture for obstacle avoidance (1/4 resolution)
	const wallTextureWidth = Math.ceil(canvasWidth / WALL_TEXTURE_SCALE);
	const wallTextureHeight = Math.ceil(canvasHeight / WALL_TEXTURE_SCALE);
	const wallTexture = device.createTexture({
		size: [wallTextureWidth, wallTextureHeight, 1],
		format: 'r8unorm',
		usage:
			GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT
	});

	// Sampler for wall texture (linear filtering for smooth edges)
	const wallSampler = device.createSampler({
		magFilter: 'linear',
		minFilter: 'linear',
		addressModeU: 'clamp-to-edge',
		addressModeV: 'clamp-to-edge'
	});

	// Species ID buffer: u32 per boid (which species each boid belongs to)
	const speciesIds = device.createBuffer({
		size: boidCount * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Species parameters buffer: per-species flocking params (UNIFORM buffer)
	// Layout: 2 vec4s per species (8 floats = 32 bytes per species)
	// vec4[0]: [alignment, cohesion, separation, perception]
	// vec4[1]: [maxSpeed, maxForce, hue, headShape]
	// vec4[2]: [saturation, lightness, size, trailLength]
	// vec4[3]: [rebels, cursorForce, cursorResponse, cursorVortex]
	// vec4[4]: [alphaMode, unused, unused, unused]
	const speciesParams = device.createBuffer({
		size: MAX_SPECIES * 5 * 16, // 7 species * 5 vec4s * 16 bytes per vec4
		usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
	});

	// Interaction matrix: MAX_SPECIES × MAX_SPECIES (UNIFORM buffer)
	// Each entry is a vec4: [behavior, strength, range, padding]
	const interactionMatrix = device.createBuffer({
		size: MAX_SPECIES * MAX_SPECIES * 16, // 49 vec4s * 16 bytes
		usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
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
		trailHead,
		birthColors,
		wallTexture,
		wallSampler,
		speciesIds,
		speciesParams,
		interactionMatrix
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
	buffers.birthColors.destroy();
	buffers.wallTexture.destroy();
	buffers.speciesIds.destroy();
	buffers.speciesParams.destroy();
	buffers.interactionMatrix.destroy();
}

export function initializeBoids(
	device: GPUDevice,
	buffers: SimulationBuffers,
	boidCount: number,
	canvasWidth: number,
	canvasHeight: number,
	species?: Species[]
): void {
	// Safe spawn margin - keep boids away from edges and corners
	// This matches the BOUNDARY_INSET (30) in simulate.wgsl plus extra padding
	const safeMargin = 80; // Boundary inset (30) + extra padding (50)

	// Calculate safe spawn area
	const safeMinX = safeMargin;
	const safeMaxX = canvasWidth - safeMargin;
	const safeMinY = safeMargin;
	const safeMaxY = canvasHeight - safeMargin;
	const safeWidth = safeMaxX - safeMinX;
	const safeHeight = safeMaxY - safeMinY;

	// Create initial positions (random within safe area) and birth colors
	const positions = new Float32Array(boidCount * 2);
	const birthColors = new Float32Array(boidCount);
	const speciesIds = new Uint32Array(boidCount);
	const centerX = canvasWidth * 0.5;
	const centerY = canvasHeight * 0.5;

	// Calculate species assignments based on population counts
	const speciesRanges: { id: number; start: number; end: number }[] = [];
	if (species && species.length > 0) {
		let offset = 0;
		for (const s of species) {
			speciesRanges.push({
				id: s.id,
				start: offset,
				end: offset + s.population
			});
			offset += s.population;
		}
	} else {
		// Default: all boids belong to species 0
		speciesRanges.push({ id: 0, start: 0, end: boidCount });
	}

	for (let i = 0; i < boidCount; i++) {
		const x = safeMinX + Math.random() * safeWidth;
		const y = safeMinY + Math.random() * safeHeight;
		positions[i * 2] = x;
		positions[i * 2 + 1] = y;

		// Compute birth color based on angle from canvas center (rainbow wheel)
		const angle = Math.atan2(y - centerY, x - centerX);
		birthColors[i] = (angle + Math.PI) / (2 * Math.PI); // Normalize to [0, 1]

		// Assign species based on ranges
		let assignedSpecies = 0;
		for (const range of speciesRanges) {
			if (i >= range.start && i < range.end) {
				assignedSpecies = range.id;
				break;
			}
		}
		speciesIds[i] = assignedSpecies;
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
	device.queue.writeBuffer(buffers.birthColors, 0, birthColors);
	device.queue.writeBuffer(buffers.speciesIds, 0, speciesIds);
}

export function clearTrails(
	device: GPUDevice,
	buffers: SimulationBuffers,
	boidCount: number,
	// eslint-disable-next-line @typescript-eslint/no-unused-vars
	_trailLength?: number
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
	u32View[offset++] = data.params.cursorVortex ? 1 : 0;
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
	// Algorithm-specific parameters
	u32View[offset++] = data.params.kNeighbors;
	u32View[offset++] = data.params.sampleCount;
	f32View[offset++] = data.params.idealDensity;
	// Simulation timing
	f32View[offset++] = data.params.timeScale;

	device.queue.writeBuffer(buffer, 0, uniformArray);
}

// Minimum perception for buffer pre-allocation (matches UI min)
const MIN_PERCEPTION_FOR_ALLOCATION = 20;

// Maximum trail length for buffer pre-allocation (matches UI max)
export const MAX_TRAIL_LENGTH = 100;

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

// Update species parameters buffer
export function updateSpeciesParams(
	device: GPUDevice,
	buffer: GPUBuffer,
	species: Species[]
): void {
	// Layout: 5 vec4s per species (20 floats = 80 bytes per species)
	// vec4[0]: [alignment, cohesion, separation, perception]
	// vec4[1]: [maxSpeed, maxForce, hue, headShape]
	// vec4[2]: [saturation, lightness, size, trailLength]
	// vec4[3]: [rebels, cursorForce, cursorResponse, cursorVortex]
	// vec4[4]: [alphaMode, unused, unused, unused]
	const data = new Float32Array(MAX_SPECIES * 5 * 4);

	for (const s of species) {
		if (s.id >= MAX_SPECIES) continue;
		const offset = s.id * 20;
		// vec4[0]
		data[offset + 0] = s.alignment;
		data[offset + 1] = s.cohesion;
		data[offset + 2] = s.separation;
		data[offset + 3] = s.perception;
		// vec4[1]
		data[offset + 4] = s.maxSpeed;
		data[offset + 5] = s.maxForce;
		data[offset + 6] = s.hue / 360.0; // Normalize to [0, 1]
		data[offset + 7] = s.headShape;
		// vec4[2]
		data[offset + 8] = (s.saturation ?? 70) / 100.0; // Normalize to [0, 1]
		data[offset + 9] = (s.lightness ?? 55) / 100.0; // Normalize to [0, 1]
		data[offset + 10] = s.size ?? 1.5;
		data[offset + 11] = s.trailLength ?? 30;
		// vec4[3]
		data[offset + 12] = s.rebels ?? 0.02;
		data[offset + 13] = s.cursorForce ?? 0.5;
		data[offset + 14] = s.cursorResponse ?? 1; // 1 = Repel by default
		data[offset + 15] = s.cursorVortex ? 1.0 : 0.0; // 1 = vortex enabled
		// vec4[4]
		data[offset + 16] = s.alphaMode ?? 3; // 3 = Turning by default
		data[offset + 17] = 0; // unused
		data[offset + 18] = 0; // unused
		data[offset + 19] = 0; // unused
	}

	device.queue.writeBuffer(buffer, 0, data);
}

// Update interaction matrix buffer
export function updateInteractionMatrix(
	device: GPUDevice,
	buffer: GPUBuffer,
	species: Species[]
): void {
	// Layout: MAX_SPECIES × MAX_SPECIES vec4s
	// Each vec4: [behavior, strength, range, padding]
	const data = new Float32Array(MAX_SPECIES * MAX_SPECIES * 4);

	// Default: all interactions are "ignore" (behavior = 0, strength = 0)
	// This is already initialized to zeros

	for (const s of species) {
		if (s.id >= MAX_SPECIES) continue;

		for (const rule of s.interactions) {
			if (rule.targetSpecies === -1) {
				// Apply to all other species
				for (let targetId = 0; targetId < MAX_SPECIES; targetId++) {
					if (targetId === s.id) continue; // Skip self
					// Only set if no specific rule exists (specific rules take priority)
					const offset = (s.id * MAX_SPECIES + targetId) * 4;
					// Check if already set by a specific rule
					if (data[offset + 0] === 0 && data[offset + 1] === 0) {
						data[offset + 0] = rule.behavior;
						data[offset + 1] = rule.strength;
						data[offset + 2] = rule.range;
						data[offset + 3] = 0; // padding
					}
				}
			} else if (rule.targetSpecies >= 0 && rule.targetSpecies < MAX_SPECIES) {
				// Specific target species - always overwrite
				const offset = (s.id * MAX_SPECIES + rule.targetSpecies) * 4;
				data[offset + 0] = rule.behavior;
				data[offset + 1] = rule.strength;
				data[offset + 2] = rule.range;
				data[offset + 3] = 0; // padding
			}
		}
	}

	device.queue.writeBuffer(buffer, 0, data);
}

// Update wall texture from CPU data
export function updateWallTexture(
	device: GPUDevice,
	wallTexture: GPUTexture,
	wallData: Uint8Array,
	width: number,
	height: number
): void {
	device.queue.writeTexture(
		{ texture: wallTexture },
		wallData.buffer,
		{ offset: wallData.byteOffset, bytesPerRow: width, rowsPerImage: height },
		{ width, height, depthOrArrayLayers: 1 }
	);
}

// Create a new wall texture (for resize)
export function createWallTexture(
	device: GPUDevice,
	canvasWidth: number,
	canvasHeight: number
): GPUTexture {
	const wallTextureWidth = Math.ceil(canvasWidth / WALL_TEXTURE_SCALE);
	const wallTextureHeight = Math.ceil(canvasHeight / WALL_TEXTURE_SCALE);
	return device.createTexture({
		size: [wallTextureWidth, wallTextureHeight, 1],
		format: 'r8unorm',
		usage:
			GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT
	});
}
