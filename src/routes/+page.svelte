<script lang="ts">
	import BoidsCanvas from '$lib/components/BoidsCanvas.svelte';
	import ControlPanel from '$lib/components/ControlPanel.svelte';
	import { isWebGPUAvailable } from '$lib/stores/simulation';
	import { failureReason } from '$lib/webgpu/context';

	let webGPUAvailable = $derived($isWebGPUAvailable);
	
	// Check if this is a temporary failure that can be fixed with reload
	let isTemporaryFailure = $derived(
		failureReason === 'no-adapter' || failureReason === 'device-error'
	);
	
	function handleReload() {
		window.location.reload();
	}
</script>

<svelte:head>
	<title>Boids - Flocking Simulation</title>
	<meta name="description" content="High-performance WebGPU boids flocking simulation with spatial hash grid acceleration" />
</svelte:head>

{#if webGPUAvailable === false}
	<!-- WebGPU not available fallback -->
	<div class="flex min-h-screen flex-col items-center justify-center bg-[#0a0b0d] px-6 text-center">
		<div class="max-w-md space-y-6">
			<div class="flex justify-center">
				<svg
					xmlns="http://www.w3.org/2000/svg"
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="1.5"
					stroke-linecap="round"
					stroke-linejoin="round"
					class="h-16 w-16 text-red-400/80"
				>
					<circle cx="12" cy="12" r="10" />
					<line x1="12" y1="8" x2="12" y2="12" />
					<line x1="12" y1="16" x2="12.01" y2="16" />
				</svg>
			</div>
			
			{#if isTemporaryFailure}
				<!-- Temporary failure - GPU busy or crashed -->
				<h1 class="font-display text-2xl font-light tracking-wide text-zinc-100">
					GPU Temporarily Unavailable
				</h1>
				
				<p class="text-sm leading-relaxed text-zinc-400">
					The GPU device couldn't be initialized. This often happens during development
					when the page is rapidly refreshed, or when the GPU is busy with other tasks.
				</p>
				
				<div class="space-y-3 pt-4">
					<button
						onclick={handleReload}
						class="rounded-lg bg-cyan-600 px-6 py-2.5 text-sm font-medium text-white transition-colors hover:bg-cyan-500 focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2 focus:ring-offset-[#0a0b0d]"
					>
						Reload Page
					</button>
					<p class="pt-2 text-xs text-zinc-500">
						If this keeps happening, try closing other GPU-intensive tabs or restart your browser
					</p>
				</div>
			{:else}
				<!-- Permanent failure - No WebGPU support -->
				<h1 class="font-display text-2xl font-light tracking-wide text-zinc-100">
					WebGPU Not Available
				</h1>
				
				<p class="text-sm leading-relaxed text-zinc-400">
					This simulation requires WebGPU, a modern graphics API that enables GPU-accelerated 
					computing directly in the browser. Your browser doesn't support WebGPU yet.
				</p>
				
				<div class="space-y-3 pt-4">
					<p class="text-xs font-medium uppercase tracking-wider text-zinc-500">
						Supported Browsers
					</p>
					<div class="flex flex-wrap justify-center gap-3 text-xs text-zinc-400">
						<span class="rounded-md bg-zinc-800/50 px-3 py-1.5">Chrome 113+</span>
						<span class="rounded-md bg-zinc-800/50 px-3 py-1.5">Edge 113+</span>
						<span class="rounded-md bg-zinc-800/50 px-3 py-1.5">Opera 99+</span>
					</div>
					<p class="pt-2 text-xs text-zinc-500">
						Safari and Firefox have experimental support via flags
					</p>
				</div>
			{/if}
		</div>
	</div>
{:else}
	<!-- Main simulation -->
	<BoidsCanvas />
	<ControlPanel />
{/if}
