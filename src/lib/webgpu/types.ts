// Simulation parameter types and enums

export enum BoundaryMode {
	Plane = 0,
	CylinderX = 1,
	CylinderY = 2,
	Torus = 3,
	MobiusX = 4,
	MobiusY = 5,
	KleinX = 6,
	KleinY = 7,
	ProjectivePlane = 8
}

export enum ColorMode {
	Speed = 0,
	Orientation = 1,
	Neighbors = 2,
	Acceleration = 3,
	Turning = 4,
	None = 5,
	Density = 6,
	Vitality = 7 // CA system: color based on boid vitality/life-force
}

export enum ColorSpectrum {
	Chrome = 0,
	Ocean = 1,
	Bands = 2,
	Rainbow = 3,
	Mono = 4
}

export enum CursorMode {
	Off = 0,
	Attract = 1,
	Repel = 2
}

export enum CursorShape {
	Ring = 0, // Boids attracted to the circumference
	Disk = 1 // Filled circle - attraction/repulsion area
}

export enum AlgorithmMode {
	TopologicalKNN = 0, // k-nearest neighbors with smooth kernels
	SmoothMetric = 1, // Metric neighbors with smooth kernels + jitter
	HashFree = 2, // Per-boid randomized grid offset (no global seams)
	StochasticSample = 3, // Random neighbor sampling with distance weighting
	DensityAdaptive = 4 // Hash-free with advanced density-adaptive forces
}

export enum WallTool {
	None = 0, // Normal cursor interaction mode
	Pencil = 1, // Draw walls
	Eraser = 2 // Erase walls
}

export enum WallBrushShape {
	Solid = 0, // Filled circle
	Ring = 1 // Hollow ring
}

// ============================================================================
// CELLULAR AUTOMATON TYPES
// ============================================================================

/**
 * Population cap behavior when CA system is active.
 * Controls how the simulation handles population growth.
 */
export enum PopulationCap {
	None = 0, // Unlimited growth (until buffer full)
	Soft = 1, // Birth probability decreases as approaching cap
	Hard = 2 // No births when at cap
}

/**
 * A control point for influence/modulation curves.
 * Used for vitality influence, force modulation, etc.
 */
export interface CurvePoint {
	x: number; // Input value (0-1), e.g., vitality or distance
	y: number; // Output value, range depends on curve type
}

/**
 * Default curve presets for quick selection.
 * Each preset defines a characteristic curve shape.
 */
export const CURVE_PRESETS = {
	linear: [
		{ x: 0, y: 0 },
		{ x: 1, y: 1 }
	],
	constant: [
		{ x: 0, y: 1 },
		{ x: 1, y: 1 }
	],
	step: [
		{ x: 0, y: 0 },
		{ x: 0.48, y: 0 },
		{ x: 0.52, y: 1 },
		{ x: 1, y: 1 }
	],
	soft: [
		{ x: 0, y: 0 },
		{ x: 0.25, y: 0.05 },
		{ x: 0.5, y: 0.5 },
		{ x: 0.75, y: 0.95 },
		{ x: 1, y: 1 }
	],
	inhibit: [
		{ x: 0, y: 0 },
		{ x: 0.3, y: -0.5 },
		{ x: 0.7, y: -0.7 },
		{ x: 1, y: -0.4 }
	],
	boost: [
		{ x: 0, y: 0.5 },
		{ x: 0.5, y: 1.5 },
		{ x: 1, y: 1 }
	],
	decay: [
		{ x: 0, y: 1 },
		{ x: 0.3, y: 0.8 },
		{ x: 0.7, y: 0.3 },
		{ x: 1, y: 0 }
	],
	wave: [
		{ x: 0, y: 0 },
		{ x: 0.25, y: 1 },
		{ x: 0.5, y: 0 },
		{ x: 0.75, y: 1 },
		{ x: 1, y: 0.5 }
	]
} as const;

export type CurvePresetName = keyof typeof CURVE_PRESETS;

// ============================================================================
// SIMULATION PARAMETERS
// ============================================================================

export interface SimulationParams {
	alignment: number;
	cohesion: number;
	separation: number;
	perception: number;
	maxSpeed: number;
	maxForce: number;
	noise: number;
	rebels: number;
	boundaryMode: BoundaryMode;
	cursorMode: CursorMode;
	cursorShape: CursorShape;
	cursorVortex: boolean; // Independent vortex toggle (adds rotation)
	cursorForce: number;
	cursorRadius: number;
	boidSize: number;
	trailLength: number;
	colorMode: ColorMode;
	colorSpectrum: ColorSpectrum;
	sensitivity: number;
	population: number;
	algorithmMode: AlgorithmMode;
	// Algorithm-specific parameters
	kNeighbors: number; // Topological K-NN: number of neighbors (4-24)
	sampleCount: number; // Stochastic: random samples per frame (8-64)
	idealDensity: number; // Density Adaptive: target neighbor density (1-10)
	// Simulation timing
	timeScale: number; // Simulation speed multiplier (0.25-2.0)
	// Wall drawing
	wallBrushSize: number; // Brush size for pencil/eraser (10-100 pixels)
	wallBrushShape: WallBrushShape; // Brush shape

	// ========================================================================
	// CELLULAR AUTOMATON PARAMETERS
	// ========================================================================

	// Master toggle
	caEnabled: boolean; // Enable/disable entire CA system

	// Aging system
	agingEnabled: boolean; // Natural death by time
	maxAge: number; // Maximum lifespan in seconds (1-60)

	// Vitality dynamics (continuous field model)
	vitalityGain: number; // Gain multiplier for neighbor influence (0.1-2.0)

	// Birth/replication
	birthVitalityThreshold: number; // Parent vitality required to birth (0-1)
	birthFieldThreshold: number; // Weighted field strength required (0-2)
	birthSplit: number; // Fraction of vitality given to child (0-1, default 0.5)
	vitalityConservation: number; // How much total vitality preserved in birth (0.5-1.0)

	// Initial distribution
	ageSpread: number; // Initial age spread as fraction of maxAge (0-1)

	// Population limits
	populationCap: PopulationCap; // How to handle population limits
	maxPopulation: number; // Maximum allowed population

	// Curves are stored as CurvePoint[] in the store, not here
	// They get sampled to 128 f32 values for GPU upload
}

export interface CursorState {
	x: number;
	y: number;
	isPressed: boolean;
	isActive: boolean;
}

export interface GPUContext {
	device: GPUDevice;
	context: GPUCanvasContext;
	format: GPUTextureFormat;
	canvas: HTMLCanvasElement;
}

export interface SimulationBuffers {
	positionA: GPUBuffer;
	positionB: GPUBuffer;
	velocityA: GPUBuffer;
	velocityB: GPUBuffer;
	trails: GPUBuffer;
	cellCounts: GPUBuffer;
	cellOffsets: GPUBuffer;
	prefixSums: GPUBuffer;
	sortedIndices: GPUBuffer;
	boidCellIndices: GPUBuffer;
	uniforms: GPUBuffer;
	trailHead: GPUBuffer;
	birthColors: GPUBuffer; // Stores initial position-based color per boid
	wallTexture: GPUTexture; // Stores wall data for obstacle avoidance
	wallSampler: GPUSampler; // Sampler for wall texture

	// CA System buffers
	boidState: GPUBuffer; // Per-boid CA state (age, vitality, alive) - single buffer, in-place updates
	caCurvesTexture: GPUTexture; // All CA curves as 1D texture (512 pixels, r32float)
	caCurvesSampler: GPUSampler; // Sampler for curve lookup
}

export interface ComputePipelines {
	clear: GPUComputePipeline;
	count: GPUComputePipeline;
	prefixSum: GPUComputePipeline;
	prefixSumAggregate: GPUComputePipeline;
	scatter: GPUComputePipeline;
	simulate: GPUComputePipeline;
	updateTrails: GPUComputePipeline;
}

export interface RenderPipelines {
	boid: GPURenderPipeline;
	trail: GPURenderPipeline;
}

export interface BindGroups {
	compute: GPUBindGroup[];
	render: GPUBindGroup[];
}

export const DEFAULT_PARAMS: SimulationParams = {
	alignment: 1.3,
	cohesion: 0.6,
	separation: 1.5,
	perception: 80,
	maxSpeed: 4,
	maxForce: 0.1,
	noise: 0.0,
	rebels: 0.02,
	boundaryMode: BoundaryMode.Plane,
	cursorMode: CursorMode.Repel,
	cursorShape: CursorShape.Disk,
	cursorVortex: false,
	cursorForce: 0.5,
	cursorRadius: 50,
	boidSize: 1.5,
	trailLength: 30,
	colorMode: ColorMode.Orientation,
	colorSpectrum: ColorSpectrum.Rainbow,
	sensitivity: 1.0,
	population: 7000,
	algorithmMode: AlgorithmMode.SmoothMetric,
	// Algorithm-specific defaults
	kNeighbors: 12, // Topological K-NN
	sampleCount: 32, // Stochastic
	idealDensity: 5.0, // Density Adaptive
	// Simulation timing
	timeScale: 1.0, // Normal speed
	// Wall drawing
	wallBrushSize: 30, // Default brush size
	wallBrushShape: WallBrushShape.Solid, // Default brush shape

	// CA System defaults
	caEnabled: true, // On by default
	agingEnabled: true, // Natural aging on when CA enabled
	maxAge: 20, // 20 seconds default lifespan

	// Vitality dynamics
	vitalityGain: 1.0, // Default gain multiplier (1.0 = balanced)

	// Birth settings
	birthVitalityThreshold: 0.3, // Parent needs 30% vitality to birth
	birthFieldThreshold: 0.3, // Neighbor field strength required
	birthSplit: 0.5, // 50/50 split between parent and child
	vitalityConservation: 1.0, // Total vitality preserved (parent + child = parent_before)

	// Initial distribution
	ageSpread: 0.5, // Start with ages spread across 0-50% of lifespan

	// Population limits
	populationCap: PopulationCap.None, // Allow growth by default
	maxPopulation: 50000 // Large headroom for population growth
};

/**
 * Calculate optimal boid population based on canvas dimensions.
 * Aims for a comfortable density that looks good on any screen size.
 *
 * @param width Canvas width in pixels
 * @param height Canvas height in pixels
 * @returns Optimal population count
 */
export function calculateOptimalPopulation(width: number, height: number): number {
	const area = width * height;

	// Target density: roughly 1 boid per 300 square pixels
	// This gives a nice balance - not too sparse, not too crowded
	const density = 300;
	let population = Math.floor(area / density);

	// Clamp to reasonable bounds
	const MIN_POPULATION = 800; // Minimum for visual interest
	const MAX_POPULATION = 15000; // Maximum for performance

	population = Math.max(MIN_POPULATION, Math.min(MAX_POPULATION, population));

	// Round to nearest 500 for cleaner numbers
	population = Math.round(population / 500) * 500;

	return population;
}

// Uniform buffer layout (must match WGSL struct)
export const UNIFORM_BUFFER_SIZE = 256; // Padded for alignment

export const WORKGROUP_SIZE = 256;

// Wall texture is at 1/4 resolution for performance
export const WALL_TEXTURE_SCALE = 4;

// ============================================================================
// CA SYSTEM CONSTANTS
// ============================================================================

/** Number of samples per curve for GPU lookup */
export const CA_CURVE_SAMPLES = 128;

/** Number of curves in the CA system (vitality, alignment, cohesion, separation, birth) */
export const CA_CURVE_COUNT = 5;

/** Curve indices in the concatenated buffer */
export const CA_CURVE_INDICES = {
	VITALITY_INFLUENCE: 0, // Neighbor vitality → contribution to influence sum
	ALIGNMENT: 1, // Own vitality → alignment force multiplier
	COHESION: 2, // Own vitality → cohesion force multiplier
	SEPARATION: 3, // Own vitality → separation force multiplier
	BIRTH: 4 // Neighbor vitality sum → birth probability/threshold
} as const;

/** Per-boid CA state size in bytes: age (f32) + vitality (f32) + alive (u32) + padding (u32) = 16 bytes */
export const CA_BOID_STATE_SIZE = 16;

/**
 * Default curve configurations for CA system.
 * These define sensible starting points for each curve type.
 */
export const CA_DEFAULT_CURVES: Record<string, CurvePoint[]> = {
	// Vitality influence: flat at 0 = no neighbor effect on vitality
	// x = neighbor vitality, y = how much they contribute to your vitality gain
	// Adjust the curve to enable neighbor-based vitality dynamics
	vitalityInfluence: [
		{ x: 0, y: 0 },
		{ x: 1, y: 0 }
	],
	// Force modulation curves: flat at 0 = NO EFFECT
	// y = 0 means normal forces, y > 0 means stronger, y < 0 means weaker
	// These are OFFSETS added to the base multiplier of 1.0
	alignment: [
		{ x: 0, y: 0 },
		{ x: 1, y: 0 }
	],
	cohesion: [
		{ x: 0, y: 0 },
		{ x: 1, y: 0 }
	],
	separation: [
		{ x: 0, y: 0 },
		{ x: 1, y: 0 }
	],
	// Birth curve: controls birth based on neighbor vitality
	// x = neighbor's vitality, y = contribution to birth field
	// Default peaks at 0.5 - medium vitality neighbors contribute most to birth
	birth: [
		{ x: 0, y: 0 },
		{ x: 0.5, y: 0.5 },
		{ x: 1, y: 0 }
	]
};
