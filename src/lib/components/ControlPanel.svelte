<script lang="ts">
	import { fade, scale, slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { onMount, onDestroy } from 'svelte';
	import { driver } from 'driver.js';
	import 'driver.js/dist/driver.css';
	import { base } from '$app/paths';
	import BoundaryIcon from './BoundaryIcon.svelte';
	import PaletteIcon from './PaletteIcon.svelte';
	import {
		params,
		isPanelOpen,
		isRunning,
		isRecording,
		canvasElement,
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
		setKNeighbors,
		setSampleCount,
		setIdealDensity,
		setTimeScale,
		setRecording,
		BoundaryMode,
		ColorMode,
		ColorSpectrum,
		CursorMode,
		CursorShape,
		AlgorithmMode
	} from '$lib/stores/simulation';

	let currentParams = $derived($params);
	let isOpen = $derived($isPanelOpen);
	let isPlaying = $derived($isRunning);
	let recording = $derived($isRecording);
	let canvas = $derived($canvasElement);
	
	let boundaryDropdownOpen = $state(false);
	let boundaryDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let paletteDropdownOpen = $state(false);
	let paletteDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let colorizeDropdownOpen = $state(false);
	let colorizeDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let algorithmDropdownOpen = $state(false);
	let algorithmDropdownRef = $state<HTMLDivElement | undefined>(undefined);

	// Recording state
	let mediaRecorder: MediaRecorder | null = null;
	let recordedChunks: Blob[] = [];

	// Toggle play/pause
	function togglePlayPause() {
		isRunning.update(v => !v);
	}

	// Check if we can use native share (mobile)
	function canUseNativeShare(): boolean {
		return typeof navigator !== 'undefined' && 
			   typeof navigator.share === 'function' && 
			   typeof navigator.canShare === 'function';
	}

	// Save file - uses Share API on mobile (saves to Photos), download on desktop
	async function saveFile(blob: Blob, filename: string, mimeType: string) {
		const file = new File([blob], filename, { type: mimeType });
		
		// Try native share on mobile (allows saving to Photos)
		if (canUseNativeShare() && navigator.canShare({ files: [file] })) {
			try {
				await navigator.share({
					files: [file],
					title: 'Swarm'
				});
				return; // Success
			} catch (err) {
				// User cancelled or share failed - fall back to download
				if ((err as Error).name === 'AbortError') return; // User cancelled, don't download
			}
		}
		
		// Fall back to standard download (desktop or if share unavailable)
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url;
		a.download = filename;
		document.body.appendChild(a);
		a.click();
		document.body.removeChild(a);
		URL.revokeObjectURL(url);
	}

	// Take screenshot
	function takeScreenshot() {
		if (!canvas) return;
		
		canvas.toBlob(async (blob) => {
			if (!blob) return;
			
			const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
			const filename = `swarm-${timestamp}.png`;
			
			await saveFile(blob, filename, 'image/png');
		}, 'image/png');
	}

	// Start/stop video recording
	function toggleVideoRecording() {
		if (recording) {
			stopRecording();
		} else {
			startRecording();
		}
	}

	function startRecording() {
		if (!canvas) return;
		
		try {
			// Get canvas stream at 60fps
			const stream = canvas.captureStream(60);
			
			// Try to use WebM with VP9, fallback to VP8, then any available codec
			const mimeTypes = [
				'video/webm;codecs=vp9',
				'video/webm;codecs=vp8',
				'video/webm',
				'video/mp4'
			];
			
			let selectedMimeType = '';
			for (const mimeType of mimeTypes) {
				if (MediaRecorder.isTypeSupported(mimeType)) {
					selectedMimeType = mimeType;
					break;
				}
			}
			
			if (!selectedMimeType) {
				alert('Video recording is not supported in this browser.');
				return;
			}
			
			recordedChunks = [];
			mediaRecorder = new MediaRecorder(stream, {
				mimeType: selectedMimeType,
				videoBitsPerSecond: 8000000 // 8 Mbps for good quality
			});
			
			mediaRecorder.ondataavailable = (event) => {
				if (event.data.size > 0) {
					recordedChunks.push(event.data);
				}
			};
			
			mediaRecorder.onstop = async () => {
				const blob = new Blob(recordedChunks, { type: selectedMimeType });
				const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
				const extension = selectedMimeType.includes('mp4') ? 'mp4' : 'webm';
				const filename = `swarm-${timestamp}.${extension}`;
				
				await saveFile(blob, filename, selectedMimeType);
				recordedChunks = [];
			};
			
			mediaRecorder.start(100); // Collect data every 100ms
			setRecording(true);
		} catch (err) {
			console.error('Failed to start recording:', err);
			alert('Failed to start recording. Please try again.');
		}
	}

	function stopRecording() {
		if (mediaRecorder && mediaRecorder.state !== 'inactive') {
			mediaRecorder.stop();
			setRecording(false);
			mediaRecorder = null;
		}
	}

	// Handle camera button click (video when playing, screenshot when paused)
	function handleCameraClick() {
		if (isPlaying) {
			toggleVideoRecording();
		} else {
			takeScreenshot();
		}
	}

	// Cleanup on destroy
	onDestroy(() => {
		if (mediaRecorder && mediaRecorder.state !== 'inactive') {
			mediaRecorder.stop();
		}
	});

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

	function selectColorize(mode: ColorMode) {
		setColorMode(mode);
		colorizeDropdownOpen = false;
	}

	function handleClickOutside(event: MouseEvent) {
		if (boundaryDropdownOpen && boundaryDropdownRef && !boundaryDropdownRef.contains(event.target as Node)) {
			boundaryDropdownOpen = false;
		}
		if (paletteDropdownOpen && paletteDropdownRef && !paletteDropdownRef.contains(event.target as Node)) {
			paletteDropdownOpen = false;
		}
		if (colorizeDropdownOpen && colorizeDropdownRef && !colorizeDropdownRef.contains(event.target as Node)) {
			colorizeDropdownOpen = false;
		}
		if (algorithmDropdownOpen && algorithmDropdownRef && !algorithmDropdownRef.contains(event.target as Node)) {
			algorithmDropdownOpen = false;
		}
	}

	$effect(() => {
		if (boundaryDropdownOpen || paletteDropdownOpen || colorizeDropdownOpen || algorithmDropdownOpen) {
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
						element: '#header-controls',
						popover: {
							title: `<div style="display: flex; align-items: center; gap: 8px;">
								<svg viewBox="0 0 24 24" fill="none" stroke="#22d3ee" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
									<rect x="2" y="2" width="20" height="20" rx="5" ry="5"/>
									<path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/>
									<line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/>
								</svg>
								<span>Controls</span>
							</div>`,
							description: `<p>Quick access to media and navigation:</p>
								<div style="display: grid; grid-template-columns: auto 1fr; gap: 8px 12px; margin: 12px 0;">
									<div style="display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; background: rgba(34, 211, 238, 0.15); border-radius: 6px;">
										<svg viewBox="0 0 20 20" fill="#22d3ee" style="width: 14px; height: 14px;">
											<path d="M5.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75A.75.75 0 007.25 3h-1.5zM12.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75a.75.75 0 00-.75-.75h-1.5z"/>
										</svg>
									</div>
									<div>
										<div style="font-weight: 600; font-size: 11px; color: #e4e4e7;">Play / Pause</div>
										<div style="font-size: 10px; color: #71717a;">Pause or resume the animation</div>
									</div>
									<div style="display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; background: rgba(167, 139, 250, 0.15); border-radius: 6px;">
										<svg viewBox="0 0 20 20" fill="#a78bfa" style="width: 14px; height: 14px;">
											<path fill-rule="evenodd" d="M1 5.25A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 00.75-.75v-2.69l-2.22-2.219a.75.75 0 00-1.06 0l-1.91 1.909-4.19-4.19a.75.75 0 00-1.06 0L1.5 11.06zm5.5-3.31a1.25 1.25 0 100-2.5 1.25 1.25 0 000 2.5z" clip-rule="evenodd"/>
										</svg>
									</div>
									<div>
										<div style="font-weight: 600; font-size: 11px; color: #e4e4e7;">Screenshot</div>
										<div style="font-size: 10px; color: #71717a;">Save the current view as PNG</div>
									</div>
									<div style="display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; background: rgba(251, 113, 133, 0.15); border-radius: 6px;">
										<svg viewBox="0 0 20 20" fill="#fb7185" style="width: 14px; height: 14px;">
											<path d="M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-1.956l2.842 1.895A.75.75 0 0017 13.057V6.943a.75.75 0 00-1.158-.632L13 8.206V6.25A2.25 2.25 0 0010.75 4h-7.5z"/>
										</svg>
									</div>
									<div>
										<div style="font-weight: 600; font-size: 11px; color: #e4e4e7;">Record / Photo</div>
										<div style="font-size: 10px; color: #71717a;">Record video (playing) or photo (paused)</div>
									</div>
									<div style="display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; background: rgba(251, 191, 36, 0.15); border-radius: 6px;">
										<svg viewBox="0 0 20 20" fill="#fbbf24" style="width: 14px; height: 14px;">
											<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"/>
										</svg>
									</div>
									<div>
										<div style="font-weight: 600; font-size: 11px; color: #e4e4e7;">Help Tour</div>
										<div style="font-size: 10px; color: #71717a;">Take this guided tour again</div>
									</div>
								</div>
								<p style="font-size: 10px; color: #52525b; margin-top: 8px;"><em>Tip: When recording and sidebar is closed, a red indicator shows recording status.</em></p>`,
							side: 'bottom',
							align: 'end'
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
									<li><strong>Time</strong> — Simulation speed (0.25× slow-mo to 2× fast-forward)</li>
								</ul>
								<p><em>Slow down time to observe flocking patterns in detail!</em></p>`,
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
		{ value: ColorMode.Density, label: 'Density' },
		{ value: ColorMode.Acceleration, label: 'Acceleration' },
		{ value: ColorMode.Turning, label: 'Turning' },
		{ value: ColorMode.None, label: 'None' }
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

<!-- Floating button (gear or recording indicator when closed) -->
<button
	onclick={togglePanel}
	class="gear-btn fixed right-4 top-4 z-40 flex h-9 w-9 items-center justify-center rounded-full transition-all"
	class:gear-hidden={isOpen}
	class:recording-btn={recording && !isOpen}
	aria-label={recording ? "Recording - Click to open panel" : "Open Settings"}
>
	{#if recording && !isOpen}
		<!-- Recording indicator (red pulsing dot) -->
		<div class="recording-dot"></div>
	{:else}
		<!-- Gear icon -->
		<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4 text-zinc-400 hover:text-zinc-200">
			<path fill-rule="evenodd" d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
		</svg>
	{/if}
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
			<div id="header-controls" class="flex items-center gap-0.5">
				<!-- Play/Pause Button -->
				<button
					onclick={togglePlayPause}
					class="header-btn btn-cyan"
					class:active={!isPlaying}
					aria-label={isPlaying ? "Pause" : "Play"}
					title={isPlaying ? "Pause animation" : "Play animation"}
				>
					{#if isPlaying}
						<!-- Pause icon -->
						<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
							<path d="M5.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75A.75.75 0 007.25 3h-1.5zM12.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75a.75.75 0 00-.75-.75h-1.5z" />
						</svg>
					{:else}
						<!-- Play icon -->
						<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
							<path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
						</svg>
					{/if}
				</button>

				<!-- Screenshot Button -->
				<button
					onclick={takeScreenshot}
					class="header-btn btn-purple"
					aria-label="Take Screenshot"
					title="Take screenshot"
				>
					<!-- Image/Photo icon -->
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
						<path fill-rule="evenodd" d="M1 5.25A2.25 2.25 0 013.25 3h13.5A2.25 2.25 0 0119 5.25v9.5A2.25 2.25 0 0116.75 17H3.25A2.25 2.25 0 011 14.75v-9.5zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 00.75-.75v-2.69l-2.22-2.219a.75.75 0 00-1.06 0l-1.91 1.909-4.19-4.19a.75.75 0 00-1.06 0L1.5 11.06zm5.5-3.31a1.25 1.25 0 100-2.5 1.25 1.25 0 000 2.5z" clip-rule="evenodd" />
					</svg>
				</button>

				<!-- Camera/Record Button -->
				<button
					onclick={handleCameraClick}
					class="header-btn btn-rose"
					class:recording={recording}
					aria-label={isPlaying ? (recording ? "Stop Recording" : "Start Recording") : "Take Screenshot"}
					title={isPlaying ? (recording ? "Stop recording" : "Record video") : "Take screenshot (paused)"}
				>
					{#if recording}
						<!-- Stop icon (square) -->
						<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
							<rect x="4" y="4" width="12" height="12" rx="1" />
						</svg>
					{:else if isPlaying}
						<!-- Video camera icon -->
						<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
							<path d="M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-1.956l2.842 1.895A.75.75 0 0017 13.057V6.943a.75.75 0 00-1.158-.632L13 8.206V6.25A2.25 2.25 0 0010.75 4h-7.5z" />
						</svg>
					{:else}
						<!-- Camera/photo icon (when paused) -->
						<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
							<path fill-rule="evenodd" d="M1 8a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 018.07 3h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0016.07 6H17a2 2 0 012 2v7a2 2 0 01-2 2H3a2 2 0 01-2-2V8zm9.5 3a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm1.5 0a3 3 0 11-6 0 3 3 0 016 0z" clip-rule="evenodd" />
						</svg>
					{/if}
				</button>

				<!-- Help Button -->
				<button
					onclick={startTour}
					class="header-btn btn-amber"
					aria-label="Start Tour"
					title="Take a tour"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
						<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
					</svg>
				</button>

				<!-- Close Button -->
				<button
					onclick={togglePanel}
					class="header-btn btn-neutral"
					aria-label="Close Settings"
					title="Close panel"
				>
					<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-3.5 w-3.5">
						<path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
					</svg>
				</button>
			</div>
		</div>

		<!-- Separator after header -->
		<div class="header-divider"></div>

		<!-- Content -->
		<div class="content-scroll max-h-[calc(100vh-100px)]">
			<!-- Boids -->
			<div id="section-boids">
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
							<input type="range" min="1" max="100" step="1" value={currentParams.trailLength}
								oninput={(e) => setTrailLength(parseInt(e.currentTarget.value))} class="slider" aria-label="Trail" />
							<span class="value">{currentParams.trailLength}</span>
						</div>
						<div class="row">
							<span class="label">Colorize</span>
							<div class="relative flex-1" bind:this={colorizeDropdownRef}>
								<button 
									class="sel w-full flex items-center gap-2 text-left"
									onclick={() => colorizeDropdownOpen = !colorizeDropdownOpen}
									aria-label="Colorize Mode"
									aria-expanded={colorizeDropdownOpen}
								>
								{#if currentParams.colorMode === ColorMode.None}
									<!-- Lucide: minus -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/></svg>
								{:else if currentParams.colorMode === ColorMode.Orientation}
									<!-- Lucide: compass -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76" fill="currentColor" stroke="none"/></svg>
								{:else if currentParams.colorMode === ColorMode.Speed}
									<!-- Lucide: gauge -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>
								{:else if currentParams.colorMode === ColorMode.Neighbors}
									<!-- Lucide: users -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
								{:else if currentParams.colorMode === ColorMode.Density}
									<!-- Lucide: grid-3x3 -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/><path d="M9 3v18"/><path d="M15 3v18"/></svg>
								{:else if currentParams.colorMode === ColorMode.Acceleration}
									<!-- Lucide: trending-up -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>
								{:else if currentParams.colorMode === ColorMode.Turning}
									<!-- Lucide: rotate-cw -->
									<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/></svg>
								{/if}
									<span class="flex-1 truncate">{colorOptions.find(o => o.value === currentParams.colorMode)?.label}</span>
									<svg class="h-3 w-3 opacity-50 transition-transform" class:rotate-180={colorizeDropdownOpen} viewBox="0 0 20 20" fill="currentColor">
										<path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
									</svg>
								</button>
							{#if colorizeDropdownOpen}
								<div 
									class="dropdown-menu absolute left-0 right-0 top-full z-50 mt-1 max-h-[140px] overflow-y-auto rounded-md"
									transition:slide={{ duration: 150, easing: cubicOut }}
								>
										{#each colorOptions as opt}
											<button
												class="dropdown-item w-full h-[28px] flex items-center gap-2 px-[10px] text-left text-[10px]"
												class:active={currentParams.colorMode === opt.value}
												onclick={() => selectColorize(opt.value)}
											>
											{#if opt.value === ColorMode.None}
												<!-- Lucide: minus -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/></svg>
											{:else if opt.value === ColorMode.Orientation}
												<!-- Lucide: compass -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76" fill="currentColor" stroke="none"/></svg>
											{:else if opt.value === ColorMode.Speed}
												<!-- Lucide: gauge -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>
											{:else if opt.value === ColorMode.Neighbors}
												<!-- Lucide: users -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
											{:else if opt.value === ColorMode.Density}
												<!-- Lucide: grid-3x3 -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/><path d="M9 3v18"/><path d="M15 3v18"/></svg>
											{:else if opt.value === ColorMode.Acceleration}
												<!-- Lucide: trending-up -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>
											{:else if opt.value === ColorMode.Turning}
												<!-- Lucide: rotate-cw -->
												<svg class="colorize-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/></svg>
											{/if}
												<span>{opt.label}</span>
											</button>
										{/each}
									</div>
								{/if}
							</div>
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
									<PaletteIcon spectrum={currentParams.colorSpectrum} size={18} />
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
												class="dropdown-item w-full flex items-center gap-2 px-3 py-2 text-left text-[10px]"
												class:active={currentParams.colorSpectrum === opt.value}
												onclick={() => selectPalette(opt.value)}
											>
												<PaletteIcon spectrum={opt.value} size={18} />
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

			<div class="section-divider"></div>
			<!-- World -->
			<div id="section-world">
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
								<BoundaryIcon mode={currentParams.boundaryMode} size={18} />
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
											class="dropdown-item w-full flex items-center gap-2 px-3 py-2 text-left text-[10px]"
											class:active={currentParams.boundaryMode === opt.value}
											onclick={() => selectBoundary(opt.value)}
										>
											<BoundaryIcon mode={opt.value} size={18} />
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
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-4 w-4">
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

			<div class="section-divider"></div>
			<!-- Flocking -->
			<div id="section-flocking">
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

			<div class="section-divider"></div>
			<!-- Dynamics -->
			<div id="section-dynamics">
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
					<div class="row">
						<span class="label">Time</span>
						<input type="range" min="0.25" max="2" step="0.05" value={currentParams.timeScale}
							oninput={(e) => setTimeScale(parseFloat(e.currentTarget.value))} class="slider" aria-label="Time Scale" />
						<span class="value">{currentParams.timeScale.toFixed(2)}×</span>
					</div>
				</div>
			{/if}
		</div>

		<div class="section-divider"></div>
		<!-- Algorithm -->
			<div id="section-algorithm">
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
					<div class="row">
						<span class="label">Mode</span>
						<div class="relative flex-1" bind:this={algorithmDropdownRef}>
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
											class="dropdown-item w-full flex items-center gap-2 px-3 py-2 text-left text-[10px]"
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
					
					<!-- Algorithm-specific parameters -->
					{#if currentParams.algorithmMode === AlgorithmMode.TopologicalKNN}
						<div class="row">
							<span class="label">Neighbors</span>
							<input type="range" min="4" max="24" step="1" value={currentParams.kNeighbors}
								oninput={(e) => setKNeighbors(parseInt(e.currentTarget.value))} class="slider" aria-label="Neighbors" />
							<span class="value">{currentParams.kNeighbors}</span>
						</div>
					{:else if currentParams.algorithmMode === AlgorithmMode.StochasticSample}
						<div class="row">
							<span class="label">Samples</span>
							<input type="range" min="8" max="64" step="4" value={currentParams.sampleCount}
								oninput={(e) => setSampleCount(parseInt(e.currentTarget.value))} class="slider" aria-label="Sample Count" />
							<span class="value">{currentParams.sampleCount}</span>
						</div>
					{:else if currentParams.algorithmMode === AlgorithmMode.DensityAdaptive}
						<div class="row">
							<span class="label">Density</span>
							<input type="range" min="1" max="10" step="0.5" value={currentParams.idealDensity}
								oninput={(e) => setIdealDensity(parseFloat(e.currentTarget.value))} class="slider" aria-label="Ideal Density" />
							<span class="value">{currentParams.idealDensity.toFixed(1)}</span>
						</div>
					{/if}
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
		padding: 0 12px 4px 12px;
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

	.gear-btn.recording-btn {
		background: rgba(220, 38, 38, 0.9);
		border-color: rgba(255, 100, 100, 0.3);
		box-shadow: 
			0 0 20px rgba(220, 38, 38, 0.5),
			0 2px 12px rgba(0, 0, 0, 0.4);
	}
	.gear-btn.recording-btn:hover {
		background: rgba(185, 28, 28, 0.95);
	}

	.recording-dot {
		width: 12px;
		height: 12px;
		background: #fff;
		border-radius: 50%;
		animation: recording-pulse 1.5s ease-in-out infinite;
	}

	@keyframes recording-pulse {
		0%, 100% { opacity: 1; transform: scale(1); }
		50% { opacity: 0.6; transform: scale(0.85); }
	}

	.header-btn {
		display: flex;
		width: 24px;
		height: 24px;
		align-items: center;
		justify-content: center;
		border-radius: 6px;
		transition: all 0.15s ease;
	}
	.header-btn:hover {
		background: rgba(255, 255, 255, 0.1);
	}

	/* Colored button variants */
	.header-btn.btn-cyan {
		color: rgba(34, 211, 238, 0.7);
	}
	.header-btn.btn-cyan:hover {
		color: #22d3ee;
		background: rgba(34, 211, 238, 0.15);
	}
	.header-btn.btn-cyan.active {
		color: #22d3ee;
		background: rgba(34, 211, 238, 0.2);
	}

	.header-btn.btn-purple {
		color: rgba(167, 139, 250, 0.7);
	}
	.header-btn.btn-purple:hover {
		color: #a78bfa;
		background: rgba(167, 139, 250, 0.15);
	}

	.header-btn.btn-rose {
		color: rgba(251, 113, 133, 0.7);
	}
	.header-btn.btn-rose:hover {
		color: #fb7185;
		background: rgba(251, 113, 133, 0.15);
	}
	.header-btn.btn-rose.recording {
		color: #ef4444;
		background: rgba(239, 68, 68, 0.2);
		animation: recording-glow 1.5s ease-in-out infinite;
	}

	.header-btn.btn-amber {
		color: rgba(251, 191, 36, 0.7);
	}
	.header-btn.btn-amber:hover {
		color: #fbbf24;
		background: rgba(251, 191, 36, 0.15);
	}

	.header-btn.btn-neutral {
		color: rgb(113 113 122);
	}
	.header-btn.btn-neutral:hover {
		color: rgb(212 212 216);
		background: rgba(255, 255, 255, 0.1);
	}

	@keyframes recording-glow {
		0%, 100% { color: #ef4444; }
		50% { color: #fca5a5; }
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

	/* Section separators - subtle full-width lines between sections */
	.header-divider {
		height: 1px;
		background: rgba(255, 255, 255, 0.06);
		margin: 0; /* No negative margin - already at panel edges */
	}
	.section-divider {
		height: 1px;
		background: rgba(255, 255, 255, 0.06);
		margin: 0 -12px; /* Extend to panel edges within padded container */
	}

	.section-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		width: calc(100% + 24px);
		margin-left: -12px;
		padding: 8px 12px;
		background: transparent;
		border: none;
		border-radius: 0;
		cursor: pointer;
		transition: background 0.15s;
	}
	.section-header:hover {
		background: rgba(255, 255, 255, 0.03);
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
		gap: 4px;
		padding: 4px 0 4px 0;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 6px 0;
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
		height: 4px;
		cursor: pointer;
		appearance: none;
		border-radius: 2px;
		background: linear-gradient(to right, rgba(161, 161, 170, 0.25), rgba(113, 113, 122, 0.15));
	}
	.slider::-webkit-slider-thumb {
		width: 16px;
		height: 16px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(8 8 12);
		border: 1px solid rgba(212, 212, 216, 0.8);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
		transition: transform 0.1s, border-color 0.1s, box-shadow 0.1s;
	}
	.slider::-webkit-slider-thumb:hover {
		transform: scale(1.1);
		border-color: rgba(255, 255, 255, 0.9);
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.5);
	}
	.slider::-webkit-slider-thumb:active {
		transform: scale(1.15);
		border-color: rgb(255 255 255);
	}
	.slider::-moz-range-thumb {
		width: 16px;
		height: 16px;
		cursor: pointer;
		appearance: none;
		border-radius: 50%;
		background: rgb(8 8 12);
		border: 1px solid rgba(212, 212, 216, 0.8);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
	}
	.slider::-moz-range-thumb:active {
		border-color: rgb(255 255 255);
	}

	.sel {
		height: 28px;
		cursor: pointer;
		appearance: none;
		border-radius: 5px;
		border: 1px solid rgba(255, 255, 255, 0.08);
		background: rgba(255, 255, 255, 0.05);
		padding: 0 10px;
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

	.colorize-icon {
		width: 18px;
		height: 18px;
		flex-shrink: 0;
		color: rgb(161 161 170);
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
