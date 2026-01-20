<script lang="ts">
	import { ColorSpectrum } from '$lib/stores/simulation';

	interface Props {
		spectrum: ColorSpectrum;
		size?: number;
	}

	let { spectrum, size = 16 }: Props = $props();

	// Gradient stops for each spectrum (diagonal from top-left to bottom-right)
	const gradients: Record<
		ColorSpectrum,
		{ id: string; stops: Array<{ offset: string; color: string }> }
	> = {
		[ColorSpectrum.Chrome]: {
			id: 'chrome',
			stops: [
				{ offset: '0%', color: 'rgb(51, 102, 230)' },
				{ offset: '25%', color: 'rgb(77, 204, 230)' },
				{ offset: '50%', color: 'rgb(242, 242, 230)' },
				{ offset: '75%', color: 'rgb(242, 153, 51)' },
				{ offset: '100%', color: 'rgb(230, 51, 51)' }
			]
		},
		[ColorSpectrum.Ocean]: {
			id: 'ocean',
			stops: [
				{ offset: '0%', color: 'rgb(64, 89, 166)' },
				{ offset: '20%', color: 'rgb(51, 140, 153)' },
				{ offset: '40%', color: 'rgb(77, 166, 128)' },
				{ offset: '60%', color: 'rgb(217, 179, 77)' },
				{ offset: '80%', color: 'rgb(204, 115, 102)' },
				{ offset: '100%', color: 'rgb(140, 89, 140)' }
			]
		},
		[ColorSpectrum.Bands]: {
			id: 'bands',
			stops: [
				{ offset: '0%', color: 'rgb(230, 51, 77)' },
				{ offset: '20%', color: 'rgb(242, 153, 26)' },
				{ offset: '40%', color: 'rgb(242, 230, 51)' },
				{ offset: '60%', color: 'rgb(51, 204, 102)' },
				{ offset: '80%', color: 'rgb(51, 153, 230)' },
				{ offset: '100%', color: 'rgb(153, 77, 204)' }
			]
		},
		[ColorSpectrum.Rainbow]: {
			id: 'rainbow',
			stops: [
				{ offset: '0%', color: 'hsl(0, 85%, 60%)' },
				{ offset: '17%', color: 'hsl(30, 85%, 60%)' },
				{ offset: '33%', color: 'hsl(60, 85%, 60%)' },
				{ offset: '50%', color: 'hsl(120, 85%, 50%)' },
				{ offset: '67%', color: 'hsl(180, 85%, 55%)' },
				{ offset: '83%', color: 'hsl(240, 85%, 60%)' },
				{ offset: '100%', color: 'hsl(300, 85%, 60%)' }
			]
		},
		[ColorSpectrum.Mono]: {
			id: 'mono',
			stops: [
				{ offset: '0%', color: 'rgb(102, 97, 92)' },
				{ offset: '50%', color: 'rgb(179, 170, 161)' },
				{ offset: '100%', color: 'rgb(255, 242, 230)' }
			]
		}
	};

	const grad = $derived(gradients[spectrum]);
</script>

<svg width={size} height={size} viewBox="0 0 18 18" class="palette-icon">
	<defs>
		<linearGradient id="palette-{grad.id}" x1="0%" y1="0%" x2="100%" y2="100%">
			{#each grad.stops as stop}
				<stop offset={stop.offset} stop-color={stop.color} />
			{/each}
		</linearGradient>
	</defs>
	<rect x="0" y="0" width="18" height="18" rx="4" fill="url(#palette-{grad.id})" />
</svg>

<style>
	.palette-icon {
		flex-shrink: 0;
	}
</style>
