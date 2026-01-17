// Svelte stores for simulation parameters

import { writable, derived } from 'svelte/store';
import {
	type SimulationParams,
	type CursorState,
	DEFAULT_PARAMS,
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	CursorMode,
	AlgorithmMode
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

export function setBoidSize(value: number): void {
	params.update((p) => ({ ...p, boidSize: value }));
}

export function setTrailLength(value: number): void {
	params.update((p) => ({ ...p, trailLength: value }));
	needsBufferReallocation.set(true);
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

// Export enums for use in components
export { BoundaryMode, ColorMode, ColorSpectrum, CursorMode, AlgorithmMode };
