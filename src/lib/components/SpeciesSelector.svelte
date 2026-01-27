<script lang="ts">
	import {
		params,
		setActiveSpecies,
		addSpecies,
		removeSpecies,
		MAX_SPECIES
	} from '$lib/stores/simulation';
	import { HeadShape } from '$lib/webgpu/types';
	import { getShapePath } from '$lib/utils/shapes';
	import { hslColor } from '$lib/utils/color';

	let currentParams = $derived($params);
	let species = $derived(currentParams.species);
	let activeSpeciesId = $derived(currentParams.activeSpeciesId);

	// Wrapper to get shape path with container size
	function getIconPath(shape: HeadShape, containerSize: number): string {
		const s = containerSize * 0.4;
		const cx = containerSize / 2;
		const cy = containerSize / 2;
		return getShapePath(shape, cx, cy, s);
	}

	function handleAddSpecies() {
		if (species.length < MAX_SPECIES) {
			addSpecies();
		}
	}

	function handleSelectSpecies(id: number) {
		setActiveSpecies(id);
	}

	function handleRemoveSpecies(e: Event, id: number) {
		e.stopPropagation();
		if (species.length > 1) {
			removeSpecies(id);
		}
	}
</script>

<div class="species-selector">
	<div class="species-grid">
		{#each species as sp (sp.id)}
			{@const isActive = sp.id === activeSpeciesId}
			<div
				class="species-btn"
				class:active={isActive}
				onclick={() => handleSelectSpecies(sp.id)}
				onkeydown={(e) => e.key === 'Enter' && handleSelectSpecies(sp.id)}
				role="button"
				tabindex="0"
				title={sp.name}
			>
				<svg class="boid-icon" viewBox="0 0 24 24">
					<path
						d={getIconPath(sp.headShape, 24)}
						fill={hslColor(sp.hue, sp.saturation, sp.lightness)}
					/>
				</svg>
				<!-- Remove button on hover for active -->
				{#if species.length > 1 && isActive}
					<button class="remove-btn" onclick={(e) => handleRemoveSpecies(e, sp.id)} title="Remove">
						<svg viewBox="0 0 12 12" fill="currentColor">
							<path
								d="M3.5 3.5a.4.4 0 0 1 .566 0L6 5.434 7.934 3.5a.4.4 0 0 1 .566.566L6.566 6 8.5 7.934a.4.4 0 0 1-.566.566L6 6.566 4.066 8.5a.4.4 0 0 1-.566-.566L5.434 6 3.5 4.066a.4.4 0 0 1 0-.566z"
							/>
						</svg>
					</button>
				{/if}
			</div>
		{/each}

		<!-- Add species button -->
		{#if species.length < MAX_SPECIES}
			<button class="add-btn" onclick={handleAddSpecies} title="Add species">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5">
					<line x1="8" y1="4" x2="8" y2="12" />
					<line x1="4" y1="8" x2="12" y2="8" />
				</svg>
			</button>
		{/if}
	</div>
</div>

<style>
	.species-selector {
		padding: 0 0 4px;
	}

	.species-grid {
		display: flex;
		flex-wrap: wrap;
		gap: 4px;
		align-items: center;
	}

	.species-btn {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		padding: 0;
		border-radius: 6px;
		background: rgba(255, 255, 255, 0.04);
		border: 1px solid rgba(255, 255, 255, 0.08);
		cursor: pointer;
		transition: all 0.12s ease;
	}

	.species-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		border-color: rgba(255, 255, 255, 0.15);
		transform: scale(1.05);
	}

	.species-btn.active {
		background: rgba(99, 102, 241, 0.2);
		border-color: rgba(99, 102, 241, 0.5);
	}

	.boid-icon {
		width: 18px;
		height: 18px;
	}

	.remove-btn {
		position: absolute;
		top: -4px;
		right: -4px;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: rgba(239, 68, 68, 0.9);
		border: none;
		padding: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		opacity: 0;
		transition: opacity 0.1s ease;
		z-index: 1;
	}

	.species-btn.active:hover .remove-btn {
		opacity: 1;
	}

	.remove-btn:hover {
		background: rgb(239, 68, 68);
		transform: scale(1.1);
	}

	.remove-btn svg {
		width: 10px;
		height: 10px;
		color: white;
	}

	.add-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		padding: 0;
		border-radius: 6px;
		background: transparent;
		border: 1px dashed rgba(255, 255, 255, 0.15);
		cursor: pointer;
		transition: all 0.12s ease;
	}

	.add-btn:hover {
		background: rgba(99, 102, 241, 0.1);
		border-color: rgba(99, 102, 241, 0.4);
	}

	.add-btn svg {
		width: 12px;
		height: 12px;
		color: rgba(255, 255, 255, 0.35);
	}

	.add-btn:hover svg {
		color: rgba(99, 102, 241, 0.8);
	}
</style>
