<script lang="ts">
	import { fade, scale } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import {
		params,
		isPanelOpen,
		setAlignment,
		setCohesion,
		setSeparation,
		setPerception,
		setMaxSpeed,
		setMaxForce,
		setNoise,
		setRebels,
		setBoundaryMode,
		setCursorMode,
		setCursorShape,
		setCursorForce,
		setCursorRadius,
		setBoidSize,
		setTrailLength,
		setColorMode,
		setColorSpectrum,
		setSensitivity,
		setPopulation,
		setAlgorithmMode,
		BoundaryMode,
		ColorMode,
		ColorSpectrum,
		CursorMode,
		CursorShape,
		AlgorithmMode
	} from '$lib/stores/simulation';

	let currentParams = $derived($params);
	let isOpen = $derived($isPanelOpen);

	function togglePanel(): void {
		isPanelOpen.update((v) => !v);
	}

	const boundaryOptions = [
		{ value: BoundaryMode.Torus, label: 'Torus' },
		{ value: BoundaryMode.Plane, label: 'Plane' },
		{ value: BoundaryMode.CylinderX, label: 'Cylinder X' },
		{ value: BoundaryMode.CylinderY, label: 'Cylinder Y' },
		{ value: BoundaryMode.MobiusX, label: 'Möbius X' },
		{ value: BoundaryMode.MobiusY, label: 'Möbius Y' },
		{ value: BoundaryMode.KleinX, label: 'Klein X' },
		{ value: BoundaryMode.KleinY, label: 'Klein Y' },
		{ value: BoundaryMode.ProjectivePlane, label: 'Projective Plane' }
	];

	const colorOptions = [
		{ value: ColorMode.Orientation, label: 'Direction' },
		{ value: ColorMode.Speed, label: 'Speed' },
		{ value: ColorMode.Neighbors, label: 'Neighbors' },
		{ value: ColorMode.Acceleration, label: 'Acceleration' },
		{ value: ColorMode.Turning, label: 'Turning' }
	];

	const spectrumOptions = [
		{ value: ColorSpectrum.Chrome, label: 'Chrome' },
		{ value: ColorSpectrum.Cool, label: 'Cool' },
		{ value: ColorSpectrum.Warm, label: 'Warm' },
		{ value: ColorSpectrum.Rainbow, label: 'Rainbow' },
		{ value: ColorSpectrum.Mono, label: 'Mono' }
	];

	const algorithmOptions = [
		{ value: AlgorithmMode.TopologicalKNN, label: 'Topological k-NN' },
		{ value: AlgorithmMode.SmoothMetric, label: 'Smooth Metric' },
		{ value: AlgorithmMode.HashFree, label: 'Hash-Free' },
		{ value: AlgorithmMode.StochasticSample, label: 'Stochastic' },
		{ value: AlgorithmMode.DensityAdaptive, label: 'Density Adaptive' }
	];

	const cursorShapeOptions = [
		{ value: CursorShape.Ring, label: 'Ring' },
		{ value: CursorShape.Disk, label: 'Disk' },
		{ value: CursorShape.Dot, label: 'Dot' },
		{ value: CursorShape.Vortex, label: 'Vortex' }
	];
</script>

{#if isOpen}
	<!-- Panel (open state) -->
	<div
		class="panel fixed right-4 top-4 z-40 w-64 rounded-xl"
		transition:scale={{ duration: 200, easing: cubicOut, start: 0.95, opacity: 0 }}
	>
		<!-- Header with gear button -->
		<div class="flex items-center justify-between px-3 py-2.5">
			<span class="text-[10px] font-semibold uppercase tracking-widest text-zinc-400">Controls</span>
			<button
				onclick={togglePanel}
				class="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-all hover:bg-white/10 hover:text-zinc-200"
				aria-label="Close Settings"
			>
				<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5 rotate-90">
					<path fill-rule="evenodd" d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
				</svg>
			</button>
		</div>

		<!-- Content -->
		<div class="content-scroll max-h-[calc(100vh-100px)] px-3 pb-3">
			<!-- Algorithm -->
			<div class="mb-3">
				<div class="section-label">Algorithm</div>
				<select value={currentParams.algorithmMode} onchange={(e) => setAlgorithmMode(parseInt(e.currentTarget.value))}
					class="sel w-full" aria-label="Algorithm">
					{#each algorithmOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
				</select>
			</div>

			<!-- Flocking -->
			<div class="mb-3">
				<div class="section-label">Flocking</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Align</span>
						<input type="range" min="0" max="3" step="0.1" value={currentParams.alignment}
							oninput={(e) => setAlignment(parseFloat(e.currentTarget.value))} class="slider" aria-label="Alignment" />
						<span class="value">{currentParams.alignment.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Cohesion</span>
						<input type="range" min="0" max="3" step="0.1" value={currentParams.cohesion}
							oninput={(e) => setCohesion(parseFloat(e.currentTarget.value))} class="slider" aria-label="Cohesion" />
						<span class="value">{currentParams.cohesion.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Separate</span>
						<input type="range" min="0" max="4" step="0.1" value={currentParams.separation}
							oninput={(e) => setSeparation(parseFloat(e.currentTarget.value))} class="slider" aria-label="Separation" />
						<span class="value">{currentParams.separation.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Range</span>
						<input type="range" min="20" max="150" step="5" value={currentParams.perception}
							oninput={(e) => setPerception(parseInt(e.currentTarget.value))} class="slider" aria-label="Perception" />
						<span class="value">{currentParams.perception}</span>
					</div>
				</div>
			</div>

			<!-- Dynamics -->
			<div class="mb-3">
				<div class="section-label">Dynamics</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Speed</span>
						<input type="range" min="1" max="15" step="0.5" value={currentParams.maxSpeed}
							oninput={(e) => setMaxSpeed(parseFloat(e.currentTarget.value))} class="slider" aria-label="Speed" />
						<span class="value">{currentParams.maxSpeed.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Force</span>
						<input type="range" min="0.01" max="0.5" step="0.01" value={currentParams.maxForce}
							oninput={(e) => setMaxForce(parseFloat(e.currentTarget.value))} class="slider" aria-label="Force" />
						<span class="value">{currentParams.maxForce.toFixed(2)}</span>
					</div>
					<div class="row">
						<span class="label">Noise</span>
						<input type="range" min="0" max="1" step="0.05" value={currentParams.noise}
							oninput={(e) => setNoise(parseFloat(e.currentTarget.value))} class="slider" aria-label="Noise" />
						<span class="value">{currentParams.noise.toFixed(2)}</span>
					</div>
					<div class="row">
						<span class="label">Rebels</span>
						<input type="range" min="0" max="0.2" step="0.01" value={currentParams.rebels}
							oninput={(e) => setRebels(parseFloat(e.currentTarget.value))} class="slider" aria-label="Rebels" />
						<span class="value">{(currentParams.rebels * 100).toFixed(0)}%</span>
					</div>
				</div>
			</div>

			<!-- World -->
			<div class="mb-3">
				<div class="section-label">World</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Bounds</span>
						<select value={currentParams.boundaryMode} onchange={(e) => setBoundaryMode(parseInt(e.currentTarget.value))}
							class="sel flex-1" aria-label="Boundary">
							{#each boundaryOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
						</select>
					</div>
					<div class="row">
						<span class="label">Cursor</span>
						<div class="flex flex-1 gap-0.5">
							<button class="btn" class:active={currentParams.cursorMode === CursorMode.Off}
								onclick={() => setCursorMode(CursorMode.Off)}>Off</button>
							<button class="btn" class:active={currentParams.cursorMode === CursorMode.Attract}
								onclick={() => setCursorMode(CursorMode.Attract)}>Pull</button>
							<button class="btn" class:active={currentParams.cursorMode === CursorMode.Repel}
								onclick={() => setCursorMode(CursorMode.Repel)}>Push</button>
						</div>
					</div>
					<div class="row">
						<span class="label">Shape</span>
						<select value={currentParams.cursorShape} onchange={(e) => setCursorShape(parseInt(e.currentTarget.value))}
							class="sel flex-1" aria-label="Cursor Shape">
							{#each cursorShapeOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
						</select>
					</div>
					<div class="row">
						<span class="label">Size</span>
						<input type="range" min="10" max="150" step="5" value={currentParams.cursorRadius}
							oninput={(e) => setCursorRadius(parseInt(e.currentTarget.value))} class="slider" aria-label="Cursor Size" />
						<span class="value">{currentParams.cursorRadius}</span>
					</div>
					<div class="row">
						<span class="label">Power</span>
						<input type="range" min="0" max="1" step="0.05" value={currentParams.cursorForce}
							oninput={(e) => setCursorForce(parseFloat(e.currentTarget.value))} class="slider" aria-label="Cursor Force" />
						<span class="value">{currentParams.cursorForce.toFixed(2)}</span>
					</div>
				</div>
			</div>

			<!-- Visuals -->
			<div class="mb-3">
				<div class="section-label">Visuals</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Size</span>
						<input type="range" min="0.2" max="3" step="0.1" value={currentParams.boidSize}
							oninput={(e) => setBoidSize(parseFloat(e.currentTarget.value))} class="slider" aria-label="Size" />
						<span class="value">{currentParams.boidSize.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Trail</span>
						<input type="range" min="5" max="80" step="5" value={currentParams.trailLength}
							oninput={(e) => setTrailLength(parseInt(e.currentTarget.value))} class="slider" aria-label="Trail" />
						<span class="value">{currentParams.trailLength}</span>
					</div>
					<div class="row">
						<span class="label">Color</span>
						<select value={currentParams.colorMode} onchange={(e) => setColorMode(parseInt(e.currentTarget.value))}
							class="sel flex-1" aria-label="Color Mode">
							{#each colorOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
						</select>
					</div>
					<div class="row">
						<span class="label">Palette</span>
						<select value={currentParams.colorSpectrum} onchange={(e) => setColorSpectrum(parseInt(e.currentTarget.value))}
							class="sel flex-1" aria-label="Spectrum">
							{#each spectrumOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
						</select>
					</div>
				</div>
			</div>

			<!-- Population -->
			<div>
				<div class="section-label">Population</div>
				<div class="row">
					<input type="range" min="500" max="50000" step="500" value={currentParams.population}
						oninput={(e) => setPopulation(parseInt(e.currentTarget.value))} class="slider" aria-label="Population" />
					<span class="value">{(currentParams.population / 1000).toFixed(1)}k</span>
				</div>
			</div>
		</div>
	</div>
{:else}
	<!-- Gear button (closed state) - circular -->
	<button
		onclick={togglePanel}
		class="gear-btn fixed right-4 top-4 z-40 flex h-9 w-9 items-center justify-center rounded-full text-zinc-400 transition-all hover:text-zinc-200"
		aria-label="Open Settings"
		transition:scale={{ duration: 200, easing: cubicOut, start: 0.8, opacity: 0 }}
	>
		<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4">
			<path fill-rule="evenodd" d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
		</svg>
	</button>
{/if}

<style>
	.panel {
		background: rgba(20, 20, 24, 0.65);
		backdrop-filter: blur(20px) saturate(1.2);
		-webkit-backdrop-filter: blur(20px) saturate(1.2);
		border: 1px solid rgba(255, 255, 255, 0.08);
		box-shadow: 
			0 4px 24px rgba(0, 0, 0, 0.4),
			0 1px 2px rgba(0, 0, 0, 0.2),
			inset 0 1px 0 rgba(255, 255, 255, 0.05);
	}

	.content-scroll {
		overflow-y: auto;
		overflow-x: hidden;
		scrollbar-gutter: stable;
	}
	.content-scroll::-webkit-scrollbar {
		width: 6px;
	}
	.content-scroll::-webkit-scrollbar-track {
		background: transparent;
	}
	.content-scroll::-webkit-scrollbar-thumb {
		background: rgba(255, 255, 255, 0.15);
		border-radius: 3px;
	}
	.content-scroll::-webkit-scrollbar-thumb:hover {
		background: rgba(255, 255, 255, 0.25);
	}

	.gear-btn {
		background: rgba(20, 20, 24, 0.6);
		backdrop-filter: blur(16px) saturate(1.2);
		-webkit-backdrop-filter: blur(16px) saturate(1.2);
		border: 1px solid rgba(255, 255, 255, 0.1);
		box-shadow: 
			0 2px 12px rgba(0, 0, 0, 0.3),
			inset 0 1px 0 rgba(255, 255, 255, 0.05);
	}
	.gear-btn:hover {
		background: rgba(30, 30, 36, 0.7);
		border-color: rgba(255, 255, 255, 0.15);
	}

	.section-label {
		margin-bottom: 6px;
		font-size: 9px;
		font-weight: 500;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: rgb(113 113 122);
	}

	.row {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.label {
		width: 52px;
		flex-shrink: 0;
		font-size: 10px;
		color: rgb(161 161 170);
	}

	.value {
		flex-shrink: 0;
		min-width: 34px;
		text-align: right;
		font-family: ui-monospace, monospace;
		font-size: 9px;
		color: rgb(113 113 122);
		white-space: nowrap;
	}

	.slider {
		flex: 1;
		height: 3px;
		cursor: pointer;
		appearance: none;
		border-radius: 2px;
		background: linear-gradient(to right, rgba(161, 161, 170, 0.25), rgba(113, 113, 122, 0.15));
	}
	.slider::-webkit-slider-thumb {
		width: 10px;
		height: 10px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(212 212 216);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
		transition: transform 0.1s, box-shadow 0.1s;
	}
	.slider::-webkit-slider-thumb:hover {
		transform: scale(1.15);
		box-shadow: 0 1px 6px rgba(0, 0, 0, 0.4);
	}
	.slider::-moz-range-thumb {
		width: 10px;
		height: 10px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		border: 0;
		background: rgb(212 212 216);
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
	}

	.sel {
		height: 22px;
		cursor: pointer;
		appearance: none;
		border-radius: 5px;
		border: 1px solid rgba(255, 255, 255, 0.08);
		background: rgba(255, 255, 255, 0.05);
		padding: 0 8px;
		font-size: 10px;
		color: rgb(161 161 170);
		outline: none;
		transition: border-color 0.15s, background 0.15s;
	}
	.sel:hover {
		background: rgba(255, 255, 255, 0.08);
	}
	.sel:focus {
		border-color: rgba(255, 255, 255, 0.2);
	}

	.btn {
		flex: 1;
		height: 20px;
		border-radius: 4px;
		border: 1px solid rgba(255, 255, 255, 0.08);
		background: rgba(255, 255, 255, 0.03);
		font-size: 9px;
		color: rgb(113 113 122);
		cursor: pointer;
		transition: all 0.1s;
	}
	.btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgb(161 161 170);
	}
	.btn.active {
		background: rgba(255, 255, 255, 0.12);
		border-color: rgba(255, 255, 255, 0.15);
		color: rgb(228 228 231);
	}
</style>
