<script lang="ts">
	import { fade, scale, slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { onMount } from 'svelte';
	import { driver } from 'driver.js';
	import 'driver.js/dist/driver.css';
	import { base } from '$app/paths';
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
	let algorithmDropdownOpen = $state(false);
	let algorithmDropdownRef: HTMLDivElement;

	// Accordion - only one section open at a time
	let openSection = $state<'boids' | 'world' | 'flocking' | 'dynamics' | 'algorithm'>('boids');

	function toggleSection(section: typeof openSection) {
		openSection = openSection === section ? section : section; // Always open clicked section
	}

	function selectBoundary(mode: BoundaryMode) {
		setBoundaryMode(mode);
		boundaryDropdownOpen = false;
	}

	function selectPalette(spectrum: ColorSpectrum) {
		setColorSpectrum(spectrum);
		paletteDropdownOpen = false;
	}

	function selectAlgorithm(mode: AlgorithmMode) {
		setAlgorithmMode(mode);
		algorithmDropdownOpen = false;
	}

	function handleClickOutside(event: MouseEvent) {
		if (boundaryDropdownOpen && boundaryDropdownRef && !boundaryDropdownRef.contains(event.target as Node)) {
			boundaryDropdownOpen = false;
		}
		if (paletteDropdownOpen && paletteDropdownRef && !paletteDropdownRef.contains(event.target as Node)) {
			paletteDropdownOpen = false;
		}
		if (algorithmDropdownOpen && algorithmDropdownRef && !algorithmDropdownRef.contains(event.target as Node)) {
			algorithmDropdownOpen = false;
		}
	}

	$effect(() => {
		if (boundaryDropdownOpen || paletteDropdownOpen || algorithmDropdownOpen) {
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
							title: `<div style="display: flex; align-items: center; gap: 10px;">
								<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" style="width: 28px; height: 28px;">
									<defs><linearGradient id="fg" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#22d3ee"/><stop offset="100%" stop-color="#a78bfa"/></linearGradient></defs>
									<rect width="32" height="32" rx="6" fill="#0a0a0f"/>
									<g fill="url(#fg)"><path d="M16 6 L20 14 L12 14 Z"/><path d="M8 14 L12 22 L4 22 Z" opacity="0.7"/><path d="M24 14 L28 22 L20 22 Z" opacity="0.7"/></g>
								</svg>
								<span>Welcome to Swarm</span>
							</div>`,
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
						element: '#section-boids',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<polygon points="12 2 19 21 12 17 5 21 12 2"/>
								</svg>
								<span>Boids</span>
							</div>`,
							description: `<p>Control the swarm population and appearance:</p>
								<ul>
									<li><strong>Population</strong> — Number of boids (WebGPU handles 50,000+!)</li>
									<li><strong>Size</strong> — Scale of each boid triangle</li>
									<li><strong>Trail</strong> — Length of the motion trail (up to 100)</li>
									<li><strong>Colorize</strong> — What property determines color</li>
									<li><strong>Palette</strong> — Chrome, Neon, Sunset, Rainbow, or Mono</li>
								</ul>
								<p><em>Try Neon palette for synthwave vibes!</em></p>`,
							side: 'left',
							align: 'start'
						},
						onHighlightStarted: () => { openSection = 'boids'; }
					},
					{
						element: '#section-world',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#22d3ee" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
								</svg>
								<span>World</span>
							</div>`,
							description: `<p>Define the simulation space and your interaction:</p>
								<ul>
									<li><strong>Bounds</strong> — Topology of the world (Plane has walls, Torus wraps around, Möbius flips!)</li>
									<li><strong>Interaction</strong> — Power toggles cursor, then Attract or Repel</li>
									<li><strong>Shape</strong> — Dot, Ring, Disk, or Vortex cursor styles</li>
									<li><strong>Size & Power</strong> — Control cursor influence area and strength</li>
								</ul>
								<p><em>Try Vortex cursor with Attract for mesmerizing spirals!</em></p>`,
							side: 'left',
							align: 'start'
						},
						onHighlightStarted: () => { openSection = 'world'; }
					},
					{
						element: '#section-flocking',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#fb7185" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>
								</svg>
								<span>Flocking</span>
							</div>`,
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
						},
						onHighlightStarted: () => { openSection = 'flocking'; }
					},
					{
						element: '#section-dynamics',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#fbbf24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>
								</svg>
								<span>Dynamics</span>
							</div>`,
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
						},
						onHighlightStarted: () => { openSection = 'dynamics'; }
					},
					{
						element: '#section-algorithm',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<rect x="4" y="4" width="16" height="16" rx="2" ry="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/>
								</svg>
								<span>Algorithm</span>
							</div>`,
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
						},
						onHighlightStarted: () => { openSection = 'algorithm'; }
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

	// Cursor toggle indicator position
	let cursorModeIndex = $derived(
		currentParams.cursorMode === CursorMode.Off ? 0 : 
		currentParams.cursorMode === CursorMode.Attract ? 1 : 2
	);
</script>

<!-- Gear button (always rendered, animated visibility) -->
<button
	onclick={togglePanel}
	class="gear-btn fixed right-4 top-4 z-40 flex h-9 w-9 items-center justify-center rounded-full text-zinc-400 transition-all hover:text-zinc-200"
	class:gear-hidden={isOpen}
	aria-label="Open Settings"
>
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4">
		<path fill-rule="evenodd" d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
	</svg>
</button>

{#if isOpen}
	<!-- Panel (open state) -->
	<div
		class="panel fixed right-4 top-4 z-40 w-64 rounded-xl"
		transition:scale={{ duration: 200, easing: cubicOut, start: 0.95, opacity: 0 }}
	>
		<!-- Header with logo and buttons -->
		<div class="flex items-center justify-between px-3 py-2.5">
			<div class="flex items-center gap-2">
				<img src="{base}/favicon.svg" alt="Swarm" class="h-5 w-5" />
				<span class="brand-title">Swarm</span>
			</div>
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
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
						<path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
					</svg>
				</button>
			</div>
		</div>

		<!-- Content -->
		<div class="content-scroll max-h-[calc(100vh-100px)] px-3 pb-3">
			<!-- Boids -->
			<div id="section-boids" class="mb-2">
				<button class="section-header" onclick={() => toggleSection('boids')}>
					<div class="section-title">
						<svg class="section-icon icon-purple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<polygon points="12 2 19 21 12 17 5 21 12 2"/>
						</svg>
						<span class="section-label">Boids</span>
					</div>
					<svg class="section-chevron" class:open={openSection === 'boids'} viewBox="0 0 20 20" fill="currentColor">
						<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
					</svg>
				</button>
				{#if openSection === 'boids'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Population</span>
							<input type="range" min="500" max="50000" step="500" value={currentParams.population}
								oninput={(e) => setPopulation(parseInt(e.currentTarget.value))} class="slider" aria-label="Population" />
							<span class="value">{(currentParams.population / 1000).toFixed(1)}k</span>
						</div>
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
				{/if}
			</div>

			<!-- World -->
			<div id="section-world" class="mb-2">
				<button class="section-header" onclick={() => toggleSection('world')}>
					<div class="section-title">
						<svg class="section-icon icon-cyan" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<circle cx="12" cy="12" r="10"/>
							<path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
						</svg>
						<span class="section-label">World</span>
					</div>
					<svg class="section-chevron" class:open={openSection === 'world'} viewBox="0 0 20 20" fill="currentColor">
						<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
					</svg>
				</button>
				{#if openSection === 'world'}
				<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
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
						<span class="label">Interaction</span>
						<!-- Premium segmented control with sliding indicator -->
						<div class="cursor-toggle">
							<!-- Sliding indicator -->
							<div class="cursor-toggle-indicator" style="transform: translateX({cursorModeIndex * 100}%)"></div>
							
							<button 
								class="cursor-toggle-btn power-btn"
								class:active={currentParams.cursorMode !== CursorMode.Off}
								onclick={() => setCursorMode(currentParams.cursorMode === CursorMode.Off ? CursorMode.Attract : CursorMode.Off)}
								aria-label="Toggle Cursor"
							>
								<svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round">
									<!-- Proper power icon -->
									<path d="M12 3 L12 11"/>
									<path d="M6.3 6.3 A8.5 8.5 0 1 0 17.7 6.3"/>
								</svg>
							</button>
							<button 
								class="cursor-toggle-btn attract"
								class:active={currentParams.cursorMode === CursorMode.Attract}
								onclick={() => setCursorMode(CursorMode.Attract)}
								aria-label="Attract"
							>
								<svg viewBox="0 0 24 24" class="h-5 w-5">
									<!-- 3 arrows pointing inward to center -->
									<g stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
										<!-- Top -->
										<path d="M12 1 L12 8 M9 5 L12 8 L15 5"/>
										<!-- Bottom-left -->
										<path d="M1.5 19.5 L7.5 13.5 M2 14.5 L7.5 13.5 L6.5 19"/>
										<!-- Bottom-right -->
										<path d="M22.5 19.5 L16.5 13.5 M22 14.5 L16.5 13.5 L17.5 19"/>
									</g>
									<!-- Center dot -->
									<circle cx="12" cy="12" r="2.5" fill="currentColor"/>
								</svg>
							</button>
							<button 
								class="cursor-toggle-btn repel"
								class:active={currentParams.cursorMode === CursorMode.Repel}
								onclick={() => setCursorMode(CursorMode.Repel)}
								aria-label="Repel"
							>
								<svg viewBox="0 0 24 24" class="h-5 w-5">
									<!-- 3 arrows pointing outward from center -->
									<g stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
										<!-- Top -->
										<path d="M12 8 L12 1 M9 4 L12 1 L15 4"/>
										<!-- Bottom-left -->
										<path d="M7.5 13.5 L1.5 19.5 M5 19.5 L1.5 19.5 L1.5 16"/>
										<!-- Bottom-right -->
										<path d="M16.5 13.5 L22.5 19.5 M19 19.5 L22.5 19.5 L22.5 16"/>
									</g>
									<!-- Center dot -->
									<circle cx="12" cy="12" r="2.5" fill="currentColor"/>
								</svg>
							</button>
						</div>
					</div>
					<div class="row">
						<span class="label">Shape</span>
						<div class="shape-toggle">
							<button class="shape-btn" class:active={currentParams.cursorShape === CursorShape.Dot}
								onclick={() => setCursorShape(CursorShape.Dot)} aria-label="Dot" title="Dot">
								<svg viewBox="0 0 24 24" class="h-5 w-5">
									<circle cx="12" cy="12" r="4" fill="currentColor" />
								</svg>
							</button>
							<button class="shape-btn" class:active={currentParams.cursorShape === CursorShape.Ring}
								onclick={() => setCursorShape(CursorShape.Ring)} aria-label="Ring" title="Ring">
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="h-5 w-5">
									<circle cx="12" cy="12" r="7" />
								</svg>
							</button>
							<button class="shape-btn" class:active={currentParams.cursorShape === CursorShape.Disk}
								onclick={() => setCursorShape(CursorShape.Disk)} aria-label="Disk" title="Disk">
								<svg viewBox="0 0 24 24" class="h-5 w-5">
									<circle cx="12" cy="12" r="7" fill="currentColor" opacity="0.4" />
									<circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="2" />
								</svg>
							</button>
							<button class="shape-btn" class:active={currentParams.cursorShape === CursorShape.Vortex}
								onclick={() => setCursorShape(CursorShape.Vortex)} aria-label="Vortex" title="Vortex">
								<!-- Lucide: refresh-cw -->
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-5 w-5">
									<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/>
									<path d="M21 3v5h-5"/>
									<path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/>
									<path d="M3 21v-5h5"/>
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
				{/if}
			</div>

			<!-- Flocking -->
			<div id="section-flocking" class="mb-2">
				<button class="section-header" onclick={() => toggleSection('flocking')}>
					<div class="section-title">
						<svg class="section-icon icon-rose" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
							<circle cx="9" cy="7" r="4"/>
							<path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>
						</svg>
						<span class="section-label">Flocking</span>
					</div>
					<svg class="section-chevron" class:open={openSection === 'flocking'} viewBox="0 0 20 20" fill="currentColor">
						<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
					</svg>
				</button>
				{#if openSection === 'flocking'}
				<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
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
				{/if}
			</div>

			<!-- Dynamics -->
			<div id="section-dynamics" class="mb-2">
				<button class="section-header" onclick={() => toggleSection('dynamics')}>
					<div class="section-title">
						<svg class="section-icon icon-amber" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>
						</svg>
						<span class="section-label">Dynamics</span>
					</div>
					<svg class="section-chevron" class:open={openSection === 'dynamics'} viewBox="0 0 20 20" fill="currentColor">
						<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
					</svg>
				</button>
				{#if openSection === 'dynamics'}
				<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
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
				{/if}
			</div>

			<!-- Algorithm -->
			<div id="section-algorithm" class="mb-2">
				<button class="section-header" onclick={() => toggleSection('algorithm')}>
					<div class="section-title">
						<svg class="section-icon icon-emerald" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
							<rect x="4" y="4" width="16" height="16" rx="2" ry="2"/>
							<rect x="9" y="9" width="6" height="6"/>
							<line x1="9" y1="1" x2="9" y2="4"/>
							<line x1="15" y1="1" x2="15" y2="4"/>
							<line x1="9" y1="20" x2="9" y2="23"/>
							<line x1="15" y1="20" x2="15" y2="23"/>
							<line x1="20" y1="9" x2="23" y2="9"/>
							<line x1="20" y1="14" x2="23" y2="14"/>
							<line x1="1" y1="9" x2="4" y2="9"/>
							<line x1="1" y1="14" x2="4" y2="14"/>
						</svg>
						<span class="section-label">Algorithm</span>
					</div>
					<svg class="section-chevron" class:open={openSection === 'algorithm'} viewBox="0 0 20 20" fill="currentColor">
						<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
					</svg>
				</button>
				{#if openSection === 'algorithm'}
				<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
					<div class="relative" bind:this={algorithmDropdownRef}>
						<button 
							class="sel w-full flex items-center gap-2 text-left"
							onclick={() => algorithmDropdownOpen = !algorithmDropdownOpen}
							aria-label="Algorithm"
							aria-expanded={algorithmDropdownOpen}
						>
							<span class="flex-1 truncate">{algorithmOptions.find(o => o.value === currentParams.algorithmMode)?.label}</span>
							<svg class="h-3 w-3 opacity-50 transition-transform" class:rotate-180={algorithmDropdownOpen} viewBox="0 0 20 20" fill="currentColor">
								<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
							</svg>
						</button>
						{#if algorithmDropdownOpen}
							<div 
								class="dropdown-menu dropdown-up absolute left-0 right-0 bottom-full z-50 mb-1 max-h-48 overflow-y-auto rounded-md"
								transition:slide={{ duration: 150, easing: cubicOut }}
							>
								{#each algorithmOptions as opt}
									<button
										class="dropdown-item w-full flex items-center gap-2 px-2 py-1.5 text-left text-[10px]"
										class:active={currentParams.algorithmMode === opt.value}
										onclick={() => selectAlgorithm(opt.value)}
									>
										<span>{opt.label}</span>
									</button>
								{/each}
							</div>
						{/if}
					</div>
				</div>
				{/if}
			</div>
		</div>
	</div>
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
		transition: opacity 0.2s ease, transform 0.2s ease;
	}
	.gear-btn:hover {
		background: rgba(16, 16, 20, 0.9);
		border-color: rgba(255, 255, 255, 0.12);
	}
	.gear-btn.gear-hidden {
		opacity: 0;
		pointer-events: none;
		transform: scale(0.8);
	}

	.brand-title {
		font-size: 11px;
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		background: linear-gradient(135deg, #a78bfa 0%, #22d3ee 50%, #fbbf24 100%);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
	}

	.section-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		width: 100%;
		padding: 8px 6px;
		margin: 0 -6px;
		background: rgba(255, 255, 255, 0.02);
		border: none;
		border-radius: 6px;
		cursor: pointer;
		transition: background 0.15s;
	}
	.section-header:hover {
		background: rgba(255, 255, 255, 0.05);
	}
	.section-title {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.section-icon {
		width: 14px;
		height: 14px;
		flex-shrink: 0;
		transition: color 0.15s;
	}
	.section-icon.icon-purple { color: #a78bfa; }
	.section-icon.icon-cyan { color: #22d3ee; }
	.section-icon.icon-rose { color: #fb7185; }
	.section-icon.icon-amber { color: #fbbf24; }
	.section-icon.icon-emerald { color: #34d399; }

	.section-label {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: rgb(161 161 170);
	}
	.section-chevron {
		width: 14px;
		height: 14px;
		color: rgb(113 113 122);
		transition: transform 0.2s ease;
		transform: rotate(-90deg);
	}
	.section-chevron.open {
		transform: rotate(0deg);
	}
	.section-content {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 8px 0 4px 0;
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

	/* Premium Cursor Toggle */
	.cursor-toggle {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		position: relative;
		height: 36px;
		background: rgba(0, 0, 0, 0.4);
		border-radius: 8px;
		padding: 3px;
		gap: 2px;
		border: 1px solid rgba(255, 255, 255, 0.06);
	}
	.cursor-toggle-indicator {
		position: absolute;
		top: 3px;
		left: 3px;
		width: calc(33.333% - 2px);
		height: calc(100% - 6px);
		background: rgba(255, 255, 255, 0.1);
		border-radius: 6px;
		transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
		pointer-events: none;
	}
	.cursor-toggle-btn {
		position: relative;
		z-index: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: none;
		border-radius: 5px;
		color: rgb(113 113 122);
		cursor: pointer;
		transition: color 0.15s;
	}
	.cursor-toggle-btn:hover {
		color: rgb(161 161 170);
	}
	.cursor-toggle-btn.active {
		color: rgb(228 228 231);
	}
	/* Power button - green when cursor is enabled */
	.cursor-toggle-btn.power-btn.active {
		color: rgb(74 222 128);
	}
	/* Attract button glow */
	.cursor-toggle-btn.attract.active {
		color: rgb(34 211 238);
	}
	.cursor-toggle:has(.cursor-toggle-btn.attract.active) .cursor-toggle-indicator {
		background: rgba(34, 211, 238, 0.15);
		box-shadow: 0 0 12px rgba(34, 211, 238, 0.2);
	}
	/* Repel button glow */
	.cursor-toggle-btn.repel.active {
		color: rgb(251 113 133);
	}
	.cursor-toggle:has(.cursor-toggle-btn.repel.active) .cursor-toggle-indicator {
		background: rgba(251, 113, 133, 0.15);
		box-shadow: 0 0 12px rgba(251, 113, 133, 0.2);
	}

	/* Shape Toggle - square buttons */
	.shape-toggle {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		height: 32px;
		background: rgba(0, 0, 0, 0.4);
		border-radius: 8px;
		padding: 3px;
		gap: 2px;
		border: 1px solid rgba(255, 255, 255, 0.06);
	}
	.shape-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: none;
		border-radius: 5px;
		color: rgb(113 113 122);
		cursor: pointer;
		transition: all 0.15s;
	}
	.shape-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgb(161 161 170);
	}
	.shape-btn.active {
		background: rgba(255, 255, 255, 0.12);
		color: rgb(228 228 231);
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
