import {
	DEFAULT_PARAMS,
	MAX_SPECIES,
	MAX_METRIC_RULES_PER_SPECIES,
	createDefaultSpecies,
	type SimulationParams,
	type Species,
	type InteractionRule,
	type CurvePoint
} from '../webgpu/types';

export const SCENE_VERSION = 1 as const;
export const MAX_SCENE_BYTES = 5_000_000;
export const MAX_WALL_PIXELS = 4_194_304;
export const MAX_SCENE_POPULATION = 100_000;
export const MAX_SAVED_SCENES = 40;
export const MAX_SHARE_LENGTH = 12_000;

export interface SceneCamera {
	azimuth: number;
	elevation: number;
	distance: number;
	panX: number;
	panY: number;
}

/** Runs are alternating [pixel value, repeat count] pairs. */
export interface SceneWalls {
	width: number;
	height: number;
	runs: number[];
}

export interface Scene {
	version: typeof SCENE_VERSION;
	id: string;
	name: string;
	description?: string;
	createdAt: string;
	updatedAt?: string;
	thumbnail?: string;
	params: SimulationParams;
	walls?: SceneWalls;
	camera?: SceneCamera;
}

type RecordValue = Record<string, unknown>;

function record(value: unknown, label: string): RecordValue {
	if (typeof value !== 'object' || value === null || Array.isArray(value)) {
		throw new Error(`${label} must be an object.`);
	}
	return value as RecordValue;
}

function number(value: unknown, min: number, max: number, label: string, integer = false): number {
	if (
		typeof value !== 'number' ||
		!Number.isFinite(value) ||
		value < min ||
		value > max ||
		(integer && !Number.isInteger(value))
	) {
		throw new Error(
			`${label} must be ${integer ? 'an integer' : 'a number'} between ${min} and ${max}.`
		);
	}
	return value;
}

function text(value: unknown, max: number, label: string): string {
	if (typeof value !== 'string' || !value.trim() || value.length > max) {
		throw new Error(`${label} must contain 1–${max} characters.`);
	}
	return value.trim();
}

function boolean(value: unknown, label: string): boolean {
	if (typeof value !== 'boolean') throw new Error(`${label} must be true or false.`);
	return value;
}

function enumNumber(value: unknown, choices: readonly number[], label: string): number {
	if (typeof value !== 'number' || !choices.includes(value))
		throw new Error(`${label} is not supported.`);
	return value;
}

const colorModes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17];
const numericParams = {
	alignment: [0, 3],
	cohesion: [0, 3],
	separation: [0, 4],
	perception: [20, 200],
	maxSpeed: [0.1, 15],
	maxForce: [0.001, 0.5],
	noise: [0, 1],
	rebels: [0, 1],
	cursorForce: [0, 1],
	cursorRadius: [1, 300],
	boidSize: [0.1, 5],
	trailLength: [0, 50],
	sensitivity: [0.01, 10],
	timeScale: [0.05, 4],
	globalCollision: [0, 1],
	wallBrushSize: [1, 300],
	influenceIterations: [1, 8],
	hueStrength: [0.01, 3],
	saturationStrength: [0.01, 3],
	brightnessStrength: [0.01, 3]
} as const;
const booleanParams = [
	'embedded3D',
	'embedShowGrid',
	'embedAutoRotate',
	'enableInfluence',
	'hueCurveEnabled',
	'saturationCurveEnabled',
	'brightnessCurveEnabled'
] as const;
const enumParams = {
	boundaryMode: [0, 1, 2, 3, 4, 5, 6, 7, 8],
	cursorMode: [0, 1, 2],
	cursorShape: [0, 1],
	cursorVortex: [0, 1, 2],
	colorMode: colorModes,
	saturationSource: colorModes,
	brightnessSource: colorModes,
	colorSpectrum: [0, 1, 2, 3, 4],
	wallBrushShape: [0, 1],
	spectralMode: [0, 1, 2, 3, 4, 5]
} as const;

function curve(value: unknown, label: string): CurvePoint[] {
	if (!Array.isArray(value) || value.length < 2 || value.length > 64) {
		throw new Error(`${label} needs 2–64 control points.`);
	}
	const points = value.map((entry, index) => {
		const p = record(entry, `${label} point`);
		return {
			x: number(p.x, 0, 1, `${label} point ${index + 1} x`),
			y: number(p.y, 0, 1, `${label} point ${index + 1} y`)
		};
	});
	for (let i = 1; i < points.length; i++) {
		if (points[i].x <= points[i - 1].x)
			throw new Error(`${label} points must have distinct, increasing x positions.`);
	}
	return points;
}

function validateRule(value: unknown, ids: Set<number>, selfId: number): InteractionRule {
	const r = record(value, 'Interaction');
	if (r.type !== undefined && r.type !== 'species' && r.type !== 'metric')
		throw new Error('Unknown interaction type.');
	const common = {
		behavior: number(r.behavior, 0, 11, 'Interaction behavior', true),
		strength: number(r.strength, 0, 1, 'Interaction strength'),
		range: number(r.range, 0, 200, 'Interaction range')
	};
	if (r.type === 'metric') {
		return {
			...common,
			type: 'metric',
			metricSource: number(r.metricSource, 0, 7, 'Metric source', true),
			metricRole: number(r.metricRole, 0, 2, 'Metric role', true),
			curve: curve(r.curve, 'Interaction curve')
		};
	}
	const target = number(r.targetSpecies, -1, MAX_SPECIES - 1, 'Interaction target', true);
	if (target !== -1 && (!ids.has(target) || target === selfId))
		throw new Error('Interactions must target another species in this scene.');
	return { ...common, type: 'species', targetSpecies: target };
}

export function validateParams(value: unknown): SimulationParams {
	const raw = record(value, 'Scene parameters');
	const result = structuredClone(DEFAULT_PARAMS);
	for (const key of Object.keys(numericParams) as (keyof typeof numericParams)[]) {
		const [min, max] = numericParams[key];
		result[key] = number(
			raw[key] ?? result[key],
			min,
			max,
			key,
			key === 'influenceIterations' || key === 'trailLength'
		);
	}
	for (const key of booleanParams) result[key] = boolean(raw[key] ?? result[key], key);
	for (const key of Object.keys(enumParams) as (keyof typeof enumParams)[]) {
		Object.assign(result, { [key]: enumNumber(raw[key] ?? result[key], enumParams[key], key) });
	}
	for (const key of ['hueCurvePoints', 'saturationCurvePoints', 'brightnessCurvePoints'] as const) {
		result[key] = curve(raw[key] ?? result[key], key);
	}
	if (!Array.isArray(raw.species) || raw.species.length < 1 || raw.species.length > MAX_SPECIES) {
		throw new Error(`A scene needs 1–${MAX_SPECIES} species.`);
	}
	const entries = raw.species.map((value) => record(value, 'Species'));
	const ids = new Set(entries.map((s) => number(s.id, 0, MAX_SPECIES - 1, 'Species ID', true)));
	if (ids.size !== entries.length) throw new Error('Species IDs must be unique.');
	result.species = entries.map((s): Species => {
		const id = s.id as number;
		const defaults = createDefaultSpecies(id, 500);
		const species: Species = {
			id,
			name: text(s.name ?? defaults.name, 60, 'Species name'),
			headShape: number(s.headShape ?? defaults.headShape, 0, 4, 'Head shape', true),
			hue: number(s.hue ?? defaults.hue, 0, 360, 'Hue'),
			saturation: number(s.saturation ?? defaults.saturation, 0, 100, 'Saturation'),
			lightness: number(s.lightness ?? defaults.lightness, 0, 100, 'Lightness'),
			population: number(s.population, 1, MAX_SCENE_POPULATION, 'Species population', true),
			size: number(s.size ?? defaults.size, 0.1, 5, 'Size'),
			trailLength: number(s.trailLength ?? defaults.trailLength, 0, 50, 'Trail length', true),
			alignment: number(s.alignment ?? defaults.alignment, 0, 3, 'Alignment'),
			cohesion: number(s.cohesion ?? defaults.cohesion, 0, 3, 'Cohesion'),
			separation: number(s.separation ?? defaults.separation, 0, 4, 'Separation'),
			perception: number(s.perception ?? defaults.perception, 20, 200, 'Perception'),
			maxSpeed: number(s.maxSpeed ?? defaults.maxSpeed, 0.1, 15, 'Speed'),
			maxForce: number(s.maxForce ?? defaults.maxForce, 0.001, 0.5, 'Force'),
			rebels: number(s.rebels ?? defaults.rebels, 0, 1, 'Rebels'),
			cursorForce: number(s.cursorForce ?? defaults.cursorForce, 0, 1, 'Cursor force'),
			cursorResponse: number(
				s.cursorResponse ?? defaults.cursorResponse,
				0,
				2,
				'Cursor response',
				true
			),
			cursorVortex: number(s.cursorVortex ?? defaults.cursorVortex, 0, 2, 'Cursor vortex', true),
			interactions: []
		};
		if (
			!Array.isArray(s.interactions) ||
			s.interactions.length > MAX_SPECIES + MAX_METRIC_RULES_PER_SPECIES
		)
			throw new Error('Invalid number of interactions.');
		species.interactions = s.interactions.map((rule) => validateRule(rule, ids, id));
		const targets = species.interactions
			.filter((r) => r.type !== 'metric')
			.map((r) => r.targetSpecies);
		if (new Set(targets).size !== targets.length)
			throw new Error('A species cannot have duplicate interaction targets.');
		if (
			species.interactions.filter((r) => r.type === 'metric').length > MAX_METRIC_RULES_PER_SPECIES
		)
			throw new Error('Each species supports at most two metric rules.');
		return species;
	});
	result.population = result.species.reduce((sum, s) => sum + s.population, 0);
	if (result.population > MAX_SCENE_POPULATION)
		throw new Error(`Scenes support up to ${MAX_SCENE_POPULATION.toLocaleString()} boids.`);
	if (
		raw.population !== undefined &&
		number(raw.population, 1, MAX_SCENE_POPULATION, 'Population', true) !== result.population
	)
		throw new Error('Total population must match the species populations.');
	result.activeSpeciesId = number(
		raw.activeSpeciesId ?? result.species[0].id,
		0,
		MAX_SPECIES - 1,
		'Selected species',
		true
	);
	if (!ids.has(result.activeSpeciesId))
		throw new Error('Selected species is missing from this scene.');
	return result;
}

export function encodeWalls(
	snapshot: { width: number; height: number; data: Uint8Array } | null
): SceneWalls | undefined {
	if (!snapshot || !snapshot.data.some((value) => value !== 0)) return undefined;
	const { width, height, data } = snapshot;
	if (width * height !== data.length || data.length > MAX_WALL_PIXELS)
		throw new Error('Wall drawing is too large to save.');
	const runs: number[] = [];
	for (let start = 0; start < data.length; ) {
		const value = data[start];
		let end = start + 1;
		while (end < data.length && data[end] === value) end++;
		runs.push(value, end - start);
		start = end;
	}
	return { width, height, runs };
}

function validateWalls(value: unknown): SceneWalls {
	const raw = record(value, 'Walls');
	const width = number(raw.width, 1, 4096, 'Wall width', true);
	const height = number(raw.height, 1, 4096, 'Wall height', true);
	const area = width * height;
	if (
		area > MAX_WALL_PIXELS ||
		!Array.isArray(raw.runs) ||
		raw.runs.length < 2 ||
		raw.runs.length % 2 !== 0 ||
		raw.runs.length > area * 2
	)
		throw new Error('Invalid wall drawing size.');
	let total = 0;
	const runs: number[] = [];
	for (let i = 0; i < raw.runs.length; i += 2) {
		const value = number(raw.runs[i], 0, 255, 'Wall pixel', true);
		const count = number(raw.runs[i + 1], 1, area, 'Wall run', true);
		total += count;
		if (total > area) throw new Error('Wall drawing exceeds its dimensions.');
		runs.push(value, count);
	}
	if (total !== area) throw new Error('Wall drawing does not fill its dimensions.');
	return { width, height, runs };
}

export function decodeWalls(walls: SceneWalls): {
	width: number;
	height: number;
	data: Uint8Array;
} {
	const checked = validateWalls(walls);
	const data = new Uint8Array(checked.width * checked.height);
	let offset = 0;
	for (let i = 0; i < checked.runs.length; i += 2) {
		data.fill(checked.runs[i], offset, offset + checked.runs[i + 1]);
		offset += checked.runs[i + 1];
	}
	return { width: checked.width, height: checked.height, data };
}

function validateCamera(value: unknown): SceneCamera {
	const camera = record(value, 'Camera');
	return {
		azimuth: number(camera.azimuth, -1e6, 1e6, 'Camera azimuth'),
		elevation: number(camera.elevation, -Math.PI / 2, Math.PI / 2, 'Camera elevation'),
		distance: number(camera.distance, 0.01, 100, 'Camera distance'),
		panX: number(camera.panX, -100, 100, 'Camera pan X'),
		panY: number(camera.panY, -100, 100, 'Camera pan Y')
	};
}

export function newSceneId(): string {
	return `scene-${globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`}`;
}

function timestamp(value: unknown, label: string): string {
	const date = text(value, 40, label);
	if (!Number.isFinite(Date.parse(date))) throw new Error(`${label} is invalid.`);
	return new Date(date).toISOString();
}

/** Construct a fresh object; unknown/imported keys are never applied to the stores. */
export function validateScene(value: unknown): Scene {
	const raw = record(value, 'Scene');
	// Supports the old Shift-click export, which was a bare SimulationParams object.
	const legacy = raw.params === undefined && Array.isArray(raw.species);
	if (!legacy && raw.version !== SCENE_VERSION)
		throw new Error('This scene version is not supported.');
	const scene: Scene = {
		version: SCENE_VERSION,
		id: raw.id === undefined ? newSceneId() : text(raw.id, 100, 'Scene ID'),
		name: raw.name === undefined ? 'Imported scene' : text(raw.name, 80, 'Scene name'),
		createdAt:
			raw.createdAt === undefined
				? new Date().toISOString()
				: timestamp(raw.createdAt, 'Creation date'),
		params: validateParams(legacy ? raw : raw.params)
	};
	if (raw.description !== undefined) scene.description = text(raw.description, 500, 'Description');
	if (raw.updatedAt !== undefined) scene.updatedAt = timestamp(raw.updatedAt, 'Update date');
	if (raw.thumbnail !== undefined) {
		if (
			typeof raw.thumbnail !== 'string' ||
			raw.thumbnail.length > 200_000 ||
			!/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/.test(raw.thumbnail)
		)
			throw new Error('Scene preview must be a small PNG, JPEG, or WebP image.');
		scene.thumbnail = raw.thumbnail;
	}
	if (raw.walls !== undefined) scene.walls = validateWalls(raw.walls);
	if (raw.camera !== undefined) scene.camera = validateCamera(raw.camera);
	return scene;
}

export function parseScene(json: string): Scene {
	if (json.length > MAX_SCENE_BYTES)
		throw new Error('This file is too large. Scene files must be smaller than 5 MB.');
	try {
		return validateScene(JSON.parse(json));
	} catch (error) {
		if (error instanceof SyntaxError) throw new Error('This file is not valid scene JSON.');
		throw error;
	}
}

export function serializeScene(scene: Scene): string {
	const serialized = JSON.stringify(validateScene(scene), null, 2);
	if (serialized.length > MAX_SCENE_BYTES)
		throw new Error('This scene is too detailed to export. Simplify the wall drawing.');
	return serialized;
}

export function encodeSceneHash(scene: Scene): string {
	const checked = validateScene(scene);
	const compactParams = Object.fromEntries(
		Object.entries(checked.params).filter(
			([key, value]) =>
				JSON.stringify(value) !== JSON.stringify(DEFAULT_PARAMS[key as keyof SimulationParams])
		)
	);
	// Always include species, even when all values happen to equal the defaults.
	compactParams.species = checked.params.species;
	const compact = JSON.stringify({
		version: SCENE_VERSION,
		name: checked.name,
		params: compactParams,
		walls: checked.walls,
		camera: checked.camera
	});
	const bytes = new TextEncoder().encode(compact);
	let binary = '';
	for (const byte of bytes) binary += String.fromCharCode(byte);
	const hash = `#scene=${btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`;
	if (hash.length > MAX_SHARE_LENGTH)
		throw new Error('This scene is too detailed for a share link. Export its JSON file instead.');
	return hash;
}

export function decodeSceneHash(hash: string): Scene | null {
	if (!hash.startsWith('#scene=')) return null;
	if (hash.length > MAX_SHARE_LENGTH)
		throw new Error('This share link is too large. Import the scene file instead.');
	try {
		const encoded = hash.slice(7);
		if (!/^[A-Za-z0-9_-]+$/.test(encoded)) throw new Error('Invalid encoding');
		const binary = atob(encoded.replace(/-/g, '+').replace(/_/g, '/'));
		return parseScene(
			new TextDecoder('utf-8', { fatal: true }).decode(
				Uint8Array.from(binary, (c) => c.charCodeAt(0))
			)
		);
	} catch (error) {
		if (error instanceof Error && !(error instanceof DOMException)) throw error;
		throw new Error('This scene link is invalid.');
	}
}
