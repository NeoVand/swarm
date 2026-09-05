import assert from 'node:assert/strict';
import test from 'node:test';
import { get } from 'svelte/store';
import {
	validateScene,
	parseScene,
	validateParams,
	serializeScene,
	encodeWalls,
	decodeWalls,
	encodeSceneHash,
	decodeSceneHash,
	MAX_WALL_PIXELS
} from '../src/lib/scenes/format';
import { BUILTIN_SCENES } from '../src/lib/scenes/presets';
import { DEFAULT_PARAMS } from '../src/lib/webgpu/types';
import {
	params,
	initWallData,
	restoreWallSnapshot,
	exportWallSnapshot,
	isRunning,
	setPopulation,
	removeSpecies
} from '../src/lib/stores/simulation';
import {
	initializeScenes,
	savedScenes,
	saveCurrentScene,
	saveScene,
	sceneError,
	deleteScene,
	undoDeleteScene,
	undoAvailable,
	renameScene,
	importScene,
	loadScene,
	undoSceneLoad,
	canUndoSceneLoad,
	registerSceneCameraHandlers,
	SCENES_STORAGE_KEY,
	shareScene,
	loadSceneFromHash,
	isSceneLibraryOpen
} from '../src/lib/stores/scenes';

function fresh(index = 0) {
	return structuredClone(BUILTIN_SCENES[index]);
}

// A minimal browser storage adapter makes quota and edit semantics testable without a GPU.
const storage = new Map<string, string>();
let storageWrites = 0;
let rejectWrites = false;
const browser = {
	location: new URL('https://example.test/swarm/'),
	localStorage: {
		getItem(key: string) {
			return storage.get(key) ?? null;
		},
		setItem(key: string, value: string) {
			if (rejectWrites) throw new DOMException('Full', 'QuotaExceededError');
			storageWrites++;
			storage.set(key, value);
		}
	}
};
Object.defineProperty(globalThis, 'window', { configurable: true, value: browser });

test('starter scenes all validate and provide distinct behavior and topology', () => {
	assert.equal(BUILTIN_SCENES.length, 6);
	for (const scene of BUILTIN_SCENES) {
		assert.equal(
			validateScene(scene).params.population,
			scene.params.species.reduce((sum, s) => sum + s.population, 0)
		);
		assert.ok(scene.params.population <= 4000);
	}
	assert.ok(new Set(BUILTIN_SCENES.map((s) => s.params.boundaryMode)).size >= 4);
	assert.ok(
		new Set(
			BUILTIN_SCENES.flatMap((s) =>
				s.params.species.flatMap((sp) => sp.interactions.map((r) => r.behavior))
			)
		).size >= 5
	);
});

test('scene export/import is detached and accepts the old raw parameters export', () => {
	const scene = fresh();
	const restored = parseScene(serializeScene(scene));
	assert.deepEqual(restored, scene);
	restored.params.species[0].name = 'Edited';
	assert.notEqual(restored.params.species[0].name, scene.params.species[0].name);
	assert.deepEqual(
		parseScene(JSON.stringify(DEFAULT_PARAMS)).params,
		validateParams(DEFAULT_PARAMS)
	);
});

test('unknown data cannot introduce store fields or unsafe previews', () => {
	const scene = fresh();
	assert.equal('extra' in validateScene({ ...scene, extra: 'ignored' }), false);
	assert.throws(
		() => validateScene({ ...scene, thumbnail: 'data:image/svg+xml;base64,PHN2Zz4=' }),
		/preview/
	);
	assert.throws(() => validateScene({ ...scene, version: 2 }), /version/);
	assert.throws(() => parseScene('{ nope'), /valid scene JSON/);
});

test('non-finite, invalid enum, population and rule budgets are rejected', () => {
	for (const value of [NaN, Infinity, -Infinity]) {
		assert.throws(
			() => validateScene({ ...fresh(), params: { ...fresh().params, maxSpeed: value } }),
			/maxSpeed/
		);
	}
	assert.throws(
		() => validateScene({ ...fresh(), params: { ...fresh().params, colorMode: 10 } }),
		/colorMode/
	);
	const scene = fresh(1);
	scene.params.population++;
	assert.throws(() => validateScene(scene), /Total population/);
	scene.params.population--;
	scene.params.species[0].interactions.push(
		...Array.from({ length: 3 }, () => ({
			type: 'metric' as const,
			behavior: 1,
			strength: 0.5,
			range: 0,
			metricSource: 0,
			metricRole: 0,
			curve: [
				{ x: 0, y: 0 },
				{ x: 1, y: 1 }
			]
		}))
	);
	assert.throws(() => validateScene(scene), /at most two/);
});

test('duplicate IDs, absent targets and duplicate curve positions are rejected', () => {
	const scene = fresh(1);
	scene.params.species[1].id = 0;
	assert.throws(() => validateScene(scene), /unique/);
	const missing = fresh(1);
	missing.params.species[0].interactions[0].targetSpecies = 6;
	assert.throws(() => validateScene(missing), /another species/);
	const points = fresh();
	points.params.hueCurvePoints = [
		{ x: 0.5, y: 0 },
		{ x: 0.5, y: 1 }
	];
	assert.throws(() => validateScene(points), /distinct/);
});

test('wall RLE round-trips and rejects excessive allocation and invalid lengths', () => {
	const snapshot = {
		width: 4,
		height: 2,
		data: Uint8Array.from([0, 0, 255, 255, 255, 0, 128, 128])
	};
	assert.deepEqual(decodeWalls(encodeWalls(snapshot)!), snapshot);
	assert.equal(encodeWalls({ width: 2, height: 2, data: new Uint8Array(4) }), undefined);
	assert.throws(() => decodeWalls({ width: 2, height: 2, runs: [255, 5] }), /Wall run/);
	assert.throws(() => decodeWalls({ width: 2, height: 2, runs: [0, 2] }), /fill/);
	assert.throws(() => decodeWalls({ width: 2, height: 2, runs: [0, 2, 255, 3] }), /exceeds/);
	assert.throws(
		() => decodeWalls({ width: 4096, height: 4096, runs: [0, MAX_WALL_PIXELS] }),
		/size/
	);
});

test('share links preserve Unicode names and scene settings while omitting previews', () => {
	const scene = fresh(1);
	scene.name = '海の群れ · 🐟';
	scene.thumbnail = 'data:image/png;base64,YQ==';
	const restored = decodeSceneHash(encodeSceneHash(scene))!;
	assert.equal(restored.name, scene.name);
	assert.deepEqual(restored.params, validateScene(scene).params);
	assert.equal(restored.thumbnail, undefined);
	assert.equal(decodeSceneHash('#other'), null);
	assert.throws(() => decodeSceneHash('#scene=%%%'));
});

test('sharing overly detailed walls returns an export recommendation', () => {
	const scene = fresh();
	scene.walls = {
		width: 100,
		height: 100,
		runs: Array.from({ length: 20000 }, (_, i) => (i % 2 ? 1 : i % 4 ? 255 : 0))
	};
	assert.throws(() => encodeSceneHash(scene), /Export/);
});

test('initialization is idempotent and writes only happen on library edits', () => {
	initializeScenes();
	initializeScenes();
	assert.equal(storageWrites, 0);
	assert.deepEqual(get(savedScenes), []);
	const saved = saveCurrentScene('My scene');
	assert.ok(saved);
	assert.equal(storageWrites, 1);
	assert.equal(get(savedScenes).length, 1);
	assert.equal(JSON.parse(storage.get(SCENES_STORAGE_KEY)!).scenes[0].name, 'My scene');
});

test('quota failure preserves both persisted and observable scenes', () => {
	const before = storage.get(SCENES_STORAGE_KEY);
	const scenes = get(savedScenes);
	rejectWrites = true;
	assert.equal(saveCurrentScene('Too much'), null);
	assert.equal(storage.get(SCENES_STORAGE_KEY), before);
	assert.equal(get(savedScenes), scenes);
	assert.match(get(sceneError)!, /existing scenes are safe/);
	rejectWrites = false;
});

test('rename and delete can be undone without losing the library order', () => {
	const scene = get(savedScenes)[0];
	assert.equal(renameScene(scene.id, 'Renamed'), true);
	const before = get(savedScenes);
	assert.equal(deleteScene(scene.id), true);
	assert.equal(get(undoAvailable), true);
	assert.equal(undoDeleteScene(), true);
	assert.deepEqual(get(savedScenes), before);
	assert.equal(get(undoAvailable), false);
});

test('external IDs never overwrite existing scenes on import', () => {
	const original = get(savedScenes)[0];
	const imported = importScene(JSON.stringify({ ...original, name: 'External copy' }))!;
	assert.ok(imported);
	assert.notEqual(imported.id, original.id);
	assert.equal(get(savedScenes).find((s) => s.id === original.id)?.name, 'Renamed');
	assert.equal(importScene('{'), null);
});

test('loading and undo restore parameters, walls and camera while preserving pause', () => {
	initWallData(16, 16);
	restoreWallSnapshot({
		width: 4,
		height: 4,
		data: Uint8Array.from({ length: 16 }, (_, i) => (i < 8 ? 255 : 0))
	});
	params.set(structuredClone(DEFAULT_PARAMS));
	isRunning.set(false);
	let camera = { azimuth: 0.2, elevation: 0.3, distance: 3, panX: 0.1, panY: -0.1 };
	const beforeCamera = { ...camera };
	const cleanup = registerSceneCameraHandlers({
		capture: () => ({ ...camera }),
		restore: (next) => {
			camera = next ? { ...next } : { azimuth: 0, elevation: 0, distance: 1, panX: 0, panY: 0 };
		}
	});
	const beforeWalls = exportWallSnapshot();
	const beforeParams = get(params);
	const writes = storageWrites;
	assert.equal(loadScene(fresh(1)), true);
	assert.equal(get(canUndoSceneLoad), true);
	assert.equal(get(isRunning), false);
	assert.ok(exportWallSnapshot()!.data.every((v) => v === 0));
	assert.equal(undoSceneLoad(), true);
	assert.deepEqual(get(params), validateParams(beforeParams));
	assert.deepEqual(exportWallSnapshot(), beforeWalls);
	assert.deepEqual(camera, beforeCamera);
	assert.equal(get(canUndoSceneLoad), false);
	assert.equal(storageWrites, writes);
	cleanup();
});

test('invalid scene loading is atomic and shared scene errors reveal the library', () => {
	const before = get(params);
	const invalid = fresh();
	invalid.params.maxSpeed = NaN;
	assert.equal(loadScene(invalid), false);
	assert.equal(get(params), before);
	browser.location.hash = '#scene=%%%';
	assert.equal(loadSceneFromHash(), false);
	assert.equal(get(isSceneLibraryOpen), true);
	assert.ok(get(sceneError));
	browser.location.hash = '';
});

test('browser share URL opens the expected scene without writing library storage', () => {
	const scene = fresh(2);
	const writes = storageWrites;
	const link = shareScene(scene);
	assert.ok(link?.startsWith('https://example.test/swarm/#scene='));
	browser.location.hash = new URL(link!).hash;
	assert.equal(loadSceneFromHash(), true);
	assert.deepEqual(get(params), validateParams(scene.params));
	assert.equal(storageWrites, writes);
});

test('save rejects unsafe payloads without mutating the library', () => {
	const before = get(savedScenes);
	const scene = fresh();
	scene.params.species[0].population = 100001;
	scene.params.population = 100001;
	assert.equal(saveScene(scene), null);
	assert.equal(get(savedScenes), before);
});

test('a single species grown to 50,000 by the population shortcut remains saveable', () => {
	const scene = fresh();
	scene.params.species[0].population = 50000;
	scene.params.population = 50000;
	assert.equal(validateScene(scene).params.species[0].population, 50000);
});

test('population changes keep exact totals and positive species counts at small and large sizes', () => {
	for (const requested of [100, 1, 50000]) {
		params.set(structuredClone(DEFAULT_PARAMS));
		setPopulation(requested);
		const result = get(params);
		const expected = Math.max(requested, DEFAULT_PARAMS.species.length);
		assert.equal(result.population, expected);
		assert.equal(
			result.species.reduce((sum, species) => sum + species.population, 0),
			expected
		);
		assert.ok(
			result.species.every(
				(species) => Number.isInteger(species.population) && species.population >= 1
			)
		);
		assert.deepEqual(
			result.species.map((species) => species.id),
			DEFAULT_PARAMS.species.map((species) => species.id)
		);
		assert.equal(validateParams(result).population, expected);
		if (requested === 50000) {
			for (const species of result.species) {
				const original = DEFAULT_PARAMS.species.find((entry) => entry.id === species.id)!;
				assert.ok(
					Math.abs(
						species.population / expected - original.population / DEFAULT_PARAMS.population
					) < 0.001
				);
			}
		}
	}
});

test('removing the main species cleans its relationships and leaves the rare species exact count', () => {
	const original = fresh(1).params;
	const metricRule = {
		type: 'metric' as const,
		behavior: 1,
		strength: 0.5,
		range: 0,
		metricSource: 0,
		metricRole: 0,
		curve: [
			{ x: 0, y: 0 },
			{ x: 1, y: 1 }
		]
	};
	original.species[1].interactions.push(
		{ targetSpecies: -1, behavior: 1, strength: 0.2, range: 0 },
		metricRule
	);
	params.set(original);
	removeSpecies(0);
	const result = get(params);
	assert.equal(result.species.length, 1);
	assert.equal(result.population, 80);
	assert.equal(result.population, result.species[0].population);
	assert.equal(result.activeSpeciesId, 1);
	assert.ok(
		result.species.every((species) =>
			species.interactions.every((rule) => rule.type === 'metric' || rule.targetSpecies !== 0)
		)
	);
	assert.deepEqual(result.species[0].interactions, [
		{ targetSpecies: -1, behavior: 1, strength: 0.2, range: 0 },
		metricRule
	]);
	assert.equal(validateParams(result).population, 80);
});

test('painted walls survive resize and scene round-trip without sharing snapshot memory', () => {
	const original = { width: 4, height: 2, data: Uint8Array.from([0, 255, 0, 0, 255, 255, 128, 0]) };
	initWallData(16, 8);
	restoreWallSnapshot(original);
	const detached = exportWallSnapshot()!;
	detached.data[0] = 99;
	assert.equal(exportWallSnapshot()!.data[0], 0);
	const encoded = encodeWalls(exportWallSnapshot())!;
	initWallData(32, 16);
	const enlarged = exportWallSnapshot()!;
	assert.equal(enlarged.width, 8);
	assert.equal(enlarged.height, 4);
	assert.deepEqual(
		Array.from(enlarged.data),
		[
			0, 0, 255, 255, 0, 0, 0, 0, 0, 0, 255, 255, 0, 0, 0, 0, 255, 255, 255, 255, 128, 128, 0, 0,
			255, 255, 255, 255, 128, 128, 0, 0
		]
	);
	restoreWallSnapshot(null);
	restoreWallSnapshot(decodeWalls(encoded));
	assert.deepEqual(exportWallSnapshot(), enlarged);
	initWallData(16, 8);
	assert.deepEqual(exportWallSnapshot(), original);
	original.data.fill(0);
	assert.equal(exportWallSnapshot()!.data[1], 255);
});
