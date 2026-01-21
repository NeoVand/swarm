// Buffer creation and management

import type { SimulationBuffers, SimulationParams, CursorState, CurvePoint } from './types';
import {
	WORKGROUP_SIZE,
	WALL_TEXTURE_SCALE,
	CA_CURVE_SAMPLES,
	CA_CURVE_COUNT,
	CA_BOID_STATE_SIZE,
	CA_DEFAULT_CURVES
} from './types';

export interface BufferConfig {
	boidCount: number; // Initial active population
	maxBoidCount: number; // Buffer size (headroom for growth)
	trailLength: number;
	gridWidth: number;
	gridHeight: number;
	canvasWidth: number;
	canvasHeight: number;
}

export function createBuffers(device: GPUDevice, config: BufferConfig): SimulationBuffers {
	const { maxBoidCount, canvasWidth, canvasHeight } = config;

	// Use max grid size for grid buffers to avoid reallocation when perception changes
	const { maxTotalCells } = calculateMaxGridDimensions(canvasWidth, canvasHeight);

	// All boid buffers sized for maxBoidCount to allow population growth
	// Position buffers (ping-pong): vec2<f32> per boid
	const positionA = device.createBuffer({
		size: maxBoidCount * 2 * 4, // 2 floats × 4 bytes
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	const positionB = device.createBuffer({
		size: maxBoidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Velocity buffers (ping-pong): vec2<f32> per boid
	const velocityA = device.createBuffer({
		size: maxBoidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	const velocityB = device.createBuffer({
		size: maxBoidCount * 2 * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Trail buffer: vec2<f32> × MAX_TRAIL_LENGTH per boid (pre-allocated for max)
	const trails = device.createBuffer({
		size: maxBoidCount * MAX_TRAIL_LENGTH * 2 * 4,
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
		size: maxBoidCount * 4,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// Boid cell indices: u32 per boid
	const boidCellIndices = device.createBuffer({
		size: maxBoidCount * 4,
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
		size: maxBoidCount * 4,
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

	// ========================================================================
	// CA SYSTEM BUFFERS
	// ========================================================================

	// Per-boid CA state: age (f32) + vitality (f32) + alive (u32) + padding (u32)
	// Total: 16 bytes per boid, aligned for vec4
	// Single buffer with in-place updates (small race conditions acceptable for visual effects)
	const boidState = device.createBuffer({
		label: 'Boid State',
		size: maxBoidCount * CA_BOID_STATE_SIZE,
		usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
	});

	// CA curves as 1D texture: 4 curves × 128 samples = 512 pixels (r32float)
	// Layout: [vitalityInfluence(128), alignment(128), cohesion(128), separation(128)]
	const caCurvesTexture = device.createTexture({
		label: 'CA Curves Texture',
		size: { width: CA_CURVE_SAMPLES * CA_CURVE_COUNT }, // 512 pixels
		format: 'r32float',
		dimension: '1d',
		usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST
	});

	// Initialize curves to zero (neutral) to prevent garbage values on first frames
	// This ensures y=0 (no effect) until proper curves are uploaded
	const zeroData = new Float32Array(CA_CURVE_SAMPLES * CA_CURVE_COUNT);
	device.queue.writeTexture(
		{ texture: caCurvesTexture },
		zeroData,
		{ bytesPerRow: CA_CURVE_COUNT * CA_CURVE_SAMPLES * 4 },
		{ width: CA_CURVE_COUNT * CA_CURVE_SAMPLES }
	);

	// Sampler for CA curves (nearest neighbor, clamp)
	const caCurvesSampler = device.createSampler({
		label: 'CA Curves Sampler',
		magFilter: 'nearest',
		minFilter: 'nearest',
		addressModeU: 'clamp-to-edge'
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
		// CA buffers
		boidState,
		caCurvesTexture,
		caCurvesSampler
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
	// CA buffers
	buffers.boidState.destroy();
	buffers.caCurvesTexture.destroy();
	// Note: Samplers don't need to be destroyed
}

export function initializeBoids(
	device: GPUDevice,
	buffers: SimulationBuffers,
	initialCount: number, // Initial active population
	maxBoidCount: number, // Buffer size (for growth headroom)
	canvasWidth: number,
	canvasHeight: number
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

	// Create initial positions and birth colors for ALL slots (up to maxBoidCount)
	// initialCount boids are alive on-screen, rest are dead (birth pool)
	const positions = new Float32Array(maxBoidCount * 2);
	const birthColors = new Float32Array(maxBoidCount);
	const centerX = canvasWidth * 0.5;
	const centerY = canvasHeight * 0.5;

	for (let i = 0; i < maxBoidCount; i++) {
		if (i < initialCount) {
			// Alive boids - random on-screen position
			const x = safeMinX + Math.random() * safeWidth;
			const y = safeMinY + Math.random() * safeHeight;
			positions[i * 2] = x;
			positions[i * 2 + 1] = y;

			// Compute birth color based on angle from canvas center (rainbow wheel)
			const angle = Math.atan2(y - centerY, x - centerX);
			birthColors[i] = (angle + Math.PI) / (2 * Math.PI); // Normalize to [0, 1]
		} else {
			// Dead boids (birth pool) - off-screen, available for birth
			positions[i * 2] = -99999;
			positions[i * 2 + 1] = -99999;
			birthColors[i] = 0;
		}
	}

	// Create initial velocities (random directions, moderate speed)
	// Dead boids in birth pool have zero velocity
	const velocities = new Float32Array(maxBoidCount * 2);
	for (let i = 0; i < maxBoidCount; i++) {
		if (i < initialCount) {
			const angle = Math.random() * Math.PI * 2;
			const speed = 1 + Math.random() * 2;
			velocities[i * 2] = Math.cos(angle) * speed;
			velocities[i * 2 + 1] = Math.sin(angle) * speed;
		} else {
			velocities[i * 2] = 0;
			velocities[i * 2 + 1] = 0;
		}
	}

	// Upload to GPU
	device.queue.writeBuffer(buffers.positionA, 0, positions);
	device.queue.writeBuffer(buffers.positionB, 0, positions);
	device.queue.writeBuffer(buffers.velocityA, 0, velocities);
	device.queue.writeBuffer(buffers.velocityB, 0, velocities);
	device.queue.writeBuffer(buffers.birthColors, 0, birthColors);
}

export function clearTrails(
	device: GPUDevice,
	buffers: SimulationBuffers,
	maxBoidCount: number
): void {
	// Zero out trail buffer (full pre-allocated size for all possible boids)
	const zeros = new Float32Array(maxBoidCount * MAX_TRAIL_LENGTH * 2);
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

	// CA System parameters (with defensive defaults)
	u32View[offset++] = data.params.caEnabled ? 1 : 0;
	u32View[offset++] = data.params.agingEnabled ? 1 : 0;
	f32View[offset++] = data.params.maxAge ?? 20.0;
	f32View[offset++] = data.params.vitalityGain ?? 1.0;
	f32View[offset++] = data.params.birthVitalityThreshold ?? 0.3;
	f32View[offset++] = data.params.birthFieldThreshold ?? 0.3;
	f32View[offset++] = data.params.vitalityConservation ?? 1.0;
	f32View[offset++] = data.params.birthSplit ?? 0.5;
	f32View[offset++] = data.params.ageSpread ?? 0.5;
	u32View[offset++] = data.params.populationCap ?? 1;
	u32View[offset++] = data.params.maxPopulation ?? 15000;

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

// ============================================================================
// CA SYSTEM FUNCTIONS
// ============================================================================

/**
 * Initialize CA state for all boids.
 * 80% start alive with distributed ages, 20% start dead (birth pool).
 * @param maxAge Maximum lifespan for age distribution
 * @param ageSpread Fraction of maxAge to spread initial ages (0-1)
 */
/**
 * Beta distribution random number (for nice 0-1 distributions)
 * alpha=2, beta=2 gives a nice bell curve centered at 0.5
 * alpha=2, beta=5 gives more low values
 * alpha=5, beta=2 gives more high values
 */
function betaRandom(alpha: number, beta: number): number {
	// Simple approximation using the inverse transform
	// For alpha=beta=2, this gives a nice symmetric distribution
	const u = Math.random();
	const v = Math.random();
	const x = Math.pow(u, 1 / alpha);
	const y = Math.pow(v, 1 / beta);
	return x / (x + y);
}

export function initializeCAState(
	device: GPUDevice,
	buffers: SimulationBuffers,
	initialCount: number, // Initial active population
	maxBoidCount: number, // Buffer size (for growth headroom)
	maxAge: number = 20,
	ageSpread: number = 0.5
): void {
	// Per-boid state: [age, vitality, alive, padding] - all floats
	// initialCount boids are alive with distributed vitality
	// Rest (up to maxBoidCount) are dead, available as birth pool
	const stateData = new Float32Array(maxBoidCount * 4);

	for (let i = 0; i < maxBoidCount; i++) {
		const offset = i * 4;
		if (i < initialCount) {
			// Use beta distribution for nice vitality spread
			// ageSpread controls how spread out the distribution is:
			// 0 = all start at vitality 1.0
			// 0.5 = nice bell curve centered around 0.5-0.7
			// 1.0 = wider spread from 0.2 to 1.0
			const baseVitality = betaRandom(2 + (1 - ageSpread) * 3, 2);
			// Ensure minimum vitality of 0.2 (not dead)
			const initialVitality = 0.2 + baseVitality * 0.8;
			// Age correlates with vitality (lower vitality = older)
			const initialAge = (1.0 - initialVitality) * maxAge * ageSpread;
			
			stateData[offset + 0] = initialAge;
			stateData[offset + 1] = initialVitality;
			stateData[offset + 2] = 1.0; // alive = 1.0
		} else {
			// Dead boids (birth pool) - available for new births
			stateData[offset + 0] = 0.0;
			stateData[offset + 1] = 0.0;
			stateData[offset + 2] = 0.0; // dead
		}
		stateData[offset + 3] = 0.0; // padding
	}

	device.queue.writeBuffer(buffers.boidState, 0, stateData);
	// Note: Don't initialize curves here - let the store handle curve uploads
	// via caCurvesDirty subscription to preserve user modifications
}

/**
 * Initialize CA curves with default values.
 */
export function initializeDefaultCACurves(device: GPUDevice, buffers: SimulationBuffers): void {
	updateCACurves(device, buffers, {
		vitalityInfluence: CA_DEFAULT_CURVES.vitalityInfluence,
		alignment: CA_DEFAULT_CURVES.alignment,
		cohesion: CA_DEFAULT_CURVES.cohesion,
		separation: CA_DEFAULT_CURVES.separation,
		birth: CA_DEFAULT_CURVES.birth
	});
}

/**
 * Monotonic cubic Hermite interpolation (Fritsch-Carlson method).
 * Produces smooth curves without overshoot between control points.
 */
function monotonicCubicInterpolation(points: CurvePoint[], xVal: number): number {
	const n = points.length;
	if (n === 0) return 0;
	if (n === 1) return points[0].y;

	// Sort points by x
	const sorted = [...points].sort((a, b) => a.x - b.x);

	// Handle out-of-range queries
	if (xVal <= sorted[0].x) return sorted[0].y;
	if (xVal >= sorted[n - 1].x) return sorted[n - 1].y;

	// Find the segment containing xVal
	let i = 0;
	while (i < n - 1 && sorted[i + 1].x < xVal) i++;

	// Calculate deltas (segment lengths) and slopes
	const deltas: number[] = [];
	const slopes: number[] = [];
	for (let j = 0; j < n - 1; j++) {
		const dx = sorted[j + 1].x - sorted[j].x;
		deltas.push(dx);
		slopes.push(dx === 0 ? 0 : (sorted[j + 1].y - sorted[j].y) / dx);
	}

	// Calculate tangents at each point (Fritsch-Carlson method)
	const tangents: number[] = [];
	for (let j = 0; j < n; j++) {
		if (j === 0) {
			tangents.push(slopes[0]);
		} else if (j === n - 1) {
			tangents.push(slopes[n - 2]);
		} else {
			const m0 = slopes[j - 1];
			const m1 = slopes[j];

			if (m0 * m1 <= 0) {
				tangents.push(0);
			} else {
				const w0 = 2 * deltas[j] + deltas[j - 1];
				const w1 = deltas[j] + 2 * deltas[j - 1];
				tangents.push((w0 + w1) / (w0 / m0 + w1 / m1));
			}
		}
	}

	// Ensure monotonicity
	for (let j = 0; j < n - 1; j++) {
		const m = slopes[j];
		if (m === 0) {
			tangents[j] = 0;
			tangents[j + 1] = 0;
		} else {
			const alpha = tangents[j] / m;
			const beta = tangents[j + 1] / m;
			const tau = alpha * alpha + beta * beta;

			if (tau > 9) {
				const s = 3 / Math.sqrt(tau);
				tangents[j] = s * alpha * m;
				tangents[j + 1] = s * beta * m;
			}
		}
	}

	// Hermite interpolation
	const x0 = sorted[i].x;
	const x1 = sorted[i + 1].x;
	const y0 = sorted[i].y;
	const y1 = sorted[i + 1].y;
	const h = x1 - x0;
	const t = (xVal - x0) / h;
	const t2 = t * t;
	const t3 = t2 * t;

	const h00 = 2 * t3 - 3 * t2 + 1;
	const h10 = t3 - 2 * t2 + t;
	const h01 = -2 * t3 + 3 * t2;
	const h11 = t3 - t2;

	return h00 * y0 + h10 * h * tangents[i] + h01 * y1 + h11 * h * tangents[i + 1];
}

/**
 * Sample a curve to fixed-size array for GPU upload.
 */
export function sampleCurve(points: CurvePoint[], numSamples: number = CA_CURVE_SAMPLES): number[] {
	if (!points || points.length < 2) {
		return new Array(numSamples).fill(0);
	}

	const samples: number[] = [];
	for (let i = 0; i < numSamples; i++) {
		const x = i / (numSamples - 1);
		const y = monotonicCubicInterpolation(points, x);
		samples.push(y);
	}

	return samples;
}

/**
 * Update all CA curves on the GPU.
 * Curves are sampled to 128 points each and concatenated into a single buffer.
 */
export function updateCACurves(
	device: GPUDevice,
	buffers: SimulationBuffers,
	curves: {
		vitalityInfluence: CurvePoint[];
		alignment: CurvePoint[];
		cohesion: CurvePoint[];
		separation: CurvePoint[];
		birth: CurvePoint[];
	}
): void {
	const allSamples = new Float32Array(CA_CURVE_COUNT * CA_CURVE_SAMPLES);

	// Sample each curve and pack into texture data
	const curveArrays = [
		sampleCurve(curves.vitalityInfluence),
		sampleCurve(curves.alignment),
		sampleCurve(curves.cohesion),
		sampleCurve(curves.separation),
		sampleCurve(curves.birth)
	];

	for (let curveIdx = 0; curveIdx < CA_CURVE_COUNT; curveIdx++) {
		const offset = curveIdx * CA_CURVE_SAMPLES;
		for (let i = 0; i < CA_CURVE_SAMPLES; i++) {
			allSamples[offset + i] = curveArrays[curveIdx][i];
		}
	}

	// Write to 1D texture
	device.queue.writeTexture(
		{ texture: buffers.caCurvesTexture },
		allSamples,
		{ bytesPerRow: CA_CURVE_COUNT * CA_CURVE_SAMPLES * 4 },
		{ width: CA_CURVE_COUNT * CA_CURVE_SAMPLES }
	);
}

/**
 * Update a single CA curve on the GPU (updates entire texture for simplicity).
 * For a single curve, we need to read-modify-write which isn't efficient,
 * so we recommend using updateCACurves for all curves at once.
 */
export function updateSingleCACurve(
	device: GPUDevice,
	buffers: SimulationBuffers,
	curveIndex: number,
	points: CurvePoint[]
): void {
	// Note: 1D textures don't support partial updates easily
	// For now, this function is a no-op - use updateCACurves instead
	console.warn('updateSingleCACurve: Use updateCACurves for texture-based curves');
}
