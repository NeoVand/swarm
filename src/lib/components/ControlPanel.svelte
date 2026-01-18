<script lang="ts">
	import { fade, scale, slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { onMount } from 'svelte';
	import { driver } from 'driver.js';
	import 'driver.js/dist/driver.css';
	import BoundaryIcon from './BoundaryIcon.svelte';
	import PaletteIcon from './PaletteIcon.svelte';
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
	let boundaryDropdownOpen = $state(false);
	let boundaryDropdownRef: HTMLDivElement;
	let paletteDropdownOpen = $state(false);
	let paletteDropdownRef: HTMLDivElement;

	function selectBoundary(mode: BoundaryMode) {
		setBoundaryMode(mode);
		boundaryDropdownOpen = false;
	}

	function selectPalette(spectrum: ColorSpectrum) {
		setColorSpectrum(spectrum);
		paletteDropdownOpen = false;
	}

	function handleClickOutside(event: MouseEvent) {
		if (boundaryDropdownOpen && boundaryDropdownRef && !boundaryDropdownRef.contains(event.target as Node)) {
			boundaryDropdownOpen = false;
		}
		if (paletteDropdownOpen && paletteDropdownRef && !paletteDropdownRef.contains(event.target as Node)) {
			paletteDropdownOpen = false;
		}
	}

	$effect(() => {
		if (boundaryDropdownOpen || paletteDropdownOpen) {
			document.addEventListener('click', handleClickOutside);
			return () => document.removeEventListener('click', handleClickOutside);
		}
	});

	function togglePanel(): void {
		isPanelOpen.update((v) => !v);
	}

	// Driver.js tour configuration
	function startTour(): void {
		// Ensure panel is open before starting tour
		if (!$isPanelOpen) {
			isPanelOpen.set(true);
		}

		// Small delay to let panel animate open
		setTimeout(() => {
			const driverObj = driver({
				showProgress: true,
				animate: true,
				smoothScroll: true,
				allowClose: true,
				overlayColor: 'rgba(0, 0, 0, 0.85)',
				stagePadding: 10,
				stageRadius: 10,
				popoverClass: 'tour-popover',
				popoverOffset: 12,
				steps: [
					{
						popover: {
							title: 'Welcome to Boids',
							description: `
								<p style="margin-bottom: 12px; color: #a1a1aa;">Boids simulate flocking behavior using three simple rules, discovered by Craig Reynolds in 1986:</p>
								<div style="display: flex; gap: 8px; margin-bottom: 12px;">
									<div style="flex: 1; background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; text-align: center;">
										<svg viewBox="0 0 60 50" style="width: 100%; height: 40px; margin-bottom: 6px;">
											<defs>
												<marker id="arrow1" markerWidth="4" markerHeight="4" refX="2" refY="2" orient="auto">
													<path d="M0,0 L4,2 L0,4 Z" fill="#22d3ee"/>
												</marker>
											</defs>
											<path d="M10,35 L25,20" stroke="#22d3ee" stroke-width="2" marker-end="url(#arrow1)"/>
											<path d="M25,40 L40,25" stroke="#22d3ee" stroke-width="2" marker-end="url(#arrow1)"/>
											<path d="M40,38 L55,23" stroke="#22d3ee" stroke-width="2" marker-end="url(#arrow1)"/>
											<polygon points="25,17 21,24 29,24" fill="#22d3ee"/>
											<polygon points="40,22 36,29 44,29" fill="#22d3ee"/>
											<polygon points="55,20 51,27 59,27" fill="#22d3ee"/>
										</svg>
										<div style="font-size: 10px; font-weight: 600; color: #22d3ee;">ALIGNMENT</div>
										<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Match neighbors' direction</div>
									</div>
									<div style="flex: 1; background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; text-align: center;">
										<svg viewBox="0 0 60 50" style="width: 100%; height: 40px; margin-bottom: 6px;">
											<circle cx="30" cy="25" r="4" fill="#a78bfa" opacity="0.3"/>
											<circle cx="30" cy="25" r="8" stroke="#a78bfa" stroke-width="1" fill="none" stroke-dasharray="2 2" opacity="0.5"/>
											<polygon points="12,15 8,22 16,22" fill="#a78bfa" transform="rotate(120, 12, 15)"/>
											<line x1="12" y1="18" x2="24" y2="24" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 1" opacity="0.6"/>
											<polygon points="48,18 44,25 52,25" fill="#a78bfa" transform="rotate(-120, 48, 18)"/>
											<line x1="48" y1="21" x2="36" y2="25" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 1" opacity="0.6"/>
											<polygon points="25,42 21,49 29,49" fill="#a78bfa" transform="rotate(-30, 25, 42)"/>
											<line x1="26" y1="44" x2="30" y2="32" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 1" opacity="0.6"/>
										</svg>
										<div style="font-size: 10px; font-weight: 600; color: #a78bfa;">COHESION</div>
										<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Move toward group center</div>
									</div>
									<div style="flex: 1; background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; text-align: center;">
										<svg viewBox="0 0 60 50" style="width: 100%; height: 40px; margin-bottom: 6px;">
											<polygon points="30,25 26,32 34,32" fill="#fb7185"/>
											<polygon points="15,20 11,27 19,27" fill="#fb7185" transform="rotate(-45, 15, 20)"/>
											<line x1="23" y1="24" x2="18" y2="22" stroke="#fb7185" stroke-width="1.5" opacity="0.5"/>
											<polygon points="45,20 41,27 49,27" fill="#fb7185" transform="rotate(45, 45, 20)"/>
											<line x1="37" y1="24" x2="42" y2="22" stroke="#fb7185" stroke-width="1.5" opacity="0.5"/>
											<polygon points="30,42 26,49 34,49" fill="#fb7185"/>
											<line x1="30" y1="34" x2="30" y2="40" stroke="#fb7185" stroke-width="1.5" opacity="0.5"/>
										</svg>
										<div style="font-size: 10px; font-weight: 600; color: #fb7185;">SEPARATION</div>
										<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Avoid crowding neighbors</div>
									</div>
								</div>
								<p style="font-size: 11px; color: #71717a; text-align: center; margin-bottom: 8px;">These simple rules create complex, lifelike swarm behavior!</p>
								<a href="https://en.wikipedia.org/wiki/Boids" target="_blank" rel="noopener noreferrer" style="display: flex; align-items: center; justify-content: center; gap: 4px; font-size: 10px; color: #a78bfa; text-decoration: none; opacity: 0.8; transition: opacity 0.2s; margin-bottom: 12px;" onmouseover="this.style.opacity='1'" onmouseout="this.style.opacity='0.8'">
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
										<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
										<polyline points="15 3 21 3 21 9"/>
										<line x1="10" y1="14" x2="21" y2="3"/>
									</svg>
									Learn more on Wikipedia
								</a>
								<div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 10px; margin-top: 4px;">
									<p style="font-size: 10px; color: #52525b; text-align: center; margin: 0;">
										<span style="color: #22d3ee;">WebGPU</span>-powered simulation · Scales to 50,000+ boids
									</p>
									<p style="font-size: 9px; color: #3f3f46; text-align: center; margin-top: 6px;">
										Developed by Neo Mohsenvand
									</p>
								</div>
							`,
							side: 'over',
							align: 'center'
						}
					},
					{
						element: '#section-visuals',
						popover: {
							title: 'Boid Appearance',
							description: `<p>Customize how the swarm looks:</p>
								<ul>
									<li><strong>Size</strong> — Scale of each boid triangle</li>
									<li><strong>Trail</strong> — Length of the motion trail behind each boid</li>
									<li><strong>Colorize</strong> — What property determines boid color (direction, speed, neighbors...)</li>
									<li><strong>Palette</strong> — Color scheme for visualization</li>
								</ul>
								<p><em>Rainbow palette + Direction coloring shows flow beautifully!</em></p>`,
							side: 'left',
							align: 'start'
						}
					},
					{
						element: '#section-population',
						popover: {
							title: 'Population',
							description: `<p>Control the number of boids in the simulation.</p>
								<p>This simulation uses <strong>WebGPU</strong> for massively parallel computation, allowing tens of thousands of boids to interact in real-time.</p>
								<p><em>Modern GPUs can handle 50,000+ boids at smooth framerates!</em></p>`,
							side: 'left',
							align: 'start'
						}
					},
					{
						element: '#section-world',
						popover: {
							title: 'World & Cursor',
							description: `<p>Define the simulation space and your interaction:</p>
								<ul>
									<li><strong>Bounds</strong> — Topology of the world (Torus wraps around, Plane has walls, Möbius flips!)</li>
									<li><strong>Cursor</strong> — Pull attracts boids, Push repels them</li>
									<li><strong>Shape</strong> — Ring makes boids orbit you, Vortex creates swirls!</li>
									<li><strong>Size & Power</strong> — Control cursor influence area and strength</li>
								</ul>
								<p><em>Try Vortex cursor with Pull mode for mesmerizing spirals!</em></p>`,
							side: 'left',
							align: 'start'
						}
					},
					{
						element: '#section-flocking',
						popover: {
							title: 'Flocking Behavior',
							description: `<p>The three classic rules of boids, discovered by Craig Reynolds in 1986:</p>
								<ul>
									<li><strong>Align</strong> — Steer toward the average heading of nearby boids</li>
									<li><strong>Cohesion</strong> — Move toward the center of mass of neighbors</li>
									<li><strong>Separate</strong> — Avoid crowding nearby boids</li>
									<li><strong>Range</strong> — How far each boid can "see" its neighbors</li>
								</ul>
								<p><em>Try setting Cohesion high and Separation low to see tight swarms!</em></p>`,
							side: 'left',
							align: 'start'
						}
					},
					{
						element: '#section-dynamics',
						popover: {
							title: 'Dynamics',
							description: `<p>Control the physics of movement:</p>
								<ul>
									<li><strong>Speed</strong> — Maximum velocity of each boid</li>
									<li><strong>Force</strong> — How quickly boids can change direction (agility)</li>
									<li><strong>Noise</strong> — Random perturbation for organic, less robotic movement</li>
									<li><strong>Rebels</strong> — Percentage of boids that temporarily ignore flocking rules</li>
								</ul>
								<p><em>High noise + rebels creates chaotic, lifelike behavior!</em></p>`,
							side: 'left',
							align: 'start'
						}
					},
					{
						element: '#section-algorithm',
						popover: {
							title: 'Algorithm',
							description: `<p>Choose the spatial algorithm for neighbor detection.</p>
								<ul>
									<li><strong>Hash-Free</strong> — Eliminates grid artifacts by giving each boid a unique spatial offset</li>
									<li><strong>Topological k-NN</strong> — Each boid considers exactly k nearest neighbors regardless of distance</li>
									<li><strong>Smooth Metric</strong> — Uses smooth kernel weighting with grid jitter</li>
									<li><strong>Stochastic</strong> — Random spatial sampling for organic behavior</li>
									<li><strong>Density Adaptive</strong> — Adjusts forces based on local crowding</li>
								</ul>`,
							side: 'left',
							align: 'start'
						}
					}
				]
			});

			driverObj.drive();
		}, 250);
	}

	const boundaryOptions = [
		{ value: BoundaryMode.Plane, label: 'Plane (bounce)' },
		{ value: BoundaryMode.Torus, label: 'Torus' },
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
		{ value: ColorSpectrum.Neon, label: 'Neon' },
		{ value: ColorSpectrum.Sunset, label: 'Sunset' },
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
		{ value: CursorShape.Dot, label: 'Dot' },
		{ value: CursorShape.Ring, label: 'Ring' },
		{ value: CursorShape.Disk, label: 'Disk' },
		{ value: CursorShape.Vortex, label: 'Vortex' }
	];
</script>

{#if isOpen}
	<!-- Panel (open state) -->
	<div
		class="panel fixed right-4 top-4 z-40 w-64 rounded-xl"
		transition:scale={{ duration: 200, easing: cubicOut, start: 0.95, opacity: 0 }}
	>
		<!-- Header with help and gear buttons -->
		<div class="flex items-center justify-between px-3 py-2.5">
			<span class="text-[10px] font-semibold uppercase tracking-widest text-zinc-400">Controls</span>
			<div class="flex items-center gap-1">
				<button
					onclick={startTour}
					class="flex h-6 w-6 items-center justify-center rounded-md text-zinc-500 transition-all hover:bg-white/10 hover:text-zinc-300"
					aria-label="Start Tour"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
						<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
					</svg>
				</button>
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
		</div>

		<!-- Content -->
		<div class="content-scroll max-h-[calc(100vh-100px)] px-3 pb-3">
			<!-- Visuals -->
			<div id="section-visuals" class="mb-3">
				<div class="section-label">Boids</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Size</span>
						<input type="range" min="0.2" max="3" step="0.1" value={currentParams.boidSize}
							oninput={(e) => setBoidSize(parseFloat(e.currentTarget.value))} class="slider" aria-label="Boid Size" />
						<span class="value">{currentParams.boidSize.toFixed(1)}</span>
					</div>
					<div class="row">
						<span class="label">Trail</span>
						<input type="range" min="5" max="100" step="5" value={currentParams.trailLength}
							oninput={(e) => setTrailLength(parseInt(e.currentTarget.value))} class="slider" aria-label="Trail" />
						<span class="value">{currentParams.trailLength}</span>
					</div>
					<div class="row">
						<span class="label">Colorize</span>
						<select value={currentParams.colorMode} onchange={(e) => setColorMode(parseInt(e.currentTarget.value))}
							class="sel flex-1" aria-label="Colorize Mode">
							{#each colorOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
						</select>
					</div>
					<div class="row">
						<span class="label">Palette</span>
						<div class="relative flex-1" bind:this={paletteDropdownRef}>
							<button 
								class="sel w-full flex items-center gap-2 text-left"
								onclick={() => paletteDropdownOpen = !paletteDropdownOpen}
								aria-label="Palette"
								aria-expanded={paletteDropdownOpen}
							>
								<PaletteIcon spectrum={currentParams.colorSpectrum} size={14} />
								<span class="flex-1 truncate">{spectrumOptions.find(o => o.value === currentParams.colorSpectrum)?.label}</span>
								<svg class="h-3 w-3 opacity-50 transition-transform" class:rotate-180={paletteDropdownOpen} viewBox="0 0 20 20" fill="currentColor">
									<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
								</svg>
							</button>
							{#if paletteDropdownOpen}
								<div 
									class="dropdown-menu absolute left-0 right-0 top-full z-50 mt-1 overflow-y-auto rounded-md"
									transition:slide={{ duration: 150, easing: cubicOut }}
								>
									{#each spectrumOptions as opt}
										<button
											class="dropdown-item w-full flex items-center gap-2 px-2 py-1.5 text-left text-[10px]"
											class:active={currentParams.colorSpectrum === opt.value}
											onclick={() => selectPalette(opt.value)}
										>
											<PaletteIcon spectrum={opt.value} size={14} />
											<span>{opt.label}</span>
										</button>
									{/each}
								</div>
							{/if}
						</div>
					</div>
				</div>
			</div>

			<!-- Population -->
			<div id="section-population" class="mb-3">
				<div class="section-label">Population</div>
				<div class="row">
					<input type="range" min="500" max="50000" step="500" value={currentParams.population}
						oninput={(e) => setPopulation(parseInt(e.currentTarget.value))} class="slider" aria-label="Population" />
					<span class="value">{(currentParams.population / 1000).toFixed(1)}k</span>
				</div>
			</div>

			<!-- World -->
			<div id="section-world" class="mb-3">
				<div class="section-label">World & Cursor</div>
				<div class="space-y-1.5">
					<div class="row">
						<span class="label">Bounds</span>
						<div class="relative flex-1" bind:this={boundaryDropdownRef}>
							<button 
								class="sel w-full flex items-center gap-2 text-left"
								onclick={() => boundaryDropdownOpen = !boundaryDropdownOpen}
								aria-label="Boundary"
								aria-expanded={boundaryDropdownOpen}
							>
								<BoundaryIcon mode={currentParams.boundaryMode} size={14} />
								<span class="flex-1 truncate">{boundaryOptions.find(o => o.value === currentParams.boundaryMode)?.label}</span>
								<svg class="h-3 w-3 opacity-50 transition-transform" class:rotate-180={boundaryDropdownOpen} viewBox="0 0 20 20" fill="currentColor">
									<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
								</svg>
							</button>
							{#if boundaryDropdownOpen}
								<div 
									class="dropdown-menu absolute left-0 right-0 top-full z-50 mt-1 max-h-48 overflow-y-auto rounded-md"
									transition:slide={{ duration: 150, easing: cubicOut }}
								>
									{#each boundaryOptions as opt}
										<button
											class="dropdown-item w-full flex items-center gap-2 px-2 py-1.5 text-left text-[10px]"
											class:active={currentParams.boundaryMode === opt.value}
											onclick={() => selectBoundary(opt.value)}
										>
											<BoundaryIcon mode={opt.value} size={14} />
											<span>{opt.label}</span>
										</button>
									{/each}
								</div>
							{/if}
						</div>
					</div>
					<div class="row">
						<span class="label">Cursor</span>
						<div class="flex flex-1 gap-0.5">
							<button class="btn icon-btn" class:active={currentParams.cursorMode === CursorMode.Off}
								onclick={() => setCursorMode(CursorMode.Off)} aria-label="Cursor Off" title="Off">
								<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="5" stroke-dasharray="2 2" />
									<line x1="4" y1="4" x2="12" y2="12" />
								</svg>
							</button>
							<button class="btn icon-btn" class:active={currentParams.cursorMode === CursorMode.Attract}
								onclick={() => setCursorMode(CursorMode.Attract)} aria-label="Pull/Attract" title="Pull">
								<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="5" />
									<path d="M8 5v6M5 8l3-3 3 3" />
								</svg>
							</button>
							<button class="btn icon-btn" class:active={currentParams.cursorMode === CursorMode.Repel}
								onclick={() => setCursorMode(CursorMode.Repel)} aria-label="Push/Repel" title="Push">
								<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="5" />
									<path d="M8 5v6M5 8l3 3 3-3" />
								</svg>
							</button>
						</div>
					</div>
					<div class="row">
						<span class="label">Shape</span>
						<div class="flex flex-1 gap-0.5">
							<button class="btn icon-btn" class:active={currentParams.cursorShape === CursorShape.Dot}
								onclick={() => setCursorShape(CursorShape.Dot)} aria-label="Dot" title="Dot">
								<svg viewBox="0 0 16 16" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="2.5" fill="currentColor" />
								</svg>
							</button>
							<button class="btn icon-btn" class:active={currentParams.cursorShape === CursorShape.Ring}
								onclick={() => setCursorShape(CursorShape.Ring)} aria-label="Ring" title="Ring">
								<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="5" />
								</svg>
							</button>
							<button class="btn icon-btn" class:active={currentParams.cursorShape === CursorShape.Disk}
								onclick={() => setCursorShape(CursorShape.Disk)} aria-label="Disk" title="Disk">
								<svg viewBox="0 0 16 16" class="h-3.5 w-3.5">
									<circle cx="8" cy="8" r="5" fill="currentColor" opacity="0.6" />
									<circle cx="8" cy="8" r="5" fill="none" stroke="currentColor" stroke-width="1.5" />
								</svg>
							</button>
							<button class="btn icon-btn" class:active={currentParams.cursorShape === CursorShape.Vortex}
								onclick={() => setCursorShape(CursorShape.Vortex)} aria-label="Vortex" title="Vortex">
								<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.2" class="h-3.5 w-3.5">
									<path d="M8 3c2.5 0 4.5 2 4.5 5s-2 5-4.5 5" />
									<path d="M8 5c1.5 0 2.5 1.2 2.5 3s-1 3-2.5 3" />
									<circle cx="8" cy="8" r="1" fill="currentColor" />
								</svg>
							</button>
						</div>
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

			<!-- Flocking -->
			<div id="section-flocking" class="mb-3">
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
			<div id="section-dynamics" class="mb-3">
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

			<!-- Algorithm -->
			<div id="section-algorithm">
				<div class="section-label">Algorithm</div>
				<select value={currentParams.algorithmMode} onchange={(e) => setAlgorithmMode(parseInt(e.currentTarget.value))}
					class="sel w-full" aria-label="Algorithm">
					{#each algorithmOptions as opt}<option value={opt.value}>{opt.label}</option>{/each}
				</select>
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
		background: rgba(8, 8, 12, 0.92);
		backdrop-filter: blur(24px) saturate(1.1);
		-webkit-backdrop-filter: blur(24px) saturate(1.1);
		border: 1px solid rgba(255, 255, 255, 0.06);
		box-shadow: 
			0 8px 32px rgba(0, 0, 0, 0.6),
			0 2px 4px rgba(0, 0, 0, 0.3),
			inset 0 1px 0 rgba(255, 255, 255, 0.03);
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
		background: rgba(8, 8, 12, 0.85);
		backdrop-filter: blur(16px) saturate(1.1);
		-webkit-backdrop-filter: blur(16px) saturate(1.1);
		border: 1px solid rgba(255, 255, 255, 0.08);
		box-shadow: 
			0 2px 12px rgba(0, 0, 0, 0.4),
			inset 0 1px 0 rgba(255, 255, 255, 0.03);
	}
	.gear-btn:hover {
		background: rgba(16, 16, 20, 0.9);
		border-color: rgba(255, 255, 255, 0.12);
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

	.dropdown-menu {
		background: rgba(10, 10, 14, 0.98);
		backdrop-filter: blur(16px);
		-webkit-backdrop-filter: blur(16px);
		border: 1px solid rgba(255, 255, 255, 0.08);
		border-radius: 6px;
		box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);
		padding: 2px;
	}
	.dropdown-menu::-webkit-scrollbar {
		width: 5px;
	}
	.dropdown-menu::-webkit-scrollbar-track {
		background: transparent;
	}
	.dropdown-menu::-webkit-scrollbar-thumb {
		background: rgba(255, 255, 255, 0.15);
		border-radius: 3px;
	}
	.dropdown-item {
		color: rgb(161 161 170);
		transition: background 0.1s, color 0.1s;
		border-radius: 4px;
	}
	.dropdown-item:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgb(228 228 231);
	}
	.dropdown-item.active {
		background: rgba(255, 255, 255, 0.1);
		color: rgb(250 250 250);
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
	.btn.icon-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0;
	}

	/* Driver.js custom styles */
	:global(.driver-popover) {
		background: rgba(20, 20, 24, 0.95) !important;
		backdrop-filter: blur(20px) !important;
		border: 1px solid rgba(255, 255, 255, 0.1) !important;
		border-radius: 12px !important;
		box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5) !important;
		color: #e4e4e7 !important;
		max-width: 340px !important;
	}
	:global(.driver-popover-title) {
		font-size: 15px !important;
		font-weight: 600 !important;
		color: #fafafa !important;
		margin-bottom: 8px !important;
	}
	:global(.driver-popover-description) {
		font-size: 12px !important;
		line-height: 1.6 !important;
		color: #a1a1aa !important;
	}
	:global(.driver-popover-description p) {
		margin: 0 0 8px 0 !important;
	}
	:global(.driver-popover-description ul) {
		margin: 8px 0 !important;
		padding-left: 16px !important;
	}
	:global(.driver-popover-description li) {
		margin: 4px 0 !important;
	}
	:global(.driver-popover-description strong) {
		color: #e4e4e7 !important;
	}
	:global(.driver-popover-description em) {
		color: #a78bfa !important;
		font-style: normal !important;
	}
	:global(.driver-popover-progress-text) {
		font-size: 10px !important;
		color: #71717a !important;
	}
	:global(.driver-popover-navigation-btns) {
		gap: 8px !important;
	}
	:global(.driver-popover-prev-btn),
	:global(.driver-popover-next-btn) {
		background: rgba(255, 255, 255, 0.1) !important;
		border: 1px solid rgba(255, 255, 255, 0.15) !important;
		border-radius: 6px !important;
		color: #e4e4e7 !important;
		font-size: 11px !important;
		padding: 6px 14px !important;
		transition: all 0.15s !important;
	}
	:global(.driver-popover-prev-btn:hover),
	:global(.driver-popover-next-btn:hover) {
		background: rgba(255, 255, 255, 0.15) !important;
		border-color: rgba(255, 255, 255, 0.2) !important;
	}
	:global(.driver-popover-close-btn) {
		color: #71717a !important;
	}
	:global(.driver-popover-close-btn:hover) {
		color: #e4e4e7 !important;
	}
	:global(.driver-popover-arrow) {
		display: none !important;
	}
</style>
