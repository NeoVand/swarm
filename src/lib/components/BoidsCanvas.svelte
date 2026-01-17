<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { initWebGPU, resizeCanvas } from '$lib/webgpu/context';
	import { createSimulation, type Simulation } from '$lib/webgpu/simulation';
	import type { GPUContext, SimulationParams, CursorState } from '$lib/webgpu/types';
	import {
		params,
		cursor,
		dimensions,
		isWebGPUAvailable,
		fps,
		needsBufferReallocation,
		needsTrailClear
	} from '$lib/stores/simulation';

	let canvas: HTMLCanvasElement;
	let container: HTMLDivElement;
	let gpuContext: GPUContext | null = null;
	let simulation: Simulation | null = null;

	// Subscribe to stores
	let currentParams: SimulationParams;
	let currentCursor: CursorState;

	const unsubParams = params.subscribe((p) => {
		currentParams = p;
		simulation?.updateParams(p);
	});

	const unsubCursor = cursor.subscribe((c) => {
		currentCursor = c;
		simulation?.updateCursor(c);
	});

	const unsubRealloc = needsBufferReallocation.subscribe((needs) => {
		if (needs && simulation) {
			simulation.reallocateBuffers();
			needsBufferReallocation.set(false);
		}
	});

	const unsubTrailClear = needsTrailClear.subscribe((needs) => {
		if (needs && simulation) {
			simulation.clearTrails();
			needsTrailClear.set(false);
		}
	});

	function updateDimensions(): void {
		if (!container || !canvas || !gpuContext) return;

		// Use visualViewport for accurate dimensions on mobile
		const vv = window.visualViewport;
		const width = vv ? vv.width : window.innerWidth;
		const height = vv ? vv.height : window.innerHeight;

		// Get device pixel ratio for sharp rendering
		const dpr = Math.min(window.devicePixelRatio || 1, 2);

		const canvasWidth = Math.floor(width * dpr);
		const canvasHeight = Math.floor(height * dpr);

		if (canvas.width !== canvasWidth || canvas.height !== canvasHeight) {
			canvas.width = canvasWidth;
			canvas.height = canvasHeight;
			canvas.style.width = `${width}px`;
			canvas.style.height = `${height}px`;

			resizeCanvas(gpuContext, canvasWidth, canvasHeight);
			dimensions.set({ width: canvasWidth, height: canvasHeight });
			simulation?.resize(canvasWidth, canvasHeight);
		}
	}

	function handleMouseMove(e: MouseEvent): void {
		if (!canvas) return;
		const rect = canvas.getBoundingClientRect();
		const dpr = Math.min(window.devicePixelRatio || 1, 2);
		cursor.update((c) => ({
			...c,
			x: (e.clientX - rect.left) * dpr,
			y: (e.clientY - rect.top) * dpr,
			isActive: true
		}));
	}

	function handleMouseDown(e: MouseEvent): void {
		cursor.update((c) => ({ ...c, isPressed: true }));
	}

	function handleMouseUp(): void {
		cursor.update((c) => ({ ...c, isPressed: false }));
	}

	function handleMouseLeave(): void {
		cursor.update((c) => ({ ...c, isActive: false, isPressed: false }));
	}

	function handleTouchStart(e: TouchEvent): void {
		e.preventDefault();
		if (e.touches.length > 0) {
			const touch = e.touches[0];
			const rect = canvas.getBoundingClientRect();
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			cursor.set({
				x: (touch.clientX - rect.left) * dpr,
				y: (touch.clientY - rect.top) * dpr,
				isPressed: true,
				isActive: true
			});
		}
	}

	function handleTouchMove(e: TouchEvent): void {
		e.preventDefault();
		if (e.touches.length > 0) {
			const touch = e.touches[0];
			const rect = canvas.getBoundingClientRect();
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			cursor.update((c) => ({
				...c,
				x: (touch.clientX - rect.left) * dpr,
				y: (touch.clientY - rect.top) * dpr
			}));
		}
	}

	function handleTouchEnd(): void {
		cursor.update((c) => ({ ...c, isPressed: false, isActive: false }));
	}

	onMount(async () => {
		// Initialize WebGPU
		gpuContext = await initWebGPU(canvas);

		if (!gpuContext) {
			isWebGPUAvailable.set(false);
			return;
		}

		isWebGPUAvailable.set(true);

		// Set initial dimensions
		updateDimensions();

		// Create simulation
		simulation = createSimulation(gpuContext, currentParams, (newFps) => {
			fps.set(newFps);
		});

		// Start simulation
		simulation.start();

		// Setup resize observers
		const resizeObserver = new ResizeObserver(() => {
			updateDimensions();
		});
		resizeObserver.observe(container);

		// Visual viewport listener for mobile
		if (window.visualViewport) {
			window.visualViewport.addEventListener('resize', updateDimensions);
		}

		window.addEventListener('resize', updateDimensions);
		window.addEventListener('orientationchange', updateDimensions);

		return () => {
			resizeObserver.disconnect();
			if (window.visualViewport) {
				window.visualViewport.removeEventListener('resize', updateDimensions);
			}
			window.removeEventListener('resize', updateDimensions);
			window.removeEventListener('orientationchange', updateDimensions);
		};
	});

	onDestroy(() => {
		unsubParams();
		unsubCursor();
		unsubRealloc();
		unsubTrailClear();
		simulation?.destroy();
	});
</script>

<div bind:this={container} class="fixed inset-0 overflow-hidden bg-[#0a0b0d]">
	<canvas
		bind:this={canvas}
		class="block touch-none"
		onmousemove={handleMouseMove}
		onmousedown={handleMouseDown}
		onmouseup={handleMouseUp}
		onmouseleave={handleMouseLeave}
		ontouchstart={handleTouchStart}
		ontouchmove={handleTouchMove}
		ontouchend={handleTouchEnd}
		ontouchcancel={handleTouchEnd}
	></canvas>
</div>
