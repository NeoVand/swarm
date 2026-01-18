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
	Disk = 1,        // Filled circle - point attractor at center
	Dot = 2,         // Small intense point attractor
	Vortex = 3,      // Swirling force - boids orbit tangentially
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
	cohesion: 1.0,
	separation: 1.5,
	perception: 80,
	maxSpeed: 4,
	maxForce: 0.1,
	noise: 0.35,
	rebels: 0.02,
	boundaryMode: BoundaryMode.Plane,
	cursorMode: CursorMode.Attract,
	cursorShape: CursorShape.Dot,
	cursorForce: 0.5,
	cursorRadius: 50,
	boidSize: 1,
	trailLength: 70,
	colorMode: ColorMode.Orientation,
	colorSpectrum: ColorSpectrum.Rainbow,
	sensitivity: 1.0,
	population: 5000,
	algorithmMode: AlgorithmMode.HashFree,
	// Algorithm-specific defaults
	kNeighbors: 12,      // Topological K-NN
	sampleCount: 32,     // Stochastic
	idealDensity: 5.0    // Density Adaptive
};

// Uniform buffer layout (must match WGSL struct)
export const UNIFORM_BUFFER_SIZE = 256; // Padded for alignment

export const WORKGROUP_SIZE = 256;
