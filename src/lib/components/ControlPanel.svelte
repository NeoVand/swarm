<script lang="ts">
	import {
		params,
		isPanelOpen,
		fps,
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
		setCursorForce,
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
		AlgorithmMode
	} from '$lib/stores/simulation';

	let currentParams = $derived($params);
	let isOpen = $derived($isPanelOpen);
	let currentFps = $derived($fps);

	function togglePanel(): void {
		isPanelOpen.update((v) => !v);
	}

	const boundaryOptions = [
		{ value: BoundaryMode.Torus, label: 'Torus' },
		{ value: BoundaryMode.Plane, label: 'Plane' },
		{ value: BoundaryMode.CylinderX, label: 'Cyl-X' },
		{ value: BoundaryMode.CylinderY, label: 'Cyl-Y' },
		{ value: BoundaryMode.MobiusX, label: 'Möb-X' },
		{ value: BoundaryMode.MobiusY, label: 'Möb-Y' },
		{ value: BoundaryMode.KleinX, label: 'Klein-X' },
		{ value: BoundaryMode.KleinY, label: 'Klein-Y' },
		{ value: BoundaryMode.ProjectivePlane, label: 'Proj' }
	];

	const colorOptions = [
		{ value: ColorMode.Orientation, label: 'Dir' },
		{ value: ColorMode.Speed, label: 'Spd' },
		{ value: ColorMode.Neighbors, label: 'Nbr' },
		{ value: ColorMode.Acceleration, label: 'Acc' },
		{ value: ColorMode.Turning, label: 'Turn' }
	];

	const spectrumOptions = [
		{ value: ColorSpectrum.Chrome, label: 'Chrome' },
		{ value: ColorSpectrum.Cool, label: 'Cool' },
		{ value: ColorSpectrum.Warm, label: 'Warm' },
		{ value: ColorSpectrum.Rainbow, label: 'Rainbow' },
		{ value: ColorSpectrum.Mono, label: 'Mono' }
	];

	const algorithmOptions = [
		{ value: AlgorithmMode.Classic, label: 'Classic' },
		{ value: AlgorithmMode.TopologicalKNN, label: 'Topological k-NN' },
		{ value: AlgorithmMode.SmoothMetric, label: 'Smooth Metric' },
		{ value: AlgorithmMode.HashFree, label: 'Hash-Free' },
		{ value: AlgorithmMode.StochasticSample, label: 'Stochastic' },
		{ value: AlgorithmMode.DensityAdaptive, label: 'Density Adaptive' }
	];
</script>

<!-- Gear icon -->
<button
	onclick={togglePanel}
	class="fixed right-3 top-3 z-50 flex h-8 w-8 items-center justify-center rounded-md transition-all hover:bg-zinc-800/50 hover:text-zinc-300 {isOpen ? 'bg-zinc-800/50 text-zinc-300' : 'text-zinc-500'}"
	aria-label="Settings"
>
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4">
		<path fill-rule="evenodd" d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
	</svg>
</button>

<!-- Panel -->
<div
	class="fixed right-0 top-0 z-40 flex h-full w-56 transform flex-col bg-black/80 backdrop-blur-md transition-transform duration-200"
	class:translate-x-0={isOpen}
	class:translate-x-full={!isOpen}
>
	<!-- Header -->
	<div class="flex items-center justify-between px-3 pb-2 pt-3">
		<span class="text-[10px] font-medium uppercase tracking-wider text-zinc-500">Controls</span>
		<span class="font-mono text-[10px] text-cyan-400">{currentFps} fps</span>
	</div>

	<!-- Scrollable content -->
	<div class="flex-1 overflow-y-auto px-3 pb-4">
		<!-- Algorithm -->
		<div class="mb-3">
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">Algorithm</div>
			<select value={currentParams.algorithmMode} onchange={(e) => setAlgorithmMode(parseInt(e.currentTarget.value))}
				class="sel w-full" aria-label="Algorithm">
				{#each algorithmOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
			</select>
		</div>

		<!-- Flocking -->
		<div class="mb-3">
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">Flocking</div>
			<div class="grid grid-cols-2 gap-x-2 gap-y-1.5">
				<div class="col-span-2">
					<div class="flex items-center gap-1.5">
						<span class="w-12 text-[10px] text-zinc-500">Align</span>
						<input type="range" min="0" max="3" step="0.1" value={currentParams.alignment}
							oninput={(e) => setAlignment(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Alignment" />
						<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.alignment.toFixed(1)}</span>
					</div>
				</div>
				<div class="col-span-2">
					<div class="flex items-center gap-1.5">
						<span class="w-12 text-[10px] text-zinc-500">Cohesion</span>
						<input type="range" min="0" max="3" step="0.1" value={currentParams.cohesion}
							oninput={(e) => setCohesion(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Cohesion" />
						<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.cohesion.toFixed(1)}</span>
					</div>
				</div>
				<div class="col-span-2">
					<div class="flex items-center gap-1.5">
						<span class="w-12 text-[10px] text-zinc-500">Separate</span>
						<input type="range" min="0" max="4" step="0.1" value={currentParams.separation}
							oninput={(e) => setSeparation(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Separation" />
						<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.separation.toFixed(1)}</span>
					</div>
				</div>
				<div class="col-span-2">
					<div class="flex items-center gap-1.5">
						<span class="w-12 text-[10px] text-zinc-500">Range</span>
						<input type="range" min="20" max="150" step="5" value={currentParams.perception}
							oninput={(e) => setPerception(parseInt(e.currentTarget.value))} class="slider flex-1" aria-label="Perception" />
						<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.perception}</span>
					</div>
				</div>
			</div>
		</div>

		<!-- Dynamics -->
		<div class="mb-3">
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">Dynamics</div>
			<div class="space-y-1.5">
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Speed</span>
					<input type="range" min="1" max="15" step="0.5" value={currentParams.maxSpeed}
						oninput={(e) => setMaxSpeed(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Speed" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.maxSpeed.toFixed(1)}</span>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Force</span>
					<input type="range" min="0.01" max="0.5" step="0.01" value={currentParams.maxForce}
						oninput={(e) => setMaxForce(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Force" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.maxForce.toFixed(2)}</span>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Noise</span>
					<input type="range" min="0" max="1" step="0.05" value={currentParams.noise}
						oninput={(e) => setNoise(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Noise" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.noise.toFixed(2)}</span>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Rebels</span>
					<input type="range" min="0" max="0.2" step="0.01" value={currentParams.rebels}
						oninput={(e) => setRebels(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Rebels" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{(currentParams.rebels * 100).toFixed(0)}%</span>
				</div>
			</div>
		</div>

		<!-- World -->
		<div class="mb-3">
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">World</div>
			<div class="space-y-1.5">
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Bounds</span>
					<select value={currentParams.boundaryMode} onchange={(e) => setBoundaryMode(parseInt(e.currentTarget.value))}
						class="sel flex-1" aria-label="Boundary">
						{#each boundaryOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
					</select>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Cursor</span>
					<div class="flex flex-1 gap-0.5">
						<button class="btn" class:active={currentParams.cursorMode === CursorMode.Off}
							onclick={() => setCursorMode(CursorMode.Off)}>Off</button>
						<button class="btn" class:active={currentParams.cursorMode === CursorMode.Attract}
							onclick={() => setCursorMode(CursorMode.Attract)}>Pull</button>
						<button class="btn" class:active={currentParams.cursorMode === CursorMode.Repel}
							onclick={() => setCursorMode(CursorMode.Repel)}>Push</button>
					</div>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Power</span>
					<input type="range" min="0" max="1" step="0.05" value={currentParams.cursorForce}
						oninput={(e) => setCursorForce(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Cursor Force" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.cursorForce.toFixed(2)}</span>
				</div>
			</div>
		</div>

		<!-- Visuals -->
		<div class="mb-3">
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">Visuals</div>
			<div class="space-y-1.5">
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Size</span>
					<input type="range" min="0.2" max="3" step="0.1" value={currentParams.boidSize}
						oninput={(e) => setBoidSize(parseFloat(e.currentTarget.value))} class="slider flex-1" aria-label="Size" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.boidSize.toFixed(1)}</span>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Trail</span>
					<input type="range" min="5" max="80" step="5" value={currentParams.trailLength}
						oninput={(e) => setTrailLength(parseInt(e.currentTarget.value))} class="slider flex-1" aria-label="Trail" />
					<span class="w-6 text-right font-mono text-[9px] text-zinc-600">{currentParams.trailLength}</span>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Color</span>
					<select value={currentParams.colorMode} onchange={(e) => setColorMode(parseInt(e.currentTarget.value))}
						class="sel flex-1" aria-label="Color Mode">
						{#each colorOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
					</select>
				</div>
				<div class="flex items-center gap-1.5">
					<span class="w-12 text-[10px] text-zinc-500">Palette</span>
					<select value={currentParams.colorSpectrum} onchange={(e) => setColorSpectrum(parseInt(e.currentTarget.value))}
						class="sel flex-1" aria-label="Spectrum">
						{#each spectrumOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
					</select>
				</div>
			</div>
		</div>

		<!-- Population -->
		<div>
			<div class="mb-1.5 text-[9px] font-medium uppercase tracking-wider text-zinc-600">Population</div>
			<div class="flex items-center gap-1.5">
				<input type="range" min="500" max="50000" step="500" value={currentParams.population}
					oninput={(e) => setPopulation(parseInt(e.currentTarget.value))} class="slider flex-1" aria-label="Population" />
				<span class="w-10 text-right font-mono text-[9px] text-zinc-600">{(currentParams.population / 1000).toFixed(1)}k</span>
			</div>
		</div>
	</div>
</div>

<style>
	.slider {
		height: 3px;
		cursor: pointer;
		appearance: none;
		border-radius: 2px;
		background: linear-gradient(to right, rgb(6 182 212 / 0.3), rgb(6 182 212 / 0.15));
	}
	.slider::-webkit-slider-thumb {
		width: 10px;
		height: 10px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(6 182 212);
		box-shadow: 0 0 6px rgb(6 182 212 / 0.5);
	}
	.slider::-moz-range-thumb {
		width: 10px;
		height: 10px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		border: 0;
		background: rgb(6 182 212);
		box-shadow: 0 0 6px rgb(6 182 212 / 0.5);
	}
	.sel {
		height: 22px;
		cursor: pointer;
		appearance: none;
		border-radius: 4px;
		border: 1px solid rgb(63 63 70 / 0.5);
		background: rgb(24 24 27 / 0.8);
		padding: 0 6px;
		font-size: 10px;
		color: rgb(161 161 170);
		outline: none;
	}
	.sel:focus { border-color: rgb(6 182 212 / 0.5); }
	.btn {
		flex: 1;
		height: 20px;
		border-radius: 3px;
		border: 1px solid rgb(63 63 70 / 0.5);
		background: rgb(24 24 27 / 0.6);
		font-size: 9px;
		color: rgb(113 113 122);
		cursor: pointer;
		transition: all 100ms;
	}
	.btn:hover { background: rgb(39 39 42 / 0.8); color: rgb(161 161 170); }
	.btn.active {
		background: rgb(6 182 212 / 0.15);
		border-color: rgb(6 182 212 / 0.4);
		color: rgb(6 182 212);
	}
</style>
