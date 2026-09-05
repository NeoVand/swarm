<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { canvasElement, isWebGPUAvailable } from '$lib/stores/simulation';
	import {
		BUILTIN_SCENES,
		savedScenes,
		sceneStatus,
		sceneError,
		undoAvailable,
		deletedSceneName,
		initializeScenes,
		captureScene,
		saveCurrentScene,
		loadScene,
		renameScene,
		deleteScene,
		undoDeleteScene,
		canUndoSceneLoad,
		undoSceneLoad,
		importScene,
		exportScene,
		shareScene,
		type Scene
	} from '$lib/stores/scenes';
	import ScenePreview from './ScenePreview.svelte';

	let { onclose }: { onclose: () => void } = $props();
	const uid = $props.id();
	let collection = $state<'explore' | 'saved'>('explore');
	let sceneName = $state('');
	let saving = $state(false);
	let loadedId = $state<string | null>(null);
	let editingId = $state<string | null>(null);
	let editedName = $state('');
	let shareUrl = $state('');
	let visibleScenes = $derived(collection === 'explore' ? BUILTIN_SCENES : $savedScenes);
	const topologyNames = [
		'Plane',
		'Cylinder',
		'Cylinder',
		'Torus',
		'Möbius',
		'Möbius',
		'Klein',
		'Klein',
		'Roman'
	];
	const icons = {
		back: 'M14 5 7 12l7 7',
		plus: 'M12 5v14M5 12h14',
		check: 'm5 12 4 4L19 6',
		more: 'M5 12h.01M12 12h.01M19 12h.01',
		import: 'M12 3v12m-4-4 4 4 4-4M5 15v5h14v-5',
		export: 'M12 16V4m-4 4 4-4 4 4M5 15v5h14v-5',
		link: 'M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2',
		edit: 'm16 3 5 5-12 12-6 1 1-6L16 3Zm-1 1 5 5',
		trash: 'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7',
		close: 'm6 6 12 12M6 18 18 6',
		bookmark: 'M6 3h12v18l-6-4-6 4V3Z',
		undo: 'M3 10h12a6 6 0 0 1 0 12M3 10l5-5M3 10l5 5'
	};

	onMount(initializeScenes);

	function focusField(field: 'name' | 'rename' | 'share') {
		const input = document.getElementById(`${uid}-${field}`);
		if (input instanceof HTMLInputElement) {
			input.focus();
			input.select();
		}
	}

	function selectCollection(value: 'explore' | 'saved') {
		collection = value;
		editingId = null;
		shareUrl = '';
	}

	function applyScene(scene: Scene) {
		if (!$isWebGPUAvailable) return;
		if (loadScene(scene)) loadedId = scene.id;
	}

	function captureThumbnail(): string | undefined {
		const source = $canvasElement;
		if (!source || !source.width || !source.height) return;
		try {
			const thumbnail = document.createElement('canvas');
			thumbnail.width = 280;
			thumbnail.height = 180;
			const context = thumbnail.getContext('2d');
			if (!context) return;
			const scale = Math.max(thumbnail.width / source.width, thumbnail.height / source.height);
			const width = source.width * scale;
			const height = source.height * scale;
			context.drawImage(source, (280 - width) / 2, (180 - height) / 2, width, height);
			return thumbnail.toDataURL('image/jpeg', 0.75);
		} catch {
			return;
		}
	}

	async function saveScene(event: SubmitEvent) {
		event.preventDefault();
		if (saving || !sceneName.trim() || !$isWebGPUAvailable) return;
		saving = true;
		try {
			await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
			const saved = saveCurrentScene(sceneName.trim(), captureThumbnail());
			if (saved) {
				collection = 'saved';
				loadedId = saved.id;
				sceneName = '';
			}
		} finally {
			saving = false;
		}
	}

	function closeActions(event: MouseEvent) {
		(event.currentTarget as HTMLElement).closest('details')?.removeAttribute('open');
	}

	async function beginRename(event: MouseEvent, scene: Scene) {
		closeActions(event);
		editingId = scene.id;
		editedName = scene.name;
		shareUrl = '';
		await tick();
		focusField('rename');
	}

	function finishRename(event: SubmitEvent) {
		event.preventDefault();
		if (editingId && renameScene(editingId, editedName.trim())) editingId = null;
	}

	function downloadScene(event: MouseEvent, scene: Scene) {
		closeActions(event);
		try {
			const json = exportScene(scene);
			if (!json) return;
			const blob = new Blob([json], { type: 'application/json' });
			const url = URL.createObjectURL(blob);
			const anchor = document.createElement('a');
			anchor.href = url;
			anchor.download = `${scene.name.replace(/[^a-z0-9-]+/gi, '-').toLowerCase() || 'swarm'}-scene.json`;
			anchor.click();
			setTimeout(() => URL.revokeObjectURL(url), 1000);
			sceneError.set(null);
			sceneStatus.set(`Exported “${scene.name}”.`);
		} catch {
			sceneError.set('This scene could not be exported. Please try again.');
		}
	}

	function exportCurrent(event: MouseEvent) {
		try {
			downloadScene(event, captureScene(sceneName.trim() || 'Untitled scene'));
		} catch {
			sceneError.set('The current scene could not be exported. Please try again.');
		}
	}

	async function copySceneLink(event: MouseEvent, scene: Scene) {
		closeActions(event);
		const url = shareScene(scene);
		if (!url) return;
		try {
			await navigator.clipboard.writeText(url);
			shareUrl = '';
			sceneStatus.set('Scene link copied.');
		} catch {
			shareUrl = url;
			sceneStatus.set('Copy the scene link below.');
			await tick();
			focusField('share');
		}
	}

	function removeScene(event: MouseEvent, scene: Scene) {
		closeActions(event);
		if (deleteScene(scene.id) && editingId === scene.id) editingId = null;
	}

	async function importFile(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		try {
			if (file.size > 5_000_000) {
				sceneError.set('Choose a scene file smaller than 5 MB.');
				return;
			}
			if (importScene(await file.text())) collection = 'saved';
		} catch {
			sceneError.set('This file could not be read. Choose a Swarm scene JSON file.');
		} finally {
			input.value = '';
		}
	}
</script>

{#snippet icon(name: keyof typeof icons, size = 14)}
	<svg
		width={size}
		height={size}
		viewBox="0 0 24 24"
		fill="none"
		stroke="currentColor"
		stroke-width="1.6"
		stroke-linecap="round"
		stroke-linejoin="round"
		aria-hidden="true"
	>
		<path d={icons[name]} />
	</svg>
{/snippet}

<section class="scene-library" aria-labelledby="{uid}-heading" data-scene-library>
	<button type="button" class="back-button" onclick={onclose}>
		{@render icon('back', 12)}
		Controls
	</button>

	<div class="heading-row">
		<h2 id="{uid}-heading">Scenes</h2>
		<span class="collection-mark">COLLECTION</span>
	</div>
	<p class="intro">A starting point for your next discovery.</p>

	<div class="collection-switch" role="group" aria-label="Scene collection">
		<button
			type="button"
			class:active={collection === 'explore'}
			aria-pressed={collection === 'explore'}
			onclick={() => selectCollection('explore')}
		>
			Explore <span>{BUILTIN_SCENES.length}</span>
		</button>
		<button
			type="button"
			class:active={collection === 'saved'}
			aria-pressed={collection === 'saved'}
			onclick={() => selectCollection('saved')}
		>
			Saved <span>{$savedScenes.length}</span>
		</button>
	</div>

	{#if visibleScenes.length}
		<div class="scene-grid">
			{#each visibleScenes as scene (scene.id)}
				<article class="scene-card" class:loaded={loadedId === scene.id}>
					<button
						type="button"
						class="load-scene"
						disabled={!$isWebGPUAvailable}
						aria-label="Load {scene.name}"
						title={scene.description || `Load ${scene.name}`}
						onclick={() => applyScene(scene)}
					>
						<ScenePreview {scene} />
						{#if loadedId === scene.id}
							<span class="loaded-mark" aria-label="Loaded">{@render icon('check', 10)}</span>
						{/if}
						<span class="scene-copy">
							<span class="scene-name">{scene.name}</span>
							<span class="scene-meta"
								>{topologyNames[scene.params.boundaryMode] ?? 'World'}<span aria-hidden="true">
									·
								</span>{scene.params.species.length} species</span
							>
						</span>
					</button>
					{#if collection === 'saved'}
						<details class="scene-actions" name="{uid}-actions">
							<summary aria-label="Actions for {scene.name}" title="Scene actions"
								>{@render icon('more', 16)}</summary
							>
							<div class="action-menu">
								<button type="button" onclick={(event) => beginRename(event, scene)}
									>{@render icon('edit', 12)} Rename</button
								>
								<button type="button" onclick={(event) => downloadScene(event, scene)}
									>{@render icon('export', 12)} Export file</button
								>
								<button type="button" onclick={(event) => copySceneLink(event, scene)}
									>{@render icon('link', 12)} Copy link</button
								>
								<button
									type="button"
									class="delete-action"
									onclick={(event) => removeScene(event, scene)}
									>{@render icon('trash', 12)} Delete</button
								>
							</div>
						</details>
					{/if}
				</article>
			{/each}
		</div>
	{:else}
		<div class="empty-library">
			<span class="empty-icon">{@render icon('bookmark', 23)}</span>
			<h3>Keep a good discovery.</h3>
			<p>Save your settings, painted walls, and view. Your scenes stay in this browser.</p>
			<button type="button" onclick={() => focusField('name')}
				>Save your first scene {@render icon('plus', 11)}</button
			>
		</div>
	{/if}

	{#if editingId}
		<form class="inline-editor" onsubmit={finishRename}>
			<label for="{uid}-rename">Rename scene</label>
			<div class="input-row">
				<input
					id="{uid}-rename"
					bind:value={editedName}
					maxlength="80"
					required
					autocomplete="off"
				/>
				<button
					type="submit"
					class="square-button"
					aria-label="Save scene name"
					disabled={!editedName.trim()}>{@render icon('check')}</button
				>
				<button
					type="button"
					class="square-button muted-button"
					aria-label="Cancel rename"
					onclick={() => (editingId = null)}>{@render icon('close')}</button
				>
			</div>
		</form>
	{/if}

	<form class="save-scene" onsubmit={saveScene}>
		<label for="{uid}-name">Save current scene</label>
		<div class="input-row">
			<input
				id="{uid}-name"
				bind:value={sceneName}
				placeholder="Give it a name…"
				maxlength="80"
				required
				autocomplete="off"
			/>
			<button
				type="submit"
				class="save-button"
				disabled={saving || !sceneName.trim() || !$isWebGPUAvailable}
				>{saving ? 'Saving' : 'Save'}</button
			>
		</div>
		<p>Settings, walls & view. A fresh flock on load.</p>
	</form>

	{#if $sceneError || $sceneStatus || $undoAvailable}
		<div class="feedback" class:error={!!$sceneError} role="status" aria-live="polite">
			<span>{$sceneError || $sceneStatus}</span>
		</div>
	{/if}
	{#if $undoAvailable || $canUndoSceneLoad}
		<div class="undo-actions">
			{#if $canUndoSceneLoad}
				<button
					type="button"
					class="undo-button"
					onclick={() => {
						if (undoSceneLoad()) loadedId = null;
					}}>Undo scene load</button
				>
			{/if}
			{#if $undoAvailable}
				<button
					type="button"
					class="undo-button"
					onclick={undoDeleteScene}
					aria-label="Undo deletion of {$deletedSceneName || 'scene'}">Undo delete</button
				>
			{/if}
		</div>
	{/if}

	{#if shareUrl}
		<div class="share-fallback">
			<label for="{uid}-share">Scene link</label>
			<input
				id="{uid}-share"
				value={shareUrl}
				readonly
				onclick={(event) => event.currentTarget.select()}
			/>
		</div>
	{/if}

	<footer>
		<button
			type="button"
			class="import-button"
			onclick={() => document.getElementById(`${uid}-import`)?.click()}
			>{@render icon('import', 12)} Import scene</button
		>
		<button
			type="button"
			class="import-button"
			onclick={exportCurrent}
			title="Export current settings, walls and view as a JSON file"
			>{@render icon('export', 12)} Export current</button
		>
	</footer>
	<input
		id="{uid}-import"
		type="file"
		accept="application/json,.json"
		onchange={importFile}
		aria-label="Import scene file"
		hidden
	/>
</section>

<style>
	.scene-library {
		padding: 12px;
		color: #d4d4da;
	}
	button,
	input,
	summary {
		font: inherit;
	}
	button,
	summary {
		-webkit-tap-highlight-color: transparent;
	}
	button {
		cursor: pointer;
	}
	button:disabled {
		cursor: default;
		opacity: 0.36;
	}
	button:focus-visible,
	summary:focus-visible,
	input:focus-visible {
		outline: 2px solid #9f9cea;
		outline-offset: 3px;
	}
	.back-button {
		display: flex;
		align-items: center;
		gap: 3px;
		margin: 0 0 14px -3px;
		padding: 3px 0;
		border: 0;
		background: none;
		color: #95959f;
		font-size: 10px;
	}
	.back-button:hover {
		color: #ededf0;
	}
	.heading-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	h2 {
		margin: 0;
		color: #f0eff4;
		font-size: 18px;
		font-weight: 550;
		letter-spacing: -0.5px;
		line-height: 1.3;
	}
	.collection-mark {
		color: #747480;
		font-size: 7px;
		letter-spacing: 1.5px;
	}
	.intro {
		margin: 5px 0 15px;
		color: #93939f;
		font-size: 10px;
		line-height: 1.5;
	}
	.collection-switch {
		display: flex;
		gap: 3px;
		padding: 3px;
		margin-bottom: 13px;
		background: #08090d66;
		border: 1px solid #ffffff06;
		border-radius: 7px;
	}
	.collection-switch button {
		flex: 1;
		display: flex;
		justify-content: center;
		align-items: center;
		gap: 7px;
		min-height: 29px;
		padding: 0 5px;
		border: 1px solid transparent;
		border-radius: 4px;
		background: transparent;
		color: #91919c;
		font-size: 10px;
		transition:
			color 140ms,
			background 140ms;
	}
	.collection-switch button.active {
		border-color: #ffffff09;
		background: #ffffff0c;
		color: #efedf5;
		box-shadow: 0 1px 3px #0002;
	}
	.collection-switch button span {
		color: #777681;
		font-size: 8px;
		font-variant-numeric: tabular-nums;
	}
	.collection-switch button.active span {
		color: #b2abc8;
	}
	.scene-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 9px;
	}
	.scene-card {
		position: relative;
		min-width: 0;
		border: 1px solid #ffffff0c;
		border-radius: 7px;
		background: #ffffff02;
		transition:
			border-color 160ms,
			background 160ms;
	}
	.scene-card:hover {
		border-color: #a9a0d13d;
		background: #ffffff04;
	}
	.scene-card.loaded {
		border-color: #a9a0d169;
	}
	.load-scene {
		position: relative;
		display: block;
		width: 100%;
		padding: 0;
		border: 0;
		border-radius: 6px;
		background: none;
		text-align: left;
		overflow: hidden;
	}
	.scene-copy {
		display: block;
		min-height: 44px;
		padding: 8px 7px 7px;
	}
	.scene-name {
		display: block;
		overflow: hidden;
		color: #dddae7;
		font-size: 10px;
		font-weight: 500;
		line-height: 1.35;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.scene-meta {
		display: block;
		margin-top: 3px;
		color: #7d7b89;
		font-size: 8px;
		line-height: 1.3;
		white-space: nowrap;
	}
	.scene-meta span {
		padding: 0 1px;
	}
	.loaded-mark {
		position: absolute;
		top: 6px;
		right: 6px;
		display: grid;
		width: 17px;
		height: 17px;
		place-items: center;
		border: 1px solid #c4b5fd52;
		border-radius: 50%;
		background: #1c182fe6;
		color: #d7cbff;
	}
	.scene-actions {
		position: absolute;
		top: 4px;
		right: 4px;
		z-index: 1;
	}
	.scene-card.loaded .scene-actions {
		top: 25px;
	}
	.scene-actions summary {
		display: grid;
		width: 25px;
		height: 23px;
		list-style: none;
		place-items: center;
		border: 1px solid #ffffff0c;
		border-radius: 5px;
		background: #101018dd;
		color: #a9a7b7;
		cursor: pointer;
	}
	.scene-actions summary::-webkit-details-marker {
		display: none;
	}
	.scene-actions[open] {
		z-index: 5;
	}
	.scene-actions[open] summary,
	.scene-actions summary:hover {
		background: #282432;
		color: #e2ddec;
	}
	.action-menu {
		position: absolute;
		right: 0;
		top: 27px;
		display: grid;
		min-width: 120px;
		padding: 4px;
		border: 1px solid #ffffff14;
		border-radius: 7px;
		background: #191820;
		box-shadow: 0 7px 25px #0008;
	}
	.scene-card:nth-child(odd) .action-menu {
		left: 0;
		right: auto;
	}
	.action-menu button {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 31px;
		padding: 0 8px;
		border: 0;
		border-radius: 4px;
		background: none;
		color: #c4c1ce;
		font-size: 10px;
		text-align: left;
	}
	.action-menu button:hover {
		background: #ffffff09;
		color: #eeecf4;
	}
	.action-menu button.delete-action {
		color: #e799a6;
	}
	.empty-library {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 22px 14px 24px;
		border: 1px dashed #ffffff12;
		border-radius: 8px;
		text-align: center;
	}
	.empty-icon {
		color: #858094;
	}
	h3 {
		margin: 12px 0 6px;
		color: #d8d5e0;
		font-size: 12px;
		font-weight: 500;
	}
	.empty-library p {
		max-width: 180px;
		margin: 0;
		color: #878390;
		font-size: 10px;
		line-height: 1.65;
	}
	.empty-library button {
		display: flex;
		align-items: center;
		gap: 5px;
		margin-top: 13px;
		padding: 6px 0;
		border: 0;
		background: none;
		color: #b6accf;
		font-size: 10px;
	}
	.save-scene {
		margin-top: 17px;
		padding-top: 14px;
		border-top: 1px solid #ffffff0b;
	}
	label {
		display: block;
		margin-bottom: 7px;
		color: #b4b0bf;
		font-size: 10px;
	}
	.input-row {
		display: flex;
		align-items: stretch;
		gap: 5px;
	}
	input {
		width: 100%;
		min-width: 0;
		height: 32px;
		padding: 0 8px;
		border: 1px solid #ffffff12;
		border-radius: 5px;
		background: #09090f66;
		color: #e0dce9;
		font-size: 10px;
	}
	input::placeholder {
		color: #73707e;
	}
	input:focus {
		border-color: #a99dbb66;
	}
	.save-button,
	.square-button {
		display: flex;
		align-items: center;
		justify-content: center;
		min-width: 44px;
		padding: 0 10px;
		border: 1px solid #b6a2e12b;
		border-radius: 5px;
		background: #9980c51a;
		color: #c8badd;
		font-size: 10px;
	}
	.save-button:hover:not(:disabled),
	.square-button:hover:not(:disabled) {
		background: #9980c52c;
	}
	.save-scene p {
		margin: 7px 0 0;
		color: #76717f;
		font-size: 8px;
		line-height: 1.5;
	}
	.inline-editor,
	.share-fallback {
		margin-top: 13px;
	}
	.square-button {
		min-width: 31px;
		padding: 0;
	}
	.muted-button {
		background: transparent;
		color: #96909f;
		border-color: #ffffff10;
	}
	.feedback {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 7px;
		margin-top: 12px;
		padding: 9px;
		border: 1px solid #b6a2e11a;
		border-radius: 5px;
		background: #a18ac008;
		color: #b2a5c2;
		font-size: 9px;
		line-height: 1.5;
		overflow-wrap: anywhere;
	}
	.feedback.error {
		border-color: #fda4af24;
		background: #fb718508;
		color: #e1a0aa;
	}
	.undo-button {
		flex-shrink: 0;
		padding: 3px;
		border: 0;
		background: none;
		color: #dfd1f5;
		font-size: 9px;
		text-decoration: underline;
		text-underline-offset: 3px;
	}
	.undo-actions {
		display: flex;
		gap: 10px;
		margin-top: 5px;
	}
	footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-top: 14px;
		padding-top: 11px;
		border-top: 1px solid #ffffff08;
	}
	.import-button {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 4px 0;
		border: 0;
		background: none;
		color: #a6a0b1;
		font-size: 9px;
	}
	.import-button:hover {
		color: #e0d9ec;
	}
	@media (prefers-reduced-motion: reduce) {
		*,
		*::before,
		*::after {
			transition: none !important;
		}
	}
</style>
