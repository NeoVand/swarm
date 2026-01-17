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
		BoundaryMode,
		ColorMode,
		ColorSpectrum,
		CursorMode
	} from '$lib/stores/simulation';

	let currentParams = $derived($params);
	let isOpen = $derived($isPanelOpen);
	let currentFps = $derived($fps);

	function togglePanel(): void {
		isPanelOpen.update((v) => !v);
	}

	const boundaryModes = [
		{ value: BoundaryMode.Plane, label: 'Plane' },
		{ value: BoundaryMode.CylinderX, label: 'Cylinder X' },
		{ value: BoundaryMode.CylinderY, label: 'Cylinder Y' },
		{ value: BoundaryMode.Torus, label: 'Torus' },
		{ value: BoundaryMode.MobiusX, label: 'Möbius X' },
		{ value: BoundaryMode.MobiusY, label: 'Möbius Y' },
		{ value: BoundaryMode.KleinX, label: 'Klein X' },
		{ value: BoundaryMode.KleinY, label: 'Klein Y' },
		{ value: BoundaryMode.ProjectivePlane, label: 'Projective' }
	];

	const cursorModes = [
		{ value: CursorMode.Off, label: 'Off' },
		{ value: CursorMode.Attract, label: 'Attract' },
		{ value: CursorMode.Repel, label: 'Repel' }
	];

	const colorModes = [
		{ value: ColorMode.Speed, label: 'Speed' },
		{ value: ColorMode.Orientation, label: 'Orientation' },
		{ value: ColorMode.Neighbors, label: 'Neighbors' },
		{ value: ColorMode.Acceleration, label: 'Acceleration' },
		{ value: ColorMode.Turning, label: 'Turning' }
	];

	const colorSpectrums = [
		{ value: ColorSpectrum.Chrome, label: 'Chrome' },
		{ value: ColorSpectrum.Cool, label: 'Cool' },
		{ value: ColorSpectrum.Warm, label: 'Warm' },
		{ value: ColorSpectrum.Rainbow, label: 'Rainbow' },
		{ value: ColorSpectrum.Mono, label: 'Mono' }
	];
</script>

<!-- Gear icon button -->
<button
	onclick={togglePanel}
	class="fixed right-4 top-4 z-50 flex h-10 w-10 items-center justify-center rounded-lg bg-zinc-800/30 text-zinc-400 backdrop-blur-sm transition-all hover:bg-zinc-800/50 hover:text-zinc-200"
	aria-label="Toggle settings"
>
	<svg
		xmlns="http://www.w3.org/2000/svg"
		viewBox="0 0 24 24"
		fill="none"
		stroke="currentColor"
		stroke-width="1.5"
		stroke-linecap="round"
		stroke-linejoin="round"
		class="h-5 w-5 transition-transform duration-300"
		class:rotate-90={isOpen}
	>
		<circle cx="12" cy="12" r="3" />
		<path
			d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"
		/>
	</svg>
</button>

<!-- Sliding panel -->
<div
	class="fixed right-0 top-0 z-40 h-full w-80 transform overflow-y-auto bg-zinc-900/70 p-6 pt-16 backdrop-blur-xl transition-transform duration-300 ease-out"
	class:translate-x-0={isOpen}
	class:translate-x-full={!isOpen}
>
	<!-- FPS counter -->
	<div class="mb-6 flex items-center justify-between text-xs">
		<span class="text-zinc-500">Performance</span>
		<span class="font-mono text-zinc-300">{currentFps} FPS</span>
	</div>

	<!-- Flocking Rules -->
	<div class="mb-6 space-y-4">
		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Alignment</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.alignment.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0"
				max="3"
				step="0.05"
				value={currentParams.alignment}
				oninput={(e) => setAlignment(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Alignment"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Cohesion</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.cohesion.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0"
				max="3"
				step="0.05"
				value={currentParams.cohesion}
				oninput={(e) => setCohesion(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Cohesion"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Separation</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.separation.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0"
				max="4"
				step="0.05"
				value={currentParams.separation}
				oninput={(e) => setSeparation(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Separation"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Perception</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.perception}</span>
			</div>
			<input
				type="range"
				min="10"
				max="200"
				step="5"
				value={currentParams.perception}
				oninput={(e) => setPerception(parseInt(e.currentTarget.value))}
				class="slider"
				aria-label="Perception"
			/>
		</div>
	</div>

	<div class="mb-6 h-px bg-zinc-700/50"></div>

	<!-- Movement -->
	<div class="mb-6 space-y-4">
		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Max Speed</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.maxSpeed.toFixed(1)}</span>
			</div>
			<input
				type="range"
				min="0.5"
				max="10"
				step="0.5"
				value={currentParams.maxSpeed}
				oninput={(e) => setMaxSpeed(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Max Speed"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Max Force</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.maxForce.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0.01"
				max="1"
				step="0.01"
				value={currentParams.maxForce}
				oninput={(e) => setMaxForce(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Max Force"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Noise</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.noise.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0"
				max="1"
				step="0.05"
				value={currentParams.noise}
				oninput={(e) => setNoise(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Noise"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Rebels</span>
				<span class="font-mono text-xs text-zinc-500"
					>{(currentParams.rebels * 100).toFixed(0)}%</span
				>
			</div>
			<input
				type="range"
				min="0"
				max="0.3"
				step="0.01"
				value={currentParams.rebels}
				oninput={(e) => setRebels(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Rebels"
			/>
		</div>
	</div>

	<div class="mb-6 h-px bg-zinc-700/50"></div>

	<!-- Boundary & Cursor -->
	<div class="mb-6 space-y-4">
		<div class="space-y-2">
			<span class="text-xs text-zinc-400">Boundary</span>
			<select
				value={currentParams.boundaryMode}
				onchange={(e) => setBoundaryMode(parseInt(e.currentTarget.value))}
				class="select"
				aria-label="Boundary Mode"
			>
				{#each boundaryModes as mode}
					<option value={mode.value}>{mode.label}</option>
				{/each}
			</select>
		</div>

		<div class="space-y-2">
			<span class="text-xs text-zinc-400">Cursor Mode</span>
			<select
				value={currentParams.cursorMode}
				onchange={(e) => setCursorMode(parseInt(e.currentTarget.value))}
				class="select"
				aria-label="Cursor Mode"
			>
				{#each cursorModes as mode}
					<option value={mode.value}>{mode.label}</option>
				{/each}
			</select>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Cursor Force</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.cursorForce.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0"
				max="1"
				step="0.05"
				value={currentParams.cursorForce}
				oninput={(e) => setCursorForce(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Cursor Force"
			/>
		</div>
	</div>

	<div class="mb-6 h-px bg-zinc-700/50"></div>

	<!-- Appearance -->
	<div class="mb-6 space-y-4">
		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Boid Size</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.boidSize.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0.1"
				max="1"
				step="0.05"
				value={currentParams.boidSize}
				oninput={(e) => setBoidSize(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Boid Size"
			/>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Trail Length</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.trailLength}</span>
			</div>
			<input
				type="range"
				min="5"
				max="100"
				step="5"
				value={currentParams.trailLength}
				oninput={(e) => setTrailLength(parseInt(e.currentTarget.value))}
				class="slider"
				aria-label="Trail Length"
			/>
		</div>

		<div class="space-y-2">
			<span class="text-xs text-zinc-400">Color Mode</span>
			<select
				value={currentParams.colorMode}
				onchange={(e) => setColorMode(parseInt(e.currentTarget.value))}
				class="select"
				aria-label="Color Mode"
			>
				{#each colorModes as mode}
					<option value={mode.value}>{mode.label}</option>
				{/each}
			</select>
		</div>

		<div class="space-y-2">
			<span class="text-xs text-zinc-400">Spectrum</span>
			<select
				value={currentParams.colorSpectrum}
				onchange={(e) => setColorSpectrum(parseInt(e.currentTarget.value))}
				class="select"
				aria-label="Color Spectrum"
			>
				{#each colorSpectrums as spectrum}
					<option value={spectrum.value}>{spectrum.label}</option>
				{/each}
			</select>
		</div>

		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Sensitivity</span>
				<span class="font-mono text-xs text-zinc-500">{currentParams.sensitivity.toFixed(2)}</span>
			</div>
			<input
				type="range"
				min="0.5"
				max="3"
				step="0.1"
				value={currentParams.sensitivity}
				oninput={(e) => setSensitivity(parseFloat(e.currentTarget.value))}
				class="slider"
				aria-label="Sensitivity"
			/>
		</div>
	</div>

	<div class="mb-6 h-px bg-zinc-700/50"></div>

	<!-- Population -->
	<div class="space-y-4">
		<div class="space-y-2">
			<div class="flex items-center justify-between">
				<span class="text-xs text-zinc-400">Population</span>
				<span class="font-mono text-xs text-zinc-500"
					>{currentParams.population.toLocaleString()}</span
				>
			</div>
			<input
				type="range"
				min="100"
				max="100000"
				step="100"
				value={currentParams.population}
				oninput={(e) => setPopulation(parseInt(e.currentTarget.value))}
				class="slider"
				aria-label="Population"
			/>
		</div>
	</div>
</div>

<style>
	.slider {
		height: 0.25rem;
		width: 100%;
		cursor: pointer;
		appearance: none;
		border-radius: 9999px;
		background-color: rgb(63 63 70);
	}

	.slider::-webkit-slider-thumb {
		height: 0.75rem;
		width: 0.75rem;
		cursor: pointer;
		appearance: none;
		border-radius: 9999px;
		background-color: rgb(34 211 238);
		transition: transform 150ms;
	}

	.slider::-webkit-slider-thumb:hover {
		transform: scale(1.25);
	}

	.slider::-moz-range-thumb {
		height: 0.75rem;
		width: 0.75rem;
		cursor: pointer;
		appearance: none;
		border-radius: 9999px;
		border: 0;
		background-color: rgb(34 211 238);
		transition: transform 150ms;
	}

	.slider::-moz-range-thumb:hover {
		transform: scale(1.25);
	}

	.select {
		width: 100%;
		cursor: pointer;
		appearance: none;
		border-radius: 0.375rem;
		border: 1px solid rgb(63 63 70);
		background-color: rgb(39 39 42 / 0.5);
		padding: 0.5rem 0.75rem;
		font-size: 0.75rem;
		line-height: 1rem;
		color: rgb(212 212 216);
		outline: none;
		transition: border-color 150ms;
	}

	.select:focus {
		border-color: rgb(6 182 212);
	}
</style>
