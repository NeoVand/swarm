<script lang="ts">
	import type { Scene } from '$lib/stores/scenes';

	let { scene }: { scene: Scene } = $props();
	const uid = $props.id();
	let hue = $derived(scene.params.species[0]?.hue ?? 190);
	let marks = $derived.by(() => {
		let seed = 0;
		for (const character of scene.id) seed = (seed * 31 + character.charCodeAt(0)) >>> 0;
		const random = (index: number) => {
			const value = Math.sin(index * 127.1 + seed * 0.001) * 43758.5453;
			return value - Math.floor(value);
		};
		const pattern = scene.params.embedded3D ? 0 : seed % 4;
		return Array.from({ length: 92 }, (_, index) => {
			const t = random(index + 1) * Math.PI * 2;
			const spread = random(index + 109);
			let x: number;
			let y: number;
			let angle: number;
			if (pattern === 0) {
				const radius = 26 + spread * 31;
				x = 90 + Math.cos(t) * radius * 1.22;
				y = 58 + Math.sin(t) * radius * 0.65;
				angle = Math.atan2(Math.cos(t) * 0.65, -Math.sin(t) * 1.22);
			} else if (pattern === 1) {
				x = 9 + random(index + 19) * 162;
				y = 25 + Math.sin(x / 31 + (index % 2) * 2.8) * 20 + spread * 37;
				angle = Math.atan(Math.cos(x / 31 + (index % 2) * 2.8) * 0.65);
			} else if (pattern === 2) {
				const side = index % 2;
				const radius = 8 + spread * 35;
				x = 57 + side * 66 + Math.cos(t) * radius;
				y = 54 + Math.sin(t) * radius * 0.83;
				angle = t + Math.PI / 2;
			} else {
				x = 16 + random(index + 19) * 148;
				y = 20 + spread * 78;
				angle = -0.3 + Math.sin(x / 42 + y / 28) * 0.8;
			}
			const species = scene.params.species[index % scene.params.species.length];
			const length = 3 + random(index + 233) * 10;
			return {
				x,
				y,
				angle: (angle * 180) / Math.PI,
				tailX: x - Math.cos(angle) * length,
				tailY: y - Math.sin(angle) * length,
				color: `hsl(${species?.hue ?? 190}, ${Math.max(55, species?.saturation ?? 70)}%, 68%)`,
				opacity: 0.32 + random(index + 331) * 0.65
			};
		});
	});
</script>

<div class="preview" aria-hidden="true">
	{#if scene.thumbnail}
		<img src={scene.thumbnail} alt="" loading="lazy" />
	{:else}
		<svg viewBox="0 0 180 116" fill="none">
			<defs>
				<radialGradient id="{uid}-glow">
					<stop stop-color="hsl({hue}, 45%, 27%)" stop-opacity="0.5" />
					<stop offset="1" stop-color="#0a0d13" stop-opacity="0" />
				</radialGradient>
			</defs>
			<rect width="180" height="116" fill="#0a0d13" />
			<ellipse cx="90" cy="58" rx="95" ry="74" fill="url(#{uid}-glow)" />
			{#if scene.params.embedded3D}
				<ellipse cx="90" cy="58" rx="61" ry="31" stroke="white" stroke-opacity="0.045" />
				<ellipse cx="90" cy="58" rx="43" ry="19" stroke="white" stroke-opacity="0.045" />
			{/if}
			{#each marks as mark, index (index)}
				<path
					d="M {mark.tailX} {mark.tailY} L {mark.x} {mark.y}"
					stroke={mark.color}
					stroke-width="0.7"
					opacity={mark.opacity * 0.32}
				/>
				<path
					d="M 1.8 0 L -1.1 -0.85 L -0.6 0 L -1.1 0.85 Z"
					transform="translate({mark.x} {mark.y}) rotate({mark.angle})"
					fill={mark.color}
					opacity={mark.opacity}
				/>
			{/each}
		</svg>
	{/if}
</div>

<style>
	.preview {
		aspect-ratio: 180 / 116;
		overflow: hidden;
		background: #0a0d13;
	}

	svg,
	img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
</style>
