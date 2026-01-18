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
	CursorShape,
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
export { BoundaryMode, ColorMode, ColorSpectrum, CursorMode, CursorShape, AlgorithmMode };
