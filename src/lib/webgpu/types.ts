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
	Species = 7
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
// MULTI-SPECIES SYSTEM
// ============================================================================

export const MAX_SPECIES = 7;

// Head shapes for distinguishing species visually (proper polygons)
export enum HeadShape {
	Triangle = 0, // 3-sided polygon
	Square = 1, // 4-sided polygon
	Pentagon = 2, // 5-sided polygon
	Hexagon = 3, // 6-sided polygon
	Arrow = 4 // Arrow/chevron shape
}

// Inter-species interaction behaviors
export enum InteractionBehavior {
	Ignore = 0, // No interaction
	Avoid = 1, // Flee from other species
	Pursue = 2, // Chase/hunt other species
	Attract = 3, // Gentle attraction toward other species
	Mirror = 4, // Match their velocity (alignment with other species)
	Orbit = 5 // Circle around them (perpendicular force)
}

// Per-species cursor response
export enum CursorResponse {
	Attract = 0, // Species is attracted to cursor
	Repel = 1, // Species is repelled by cursor
	Ignore = 2 // Species ignores cursor
}

// Interaction rule for how one species interacts with another
export interface InteractionRule {
	targetSpecies: number | -1; // -1 means "all others"
	behavior: InteractionBehavior;
	strength: number; // 0 to 1 (intensity of the interaction)
	range: number; // Perception range for this interaction (0 = use default perception)
}

// Species definition
export interface Species {
	id: number; // 0 to MAX_SPECIES-1
	name: string; // User-editable name
	headShape: HeadShape;
	hue: number; // Base hue for this species (0-360)
	saturation: number; // Color saturation (0-100)
	lightness: number; // Color lightness (0-100)
	population: number; // Count of boids in this species

	// Per-species visual/rendering parameters
	size: number; // Boid size for this species
	trailLength: number; // Trail length for this species

	// Per-species flocking parameters
	alignment: number;
	cohesion: number;
	separation: number;
	perception: number;
	maxSpeed: number;
	maxForce: number;
	rebels: number; // Percentage of rebels in this species (0-1)

	// Per-species cursor interaction
	cursorForce: number; // How strongly this species responds to cursor
	cursorResponse: CursorResponse; // How this species responds to cursor
	cursorVortex: boolean; // Whether this species responds to vortex/rotation

	// Inter-species interaction rules
	interactions: InteractionRule[];
}

// Default species colors (hues) - evenly spaced for maximum distinction
export const SPECIES_HUES = [
	210, // Blue
	20, // Red-Orange
	120, // Green
	280, // Purple
	55, // Yellow-Orange
	180, // Cyan
	330 // Pink
];

// Default species names
export const SPECIES_NAMES = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta', 'Eta'];

// Create a default species
export function createDefaultSpecies(id: number, population: number): Species {
	// Cycle through available shapes (0-4: Triangle, Square, Pentagon, Hexagon, Arrow)
	const numShapes = 5;
	return {
		id,
		name: SPECIES_NAMES[id] || `Species ${id + 1}`,
		headShape: (id % numShapes) as HeadShape,
		hue: SPECIES_HUES[id] || (id * 51) % 360,
		saturation: 70, // Default saturation
		lightness: 55, // Default lightness
		population,
		// Per-species visual parameters
		size: 1.5, // Default boid size
		trailLength: 30, // Default trail length
		// Flocking parameters
		alignment: 1.3,
		cohesion: 0.6,
		separation: 1.5,
		perception: 80,
		maxSpeed: 4,
		maxForce: 0.1,
		rebels: 0.02, // 2% rebels by default
		// Cursor interaction
		cursorForce: 0.5, // Medium response to cursor
		cursorResponse: CursorResponse.Repel, // Default: repelled by cursor
		cursorVortex: false, // Default: no vortex response
		// Inter-species interactions
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Avoid,
				strength: 0.5,
				range: 0 // Use default perception
			}
		]
	};
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
	// Multi-species
	species: Species[]; // Array of species definitions
	activeSpeciesId: number; // Currently selected species in UI
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
	// Multi-species buffers
	speciesIds: GPUBuffer; // u32 per boid - which species each boid belongs to
	speciesParams: GPUBuffer; // Per-species flocking parameters (alignment, cohesion, etc.)
	interactionMatrix: GPUBuffer; // MAX_SPECIES × MAX_SPECIES interaction rules
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
	// Multi-species defaults
	species: [createDefaultSpecies(0, 7000)],
	activeSpeciesId: 0
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
