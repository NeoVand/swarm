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
	Density = 6
}

export enum ColorSpectrum {
	Chrome = 0,
	Neon = 1,
	Sunset = 2,
	Rainbow = 3,
	Mono = 4
}

export enum CursorMode {
	Off = 0,
	Attract = 1,
	Repel = 2
}

export enum CursorShape {
	Ring = 0,        // Boids attracted to the circumference
	Disk = 1,        // Filled circle - attraction/repulsion area
}

export enum AlgorithmMode {
	TopologicalKNN = 0,    // k-nearest neighbors with smooth kernels
	SmoothMetric = 1,      // Metric neighbors with smooth kernels + jitter
	HashFree = 2,          // Per-boid randomized grid offset (no global seams)
	StochasticSample = 3,  // Random neighbor sampling with distance weighting
	DensityAdaptive = 4,   // Hash-free with advanced density-adaptive forces
}

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
	cursorVortex: boolean;      // Independent vortex toggle (adds rotation)
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
	kNeighbors: number;      // Topological K-NN: number of neighbors (4-24)
	sampleCount: number;     // Stochastic: random samples per frame (8-64)
	idealDensity: number;    // Density Adaptive: target neighbor density (1-10)
	// Simulation timing
	timeScale: number;       // Simulation speed multiplier (0.25-2.0)
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
	alignment: 1.0,
	cohesion: 0.6,
	separation: 1.5,
	perception: 80,
	maxSpeed: 4,
	maxForce: 0.1,
	noise: 0.0,
	rebels: 0.02,
	boundaryMode: BoundaryMode.Plane,
	cursorMode: CursorMode.Attract,
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
	kNeighbors: 12,      // Topological K-NN
	sampleCount: 32,     // Stochastic
	idealDensity: 5.0,   // Density Adaptive
	// Simulation timing
	timeScale: 1.0       // Normal speed
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
	
	// Target density: roughly 1 boid per 250 square pixels
	// This gives a nice balance - not too sparse, not too crowded
	const density = 250;
	let population = Math.floor(area / density);
	
	// Clamp to reasonable bounds
	const MIN_POPULATION = 800;   // Minimum for visual interest
	const MAX_POPULATION = 15000; // Maximum for performance
	
	population = Math.max(MIN_POPULATION, Math.min(MAX_POPULATION, population));
	
	// Round to nearest 500 for cleaner numbers
	population = Math.round(population / 500) * 500;
	
	return population;
}

// Uniform buffer layout (must match WGSL struct)
export const UNIFORM_BUFFER_SIZE = 256; // Padded for alignment

export const WORKGROUP_SIZE = 256;
