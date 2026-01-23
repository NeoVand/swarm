<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import {
		params,
		setActiveSpecies,
		addSpecies,
		removeSpecies,
		MAX_SPECIES
	} from '$lib/stores/simulation';
	import { HeadShape } from '$lib/webgpu/types';

	let currentParams = $derived($params);
	let species = $derived(currentParams.species);
	let activeSpeciesId = $derived(currentParams.activeSpeciesId);

	// Animation frame for mini boid previews
	let animationTime = $state(0);
	let animationFrame: number | null = null;

	onMount(() => {
		function animate() {
			animationTime = performance.now() / 1000;
			animationFrame = requestAnimationFrame(animate);
		}
		animationFrame = requestAnimationFrame(animate);
	});

	onDestroy(() => {
		if (animationFrame !== null) {
			cancelAnimationFrame(animationFrame);
		}
	});

	// Get SVG path for each head shape (matching shader shapes)
	function getShapePath(shape: HeadShape, size: number): string {
		const s = size * 0.4;
		const cx = size / 2;
		const cy = size / 2;

		// Helper to generate regular polygon with first vertex pointing right
		function polygon(sides: number): string {
			const points: string[] = [];
			for (let i = 0; i < sides; i++) {
				const angle = (2 * Math.PI * i) / sides;
				points.push(`${cx + Math.cos(angle) * s},${cy + Math.sin(angle) * s}`);
			}
			return `M ${points.join(' L ')} Z`;
		}

		switch (shape) {
			case HeadShape.Triangle:
				// Original triangle: nose at right, base at left (matching shader)
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
			case HeadShape.Square:
				// Square rotated 45° so corner points right (matching shader)
				return `M ${cx + s} ${cy} L ${cx} ${cy + s} L ${cx - s} ${cy} L ${cx} ${cy - s} Z`;
			case HeadShape.Pentagon:
				return polygon(5);
			case HeadShape.Hexagon:
				return polygon(6);
			case HeadShape.Arrow:
				// Arrow/chevron shape (matching shader)
				return `M ${cx + s} ${cy} L ${cx - s * 0.5} ${cy + s * 0.6} L ${cx - s * 0.2} ${cy} L ${cx - s * 0.5} ${cy - s * 0.6} Z`;
			default:
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
		}
	}

	// Convert HSL to color string
	function hslColor(hue: number, saturation: number, lightness: number): string {
		return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
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
	<div class="species-list">
		{#each species as sp (sp.id)}
			{@const isActive = sp.id === activeSpeciesId}
			{@const bob = Math.sin(animationTime * 0.8 + sp.id * 1.5) * 1.5}
			{@const rotation = Math.sin(animationTime * 0.5 + sp.id) * 5 + 45}
			<div
				class="species-card"
				class:active={isActive}
				onclick={() => handleSelectSpecies(sp.id)}
				onkeydown={(e) => e.key === 'Enter' && handleSelectSpecies(sp.id)}
				role="button"
				tabindex="0"
				title={sp.name}
			>
				<!-- Mini boid preview (no trail, subtle movement) -->
				<svg class="boid-preview" viewBox="0 0 32 32">
					<g transform="translate(16, {16 + bob}) rotate({rotation})">
						<path
							d={getShapePath(sp.headShape, 22)}
							fill={hslColor(sp.hue, sp.saturation, sp.lightness)}
							stroke={hslColor(sp.hue, sp.saturation, Math.min(sp.lightness + 20, 100))}
							stroke-width="0.5"
							transform="translate(-11, -11)"
						/>
					</g>
				</svg>
				<!-- Species name -->
				<span class="species-name">{sp.name}</span>
				<!-- Remove button (only if more than 1 species) -->
				{#if species.length > 1 && isActive}
					<button
						class="remove-btn"
						onclick={(e) => handleRemoveSpecies(e, sp.id)}
						title="Remove species"
					>
						<svg viewBox="0 0 16 16" fill="currentColor">
							<path
								d="M4.646 4.646a.5.5 0 0 1 .708 0L8 7.293l2.646-2.647a.5.5 0 0 1 .708.708L8.707 8l2.647 2.646a.5.5 0 0 1-.708.708L8 8.707l-2.646 2.647a.5.5 0 0 1-.708-.708L7.293 8 4.646 5.354a.5.5 0 0 1 0-.708z"
							/>
						</svg>
					</button>
				{/if}
			</div>
		{/each}

		<!-- Add species button -->
		{#if species.length < MAX_SPECIES}
			<button class="add-species-btn" onclick={handleAddSpecies} title="Add new species">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<line x1="12" y1="5" x2="12" y2="19" />
					<line x1="5" y1="12" x2="19" y2="12" />
				</svg>
			</button>
		{/if}
	</div>
</div>

<style>
	.species-selector {
		padding: 0 0 8px;
	}

	.species-list {
		display: flex;
		gap: 6px;
		align-items: center;
		overflow-x: auto;
		padding-bottom: 4px;
	}

	.species-list::-webkit-scrollbar {
		height: 3px;
	}

	.species-list::-webkit-scrollbar-track {
		background: rgba(255, 255, 255, 0.05);
		border-radius: 2px;
	}

	.species-list::-webkit-scrollbar-thumb {
		background: rgba(255, 255, 255, 0.15);
		border-radius: 2px;
	}

	.species-card {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		padding: 4px;
		border-radius: 8px;
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid rgba(255, 255, 255, 0.08);
		cursor: pointer;
		transition: all 0.15s ease;
		min-width: 44px;
	}

	.species-card:hover {
		background: rgba(255, 255, 255, 0.06);
		border-color: rgba(255, 255, 255, 0.15);
	}

	.species-card.active {
		background: rgba(99, 102, 241, 0.15);
		border-color: rgba(99, 102, 241, 0.4);
		box-shadow: 0 0 12px rgba(99, 102, 241, 0.2);
	}

	.boid-preview {
		width: 32px;
		height: 32px;
		transition: transform 0.1s ease;
	}

	.species-name {
		font-size: 8px;
		color: rgba(255, 255, 255, 0.6);
		text-transform: uppercase;
		letter-spacing: 0.5px;
		max-width: 40px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.species-card.active .species-name {
		color: rgba(255, 255, 255, 0.9);
	}

	.remove-btn {
		position: absolute;
		top: 2px;
		right: 2px;
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: rgba(239, 68, 68, 0.9);
		border: none;
		padding: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		opacity: 0;
		transition: opacity 0.15s ease;
		z-index: 1;
	}

	.species-card.active:hover .remove-btn {
		opacity: 1;
	}

	.remove-btn:hover {
		background: rgba(239, 68, 68, 1);
		transform: scale(1.1);
	}

	.remove-btn svg {
		width: 8px;
		height: 8px;
		color: white;
	}

	.add-species-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 44px;
		height: 52px;
		border-radius: 8px;
		background: rgba(255, 255, 255, 0.02);
		border: 1px dashed rgba(255, 255, 255, 0.15);
		cursor: pointer;
		transition: all 0.15s ease;
	}

	.add-species-btn:hover {
		background: rgba(99, 102, 241, 0.1);
		border-color: rgba(99, 102, 241, 0.4);
	}

	.add-species-btn svg {
		width: 18px;
		height: 18px;
		color: rgba(255, 255, 255, 0.4);
	}

	.add-species-btn:hover svg {
		color: rgba(99, 102, 241, 0.8);
	}
</style>
