import { get, writable } from 'svelte/store';
import {
	params,
	needsBufferReallocation,
	wallTool,
	WallTool,
	exportWallSnapshot,
	restoreWallSnapshot
} from './simulation';
import {
	SCENE_VERSION,
	MAX_SAVED_SCENES,
	MAX_SCENE_BYTES,
	MAX_SHARE_LENGTH,
	newSceneId,
	validateScene,
	parseScene,
	serializeScene,
	encodeWalls,
	decodeWalls,
	encodeSceneHash,
	decodeSceneHash,
	type Scene,
	type SceneCamera
} from '../scenes/format';

export { BUILTIN_SCENES } from '../scenes/presets';
export type { Scene, SceneCamera, SceneWalls } from '../scenes/format';

export const SCENES_STORAGE_KEY = 'swarm.scenes.v1';
export const savedScenes = writable<Scene[]>([]);
export const isSceneLibraryOpen = writable(false);
export const sceneStatus = writable('');
export const sceneError = writable<string | null>(null);
export const undoAvailable = writable(false);
export const deletedSceneName = writable<string | null>(null);
export const canUndoSceneLoad = writable(false);

let initialized = false;
let storageUnreadable = false;
let deleted: { scene: Scene; index: number } | null = null;
let previousScene: Scene | null = null;
let cameraHandlers: {
	capture: () => SceneCamera | undefined;
	restore: (camera?: SceneCamera) => void;
} | null = null;

export function registerSceneCameraHandlers(
	handlers: NonNullable<typeof cameraHandlers>
): () => void {
	cameraHandlers = handlers;
	return () => {
		if (cameraHandlers === handlers) cameraHandlers = null;
	};
}

function failure(error: unknown): void {
	sceneError.set(error instanceof Error ? error.message : 'The scene could not be saved.');
	sceneStatus.set('');
}

function success(message: string): void {
	sceneError.set(null);
	sceneStatus.set(message);
}

export function initializeScenes(): void {
	if (initialized || typeof window === 'undefined') return;
	initialized = true;
	try {
		const stored = window.localStorage.getItem(SCENES_STORAGE_KEY);
		if (!stored) return;
		if (stored.length > MAX_SCENE_BYTES * MAX_SAVED_SCENES)
			throw new Error('The scene library is too large to read.');
		const library = JSON.parse(stored);
		if (
			library?.version !== SCENE_VERSION ||
			!Array.isArray(library.scenes) ||
			library.scenes.length > MAX_SAVED_SCENES
		)
			throw new Error('The saved scene library has an unsupported format.');
		const scenes = library.scenes.map((scene: unknown) => validateScene(scene));
		if (new Set(scenes.map((scene: Scene) => scene.id)).size !== scenes.length)
			throw new Error('The saved scene library contains duplicate IDs.');
		savedScenes.set(scenes);
	} catch {
		storageUnreadable = true;
		failure(
			new Error(
				'The saved library could not be read. Existing browser data has been preserved. You can still load starter scenes and export the current scene.'
			)
		);
	}
}

/** Commit storage before publishing state, so a quota failure leaves the old library intact. */
function persist(scenes: Scene[]): void {
	initializeScenes();
	if (typeof window === 'undefined') throw new Error('Scene saving is available in the browser.');
	if (storageUnreadable)
		throw new Error(
			'The saved library cannot be updated because its browser data could not be read. Export this scene to keep a copy.'
		);
	if (scenes.length > MAX_SAVED_SCENES)
		throw new Error(
			`Your library is full (${MAX_SAVED_SCENES} scenes). Export or delete a scene to make room.`
		);
	try {
		window.localStorage.setItem(
			SCENES_STORAGE_KEY,
			JSON.stringify({ version: SCENE_VERSION, scenes })
		);
	} catch {
		throw new Error(
			'Browser storage is full or unavailable. Your existing scenes are safe. Export this scene, or delete an older scene and try again.'
		);
	}
	savedScenes.set(scenes);
}

export function captureScene(name: string, thumbnail?: string): Scene {
	return validateScene({
		version: SCENE_VERSION,
		id: newSceneId(),
		name,
		createdAt: new Date().toISOString(),
		params: get(params),
		walls: encodeWalls(exportWallSnapshot()),
		camera: cameraHandlers?.capture(),
		...(thumbnail ? { thumbnail } : {})
	});
}

export function saveScene(scene: Scene): Scene | null {
	try {
		initializeScenes();
		const checked = validateScene(scene);
		// Also enforce the per-scene size budget for scenes created locally.
		serializeScene(checked);
		const library = get(savedScenes);
		const existingIndex = library.findIndex((entry) => entry.id === checked.id);
		if (existingIndex >= 0) {
			const next = [...library];
			next[existingIndex] = { ...checked, updatedAt: new Date().toISOString() };
			persist(next);
		} else {
			persist([checked, ...library]);
		}
		success(`Saved “${checked.name}”.`);
		return checked;
	} catch (error) {
		failure(error);
		return null;
	}
}

export function saveCurrentScene(name: string, thumbnail?: string): Scene | null {
	try {
		return saveScene(captureScene(name, thumbnail));
	} catch (error) {
		failure(error);
		return null;
	}
}

function apply(scene: Scene): void {
	const wallSnapshot = scene.walls ? decodeWalls(scene.walls) : null;
	wallTool.set(WallTool.None);
	params.set(structuredClone(scene.params));
	restoreWallSnapshot(wallSnapshot);
	needsBufferReallocation.set(true);
	cameraHandlers?.restore(scene.camera);
}

export function loadScene(scene: Scene): boolean {
	try {
		const checked = validateScene(scene);
		const before = captureScene('Previous scene');
		apply(checked);
		previousScene = before;
		canUndoSceneLoad.set(true);
		success(`Loaded “${checked.name}”. Particles start fresh.`);
		return true;
	} catch (error) {
		failure(error);
		return false;
	}
}

export function undoSceneLoad(): boolean {
	if (!previousScene) return false;
	try {
		apply(previousScene);
		previousScene = null;
		canUndoSceneLoad.set(false);
		success('Restored the previous scene settings and walls.');
		return true;
	} catch (error) {
		failure(error);
		return false;
	}
}

export function renameScene(id: string, name: string): boolean {
	try {
		initializeScenes();
		const scene = get(savedScenes).find((entry) => entry.id === id);
		if (!scene) throw new Error('This saved scene could not be found.');
		return saveScene({ ...scene, name }) !== null;
	} catch (error) {
		failure(error);
		return false;
	}
}

export function deleteScene(id: string): boolean {
	try {
		initializeScenes();
		const library = get(savedScenes);
		const index = library.findIndex((entry) => entry.id === id);
		if (index === -1) throw new Error('This saved scene could not be found.');
		persist(library.filter((entry) => entry.id !== id));
		deleted = { scene: library[index], index };
		deletedSceneName.set(deleted.scene.name);
		undoAvailable.set(true);
		success(`Deleted “${deleted.scene.name}”.`);
		return true;
	} catch (error) {
		failure(error);
		return false;
	}
}

export function undoDeleteScene(): boolean {
	if (!deleted) return false;
	try {
		const library = [...get(savedScenes)];
		if (library.some((scene) => scene.id === deleted!.scene.id))
			throw new Error('That scene already exists in your library.');
		library.splice(Math.min(deleted.index, library.length), 0, deleted.scene);
		persist(library);
		success(`Restored “${deleted.scene.name}”.`);
		deleted = null;
		deletedSceneName.set(null);
		undoAvailable.set(false);
		return true;
	} catch (error) {
		failure(error);
		return false;
	}
}

export function importScene(json: string): Scene | null {
	try {
		const imported = parseScene(json);
		// Imports are copies; an external ID cannot overwrite a local scene.
		return saveScene({
			...imported,
			id: newSceneId(),
			createdAt: new Date().toISOString(),
			updatedAt: undefined
		});
	} catch (error) {
		failure(error);
		return null;
	}
}

export function exportScene(scene: Scene): string {
	try {
		const json = serializeScene(scene);
		success(`Exported “${scene.name}”.`);
		return json;
	} catch (error) {
		failure(error);
		return '';
	}
}

export function shareScene(scene: Scene): string | null {
	try {
		if (typeof window === 'undefined')
			throw new Error('Scene sharing is available in the browser.');
		const url = new URL(window.location.href);
		url.hash = encodeSceneHash(scene);
		if (url.href.length > MAX_SHARE_LENGTH)
			throw new Error('This scene is too detailed for a share link. Export its JSON file instead.');
		success('Share link ready. Opening it starts this scene with fresh particles.');
		return url.href;
	} catch (error) {
		failure(error);
		return null;
	}
}

export function loadSceneFromHash(): boolean {
	if (typeof window === 'undefined') return false;
	if (window.location.hash.startsWith('#scene=')) isSceneLibraryOpen.set(true);
	try {
		const scene = decodeSceneHash(window.location.hash);
		return scene ? loadScene(scene) : false;
	} catch (error) {
		failure(error);
		return false;
	}
}
