<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { initWebGPU, resizeCanvas, destroyWebGPU } from '$lib/webgpu/context';
	import { createSimulation, type Simulation } from '$lib/webgpu/simulation';
	import type { GPUContext, SimulationParams, CursorState } from '$lib/webgpu/types';
	import { CursorMode, CursorShape } from '$lib/webgpu/types';
	import {
		params,
		cursor,
		dimensions,
		isWebGPUAvailable,
		isRunning,
		fps,
		needsBufferReallocation,
		needsTrailClear,
		canvasElement
	} from '$lib/stores/simulation';

	let canvas: HTMLCanvasElement;
	let container: HTMLDivElement;
	let gpuContext: GPUContext | null = null;
	let simulation: Simulation | null = null;

	// Track cursor CSS position (not DPR scaled)
	let cursorCssX = 0;
	let cursorCssY = 0;

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

	// Play/pause subscription
	const unsubRunning = isRunning.subscribe((running) => {
		if (simulation) {
			if (running) {
				simulation.start();
			} else {
				simulation.stop();
			}
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
		// Track CSS position for visual cursor
		cursorCssX = e.clientX - rect.left;
		cursorCssY = e.clientY - rect.top;
		cursor.update((c) => ({
			...c,
			x: cursorCssX * dpr,
			y: cursorCssY * dpr,
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
			cursorCssX = touch.clientX - rect.left;
			cursorCssY = touch.clientY - rect.top;
			cursor.set({
				x: cursorCssX * dpr,
				y: cursorCssY * dpr,
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
			cursorCssX = touch.clientX - rect.left;
			cursorCssY = touch.clientY - rect.top;
			cursor.update((c) => ({
				...c,
				x: cursorCssX * dpr,
				y: cursorCssY * dpr
			}));
		}
	}

	function handleTouchEnd(): void {
		cursor.update((c) => ({ ...c, isPressed: false, isActive: false }));
	}

	let resizeObserver: ResizeObserver | null = null;

	onMount(() => {
		// Expose canvas element for screenshot/recording
		canvasElement.set(canvas);

		// Initialize WebGPU (async but we don't return the promise)
		initWebGPU(canvas).then((ctx) => {
			gpuContext = ctx;

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

			// Start simulation (respects current isRunning state)
			let currentRunning = true;
			const unsub = isRunning.subscribe(v => currentRunning = v);
			unsub();
			if (currentRunning) {
				simulation.start();
			}

			// Setup resize observers
			resizeObserver = new ResizeObserver(() => {
				updateDimensions();
			});
			resizeObserver.observe(container);

			// Visual viewport listener for mobile
			if (window.visualViewport) {
				window.visualViewport.addEventListener('resize', updateDimensions);
			}

			window.addEventListener('resize', updateDimensions);
			window.addEventListener('orientationchange', updateDimensions);
		});

		// Return cleanup function
		return () => {
			resizeObserver?.disconnect();
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
		unsubRunning();
		canvasElement.set(null);
		simulation?.destroy();
		destroyWebGPU(gpuContext);
		gpuContext = null;
	});
</script>

<div bind:this={container} class="fixed inset-0 overflow-hidden bg-[#0a0b0d] relative">
	<canvas
		bind:this={canvas}
		class="block touch-none select-none {currentParams?.cursorMode !== CursorMode.Off ? 'cursor-none' : ''}"
		onmousemove={handleMouseMove}
		onmousedown={handleMouseDown}
		onmouseup={handleMouseUp}
		onmouseleave={handleMouseLeave}
		ontouchstart={handleTouchStart}
		ontouchmove={handleTouchMove}
		ontouchend={handleTouchEnd}
		ontouchcancel={handleTouchEnd}
		oncontextmenu={(e) => e.preventDefault()}
	></canvas>
	
	<!-- Custom cursor overlay -->
	{#if currentCursor?.isActive && currentParams?.cursorMode !== CursorMode.Off}
		{@const radius = currentParams?.cursorRadius ?? 50}
		{@const isAttract = currentParams?.cursorMode === CursorMode.Attract}
		{@const shape = currentParams?.cursorShape ?? CursorShape.Ring}
		{@const color = isAttract ? '6, 182, 212' : '244, 63, 94'}
		{@const baseOpacity = currentCursor.isPressed ? 0.9 : 0.6}
		{@const dotSize = Math.max(radius * 0.25, 8)}
		
		<div
			class="pointer-events-none absolute"
			style="left: {cursorCssX}px; top: {cursorCssY}px; transform: translate(-50%, -50%);"
		>
			<!-- Ring Shape -->
			{#if shape === CursorShape.Ring}
				<svg width="{radius * 2}" height="{radius * 2}" class="animate-spin-slow">
					<circle
						cx={radius}
						cy={radius}
						r={radius - 2}
						fill="none"
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2.5 : 1.5}
						stroke-dasharray={currentCursor.isPressed ? "8 4" : "6 6"}
					/>
				</svg>
			
			<!-- Disk Shape -->
			{:else if shape === CursorShape.Disk}
				<svg width="{radius * 2}" height="{radius * 2}">
					<circle
						cx={radius}
						cy={radius}
						r={radius - 1}
						fill="rgba({color}, {baseOpacity * 0.15})"
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2 : 1}
					/>
					<!-- Center dot -->
					<circle
						cx={radius}
						cy={radius}
						r="3"
						fill="rgba({color}, {baseOpacity})"
					/>
				</svg>
			
			<!-- Dot Shape -->
			{:else if shape === CursorShape.Dot}
				<svg width="{dotSize * 2 + 10}" height="{dotSize * 2 + 10}">
					<circle
						cx={dotSize + 5}
						cy={dotSize + 5}
						r={dotSize - 1}
						fill="rgba({color}, {baseOpacity})"
					/>
					<!-- Glow ring -->
					<circle
						cx={dotSize + 5}
						cy={dotSize + 5}
						r={dotSize + 4}
						fill="none"
						stroke="rgba({color}, {baseOpacity * 0.4})"
						stroke-width="1"
					/>
				</svg>
			
			<!-- Vortex Shape -->
			{:else if shape === CursorShape.Vortex}
				<svg width="{radius * 2}" height="{radius * 2}" class={isAttract ? 'animate-spin-vortex' : 'animate-spin-vortex-reverse'}>
					<!-- Spiral arms -->
					<g transform="translate({radius}, {radius})">
						{#each [0, 45, 90, 135, 180, 225, 270, 315] as angle, i}
							<path
								d="M 0 0 Q {radius * 0.35} {radius * 0.15} {radius * 0.65} {radius * 0.4}"
								fill="none"
								stroke="rgba({color}, {baseOpacity * (0.5 + (i % 2) * 0.3)})"
								stroke-width={currentCursor.isPressed ? 2 : 1.2}
								stroke-linecap="round"
								transform="rotate({angle})"
							/>
						{/each}
						<!-- Center -->
						<circle
							cx="0"
							cy="0"
							r="3"
							fill="rgba({color}, {baseOpacity})"
						/>
						<!-- Outer dashed ring -->
						<circle
							cx="0"
							cy="0"
							r={radius - 4}
							fill="none"
							stroke="rgba({color}, {baseOpacity * 0.3})"
							stroke-width="1"
							stroke-dasharray="3 3"
						/>
					</g>
				</svg>
			{/if}
		</div>
	{/if}
</div>

<style>
	.cursor-none {
		cursor: none;
	}
	
	@keyframes spin-slow {
		from { transform: rotate(0deg); }
		to { transform: rotate(360deg); }
	}
	.animate-spin-slow {
		animation: spin-slow 10s linear infinite;
	}
	
	@keyframes spin-vortex {
		from { transform: rotate(0deg); }
		to { transform: rotate(360deg); }
	}
	.animate-spin-vortex {
		animation: spin-vortex 3s linear infinite;
	}
	
	@keyframes spin-vortex-reverse {
		from { transform: rotate(360deg); }
		to { transform: rotate(0deg); }
	}
	.animate-spin-vortex-reverse {
		animation: spin-vortex-reverse 3s linear infinite;
	}
</style>
