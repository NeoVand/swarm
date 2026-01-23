<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { initWebGPU, resizeCanvas, destroyWebGPU } from '$lib/webgpu/context';
	import { createSimulation, type Simulation } from '$lib/webgpu/simulation';
	import type { GPUContext, SimulationParams, CursorState } from '$lib/webgpu/types';
	import {
		CursorMode,
		CursorResponse,
		CursorShape,
		WallTool,
		WallBrushShape,
		calculateOptimalPopulation
	} from '$lib/webgpu/types';
	import {
		params,
		cursor,
		dimensions,
		isWebGPUAvailable,
		isRunning,
		fps,
		needsBufferReallocation,
		needsTrailClear,
		needsSimulationReset,
		canvasElement,
		wallTool,
		paintWall,
		beginStroke,
		endStrokeWithHollow,
		wallsDirty,
		speciesDirty
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
	let currentWallTool: WallTool = WallTool.None;
	let isPaintingWall = false;

	const unsubParams = params.subscribe((p) => {
		currentParams = p;
		simulation?.updateParams(p);
	});

	const unsubCursor = cursor.subscribe((c) => {
		currentCursor = c;
		simulation?.updateCursor(c);
	});

	const unsubWallTool = wallTool.subscribe((t) => {
		currentWallTool = t;
	});

	const unsubWallsDirty = wallsDirty.subscribe((dirty) => {
		if (dirty && simulation) {
			simulation.updateWalls();
		}
	});

	// Reactive cursor state based on active species
	$: activeSpeciesForCursor = currentParams?.species?.find(
		(s) => s.id === currentParams?.activeSpeciesId
	);
	$: speciesCursorResponse = activeSpeciesForCursor?.cursorResponse ?? CursorResponse.Ignore;
	$: speciesCursorVortex = activeSpeciesForCursor?.cursorVortex ?? false;
	$: hasCursorInteraction = speciesCursorResponse !== CursorResponse.Ignore || speciesCursorVortex;

	const unsubSpeciesDirty = speciesDirty.subscribe((dirty) => {
		if (dirty && simulation) {
			simulation.updateSpecies();
			speciesDirty.set(false);
		}
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

	const unsubSimulationReset = needsSimulationReset.subscribe((needs) => {
		if (needs && simulation) {
			simulation.resetBoids();
			needsSimulationReset.set(false);
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
		const canvasX = cursorCssX * dpr;
		const canvasY = cursorCssY * dpr;

		// Paint walls if wall tool is active and mouse is pressed
		if (isPaintingWall && currentWallTool !== WallTool.None) {
			paintWall(
				canvasX,
				canvasY,
				currentParams.wallBrushSize * dpr,
				currentWallTool === WallTool.Eraser
			);
		}

		cursor.update((c) => ({
			...c,
			x: canvasX,
			y: canvasY,
			isActive: true
		}));
	}

	function handleMouseDown(): void {
		if (currentWallTool !== WallTool.None) {
			isPaintingWall = true;
			// Begin stroke tracking if using ring brush with pencil
			if (
				currentWallTool === WallTool.Pencil &&
				currentParams.wallBrushShape === WallBrushShape.Ring
			) {
				beginStroke();
			}
			// Paint at current position immediately
			const dpr = Math.min(window.devicePixelRatio || 1, 2);
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;
			paintWall(
				canvasX,
				canvasY,
				currentParams.wallBrushSize * dpr,
				currentWallTool === WallTool.Eraser
			);
		}
		cursor.update((c) => ({ ...c, isPressed: true }));
	}

	function handleMouseUp(): void {
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
		cursor.update((c) => ({ ...c, isPressed: false }));
	}

	function handleMouseLeave(): void {
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
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
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;

			// Paint walls if wall tool is active
			if (currentWallTool !== WallTool.None) {
				isPaintingWall = true;
				// Begin stroke tracking if using ring brush with pencil
				if (
					currentWallTool === WallTool.Pencil &&
					currentParams.wallBrushShape === WallBrushShape.Ring
				) {
					beginStroke();
				}
				paintWall(
					canvasX,
					canvasY,
					currentParams.wallBrushSize * dpr,
					currentWallTool === WallTool.Eraser
				);
			}

			cursor.set({
				x: canvasX,
				y: canvasY,
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
			const canvasX = cursorCssX * dpr;
			const canvasY = cursorCssY * dpr;

			// Paint walls if wall tool is active
			if (isPaintingWall && currentWallTool !== WallTool.None) {
				paintWall(
					canvasX,
					canvasY,
					currentParams.wallBrushSize * dpr,
					currentWallTool === WallTool.Eraser
				);
			}

			cursor.update((c) => ({
				...c,
				x: canvasX,
				y: canvasY
			}));
		}
	}

	function handleTouchEnd(e: TouchEvent): void {
		e.preventDefault();
		// Auto-hollow if ring brush was used for drawing
		if (
			isPaintingWall &&
			currentWallTool === WallTool.Pencil &&
			currentParams.wallBrushShape === WallBrushShape.Ring
		) {
			endStrokeWithHollow(currentParams.wallBrushSize);
		}
		isPaintingWall = false;
		// Fully reset cursor state when touch ends
		cursor.set({ x: -9999, y: -9999, isPressed: false, isActive: false });
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

			// Calculate optimal population based on screen size
			const optimalPopulation = calculateOptimalPopulation(canvas.width, canvas.height);

			// Update params with optimal population directly (without triggering reallocation flag)
			params.update((p) => ({ ...p, population: optimalPopulation }));

			// Get params for simulation init
			let initParams: SimulationParams;
			const unsub0 = params.subscribe((p) => (initParams = p));
			unsub0();

			// Create simulation
			simulation = createSimulation(gpuContext, initParams!, (newFps) => {
				fps.set(newFps);
			});

			// Ensure reallocation flag is clean after init
			needsBufferReallocation.set(false);

			// Start simulation (respects current isRunning state)
			let currentRunning = true;
			const unsub = isRunning.subscribe((v) => (currentRunning = v));
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
		unsubSimulationReset();
		unsubRunning();
		unsubWallTool();
		unsubWallsDirty();
		unsubSpeciesDirty();
		canvasElement.set(null);
		simulation?.destroy();
		destroyWebGPU(gpuContext);
		gpuContext = null;
	});
</script>

<div bind:this={container} class="fixed relative inset-0 overflow-hidden bg-[#0a0b0d]">
	<canvas
		bind:this={canvas}
		class="block touch-none select-none {currentParams?.cursorMode !== CursorMode.Off ||
		currentParams?.cursorVortex ||
		currentWallTool !== WallTool.None
			? 'cursor-none'
			: ''}"
		onmousemove={handleMouseMove}
		onmousedown={handleMouseDown}
		onmouseup={handleMouseUp}
		onmouseleave={handleMouseLeave}
		ontouchstart={handleTouchStart}
		ontouchmove={handleTouchMove}
		ontouchend={(e) => handleTouchEnd(e)}
		ontouchcancel={(e) => handleTouchEnd(e)}
		oncontextmenu={(e) => e.preventDefault()}
	></canvas>

	<!-- Wall tool cursor overlay -->
	{#if currentCursor?.isActive && currentWallTool !== WallTool.None}
		{@const brushSize = currentParams?.wallBrushSize ?? 30}
		{@const isPencil = currentWallTool === WallTool.Pencil}
		{@const brushColor = isPencil ? '100, 116, 139' : '239, 68, 68'}

		<div
			class="pointer-events-none absolute"
			style="left: {cursorCssX}px; top: {cursorCssY}px; transform: translate(-50%, -50%);"
		>
			<svg width={brushSize * 2} height={brushSize * 2}>
				<circle
					cx={brushSize}
					cy={brushSize}
					r={brushSize - 1}
					fill={isPaintingWall ? `rgba(${brushColor}, 0.3)` : 'none'}
					stroke="rgba({brushColor}, {isPaintingWall ? 0.9 : 0.6})"
					stroke-width={isPaintingWall ? 2 : 1.5}
					stroke-dasharray={isPencil ? 'none' : '6 4'}
				/>
				<!-- Center crosshair -->
				<line
					x1={brushSize - 6}
					y1={brushSize}
					x2={brushSize + 6}
					y2={brushSize}
					stroke="rgba({brushColor}, 0.8)"
					stroke-width="1"
				/>
				<line
					x1={brushSize}
					y1={brushSize - 6}
					x2={brushSize}
					y2={brushSize + 6}
					stroke="rgba({brushColor}, 0.8)"
					stroke-width="1"
				/>
			</svg>
		</div>
	{/if}

	<!-- Custom cursor overlay for boid interaction (shows alongside wall tool cursor) -->
	{#if currentCursor?.isActive && hasCursorInteraction}
		{@const radius = currentParams?.cursorRadius ?? 50}
		{@const isAttract = speciesCursorResponse === CursorResponse.Attract}
		{@const isRepel = speciesCursorResponse === CursorResponse.Repel}
		{@const isVortexOnly = speciesCursorResponse === CursorResponse.Ignore && speciesCursorVortex}
		{@const shape = currentParams?.cursorShape ?? CursorShape.Disk}
		{@const hasVortex = speciesCursorVortex}
		{@const color = isVortexOnly ? '249, 115, 22' : isAttract ? '6, 182, 212' : '244, 63, 94'}
		{@const baseOpacity = currentCursor.isPressed ? 0.9 : 0.6}
		{@const spinClass = hasVortex
			? isRepel
				? 'animate-spin-vortex-reverse'
				: 'animate-spin-vortex'
			: ''}

		<div
			class="pointer-events-none absolute"
			style="left: {cursorCssX}px; top: {cursorCssY}px; transform: translate(-50%, -50%);"
		>
			<!-- Ring Shape -->
			{#if shape === CursorShape.Ring}
				<svg width={radius * 2} height={radius * 2} class={spinClass}>
					<circle
						cx={radius}
						cy={radius}
						r={radius - 2}
						fill="none"
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2.5 : 1.5}
						stroke-dasharray={hasVortex || isVortexOnly ? '10 8' : 'none'}
					/>
				</svg>

				<!-- Disk Shape (default) -->
			{:else}
				<svg width={radius * 2} height={radius * 2} class={spinClass}>
					<circle
						cx={radius}
						cy={radius}
						r={radius - 1}
						fill={isVortexOnly ? 'none' : `rgba(${color}, ${baseOpacity * 0.15})`}
						stroke="rgba({color}, {baseOpacity})"
						stroke-width={currentCursor.isPressed ? 2 : 1.5}
						stroke-dasharray={hasVortex || isVortexOnly ? '10 8' : 'none'}
					/>
					<!-- Center dot (not shown for vortex-only) -->
					{#if !isVortexOnly}
						<circle cx={radius} cy={radius} r="3" fill="rgba({color}, {baseOpacity})" />
					{/if}
				</svg>
			{/if}
		</div>
	{/if}
</div>

<style>
	.cursor-none {
		cursor: none;
	}

	@keyframes spin-vortex {
		from {
			transform: rotate(0deg);
		}
		to {
			transform: rotate(360deg);
		}
	}
	.animate-spin-vortex {
		animation: spin-vortex 2s linear infinite;
		will-change: transform;
	}

	@keyframes spin-vortex-reverse {
		from {
			transform: rotate(0deg);
		}
		to {
			transform: rotate(-360deg);
		}
	}
	.animate-spin-vortex-reverse {
		animation: spin-vortex-reverse 2s linear infinite;
		will-change: transform;
	}
</style>
