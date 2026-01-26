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
	Density = 6, // Position-based (birth color)
	Species = 7,
	LocalDensity = 8, // Computed same-species neighbor density
	Anisotropy = 9, // Computed local structure (edge vs blob)
	Diffusion = 10, // [DEPRECATED - not used]
	Influence = 11, // Spectral Angular - direction from local center
	SpectralRadial = 12, // Spectral Radial - distance from local center
	SpectralAsymmetry = 13, // Spectral Asymmetry - boundary detection
	FlowAngular = 14, // Flow Angular - velocity vs local flow direction
	FlowRadial = 15, // Flow Radial - moving toward/away from center
	FlowDivergence = 16, // Flow Divergence - velocity alignment with neighbors
	TrueTurning = 17 // True Turning - actual angular velocity (how fast turning)
}

export enum ColorSpectrum {
	Chrome = 0,
	Ocean = 1,
	Bands = 2,
	Rainbow = 3,
	Mono = 4
}

// Alpha mode for per-species transparency variation
export enum AlphaMode {
	Solid = 0, // No alpha variation, fully opaque
	Direction = 1, // Alpha based on movement direction
	Speed = 2, // Alpha based on speed
	Turning = 3, // Alpha based on turning rate
	Acceleration = 4, // Alpha based on acceleration
	Density = 5, // Alpha based on local same-species density
	Anisotropy = 6, // Alpha based on local structure (edge vs interior)
	Diffusion = 7, // Alpha based on smoothed feature value
	Influence = 8 // Alpha based on PageRank-like influence
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

export enum WallTool {
	None = 0, // Normal cursor interaction mode
	Pencil = 1, // Draw walls
	Eraser = 2 // Erase walls
}

export enum WallBrushShape {
	Solid = 0, // Filled circle
	Ring = 1 // Hollow ring
}

export enum SpectralMode {
	Angular = 0, // Angular position relative to local center (color wheel effect)
	Radial = 1, // Distance from local center (edge vs core)
	Asymmetry = 2, // Neighborhood asymmetry (boundary detection)
	FlowAngular = 3, // Velocity angle relative to local average flow
	FlowRadial = 4, // Moving toward/away from cluster center
	FlowDivergence = 5 // Velocity alignment with neighbors (coherence)
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
	Flee = 1, // Strong escape response - prey behavior
	Chase = 2, // Predatory pursuit with prediction
	Cohere = 3, // Gentle attraction + partial alignment (mutualistic flocking)
	Align = 4, // Pure velocity matching - information transfer
	Orbit = 5, // Circular motion around target - territorial/escort
	Follow = 6, // Trail behind - leader-follower dynamics
	Guard = 7, // Maintain optimal distance - protective escort
	Disperse = 8, // Explosive scatter - confusion effect
	Mob = 9 // Aggressive swarming - counter-attack behavior
}

// Per-species cursor response
export enum CursorResponse {
	Attract = 0, // Species is attracted to cursor
	Repel = 1, // Species is repelled by cursor
	Ignore = 2 // Species ignores cursor
}

export enum VortexDirection {
	Off = 0, // No vortex rotation
	Clockwise = 1, // Clockwise rotation
	CounterClockwise = 2 // Counter-clockwise rotation
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
	alphaMode: AlphaMode; // What determines alpha/transparency for this species
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
	cursorVortex: VortexDirection; // Vortex rotation direction (Off, Clockwise, CounterClockwise)

	// Inter-species interaction rules
	interactions: InteractionRule[];
}

// Default species colors - tuned per-hue for vibrant, visually distinct appearance
// Each entry: [hue, saturation, lightness]
export const SPECIES_COLORS: [number, number, number][] = [
	[210, 90, 50], // Blue - vibrant, slightly dark
	[25, 95, 58], // Orange - rich, warm
	[145, 75, 40], // Green - toned down (green appears brighter perceptually)
	[275, 85, 68], // Purple - boosted (purple appears darker perceptually)
	[50, 90, 55], // Gold/Yellow - rich, warm
	[185, 85, 50], // Teal/Cyan - saturated, balanced
	[340, 85, 60] // Pink/Magenta - vivid, lively
];

// Legacy exports for backwards compatibility
export const SPECIES_HUES = SPECIES_COLORS.map(([h]) => h);

// Default species names (simple numbered names)
export const SPECIES_NAMES = ['Species 1', 'Species 2', 'Species 3', 'Species 4', 'Species 5', 'Species 6', 'Species 7'];

// Create a default species
export function createDefaultSpecies(id: number, population: number): Species {
	// Cycle through available shapes (0-4: Triangle, Square, Pentagon, Hexagon, Arrow)
	const numShapes = 5;
	const colorIndex = id % SPECIES_COLORS.length;
	const [hue, saturation, lightness] = SPECIES_COLORS[colorIndex] || [((id * 51) % 360), 85, 55];
	return {
		id,
		name: SPECIES_NAMES[id] || `Species ${id + 1}`,
		headShape: (id % numShapes) as HeadShape,
		hue,
		saturation,
		lightness,
		alphaMode: AlphaMode.Turning, // Default: alpha based on turning
		population,
		// Per-species visual parameters
		size: 1.5, // Default boid size
		trailLength: 20, // Default trail length
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
		cursorVortex: VortexDirection.Off, // Default: no vortex rotation
		// Inter-species interactions
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Flee,
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
	cursorVortex: VortexDirection; // Vortex rotation direction (Off, Clockwise, CounterClockwise)
	cursorForce: number;
	cursorRadius: number;
	boidSize: number;
	trailLength: number;
	colorMode: ColorMode;
	colorSpectrum: ColorSpectrum;
	sensitivity: number;
	population: number;
	// Simulation timing
	timeScale: number; // Simulation speed multiplier (0.25-2.0)
	// Dynamics
	globalCollision: number; // 0-1, strength of cross-species collision avoidance
	// Wall drawing
	wallBrushSize: number; // Brush size for pencil/eraser (10-100 pixels)
	wallBrushShape: WallBrushShape; // Brush shape
	// Multi-species
	species: Species[]; // Array of species definitions
	activeSpeciesId: number; // Currently selected species in UI
	// Spectral/Flow metrics algorithm
	enableInfluence: boolean; // Toggle spectral/flow computation
	influenceIterations: number; // 4-8 iterations per frame
	spectralMode: SpectralMode; // Which spectral visualization to compute
	// HSL control sources
	saturationSource: ColorMode; // What controls saturation (Species uses per-species value)
	brightnessSource: ColorMode; // What controls brightness/lightness (Species uses per-species value)
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
	// Metrics buffer for visualization
	metrics: GPUBuffer; // vec4<f32> per boid [density, anisotropy, diffusion, influence]
	// Iterative algorithm ping-pong buffers
	diffuseA: GPUBuffer; // f32 per boid - diffusion feature value (read)
	diffuseB: GPUBuffer; // f32 per boid - diffusion feature value (write)
	rankA: GPUBuffer; // f32 per boid - PageRank influence value (read)
	rankB: GPUBuffer; // f32 per boid - PageRank influence value (write)
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

// Create default species with predefined interactions for interesting dynamics
function createDefaultSpecies1(population: number): Species {
	const base = createDefaultSpecies(0, population);
	// Species 1: Main flock - attracted to cursor, flees from other species
	return {
		...base,
		cursorResponse: CursorResponse.Attract, // Attracted to cursor
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Flee,
				strength: 0.6,
				range: 0
			}
		]
	};
}

function createDefaultSpecies2(population: number): Species {
	const base = createDefaultSpecies(1, population);
	// Species 2: Secondary group - flees from all others
	return {
		...base,
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Flee,
				strength: 0.5,
				range: 0
			}
		]
	};
}

function createDefaultSpecies3(population: number): Species {
	const base = createDefaultSpecies(2, population);
	// Species 3: Tertiary group - flees from all others
	return {
		...base,
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Flee,
				strength: 0.5,
				range: 0
			}
		]
	};
}

function createDefaultSpecies4(population: number): Species {
	const base = createDefaultSpecies(3, population);
	// Species 4: Fourth group - chases all others (predator species)
	return {
		...base,
		interactions: [
			{
				targetSpecies: -1, // All others
				behavior: InteractionBehavior.Chase,
				strength: 0.5,
				range: 0
			}
		]
	};
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
	cursorVortex: VortexDirection.Off,
	cursorForce: 0.5,
	cursorRadius: 50,
	boidSize: 1.5,
	trailLength: 20,
	colorMode: ColorMode.Species,
	colorSpectrum: ColorSpectrum.Rainbow,
	sensitivity: 1.0,
	population: 6000, // Default total (will be recalculated based on screen size)
	// Simulation timing
	timeScale: 1.0, // Normal speed
	// Dynamics
	globalCollision: 0.5, // Default cross-species collision strength
	// Wall drawing
	wallBrushSize: 30, // Default brush size
	wallBrushShape: WallBrushShape.Solid, // Default brush shape
	// Multi-species defaults: Start with four species, all avoiding each other
	species: [createDefaultSpecies1(3500), createDefaultSpecies2(1000), createDefaultSpecies3(750), createDefaultSpecies4(750)],
	activeSpeciesId: 0,
	// Spectral/Flow metrics defaults
	enableInfluence: true,
	influenceIterations: 6,
	spectralMode: SpectralMode.FlowDivergence,
	// HSL control defaults
	saturationSource: ColorMode.None, // None = full saturation (100%)
	brightnessSource: ColorMode.LocalDensity  // Local density shows cluster structure nicely
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

/**
 * Calculate optimal populations for default four-species setup.
 * Species 1 gets ~58% (main swarm), Species 2 gets ~17%, Species 3 & 4 get ~12.5% each.
 * This creates visually interesting multi-swarm dynamics.
 *
 * @param width Canvas width in pixels
 * @param height Canvas height in pixels
 * @returns Object with species1, species2, species3, species4 populations and total
 */
export function calculateOptimalSpeciesPopulations(
	width: number,
	height: number
): { species1: number; species2: number; species3: number; species4: number; total: number } {
	const area = width * height;

	// Target density: roughly 1 boid per 300 square pixels
	const density = 300;
	let totalPopulation = Math.floor(area / density);

	// Mobile detection: smaller screens get reduced populations
	const isMobile = width < 768 || area < 500000;

	// Clamp to reasonable bounds (tighter bounds for mobile)
	const MIN_POPULATION = isMobile ? 600 : 1000;
	const MAX_POPULATION = isMobile ? 6000 : 15000;

	totalPopulation = Math.max(MIN_POPULATION, Math.min(MAX_POPULATION, totalPopulation));

	// Split: Species 1 ~58%, Species 2 ~17%, Species 3 ~12.5%, Species 4 ~12.5%
	// This creates good visual dynamics - main flock with three smaller groups
	const species1Raw = Math.floor(totalPopulation * 0.58);
	const species2Raw = Math.floor(totalPopulation * 0.17);
	const species3Raw = Math.floor(totalPopulation * 0.125);
	const species4Raw = totalPopulation - species1Raw - species2Raw - species3Raw;

	// Round to nearest 100 for cleaner numbers (50 for mobile)
	const roundTo = isMobile ? 50 : 100;
	const species1 = Math.round(species1Raw / roundTo) * roundTo;
	const species2 = Math.max(roundTo, Math.round(species2Raw / roundTo) * roundTo);
	const species3 = Math.max(roundTo, Math.round(species3Raw / roundTo) * roundTo);
	const species4 = Math.max(roundTo, Math.round(species4Raw / roundTo) * roundTo);

	return {
		species1,
		species2,
		species3,
		species4,
		total: species1 + species2 + species3 + species4
	};
}

// Uniform buffer layout (must match WGSL struct)
export const UNIFORM_BUFFER_SIZE = 256; // Padded for alignment

export const WORKGROUP_SIZE = 256;

// Wall texture is at 1/4 resolution for performance
export const WALL_TEXTURE_SCALE = 4;
