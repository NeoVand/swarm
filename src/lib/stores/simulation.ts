// Svelte stores for simulation parameters

import { writable, derived } from 'svelte/store';
import {
	type SimulationParams,
	type CursorState,
	type Species,
	type InteractionRule,
	DEFAULT_PARAMS,
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	CursorMode,
	CursorShape,
	CursorResponse,
	AlgorithmMode,
	WallTool,
	WallBrushShape,
	HeadShape,
	InteractionBehavior,
	MAX_SPECIES,
	WALL_TEXTURE_SCALE,
	createDefaultSpecies
} from '$lib/webgpu/types';

// Main simulation parameters store
export const params = writable<SimulationParams>({ ...DEFAULT_PARAMS });

// Cursor state store
export const cursor = writable<CursorState>({
	x: 0,
	y: 0,
	isPressed: false,
	isActive: false
});

// Canvas dimensions store
export const dimensions = writable<{ width: number; height: number }>({
	width: 800,
	height: 600
});

// Control panel visibility
export const isPanelOpen = writable(false);

// WebGPU availability
export const isWebGPUAvailable = writable<boolean | null>(null);

// Simulation running state
export const isRunning = writable(true);

// Recording state
export const isRecording = writable(false);

// Canvas element reference (for screenshot/recording)
export const canvasElement = writable<HTMLCanvasElement | null>(null);

// FPS counter
export const fps = writable(0);

// Derived store for grid dimensions based on perception radius
export const gridDimensions = derived([dimensions, params], ([$dimensions, $params]) => {
	const cellSize = $params.perception;
	const gridWidth = Math.ceil($dimensions.width / cellSize);
	const gridHeight = Math.ceil($dimensions.height / cellSize);
	return {
		cellSize,
		gridWidth,
		gridHeight,
		totalCells: gridWidth * gridHeight
	};
});

// Flag to trigger buffer reallocation
export const needsBufferReallocation = writable(false);

// Flag to trigger trail clear
export const needsTrailClear = writable(false);

// Flag to trigger simulation reset (reinitialize boid positions)
export const needsSimulationReset = writable(false);

// Wall drawing state
export const wallTool = writable<WallTool>(WallTool.None);
export const wallsDirty = writable(false);

// Species dirty flag (triggers GPU buffer update)
export const speciesDirty = writable(false);

// Wall texture data (CPU-side buffer)
// Initialized lazily based on canvas dimensions
let wallDataArray: Uint8Array | null = null;
let wallTextureWidth = 0;
let wallTextureHeight = 0;

// Stroke tracking for hollow brush
let strokeSnapshot: Uint8Array | null = null;

export function initWallData(canvasWidth: number, canvasHeight: number): Uint8Array {
	const newWidth = Math.ceil(canvasWidth / WALL_TEXTURE_SCALE);
	const newHeight = Math.ceil(canvasHeight / WALL_TEXTURE_SCALE);

	// Only recreate if dimensions changed
	if (wallDataArray === null || newWidth !== wallTextureWidth || newHeight !== wallTextureHeight) {
		wallTextureWidth = newWidth;
		wallTextureHeight = newHeight;
		wallDataArray = new Uint8Array(newWidth * newHeight);
	}

	return wallDataArray;
}

export function getWallData(): Uint8Array | null {
	return wallDataArray;
}

export function getWallTextureDimensions(): { width: number; height: number } {
	return { width: wallTextureWidth, height: wallTextureHeight };
}

// Paint a circle into the wall buffer
export function paintWall(
	canvasX: number,
	canvasY: number,
	brushSize: number,
	erase: boolean
): void {
	if (!wallDataArray) return;

	// Convert canvas coordinates to texture coordinates
	const texX = Math.floor(canvasX / WALL_TEXTURE_SCALE);
	const texY = Math.floor(canvasY / WALL_TEXTURE_SCALE);
	const texRadius = Math.ceil(brushSize / WALL_TEXTURE_SCALE);

	const value = erase ? 0 : 255;

	// Draw filled circle
	for (let dy = -texRadius; dy <= texRadius; dy++) {
		for (let dx = -texRadius; dx <= texRadius; dx++) {
			const distSq = dx * dx + dy * dy;
			if (distSq <= texRadius * texRadius) {
				const px = texX + dx;
				const py = texY + dy;
				if (px >= 0 && px < wallTextureWidth && py >= 0 && py < wallTextureHeight) {
					wallDataArray[py * wallTextureWidth + px] = value;
				}
			}
		}
	}

	wallsDirty.set(true);
}

// Begin tracking a stroke (call before drawing with hollow brush)
export function beginStroke(): void {
	if (wallDataArray) {
		strokeSnapshot = new Uint8Array(wallDataArray);
	}
}

// End stroke and apply hollow only to newly drawn pixels
export function endStrokeWithHollow(thickness: number): void {
	if (!wallDataArray || !strokeSnapshot) return;

	const erosionRadius = Math.ceil(thickness / WALL_TEXTURE_SCALE);
	const erosionRadiusSq = erosionRadius * erosionRadius;

	// Find pixels that are new (weren't in snapshot but are now walls)
	const newPixels = new Set<number>();
	for (let i = 0; i < wallDataArray.length; i++) {
		if (wallDataArray[i] > 0 && strokeSnapshot[i] === 0) {
			newPixels.add(i);
		}
	}

	// For each new pixel, check if it's interior to the NEW stroke only
	for (const idx of newPixels) {
		const x = idx % wallTextureWidth;
		const y = Math.floor(idx / wallTextureWidth);

		// Check if this pixel is interior (all neighbors within radius are also new pixels)
		let isInterior = true;

		outer: for (let dy = -erosionRadius; dy <= erosionRadius && isInterior; dy++) {
			for (let dx = -erosionRadius; dx <= erosionRadius; dx++) {
				const distSq = dx * dx + dy * dy;
				if (distSq > erosionRadiusSq) continue;

				const nx = x + dx;
				const ny = y + dy;

				// If we hit a boundary, this is not interior
				if (nx < 0 || nx >= wallTextureWidth || ny < 0 || ny >= wallTextureHeight) {
					isInterior = false;
					break outer;
				}

				const nidx = ny * wallTextureWidth + nx;
				// Check if neighbor is part of new stroke
				if (!newPixels.has(nidx)) {
					isInterior = false;
					break outer;
				}
			}
		}

		// Erase interior pixels of the new stroke
		if (isInterior) {
			wallDataArray[idx] = 0;
		}
	}

	strokeSnapshot = null;
	wallsDirty.set(true);
}

// Hollow out walls by eroding the interior (morphological erosion) - for all walls
export function hollowWalls(thickness: number): void {
	if (!wallDataArray) return;

	const erosionRadius = Math.ceil(thickness / WALL_TEXTURE_SCALE);
	const erosionRadiusSq = erosionRadius * erosionRadius;

	// Create a copy to read from while we modify the original
	const original = new Uint8Array(wallDataArray);

	// For each pixel, check if it's an interior pixel (all neighbors within radius are walls)
	for (let y = 0; y < wallTextureHeight; y++) {
		for (let x = 0; x < wallTextureWidth; x++) {
			const idx = y * wallTextureWidth + x;

			// Only process wall pixels
			if (original[idx] === 0) continue;

			// Check if this is an interior pixel
			let isInterior = true;

			// Sample in a circle pattern for efficiency
			outer: for (let dy = -erosionRadius; dy <= erosionRadius && isInterior; dy++) {
				for (let dx = -erosionRadius; dx <= erosionRadius; dx++) {
					const distSq = dx * dx + dy * dy;
					if (distSq > erosionRadiusSq) continue;

					const nx = x + dx;
					const ny = y + dy;

					// If we hit a boundary or empty pixel, this is not interior
					if (nx < 0 || nx >= wallTextureWidth || ny < 0 || ny >= wallTextureHeight) {
						isInterior = false;
						break outer;
					}

					if (original[ny * wallTextureWidth + nx] === 0) {
						isInterior = false;
						break outer;
					}
				}
			}

			// Erase interior pixels
			if (isInterior) {
				wallDataArray[idx] = 0;
			}
		}
	}

	wallsDirty.set(true);
}

// Clear all walls
export function clearWalls(): void {
	if (wallDataArray) {
		wallDataArray.fill(0);
		wallsDirty.set(true);
	}
}

// Helper functions to update specific parameters
export function setAlignment(value: number): void {
	params.update((p) => ({ ...p, alignment: value }));
}

export function setCohesion(value: number): void {
	params.update((p) => ({ ...p, cohesion: value }));
}

export function setSeparation(value: number): void {
	params.update((p) => ({ ...p, separation: value }));
}

export function setPerception(value: number): void {
	params.update((p) => ({ ...p, perception: value }));
	// Grid buffers are pre-allocated for max size, so no reallocation needed
}

export function setMaxSpeed(value: number): void {
	params.update((p) => ({ ...p, maxSpeed: value }));
}

export function setMaxForce(value: number): void {
	params.update((p) => ({ ...p, maxForce: value }));
}

export function setNoise(value: number): void {
	params.update((p) => ({ ...p, noise: value }));
}

export function setRebels(value: number): void {
	params.update((p) => ({ ...p, rebels: value }));
}

export function setBoundaryMode(value: BoundaryMode): void {
	params.update((p) => ({ ...p, boundaryMode: value }));
	needsTrailClear.set(true);
}

export function setCursorMode(value: CursorMode): void {
	params.update((p) => ({ ...p, cursorMode: value }));
}

export function setCursorForce(value: number): void {
	params.update((p) => ({ ...p, cursorForce: value }));
}

export function setCursorShape(value: CursorShape): void {
	params.update((p) => ({ ...p, cursorShape: value }));
}

export function setCursorVortex(value: boolean): void {
	params.update((p) => ({ ...p, cursorVortex: value }));
}

export function setCursorRadius(value: number): void {
	params.update((p) => ({ ...p, cursorRadius: value }));
}

export function setBoidSize(value: number): void {
	params.update((p) => ({ ...p, boidSize: value }));
}

export function setTrailLength(value: number): void {
	params.update((p) => ({ ...p, trailLength: value }));
	// No buffer reallocation needed - trail buffer is pre-allocated for max length (100)
	// Ring buffer handles length changes naturally via modulo in shader
}

export function setColorMode(value: ColorMode): void {
	params.update((p) => ({ ...p, colorMode: value }));
}

export function setColorSpectrum(value: ColorSpectrum): void {
	params.update((p) => ({ ...p, colorSpectrum: value }));
}

export function setSensitivity(value: number): void {
	params.update((p) => ({ ...p, sensitivity: value }));
}

export function setPopulation(value: number): void {
	params.update((p) => ({ ...p, population: value }));
	needsBufferReallocation.set(true);
}

export function setAlgorithmMode(value: AlgorithmMode): void {
	params.update((p) => ({ ...p, algorithmMode: value }));
}

// Algorithm-specific parameters
export function setKNeighbors(value: number): void {
	params.update((p) => ({ ...p, kNeighbors: value }));
}

export function setSampleCount(value: number): void {
	params.update((p) => ({ ...p, sampleCount: value }));
}

export function setIdealDensity(value: number): void {
	params.update((p) => ({ ...p, idealDensity: value }));
}

export function setTimeScale(value: number): void {
	params.update((p) => ({ ...p, timeScale: value }));
}

export function setWallBrushSize(value: number): void {
	params.update((p) => ({ ...p, wallBrushSize: value }));
}

export function setWallBrushShape(value: WallBrushShape): void {
	params.update((p) => ({ ...p, wallBrushShape: value }));
}

export function setWallTool(value: WallTool): void {
	wallTool.set(value);
}

// ============================================================================
// SPECIES MANAGEMENT
// ============================================================================

// Set active species for editing
export function setActiveSpecies(id: number): void {
	params.update((p) => ({ ...p, activeSpeciesId: id }));
}

// Get the currently active species
export function getActiveSpecies(p: SimulationParams): Species | undefined {
	return p.species.find((s) => s.id === p.activeSpeciesId);
}

// Add a new species
export function addSpecies(): void {
	params.update((p) => {
		if (p.species.length >= MAX_SPECIES) return p;

		// Find the next available ID
		const usedIds = new Set(p.species.map((s) => s.id));
		let newId = 0;
		while (usedIds.has(newId) && newId < MAX_SPECIES) newId++;

		if (newId >= MAX_SPECIES) return p;

		// Calculate population for new species (split from total or add small amount)
		const newPopulation = Math.min(500, Math.floor(p.population * 0.1));

		const newSpecies = createDefaultSpecies(newId, newPopulation);
		const newTotalPopulation = p.population + newPopulation;

		return {
			...p,
			species: [...p.species, newSpecies],
			population: newTotalPopulation,
			activeSpeciesId: newId
		};
	});
	// Trigger buffer reallocation to add new boids for the new species
	needsBufferReallocation.set(true);
}

// Remove a species (must have at least one)
export function removeSpecies(id: number): void {
	params.update((p) => {
		if (p.species.length <= 1) return p;

		const species = p.species.find((s) => s.id === id);
		if (!species) return p;

		const newSpecies = p.species.filter((s) => s.id !== id);
		const newTotalPopulation = p.population - species.population;

		// If we're removing the active species, switch to first available
		const newActiveId = p.activeSpeciesId === id ? newSpecies[0].id : p.activeSpeciesId;

		return {
			...p,
			species: newSpecies,
			population: Math.max(500, newTotalPopulation),
			activeSpeciesId: newActiveId
		};
	});
	needsBufferReallocation.set(true);
}

// Update a species property
export function updateSpecies(id: number, updates: Partial<Species>): void {
	params.update((p) => {
		const newSpecies = p.species.map((s) => (s.id === id ? { ...s, ...updates } : s));

		// Recalculate total population if population changed
		let newTotalPopulation = p.population;
		if (updates.population !== undefined) {
			newTotalPopulation = newSpecies.reduce((sum, s) => sum + s.population, 0);
		}

		return {
			...p,
			species: newSpecies,
			population: newTotalPopulation
		};
	});

	// Trigger buffer reallocation if population changed
	if (updates.population !== undefined) {
		needsBufferReallocation.set(true);
	} else {
		// Otherwise just update species buffers
		speciesDirty.set(true);
	}
}

// Update species flocking parameters (convenience function)
export function updateSpeciesFlocking(
	id: number,
	param: 'alignment' | 'cohesion' | 'separation' | 'perception' | 'maxSpeed' | 'maxForce',
	value: number
): void {
	updateSpecies(id, { [param]: value });
}

// Add an interaction rule to a species
export function addInteractionRule(speciesId: number, rule: InteractionRule): void {
	params.update((p) => {
		const newSpecies = p.species.map((s) => {
			if (s.id !== speciesId) return s;
			return {
				...s,
				interactions: [...s.interactions, rule]
			};
		});
		return { ...p, species: newSpecies };
	});
	speciesDirty.set(true);
}

// Update an interaction rule
export function updateInteractionRule(
	speciesId: number,
	ruleIndex: number,
	updates: Partial<InteractionRule>
): void {
	params.update((p) => {
		const newSpecies = p.species.map((s) => {
			if (s.id !== speciesId) return s;
			const newInteractions = [...s.interactions];
			if (ruleIndex >= 0 && ruleIndex < newInteractions.length) {
				newInteractions[ruleIndex] = { ...newInteractions[ruleIndex], ...updates };
			}
			return { ...s, interactions: newInteractions };
		});
		return { ...p, species: newSpecies };
	});
	speciesDirty.set(true);
}

// Remove an interaction rule
export function removeInteractionRule(speciesId: number, ruleIndex: number): void {
	params.update((p) => {
		const newSpecies = p.species.map((s) => {
			if (s.id !== speciesId) return s;
			const newInteractions = s.interactions.filter((_, i) => i !== ruleIndex);
			return { ...s, interactions: newInteractions };
		});
		return { ...p, species: newSpecies };
	});
	speciesDirty.set(true);
}

// Set species head shape
export function setSpeciesHeadShape(id: number, shape: HeadShape): void {
	updateSpecies(id, { headShape: shape });
}

// Set species hue
export function setSpeciesHue(id: number, hue: number): void {
	updateSpecies(id, { hue });
}

// Set species saturation
export function setSpeciesSaturation(id: number, saturation: number): void {
	updateSpecies(id, { saturation });
}

// Set species lightness
export function setSpeciesLightness(id: number, lightness: number): void {
	updateSpecies(id, { lightness });
}

// Set species color (hue, saturation, lightness)
export function setSpeciesColor(
	id: number,
	hue: number,
	saturation: number,
	lightness: number
): void {
	updateSpecies(id, { hue, saturation, lightness });
}

// Set species name
export function setSpeciesName(id: number, name: string): void {
	updateSpecies(id, { name });
}

// Set species population
export function setSpeciesPopulation(id: number, population: number): void {
	updateSpecies(id, { population });
}

// Set species size (boid size)
export function setSpeciesSize(id: number, size: number): void {
	updateSpecies(id, { size });
}

// Set species trail length
export function setSpeciesTrailLength(id: number, trailLength: number): void {
	updateSpecies(id, { trailLength });
}

// Set species rebels percentage
export function setSpeciesRebels(id: number, rebels: number): void {
	updateSpecies(id, { rebels });
}

// Set species cursor force
export function setSpeciesCursorForce(id: number, cursorForce: number): void {
	updateSpecies(id, { cursorForce });
}

// Set species cursor response
export function setSpeciesCursorResponse(id: number, cursorResponse: CursorResponse): void {
	updateSpecies(id, { cursorResponse });
}

// Set species cursor vortex
export function setSpeciesCursorVortex(id: number, cursorVortex: boolean): void {
	updateSpecies(id, { cursorVortex });
}

// Play/pause toggle
export function togglePlayPause(): void {
	isRunning.update((running) => !running);
}

// Recording toggle
export function toggleRecording(): void {
	isRecording.update((recording) => !recording);
}

export function setRecording(value: boolean): void {
	isRecording.set(value);
}

// Export enums for use in components
export {
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	CursorMode,
	CursorShape,
	CursorResponse,
	AlgorithmMode,
	WallTool,
	WallBrushShape,
	HeadShape,
	InteractionBehavior,
	MAX_SPECIES,
	DEFAULT_PARAMS,
	createDefaultSpecies
};

// Export types
export type { Species, InteractionRule };
