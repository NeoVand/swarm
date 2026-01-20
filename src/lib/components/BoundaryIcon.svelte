<script lang="ts">
	import { BoundaryMode } from '$lib/stores/simulation';

	interface Props {
		mode: BoundaryMode;
		size?: number;
	}

	let { mode, size = 16 }: Props = $props();

	type EdgeConfig = {
		left: 'none' | 'up' | 'down';
		right: 'none' | 'up' | 'down';
		top: 'none' | 'right' | 'left';
		bottom: 'none' | 'right' | 'left';
	};

	const edgeConfigs: Record<BoundaryMode, EdgeConfig> = {
		[BoundaryMode.Plane]: { left: 'none', right: 'none', top: 'none', bottom: 'none' },
		[BoundaryMode.CylinderX]: { left: 'up', right: 'up', top: 'none', bottom: 'none' },
		[BoundaryMode.CylinderY]: { left: 'none', right: 'none', top: 'right', bottom: 'right' },
		[BoundaryMode.Torus]: { left: 'up', right: 'up', top: 'right', bottom: 'right' },
		[BoundaryMode.MobiusX]: { left: 'up', right: 'down', top: 'none', bottom: 'none' },
		[BoundaryMode.MobiusY]: { left: 'none', right: 'none', top: 'right', bottom: 'left' },
		[BoundaryMode.KleinX]: { left: 'up', right: 'down', top: 'right', bottom: 'right' },
		[BoundaryMode.KleinY]: { left: 'up', right: 'up', top: 'right', bottom: 'left' },
		[BoundaryMode.ProjectivePlane]: { left: 'up', right: 'down', top: 'right', bottom: 'left' }
	};

	const config = $derived(edgeConfigs[mode]);
</script>

<svg
	width={size}
	height={size}
	viewBox="0 0 24 24"
	fill="none"
	stroke="currentColor"
	stroke-width="0.75"
	stroke-linecap="round"
	stroke-linejoin="round"
	class="boundary-icon"
>
	<!-- Square base -->
	<rect x="5" y="5" width="14" height="14" rx="0.5" />

	<!-- LEFT EDGE: Double chevron -->
	{#if config.left !== 'none'}
		{@const isUp = config.left === 'up'}
		{#if isUp}
			<path d="M3 12 L5 9 L7 12" stroke-width="0.7" />
			<path d="M3 15 L5 12 L7 15" stroke-width="0.7" />
		{:else}
			<path d="M3 9 L5 12 L7 9" stroke-width="0.7" />
			<path d="M3 12 L5 15 L7 12" stroke-width="0.7" />
		{/if}
	{/if}

	<!-- RIGHT EDGE: Double chevron -->
	{#if config.right !== 'none'}
		{@const isUp = config.right === 'up'}
		{#if isUp}
			<path d="M17 12 L19 9 L21 12" stroke-width="0.7" />
			<path d="M17 15 L19 12 L21 15" stroke-width="0.7" />
		{:else}
			<path d="M17 9 L19 12 L21 9" stroke-width="0.7" />
			<path d="M17 12 L19 15 L21 12" stroke-width="0.7" />
		{/if}
	{/if}

	<!-- TOP EDGE: Single chevron -->
	{#if config.top !== 'none'}
		{@const isRight = config.top === 'right'}
		{#if isRight}
			<path d="M10 3 L13 5 L10 7" stroke-width="0.7" />
		{:else}
			<path d="M14 3 L11 5 L14 7" stroke-width="0.7" />
		{/if}
	{/if}

	<!-- BOTTOM EDGE: Single chevron -->
	{#if config.bottom !== 'none'}
		{@const isRight = config.bottom === 'right'}
		{#if isRight}
			<path d="M10 17 L13 19 L10 21" stroke-width="0.7" />
		{:else}
			<path d="M14 17 L11 19 L14 21" stroke-width="0.7" />
		{/if}
	{/if}
</svg>

<style>
	.boundary-icon {
		flex-shrink: 0;
	}
</style>
