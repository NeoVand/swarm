// Svelte stores for simulation parameters

import { writable, derived } from 'svelte/store';
import {
	type SimulationParams,
	type CursorState,
	type CurvePoint,
	DEFAULT_PARAMS,
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	CursorMode,
	CursorShape,
	AlgorithmMode,
	WallTool,
	WallBrushShape,
	PopulationCap,
	WALL_TEXTURE_SCALE,
	CA_DEFAULT_CURVES
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

// ============================================================================
// CA SYSTEM STORES
// ============================================================================

// CA curve stores - each curve is an array of control points
// These are separate from params because they need special handling for GPU upload
export const caCurves = writable<{
	vitalityInfluence: CurvePoint[];
	alignment: CurvePoint[];
	cohesion: CurvePoint[];
	separation: CurvePoint[];
	birth: CurvePoint[];
}>({
	vitalityInfluence: CA_DEFAULT_CURVES.vitalityInfluence.map((p) => ({ ...p })),
	alignment: CA_DEFAULT_CURVES.alignment.map((p) => ({ ...p })),
	cohesion: CA_DEFAULT_CURVES.cohesion.map((p) => ({ ...p })),
	separation: CA_DEFAULT_CURVES.separation.map((p) => ({ ...p })),
	birth: CA_DEFAULT_CURVES.birth.map((p) => ({ ...p }))
});

// Flag to trigger CA curve GPU upload
export const caCurvesDirty = writable(false);

// Flag to trigger CA state reinitialization
export const needsCAStateReset = writable(false);

// Currently active population (may differ from params.population due to CA dynamics)
export const activePopulation = writable(0);

// Wall drawing state
export const wallTool = writable<WallTool>(WallTool.None);
export const wallsDirty = writable(false);

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

// ============================================================================
// CA SYSTEM SETTERS
// ============================================================================

export function setCAEnabled(value: boolean): void {
	params.update((p) => ({ ...p, caEnabled: value }));
	if (value) {
		// When enabling CA, reinitialize CA state AND upload current curves
		needsCAStateReset.set(true);
		caCurvesDirty.set(true); // Ensure store curves are uploaded to GPU
	}
}

export function setAgingEnabled(value: boolean): void {
	params.update((p) => ({ ...p, agingEnabled: value }));
}

export function setMaxAge(value: number): void {
	params.update((p) => ({ ...p, maxAge: value }));
}

export function setVitalityGain(value: number): void {
	params.update((p) => ({ ...p, vitalityGain: value }));
}

export function setBirthVitalityThreshold(value: number): void {
	params.update((p) => ({ ...p, birthVitalityThreshold: value }));
}

export function setBirthFieldThreshold(value: number): void {
	params.update((p) => ({ ...p, birthFieldThreshold: value }));
}

export function setBirthSplit(value: number): void {
	params.update((p) => ({ ...p, birthSplit: value }));
}

export function setVitalityConservation(value: number): void {
	params.update((p) => ({ ...p, vitalityConservation: value }));
}

export function setAgeSpread(value: number): void {
	params.update((p) => ({ ...p, ageSpread: value }));
}

export function setPopulationCap(value: PopulationCap): void {
	params.update((p) => ({ ...p, populationCap: value }));
}

export function setMaxPopulation(value: number): void {
	params.update((p) => ({ ...p, maxPopulation: value }));
}

/**
 * Update a specific CA curve and mark as dirty for GPU upload.
 */
export function setCACurve(
	curveType: 'vitalityInfluence' | 'alignment' | 'cohesion' | 'separation' | 'birth',
	points: CurvePoint[]
): void {
	caCurves.update((curves) => ({
		...curves,
		[curveType]: [...points]
	}));
	caCurvesDirty.set(true);
}

/**
 * Update all CA curves at once.
 */
export function setAllCACurves(curves: {
	vitalityInfluence: CurvePoint[];
	alignment: CurvePoint[];
	cohesion: CurvePoint[];
	separation: CurvePoint[];
	birth: CurvePoint[];
}): void {
	caCurves.set({
		vitalityInfluence: [...curves.vitalityInfluence],
		alignment: [...curves.alignment],
		cohesion: [...curves.cohesion],
		separation: [...curves.separation],
		birth: [...curves.birth]
	});
	caCurvesDirty.set(true);
}

/**
 * Reset CA curves to defaults.
 */
export function resetCACurves(): void {
	setAllCACurves({
		vitalityInfluence: [...CA_DEFAULT_CURVES.vitalityInfluence],
		alignment: [...CA_DEFAULT_CURVES.alignment],
		cohesion: [...CA_DEFAULT_CURVES.cohesion],
		separation: [...CA_DEFAULT_CURVES.separation],
		birth: [...CA_DEFAULT_CURVES.birth]
	});
}

/**
 * Reset entire CA system to defaults.
 */
export function resetCASystem(): void {
	params.update((p) => ({
		...p,
		caEnabled: false,
		agingEnabled: true,
		maxAge: 15,
		birthThreshold: 3.5,
		populationCap: PopulationCap.Soft,
		maxPopulation: 15000
	}));
	resetCACurves();
	needsCAStateReset.set(true);
}

// Export enums for use in components
export {
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	CursorMode,
	CursorShape,
	AlgorithmMode,
	WallTool,
	WallBrushShape,
	PopulationCap,
	DEFAULT_PARAMS
};

// Export CA curve type for components
export type { CurvePoint };
