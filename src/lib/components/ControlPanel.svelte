<script lang="ts">
	import { scale, slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { onMount, onDestroy } from 'svelte';
	import { driver } from 'driver.js';
	import 'driver.js/dist/driver.css';
	import { base } from '$app/paths';
	import PaletteIcon from './PaletteIcon.svelte';
	import TopologySelector from './TopologySelector.svelte';
	import SpeciesSelector from './SpeciesSelector.svelte';
	import InteractionsPanel from './InteractionsPanel.svelte';
	import ForceAnimation from './ForceAnimation.svelte';
	import { TOPOLOGY_NAMES } from '$lib/utils/topologyMeshes';
	import { HeadShape } from '$lib/webgpu/types';
	import {
		params,
		isPanelOpen,
		isRunning,
		isRecording,
		canvasElement,
		needsSimulationReset,
		wallTool,
		setAlignment,
		setCohesion,
		setSeparation,
		setPerception,
		setMaxSpeed,
		setMaxForce,
		setNoise,
		setBoundaryMode,
		setCursorShape,
		setCursorRadius,
		setColorMode,
		setColorSpectrum,
		setPopulation,
		setAlgorithmMode,
		setKNeighbors,
		setSampleCount,
		setIdealDensity,
		setTimeScale,
		setRecording,
		setWallTool,
		setWallBrushSize,
		setWallBrushShape,
		clearWalls,
		setSpeciesPopulation,
		updateSpeciesFlocking,
		getActiveSpecies,
		setSpeciesHue,
		setSpeciesColor,
		setSpeciesSize,
		setSpeciesTrailLength,
		setSpeciesRebels,
		setSpeciesCursorForce,
		setSpeciesCursorResponse,
		setSpeciesCursorVortex,
		cycleSpeciesCursorVortex,
		setSpeciesAlphaMode,
		setActiveSpecies,
		CursorResponse,
		VortexDirection,
		BoundaryMode,
		ColorMode,
		ColorSpectrum,
		CursorMode,
		CursorShape,
		AlgorithmMode,
		AlphaMode,
		WallTool,
		WallBrushShape,
		DEFAULT_PARAMS
	} from '$lib/stores/simulation';

	let currentParams = $derived($params);
	let activeSpecies = $derived(getActiveSpecies($params));
	let isOpen = $derived($isPanelOpen);
	let isPlaying = $derived($isRunning);
	let recording = $derived($isRecording);
	let canvas = $derived($canvasElement);
	let currentWallTool = $derived($wallTool);

	// Helper function to generate SVG path for boid shape (for quick species selector)
	function getQuickBoidPath(shape: HeadShape, cx: number, cy: number, size: number): string {
		const s = size;
		// Generate polygon points for n-sided polygon
		const polygon = (n: number): string => {
			const points: string[] = [];
			for (let i = 0; i < n; i++) {
				const angle = (i * 2 * Math.PI) / n - Math.PI / 2; // Start from top
				const x = cx + s * Math.cos(angle);
				const y = cy + s * Math.sin(angle);
				points.push(`${x} ${y}`);
			}
			return `M ${points.join(' L ')} Z`;
		};

		switch (shape) {
			case HeadShape.Triangle:
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
			case HeadShape.Square:
				return `M ${cx + s} ${cy} L ${cx} ${cy + s} L ${cx - s} ${cy} L ${cx} ${cy - s} Z`;
			case HeadShape.Pentagon:
				return polygon(5);
			case HeadShape.Hexagon:
				return polygon(6);
			case HeadShape.Arrow:
				return `M ${cx + s} ${cy} L ${cx - s * 0.5} ${cy + s * 0.6} L ${cx - s * 0.2} ${cy} L ${cx - s * 0.5} ${cy - s * 0.6} Z`;
			default:
				return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
		}
	}

	let paletteDropdownOpen = $state(false);
	let paletteDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let colorizeDropdownOpen = $state(false);
	let colorizeDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let algorithmDropdownOpen = $state(false);
	let algorithmDropdownRef = $state<HTMLDivElement | undefined>(undefined);
	let colorPickerOpen = $state(false);
	let colorPickerRef = $state<HTMLDivElement | undefined>(undefined);
	let alphaDropdownOpen = $state(false);
	let alphaDropdownRef = $state<HTMLDivElement | undefined>(undefined);

	// Population preview (for live display while dragging slider)
	let populationPreview = $state<number | null>(null);

	// Remember last cursor response for toggle behavior (default to Repel)
	let lastCursorResponse = $state<typeof CursorResponse.Attract | typeof CursorResponse.Repel>(
		CursorResponse.Repel
	);

	// Remember last vortex state for restoring
	let lastVortexState = $state<VortexDirection>(VortexDirection.Off);

	// Handle cursor mode toggle with memory - controls per-species cursorResponse
	function handleCursorModeToggle(
		mode: typeof CursorMode.Off | typeof CursorMode.Attract | typeof CursorMode.Repel
	) {
		if (!activeSpecies) return;

		// Current species response
		const currentResponse = activeSpecies.cursorResponse ?? CursorResponse.Repel;

		if (mode === CursorMode.Off) {
			// Power button: toggle interaction on/off for this species
			const speciesVortex = activeSpecies.cursorVortex ?? VortexDirection.Off;
			const hasVortex = speciesVortex !== VortexDirection.Off;
			const isActive = currentResponse !== CursorResponse.Ignore || hasVortex;
			if (isActive) {
				// Turn off, but remember state
				if (currentResponse !== CursorResponse.Ignore) {
					lastCursorResponse = currentResponse as
						| typeof CursorResponse.Attract
						| typeof CursorResponse.Repel;
				}
				lastVortexState = speciesVortex;
				setSpeciesCursorResponse(activeSpecies.id, CursorResponse.Ignore);
				setSpeciesCursorVortex(activeSpecies.id, VortexDirection.Off);
			} else {
				// Restore previous state
				setSpeciesCursorResponse(activeSpecies.id, lastCursorResponse);
				setSpeciesCursorVortex(activeSpecies.id, lastVortexState);
			}
		} else {
			// Attract/Repel button: toggle self off, or switch to this mode
			const targetResponse =
				mode === CursorMode.Attract ? CursorResponse.Attract : CursorResponse.Repel;

			if (currentResponse === targetResponse) {
				// Same mode clicked: turn off (but remember this mode)
				lastCursorResponse = targetResponse;
				setSpeciesCursorResponse(activeSpecies.id, CursorResponse.Ignore);
			} else {
				// Different mode: switch to it
				lastCursorResponse = targetResponse;
				setSpeciesCursorResponse(activeSpecies.id, targetResponse);
			}
		}
	}

	// Recording state
	let mediaRecorder: MediaRecorder | null = null;
	let recordedChunks: Blob[] = [];

	// Toggle play/pause
	function togglePlayPause() {
		isRunning.update((v) => !v);
	}

	// Check if we can use native share (mobile)
	function canUseNativeShare(): boolean {
		return (
			typeof navigator !== 'undefined' &&
			typeof navigator.share === 'function' &&
			typeof navigator.canShare === 'function'
		);
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
			// Prioritize MP4 for better mobile compatibility (especially iOS)
			// Safari supports MP4, Chrome/Firefox support WebM
			const mimeTypes = [
				'video/mp4;codecs=avc1',
				'video/mp4',
				'video/webm;codecs=vp9',
				'video/webm;codecs=vp8',
				'video/webm'
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
				videoBitsPerSecond: 16000000 // 16 Mbps for high quality colors
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
	let openSection = $state<
		'boids' | 'world' | 'interaction' | 'species' | 'flocking' | 'dynamics' | 'algorithm'
	>('boids');

	function toggleSection(section: typeof openSection) {
		openSection = openSection === section ? section : section; // Always open clicked section
	}

	// Section tour step indices (for jumping to specific cards)
	// Order: Welcome(0), Controls(1), Boids(2), Interaction(3), Species(4), Flocking(5), World(6), Dynamics(7), Algorithm(8)
	const sectionTourSteps: Record<typeof openSection, number> = {
		boids: 2,
		interaction: 3,
		species: 4,
		flocking: 5,
		world: 6,
		dynamics: 7,
		algorithm: 8
	};

	// Start tour at a specific section
	function startTourAtSection(section: typeof openSection): void {
		if (!$isPanelOpen) {
			isPanelOpen.set(true);
		}
		setTimeout(() => {
			startTourAtStep(sectionTourSteps[section]);
		}, 100);
	}

	// Reset functions for each section
	function resetBoidsSection(e: Event): void {
		e.stopPropagation();
		if (activeSpecies) {
			setSpeciesSize(activeSpecies.id, 1.5);
			setSpeciesTrailLength(activeSpecies.id, 30);
			setSpeciesRebels(activeSpecies.id, 0.02);
		}
		setColorMode(DEFAULT_PARAMS.colorMode);
		setColorSpectrum(DEFAULT_PARAMS.colorSpectrum);
	}

	function resetWorldSection(e: Event): void {
		e.stopPropagation();
		setBoundaryMode(DEFAULT_PARAMS.boundaryMode);
		// Reset wall tools
		setWallTool(WallTool.None);
		setWallBrushSize(DEFAULT_PARAMS.wallBrushSize);
		setWallBrushShape(DEFAULT_PARAMS.wallBrushShape);
	}

	function resetInteractionSection(e: Event): void {
		e.stopPropagation();
		setCursorShape(DEFAULT_PARAMS.cursorShape);
		setCursorRadius(DEFAULT_PARAMS.cursorRadius);
		// Reset per-species cursor settings
		if (activeSpecies) {
			setSpeciesCursorForce(activeSpecies.id, 0.5);
			setSpeciesCursorResponse(activeSpecies.id, CursorResponse.Repel);
			setSpeciesCursorVortex(activeSpecies.id, VortexDirection.Off);
		}
	}

	function resetFlockingSection(e: Event): void {
		e.stopPropagation();
		setAlignment(DEFAULT_PARAMS.alignment);
		setCohesion(DEFAULT_PARAMS.cohesion);
		setSeparation(DEFAULT_PARAMS.separation);
		setPerception(DEFAULT_PARAMS.perception);
	}

	function resetDynamicsSection(e: Event): void {
		e.stopPropagation();
		setMaxSpeed(DEFAULT_PARAMS.maxSpeed);
		setMaxForce(DEFAULT_PARAMS.maxForce);
		setNoise(DEFAULT_PARAMS.noise);
		setTimeScale(DEFAULT_PARAMS.timeScale);
	}

	function resetAlgorithmSection(e: Event): void {
		e.stopPropagation();
		setAlgorithmMode(DEFAULT_PARAMS.algorithmMode);
		setKNeighbors(DEFAULT_PARAMS.kNeighbors);
		setSampleCount(DEFAULT_PARAMS.sampleCount);
		setIdealDensity(DEFAULT_PARAMS.idealDensity);
	}

	// Keyboard handler for accessible span buttons
	function handleKeydown(e: KeyboardEvent, action: (e: Event) => void): void {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			action(e);
		}
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
		if (
			paletteDropdownOpen &&
			paletteDropdownRef &&
			!paletteDropdownRef.contains(event.target as Node)
		) {
			paletteDropdownOpen = false;
		}
		if (
			colorizeDropdownOpen &&
			colorizeDropdownRef &&
			!colorizeDropdownRef.contains(event.target as Node)
		) {
			colorizeDropdownOpen = false;
		}
		if (
			algorithmDropdownOpen &&
			algorithmDropdownRef &&
			!algorithmDropdownRef.contains(event.target as Node)
		) {
			algorithmDropdownOpen = false;
		}
		if (colorPickerOpen && colorPickerRef && !colorPickerRef.contains(event.target as Node)) {
			colorPickerOpen = false;
		}
		if (alphaDropdownOpen && alphaDropdownRef && !alphaDropdownRef.contains(event.target as Node)) {
			alphaDropdownOpen = false;
		}
	}

	$effect(() => {
		if (
			paletteDropdownOpen ||
			colorizeDropdownOpen ||
			algorithmDropdownOpen ||
			colorPickerOpen ||
			alphaDropdownOpen
		) {
			document.addEventListener('click', handleClickOutside);
			return () => document.removeEventListener('click', handleClickOutside);
		}
	});

	function togglePanel(): void {
		isPanelOpen.update((v) => !v);
	}

	// Keyboard shortcuts
	function handleKeyboard(event: KeyboardEvent) {
		// Ignore if user is typing in an input field
		if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) {
			return;
		}

		// Blur any focused element to prevent ugly focus outlines when using shortcuts
		if (document.activeElement instanceof HTMLElement && document.activeElement !== document.body) {
			document.activeElement.blur();
		}

		// Get current values for cycling
		const boundaryModes = [
			BoundaryMode.Plane,
			BoundaryMode.Torus,
			BoundaryMode.CylinderX,
			BoundaryMode.MobiusX,
			BoundaryMode.KleinX,
			BoundaryMode.ProjectivePlane
		];
		const colorModes = [
			ColorMode.None,
			ColorMode.Orientation,
			ColorMode.Speed,
			ColorMode.Neighbors,
			ColorMode.Density,
			ColorMode.Acceleration,
			ColorMode.Turning,
			ColorMode.Species
		];
		const algorithmModes = [
			AlgorithmMode.TopologicalKNN,
			AlgorithmMode.SmoothMetric,
			AlgorithmMode.HashFree,
			AlgorithmMode.StochasticSample,
			AlgorithmMode.DensityAdaptive
		];
		const colorSpectrums = [
			ColorSpectrum.Rainbow,
			ColorSpectrum.Ocean,
			ColorSpectrum.Chrome,
			ColorSpectrum.Bands,
			ColorSpectrum.Mono
		];
		const cursorShapes = [CursorShape.Ring, CursorShape.Disk];

		switch (event.key.toLowerCase()) {
			// Playback controls
			case ' ':
				event.preventDefault();
				togglePlayPause();
				break;

			case 's':
				if (!event.ctrlKey && !event.metaKey) {
					event.preventDefault();
					takeScreenshot();
				}
				break;

			case 'v':
				event.preventDefault();
				toggleVideoRecording();
				break;

			case 'r':
				event.preventDefault();
				needsSimulationReset.set(true);
				break;

			// UI controls
			case 'escape':
				if (recording) {
					stopRecording();
				} else if (isOpen) {
					isPanelOpen.set(false);
				}
				break;

			case 'tab':
				if (!event.shiftKey) {
					event.preventDefault();
					togglePanel();
				}
				break;

			case 'h':
			case '?':
				event.preventDefault();
				startTour();
				break;

			// Cursor interaction modes (1-3)
			case '1':
				event.preventDefault();
				handleCursorModeToggle(CursorMode.Off);
				break;

			case '2':
				event.preventDefault();
				handleCursorModeToggle(CursorMode.Attract);
				break;

			case '3':
				event.preventDefault();
				handleCursorModeToggle(CursorMode.Repel);
				break;

			case '4':
				event.preventDefault();
				if (activeSpecies) {
					cycleSpeciesCursorVortex(activeSpecies.id);
				}
				break;

			// Wall drawing tools (5-8)
			case '5':
				event.preventDefault();
				setWallTool(currentWallTool === WallTool.None ? WallTool.Pencil : WallTool.None);
				break;

			case '6':
				event.preventDefault();
				setWallTool(WallTool.Pencil);
				break;

			case '7':
				event.preventDefault();
				setWallTool(WallTool.Eraser);
				break;

			case '8':
				event.preventDefault();
				clearWalls();
				break;

			// Cycle through options
			case 'b': {
				event.preventDefault();
				const currentBoundary = currentParams?.boundaryMode ?? BoundaryMode.Plane;
				const boundaryIndex = boundaryModes.indexOf(currentBoundary);
				const nextBoundary = boundaryModes[(boundaryIndex + 1) % boundaryModes.length];
				setBoundaryMode(nextBoundary);
				break;
			}

			case 'c': {
				event.preventDefault();
				const currentColor = currentParams?.colorMode ?? ColorMode.Orientation;
				const colorIndex = colorModes.indexOf(currentColor);
				const nextColor = colorModes[(colorIndex + 1) % colorModes.length];
				setColorMode(nextColor);
				break;
			}

			case 'a': {
				event.preventDefault();
				const currentAlgo = currentParams?.algorithmMode ?? AlgorithmMode.SmoothMetric;
				const algoIndex = algorithmModes.indexOf(currentAlgo);
				const nextAlgo = algorithmModes[(algoIndex + 1) % algorithmModes.length];
				setAlgorithmMode(nextAlgo);
				break;
			}

			case 'p': {
				event.preventDefault();
				const currentPalette = currentParams?.colorSpectrum ?? ColorSpectrum.Rainbow;
				const paletteIndex = colorSpectrums.indexOf(currentPalette);
				const nextPalette = colorSpectrums[(paletteIndex + 1) % colorSpectrums.length];
				setColorSpectrum(nextPalette);
				break;
			}

			case 't': {
				event.preventDefault();
				const currentShape = currentParams?.cursorShape ?? CursorShape.Disk;
				const shapeIndex = cursorShapes.indexOf(currentShape);
				const nextShape = cursorShapes[(shapeIndex + 1) % cursorShapes.length];
				setCursorShape(nextShape);
				break;
			}

			// Cycle through species
			case 'n': {
				event.preventDefault();
				if (currentParams && currentParams.species.length > 1) {
					const currentIndex = currentParams.species.findIndex(
						(s) => s.id === currentParams.activeSpeciesId
					);
					const nextIndex = (currentIndex + 1) % currentParams.species.length;
					setActiveSpecies(currentParams.species[nextIndex].id);
				}
				break;
			}

			// Flocking parameters: Q/W for Align, E/D for Cohesion, Z/X for Separate
			// Left key = decrease, Right key = increase (matches keyboard layout)
			case 'q':
				event.preventDefault();
				if (currentParams) {
					const newAlign = Math.max(currentParams.alignment - 0.1, 0);
					setAlignment(newAlign);
				}
				break;

			case 'w':
				event.preventDefault();
				if (currentParams) {
					const newAlign = Math.min(currentParams.alignment + 0.1, 2);
					setAlignment(newAlign);
				}
				break;

			case 'e':
				event.preventDefault();
				if (currentParams) {
					const newCohesion = Math.max(currentParams.cohesion - 0.1, 0);
					setCohesion(newCohesion);
				}
				break;

			case 'd':
				event.preventDefault();
				if (currentParams) {
					const newCohesion = Math.min(currentParams.cohesion + 0.1, 2);
					setCohesion(newCohesion);
				}
				break;

			case 'z':
				event.preventDefault();
				if (currentParams) {
					const newSep = Math.max(currentParams.separation - 0.1, 0);
					setSeparation(newSep);
				}
				break;

			case 'x':
				event.preventDefault();
				if (currentParams) {
					const newSep = Math.min(currentParams.separation + 0.1, 2);
					setSeparation(newSep);
				}
				break;

			// Adjustments with +/- and [/]
			case '=':
			case '+':
				event.preventDefault();
				if (currentParams) {
					const newPop = Math.min(currentParams.population + 1000, 50000);
					setPopulation(newPop);
				}
				break;

			case '-':
				event.preventDefault();
				if (currentParams) {
					const newPop = Math.max(currentParams.population - 1000, 100);
					setPopulation(newPop);
				}
				break;

			case ']':
				event.preventDefault();
				if (activeSpecies) {
					const newTrail = Math.min((activeSpecies.trailLength ?? 30) + 10, 100);
					setSpeciesTrailLength(activeSpecies.id, newTrail);
				}
				break;

			case '[':
				event.preventDefault();
				if (activeSpecies) {
					const newTrail = Math.max((activeSpecies.trailLength ?? 30) - 10, 1);
					setSpeciesTrailLength(activeSpecies.id, newTrail);
				}
				break;

			// Arrow keys for fine adjustments when sidebar is closed
			case 'arrowup':
				if (!isOpen) {
					event.preventDefault();
					if (currentParams) {
						const newSpeed = Math.min(currentParams.maxSpeed + 0.5, 10);
						setMaxSpeed(newSpeed);
					}
				}
				break;

			case 'arrowdown':
				if (!isOpen) {
					event.preventDefault();
					if (currentParams) {
						const newSpeed = Math.max(currentParams.maxSpeed - 0.5, 0.5);
						setMaxSpeed(newSpeed);
					}
				}
				break;

			case 'arrowleft':
				if (!isOpen) {
					event.preventDefault();
					if (activeSpecies) {
						const newSize = Math.max((activeSpecies.size ?? 1.5) - 0.5, 0.2);
						setSpeciesSize(activeSpecies.id, newSize);
					}
				}
				break;

			case 'arrowright':
				if (!isOpen) {
					event.preventDefault();
					if (activeSpecies) {
						const newSize = Math.min((activeSpecies.size ?? 1.5) + 0.5, 3);
						setSpeciesSize(activeSpecies.id, newSize);
					}
				}
				break;
		}
	}

	onMount(() => {
		window.addEventListener('keydown', handleKeyboard);
		return () => window.removeEventListener('keydown', handleKeyboard);
	});

	// Detect if device is touch-only (mobile/tablet without keyboard)
	function isTouchDevice(): boolean {
		if (typeof window === 'undefined') return false;
		return (
			('ontouchstart' in window || navigator.maxTouchPoints > 0) &&
			!window.matchMedia('(pointer: fine)').matches
		);
	}

	// Helper to create keyboard shortcut badges (only on desktop)
	function kbd(keys: string, isTouch: boolean): string {
		if (isTouch) return '';
		return keys
			.split(' ')
			.map(
				(k) =>
					`<kbd style="background:#27272a;padding:1px 4px;border-radius:3px;font-size:10px;margin-left:4px;">${k}</kbd>`
			)
			.join('');
	}

	// Driver.js tour configuration
	function startTour(): void {
		startTourAtStep(0);
	}

	function startTourAtStep(startStep: number): void {
		// Ensure panel is open before starting tour
		if (!$isPanelOpen) {
			isPanelOpen.set(true);
		}

		// Small delay to let panel animate open
		setTimeout(() => {
			const isTouch = isTouchDevice();

			// Build tour steps dynamically based on device type
			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			const tourSteps: any[] = [
				// Step 0: Welcome
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
										<polygon points="12,38 8,32 16,32" fill="#22d3ee" transform="rotate(-45, 12, 35)"/>
										<polygon points="30,32 26,26 34,26" fill="#22d3ee" transform="rotate(-45, 30, 29)"/>
										<polygon points="48,26 44,20 52,20" fill="#22d3ee" transform="rotate(-45, 48, 23)"/>
									</svg>
									<div style="font-size: 10px; font-weight: 600; color: #22d3ee;">ALIGNMENT</div>
									<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Match neighbors' direction</div>
								</div>
								<div style="flex: 1; background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; text-align: center;">
									<svg viewBox="0 0 60 50" style="width: 100%; height: 40px; margin-bottom: 6px;">
										<circle cx="30" cy="25" r="4" fill="#a78bfa" opacity="0.3"/>
										<circle cx="30" cy="25" r="12" stroke="#a78bfa" stroke-width="1" fill="none" stroke-dasharray="3 2" opacity="0.4"/>
										<polygon points="12,12 8,18 16,18" fill="#a78bfa" transform="rotate(135, 12, 15)"/>
										<line x1="15" y1="18" x2="24" y2="23" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 2" opacity="0.5"/>
										<polygon points="48,12 44,18 52,18" fill="#a78bfa" transform="rotate(-135, 48, 15)"/>
										<line x1="45" y1="18" x2="36" y2="23" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 2" opacity="0.5"/>
										<polygon points="30,44 26,38 34,38" fill="#a78bfa" transform="rotate(180, 30, 41)"/>
										<line x1="30" y1="38" x2="30" y2="30" stroke="#a78bfa" stroke-width="1" stroke-dasharray="2 2" opacity="0.5"/>
									</svg>
									<div style="font-size: 10px; font-weight: 600; color: #a78bfa;">COHESION</div>
									<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Move toward group center</div>
								</div>
								<div style="flex: 1; background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; text-align: center;">
									<svg viewBox="0 0 60 50" style="width: 100%; height: 40px; margin-bottom: 6px;">
										<polygon points="30,25 26,31 34,31" fill="#fb7185"/>
										<polygon points="14,14 10,20 18,20" fill="#fb7185" transform="rotate(-45, 14, 17)"/>
										<line x1="18" y1="20" x2="24" y2="24" stroke="#fb7185" stroke-width="1.5" opacity="0.4"/>
										<polygon points="46,14 42,20 50,20" fill="#fb7185" transform="rotate(45, 46, 17)"/>
										<line x1="42" y1="20" x2="36" y2="24" stroke="#fb7185" stroke-width="1.5" opacity="0.4"/>
										<polygon points="30,44 26,38 34,38" fill="#fb7185" transform="rotate(0, 30, 41)"/>
										<line x1="30" y1="38" x2="30" y2="33" stroke="#fb7185" stroke-width="1.5" opacity="0.4"/>
									</svg>
									<div style="font-size: 10px; font-weight: 600; color: #fb7185;">SEPARATION</div>
									<div style="font-size: 9px; color: #71717a; margin-top: 2px;">Avoid crowding neighbors</div>
								</div>
							</div>
							<p style="font-size: 11px; color: #71717a; text-align: center; margin-bottom: 8px;">These simple rules create complex, lifelike swarm behavior!</p>
							<a href="https://en.wikipedia.org/wiki/Boids" target="_blank" rel="noopener noreferrer" style="display: flex; align-items: center; justify-content: center; gap: 4px; font-size: 10px; color: #a78bfa; text-decoration: none; opacity: 0.8; transition: opacity 0.2s; margin-bottom: 10px;" onmouseover="this.style.opacity='1'" onmouseout="this.style.opacity='0.8'">
								<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
									<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
									<polyline points="15 3 21 3 21 9"/>
									<line x1="10" y1="14" x2="21" y2="3"/>
								</svg>
								Learn more on Wikipedia
							</a>
							<p style="font-size: 10px; color: #52525b; text-align: center; margin: 0;">
								<span style="color: #22d3ee;">WebGPU</span>-powered simulation · Scales to 50,000+ boids
							</p>
							<p style="font-size: 9px; color: #3f3f46; text-align: center; margin-top: 6px;">
								Developed by Neo Mohsenvand
							</p>
						`,
						side: 'over',
						align: 'center'
					}
				},
				// Step 1: Controls
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
							<div style="display: flex; flex-direction: column; gap: 4px; margin-top: 8px;">
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 20 20" fill="#22d3ee" style="width: 14px; height: 14px; flex-shrink: 0;">
										<path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z"/>
									</svg>
									<span><strong>Play/Pause</strong> — Pause or resume${kbd('Space', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 14px; height: 14px; flex-shrink: 0;">
										<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>
									</svg>
									<span><strong>Reset</strong> — Reinitialize boids${kbd('R', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 20 20" fill="#fb7185" style="width: 14px; height: 14px; flex-shrink: 0;">
										<path d="M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-1.956l2.842 1.895A.75.75 0 0017 13.057V6.943a.75.75 0 00-1.158-.632L13 8.206V6.25A2.25 2.25 0 0010.75 4h-7.5z"/>
									</svg>
									<span><strong>Record</strong> — Capture video${kbd('V', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 20 20" fill="#fb7185" style="width: 14px; height: 14px; flex-shrink: 0;">
										<path fill-rule="evenodd" d="M1 8a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 018.07 3h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0016.07 6H17a2 2 0 012 2v7a2 2 0 01-2 2H3a2 2 0 01-2-2V8zm9.5 3a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm1.5 0a3 3 0 11-6 0 3 3 0 016 0z" clip-rule="evenodd"/>
									</svg>
									<span><strong>Photo</strong> — Take screenshot${kbd('S', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 20 20" fill="#fbbf24" style="width: 14px; height: 14px; flex-shrink: 0;">
										<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"/>
									</svg>
									<span><strong>Help</strong> — This tour${kbd('H', isTouch)}</span>
								</div>
							</div>`,
						side: 'bottom',
						align: 'end'
					}
				},
				// Step 2: Boids
				{
					element: '#section-boids',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<polygon points="12 2 19 21 12 17 5 21 12 2"/>
							</svg>
							<span>Boids</span>
						</div>`,
						description: `<p>Control the swarm appearance (per-species):</p>
							<ul>
								<li><strong>Population</strong> — Number of boids${kbd('+ -', isTouch)}</li>
								<li><strong>Size</strong> — Scale of each boid${kbd('← →', isTouch)}</li>
								<li><strong>Trail</strong> — Motion trail length${kbd('[ ]', isTouch)}</li>
								<li><strong>Rebels</strong> — Boids ignoring rules</li>
								<li><strong>Colorize</strong> — Color property${kbd('C', isTouch)}</li>
								<li><strong>Palette/Color</strong> — Color spectrum${kbd('P', isTouch)}</li>
							</ul>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'boids';
					}
				},
				// Step 3: Interaction (cursor only, walls moved to World)
				{
					element: '#section-interaction',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#f87171" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<path d="M15 4V2"/><path d="M15 16v-2"/><path d="M8 9h2"/><path d="M20 9h2"/>
								<path d="M17.8 11.8L19 13"/><path d="M15 9h0"/><path d="M17.8 6.2L19 5"/>
								<path d="M3 21l9-9"/><path d="M12.2 6.2L11 5"/>
							</svg>
							<span>Interaction</span>
						</div>`,
						description: `<p><strong style="color: #e4e4e7;">Cursor Force</strong> — ${isTouch ? 'Touch' : 'Move cursor over'} canvas (per-species):</p>
							<div style="display: flex; flex-direction: column; gap: 4px; margin-top: 6px;">
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 24 24" style="width: 15px; height: 15px; flex-shrink: 0;">
										<g stroke="#22d3ee" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
											<path d="M12 1 L12 8 M9 5 L12 8 L15 5"/>
											<path d="M1.5 19.5 L7.5 13.5 M2 14.5 L7.5 13.5 L6.5 19"/>
											<path d="M22.5 19.5 L16.5 13.5 M22 14.5 L16.5 13.5 L17.5 19"/>
										</g>
										<circle cx="12" cy="12" r="2.5" fill="#22d3ee"/>
									</svg>
									<span><strong>Attract</strong> — Pull boids${kbd('2', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 24 24" style="width: 15px; height: 15px; flex-shrink: 0;">
										<g stroke="#fb7185" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
											<path d="M12 8 L12 1 M9 4 L12 1 L15 4"/>
											<path d="M7.5 13.5 L1.5 19.5 M5 19.5 L1.5 19.5 L1.5 16"/>
											<path d="M16.5 13.5 L22.5 19.5 M19 19.5 L22.5 19.5 L22.5 16"/>
										</g>
										<circle cx="12" cy="12" r="2.5" fill="#fb7185"/>
									</svg>
									<span><strong>Repel</strong> — Push boids${kbd('3', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 8px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#f97316" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 15px; height: 15px; flex-shrink: 0;">
										<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/>
										<path d="M21 3v5h-5"/>
										<path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/>
										<path d="M3 21v-5h5"/>
									</svg>
									<span><strong>Vortex</strong> — Spin${kbd('4', isTouch)}</span>
								</div>
							</div>
							<p style="margin-top: 8px; font-size: 11px; color: #71717a;">${isTouch ? 'Press and hold' : 'Click'} canvas to boost force! Each species can respond differently.</p>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'interaction';
					}
				},
				// Step 4: Species (NEW)
				{
					element: '#section-species',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#818cf8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<circle cx="12" cy="12" r="3"/>
								<path d="M12 2v4m0 12v4M2 12h4m12 0h4"/>
								<path d="m4.93 4.93 2.83 2.83m8.48 8.48 2.83 2.83m0-14.14-2.83 2.83m-8.48 8.48-2.83 2.83"/>
							</svg>
							<span>Species</span>
						</div>`,
						description: `<p>Create multiple swarms with unique behaviors:${kbd('N', isTouch)}</p>
							<ul>
								<li><strong>Add/Remove</strong> — Manage up to 7 species</li>
								<li><strong>Quick Select</strong> — Click icons in header</li>
								<li><strong>Interactions</strong> — Define how species interact:</li>
							</ul>
							<div style="display: flex; flex-direction: column; gap: 3px; margin-top: 4px; font-size: 11px;">
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#71717a" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><circle cx="12" cy="12" r="9"/><path d="m9 9 6 6m0-6-6 6"/></svg>
									<span><strong>Ignore</strong> — No interaction</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#f87171" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="M12 8 L12 1 M9 4 L12 1 L15 4"/><path d="M7.5 13.5 L1.5 19.5"/><path d="M16.5 13.5 L22.5 19.5"/></svg>
									<span><strong>Avoid</strong> — Flee from others</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#fb923c" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><circle cx="12" cy="12" r="3" fill="#fb923c"/><path d="M12 1v5M12 18v5M23 12h-5M6 12H1"/></svg>
									<span><strong>Pursue</strong> — Chase/hunt others</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#22d3ee" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="M12 1 L12 8 M9 5 L12 8 L15 5"/><path d="M1.5 19.5 L7.5 13.5"/><path d="M22.5 19.5 L16.5 13.5"/></svg>
									<span><strong>Attract</strong> — Gentle attraction</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="M4 12h4m8 0h4"/><path d="M8 8h8v8H8z"/></svg>
									<span><strong>Mirror</strong> — Match velocity</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#f97316" stroke-width="2" stroke-linecap="round" style="width: 12px; height: 12px; flex-shrink: 0;"><circle cx="12" cy="12" r="8" stroke-dasharray="4 3"/><circle cx="12" cy="12" r="2" fill="#f97316"/></svg>
									<span><strong>Orbit</strong> — Circle around</span>
								</div>
							</div>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'species';
					}
				},
				// Step 5: Flocking
				{
					element: '#section-flocking',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#fb7185" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>
							</svg>
							<span>Flocking</span>
						</div>`,
						description: `<p>The three classic boid rules (per-species):</p>
							<ul>
								<li><strong>Align</strong> — Match neighbors' heading${kbd('Q− W+', isTouch)}</li>
								<li><strong>Cohesion</strong> — Move toward group center${kbd('E− D+', isTouch)}</li>
								<li><strong>Separate</strong> — Avoid crowding${kbd('Z− X+', isTouch)}</li>
								<li><strong>Range</strong> — Perception distance</li>
							</ul>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'flocking';
					}
				},
				// Step 6: World (topology + walls)
				{
					element: '#section-world',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
							</svg>
							<span>World</span>
						</div>`,
						description: `<p><strong style="color: #e4e4e7;">Topology</strong> — 9 topologies in a 3×3 grid:${kbd('B', isTouch)}</p>
							<div style="display: flex; flex-direction: column; gap: 3px; margin: 6px 0; font-size: 11px;">
								<div><strong>Bounce</strong> — Reflect off edges</div>
								<div><strong>Wrap</strong> — Teleport to opposite side</div>
								<div><strong>Flip</strong> — Wrap + mirror direction</div>
							</div>
							<p style="margin-top: 8px;"><strong style="color: #e4e4e7;">Walls</strong> — Draw obstacles:</p>
							<div style="display: flex; flex-direction: column; gap: 3px; margin-top: 4px; font-size: 11px;">
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg>
									<span><strong>Pencil</strong> — Draw walls${kbd('6', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21"/><path d="M22 21H7"/></svg>
									<span><strong>Eraser</strong> — Remove walls${kbd('7', isTouch)}</span>
								</div>
								<div style="display: flex; align-items: center; gap: 6px;">
									<svg viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 12px; height: 12px; flex-shrink: 0;"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
									<span><strong>Clear</strong> — Delete all${kbd('8', isTouch)}</span>
								</div>
							</div>
							<p style="margin-top: 6px; font-size: 10px; color: #71717a;">Toggle draw mode${kbd('5', isTouch)}</p>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'world';
					}
				},
				// Step 7: Dynamics
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
								<li><strong>Speed</strong> — Maximum velocity${kbd('↑ ↓', isTouch)}</li>
								<li><strong>Force</strong> — Turning agility</li>
								<li><strong>Noise</strong> — Random perturbation</li>
								<li><strong>Time</strong> — Simulation speed</li>
							</ul>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'dynamics';
					}
				},
				// Step 8: Algorithm
				{
					element: '#section-algorithm',
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#34d399" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<rect x="4" y="4" width="16" height="16" rx="2" ry="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/>
							</svg>
							<span>Algorithm</span>
						</div>`,
						description: `<p>Choose the neighbor detection algorithm${kbd('A', isTouch)}</p>
							<ul>
								<li><strong>Smooth Metric</strong> — Smooth kernel weighting</li>
								<li><strong>Topological k-NN</strong> — Fixed k neighbors</li>
								<li><strong>Hash-Free</strong> — No grid artifacts</li>
								<li><strong>Stochastic</strong> — Random sampling</li>
								<li><strong>Density Adaptive</strong> — Crowding-aware</li>
							</ul>`,
						side: 'left',
						align: 'start'
					},
					onHighlightStarted: () => {
						openSection = 'algorithm';
					}
				}
			];

			// Only add keyboard shortcuts card on desktop
			if (!isTouch) {
				tourSteps.push({
					popover: {
						title: `<div style="display: flex; align-items: center; gap: 8px;">
							<svg viewBox="0 0 24 24" fill="none" stroke="#f472b6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width: 18px; height: 18px;">
								<rect x="2" y="4" width="20" height="16" rx="2" ry="2"/>
								<path d="M6 8h.001"/><path d="M10 8h.001"/><path d="M14 8h.001"/><path d="M18 8h.001"/>
								<path d="M8 12h.001"/><path d="M12 12h.001"/><path d="M16 12h.001"/>
								<path d="M7 16h10"/>
							</svg>
							<span>Keyboard Shortcuts</span>
						</div>`,
						description: `
							<p style="margin-bottom: 8px; color: #a1a1aa; font-size: 11px;">All keyboard shortcuts:</p>
							<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 5px; font-size: 9px;">
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #f87171; margin-bottom: 2px; font-size: 10px;">Force</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">1</kbd> Toggle On/Off</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">2</kbd> Attract</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">3</kbd> Repel</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">4</kbd> Vortex</div>
								</div>
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #94a3b8; margin-bottom: 2px; font-size: 10px;">Walls</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">5</kbd> Toggle Draw</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">6</kbd> Pencil</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">7</kbd> Eraser</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">8</kbd> Clear All</div>
								</div>
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #fb7185; margin-bottom: 2px; font-size: 10px;">Flocking</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">Q</kbd>−<kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">W</kbd>+ Align</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">E</kbd>−<kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">D</kbd>+ Cohesion</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">Z</kbd>−<kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">X</kbd>+ Separation</div>
								</div>
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #f472b6; margin-bottom: 2px; font-size: 10px;">Playback</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">Space</kbd> Play/Pause</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">S</kbd> Screenshot</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">V</kbd> Record Video</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">R</kbd> Reset Boids</div>
								</div>
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #a78bfa; margin-bottom: 2px; font-size: 10px;">Cycle Options</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">N</kbd> Species</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">B</kbd> Boundary</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">C</kbd> Color Mode</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">P</kbd> Palette</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">A</kbd> Algorithm</div>
								</div>
								<div style="background: rgba(255,255,255,0.05); padding: 5px; border-radius: 5px;">
									<div style="font-weight: 600; color: #fbbf24; margin-bottom: 2px; font-size: 10px;">Adjustments</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">−</kbd><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">+</kbd> Population</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">[</kbd><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">]</kbd> Trail Length</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">↑</kbd><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">↓</kbd> Speed</div>
									<div><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">←</kbd><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">→</kbd> Boid Size</div>
								</div>
							</div>
							<p style="margin-top: 6px; color: #71717a; font-size: 9px; text-align: center;"><kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">Tab</kbd> Sidebar · <kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">H</kbd> Help · <kbd style="background:#27272a;padding:1px 3px;border-radius:2px;">Esc</kbd> Close</p>
						`,
						side: 'left',
						align: 'center'
					}
				});
			}

			const driverObj = driver({
				showProgress: true,
				animate: true,
				smoothScroll: true,
				allowClose: true,
				overlayColor: 'rgba(0, 0, 0, 0.85)',
				stagePadding: 0,
				stageRadius: 6,
				popoverClass: 'tour-popover',
				popoverOffset: 12,
				onPopoverRender: (popover, { state }) => {
					// On the first step, replace the disabled Previous button with GitHub link
					if (state.activeIndex === 0) {
						const prevBtn = popover.previousButton;
						const footer = popover.footer;
						if (prevBtn && footer) {
							// Create GitHub link button
							const githubLink = document.createElement('a');
							githubLink.href = 'https://github.com/NeoVand/swarm';
							githubLink.target = '_blank';
							githubLink.rel = 'noopener noreferrer';
							githubLink.className = 'driver-popover-prev-btn';
							githubLink.style.cssText =
								'display: flex; align-items: center; justify-content: center; padding: 8px !important; text-decoration: none;';
							githubLink.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>`;
							githubLink.title = 'Star on GitHub';

							// On desktop, also add keyboard shortcuts jump button
							if (!isTouch) {
								const keyboardBtn = document.createElement('button');
								keyboardBtn.className = 'driver-popover-prev-btn';
								keyboardBtn.style.cssText =
									'display: flex; align-items: center; justify-content: center; padding: 8px !important; cursor: pointer; border: none;';
								keyboardBtn.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2" ry="2"/><path d="M6 8h.001"/><path d="M10 8h.001"/><path d="M14 8h.001"/><path d="M18 8h.001"/><path d="M8 12h.001"/><path d="M12 12h.001"/><path d="M16 12h.001"/><path d="M7 16h10"/></svg>`;
								keyboardBtn.title = 'View Keyboard Shortcuts';
								keyboardBtn.onclick = () => {
									driverObj.moveTo(tourSteps.length - 1); // Jump to last card (keyboard shortcuts)
								};

								const btnContainer = document.createElement('div');
								btnContainer.style.cssText = 'display: flex; gap: 6px;';
								btnContainer.appendChild(githubLink);
								btnContainer.appendChild(keyboardBtn);
								prevBtn.replaceWith(btnContainer);
							} else {
								prevBtn.replaceWith(githubLink);
							}
						}
					}
				},
				steps: tourSteps
			});

			driverObj.drive(startStep);
		}, 250);
	}

	const colorOptions = [
		{ value: ColorMode.Orientation, label: 'Direction' },
		{ value: ColorMode.Speed, label: 'Speed' },
		{ value: ColorMode.Species, label: 'Species' },
		{ value: ColorMode.Neighbors, label: 'Neighbors' },
		{ value: ColorMode.Density, label: 'Position' },
		{ value: ColorMode.Acceleration, label: 'Acceleration' },
		{ value: ColorMode.Turning, label: 'Turning' },
		{ value: ColorMode.None, label: 'None' }
	];

	const spectrumOptions = [
		{ value: ColorSpectrum.Chrome, label: 'Chrome' },
		{ value: ColorSpectrum.Ocean, label: 'Ocean' },
		{ value: ColorSpectrum.Bands, label: 'Bands' },
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

	const alphaModeOptions = [
		{ value: AlphaMode.Solid, label: 'Solid' },
		{ value: AlphaMode.Direction, label: 'Direction' },
		{ value: AlphaMode.Speed, label: 'Speed' },
		{ value: AlphaMode.Turning, label: 'Turning' },
		{ value: AlphaMode.Acceleration, label: 'Acceleration' }
	];

	// Cursor toggle indicator position - based on per-species cursorResponse
	let cursorModeIndex = $derived(
		activeSpecies?.cursorResponse === CursorResponse.Ignore
			? 0
			: activeSpecies?.cursorResponse === CursorResponse.Attract
				? 1
				: 2
	);
</script>

<!-- Floating button (gear or recording indicator when closed) -->
<button
	onclick={togglePanel}
	class="gear-btn fixed top-4 right-4 z-40 flex h-9 w-9 items-center justify-center rounded-full transition-all"
	class:gear-hidden={isOpen}
	class:recording-btn={recording && !isOpen}
	aria-label={recording ? 'Recording - Click to open panel' : 'Open Settings'}
>
	{#if recording && !isOpen}
		<!-- Recording indicator (red pulsing dot) -->
		<div class="recording-dot"></div>
	{:else}
		<!-- Gear icon -->
		<svg
			xmlns="http://www.w3.org/2000/svg"
			viewBox="0 0 20 20"
			fill="currentColor"
			class="h-4 w-4 text-zinc-400 hover:text-zinc-200"
		>
			<path
				fill-rule="evenodd"
				d="M7.84 1.804A1 1 0 018.82 1h2.36a1 1 0 01.98.804l.331 1.652a6.993 6.993 0 011.929 1.115l1.598-.54a1 1 0 011.186.447l1.18 2.044a1 1 0 01-.205 1.251l-1.267 1.113a7.047 7.047 0 010 2.228l1.267 1.113a1 1 0 01.206 1.25l-1.18 2.045a1 1 0 01-1.187.447l-1.598-.54a6.993 6.993 0 01-1.929 1.115l-.33 1.652a1 1 0 01-.98.804H8.82a1 1 0 01-.98-.804l-.331-1.652a6.993 6.993 0 01-1.929-1.115l-1.598.54a1 1 0 01-1.186-.447l-1.18-2.044a1 1 0 01.205-1.251l1.267-1.114a7.05 7.05 0 010-2.227L1.821 7.773a1 1 0 01-.206-1.25l1.18-2.045a1 1 0 011.187-.447l1.598.54A6.993 6.993 0 017.51 3.456l.33-1.652zM10 13a3 3 0 100-6 3 3 0 000 6z"
				clip-rule="evenodd"
			/>
		</svg>
	{/if}
</button>

{#if isOpen}
	<!-- Panel (open state) -->
	<div
		class="panel fixed top-4 right-4 z-40 w-64 rounded-xl"
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
					aria-label={isPlaying ? 'Pause' : 'Play'}
					title={isPlaying ? 'Pause animation' : 'Play animation'}
				>
					{#if isPlaying}
						<!-- Pause icon -->
						<svg
							xmlns="http://www.w3.org/2000/svg"
							viewBox="0 0 20 20"
							fill="currentColor"
							class="h-3.5 w-3.5"
						>
							<path
								d="M5.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75A.75.75 0 007.25 3h-1.5zM12.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75a.75.75 0 00-.75-.75h-1.5z"
							/>
						</svg>
					{:else}
						<!-- Play icon -->
						<svg
							xmlns="http://www.w3.org/2000/svg"
							viewBox="0 0 20 20"
							fill="currentColor"
							class="h-3.5 w-3.5"
						>
							<path
								d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z"
							/>
						</svg>
					{/if}
				</button>

				<!-- Reset Button -->
				<button
					onclick={() => needsSimulationReset.set(true)}
					class="header-btn btn-purple"
					aria-label="Reset Simulation"
					title="Reset boid positions"
				>
					<!-- Refresh/Reset icon (Lucide: rotate-ccw) -->
					<svg
						xmlns="http://www.w3.org/2000/svg"
						viewBox="0 0 24 24"
						fill="none"
						stroke="currentColor"
						stroke-width="2"
						stroke-linecap="round"
						stroke-linejoin="round"
						class="h-3.5 w-3.5"
					>
						<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
						<path d="M3 3v5h5" />
					</svg>
				</button>

				<!-- Camera/Record Button -->
				<button
					onclick={handleCameraClick}
					class="header-btn btn-rose"
					class:recording
					aria-label={isPlaying
						? recording
							? 'Stop Recording'
							: 'Start Recording'
						: 'Take Screenshot'}
					title={isPlaying
						? recording
							? 'Stop recording'
							: 'Record video'
						: 'Take screenshot (paused)'}
				>
					{#if recording}
						<!-- Stop icon (square) -->
						<svg
							xmlns="http://www.w3.org/2000/svg"
							viewBox="0 0 20 20"
							fill="currentColor"
							class="h-3.5 w-3.5"
						>
							<rect x="4" y="4" width="12" height="12" rx="1" />
						</svg>
					{:else if isPlaying}
						<!-- Video camera icon -->
						<svg
							xmlns="http://www.w3.org/2000/svg"
							viewBox="0 0 20 20"
							fill="currentColor"
							class="h-3.5 w-3.5"
						>
							<path
								d="M3.25 4A2.25 2.25 0 001 6.25v7.5A2.25 2.25 0 003.25 16h7.5A2.25 2.25 0 0013 13.75v-1.956l2.842 1.895A.75.75 0 0017 13.057V6.943a.75.75 0 00-1.158-.632L13 8.206V6.25A2.25 2.25 0 0010.75 4h-7.5z"
							/>
						</svg>
					{:else}
						<!-- Camera/photo icon (when paused) -->
						<svg
							xmlns="http://www.w3.org/2000/svg"
							viewBox="0 0 20 20"
							fill="currentColor"
							class="h-3.5 w-3.5"
						>
							<path
								fill-rule="evenodd"
								d="M1 8a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 018.07 3h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0016.07 6H17a2 2 0 012 2v7a2 2 0 01-2 2H3a2 2 0 01-2-2V8zm9.5 3a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zm1.5 0a3 3 0 11-6 0 3 3 0 016 0z"
								clip-rule="evenodd"
							/>
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
					<svg
						xmlns="http://www.w3.org/2000/svg"
						viewBox="0 0 20 20"
						fill="currentColor"
						class="h-3.5 w-3.5"
					>
						<path
							fill-rule="evenodd"
							d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
							clip-rule="evenodd"
						/>
					</svg>
				</button>

				<!-- Close Button -->
				<button
					onclick={togglePanel}
					class="header-btn btn-neutral"
					aria-label="Close Settings"
					title="Close panel"
				>
					<svg
						xmlns="http://www.w3.org/2000/svg"
						viewBox="0 0 20 20"
						fill="currentColor"
						class="h-3.5 w-3.5"
					>
						<path
							fill-rule="evenodd"
							d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
							clip-rule="evenodd"
						/>
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
						<svg
							class="section-icon icon-purple"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<polygon points="12 2 19 21 12 17 5 21 12 2" />
						</svg>
						<span class="section-label">Boids</span>
					</div>
					<div class="section-actions">
						{#if openSection === 'boids'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('boids');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('boids'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetBoidsSection}
								onkeydown={(e) => handleKeydown(e, resetBoidsSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'boids'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'boids'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Population</span>
							<input
								type="range"
								min="100"
								max="20000"
								step="100"
								value={activeSpecies?.population ?? 7000}
								oninput={(e) => (populationPreview = parseInt(e.currentTarget.value))}
								onchange={(e) => {
									if (activeSpecies) {
										setSpeciesPopulation(activeSpecies.id, parseInt(e.currentTarget.value));
									}
									populationPreview = null;
								}}
								class="slider"
								aria-label="Population"
							/>
							<span class="value"
								>{((populationPreview ?? activeSpecies?.population ?? 7000) / 1000).toFixed(
									1
								)}k</span
							>
						</div>
						<div class="row">
							<span class="label">Size</span>
							<input
								type="range"
								min="0.2"
								max="3"
								step="0.1"
								value={activeSpecies?.size ?? 1.5}
								oninput={(e) =>
									activeSpecies &&
									setSpeciesSize(activeSpecies.id, parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Boid Size"
							/>
							<span class="value">{(activeSpecies?.size ?? 1.5).toFixed(1)}</span>
						</div>
						<div class="row">
							<span class="label">Trail</span>
							<input
								type="range"
								min="1"
								max="100"
								step="1"
								value={activeSpecies?.trailLength ?? 30}
								oninput={(e) =>
									activeSpecies &&
									setSpeciesTrailLength(activeSpecies.id, parseInt(e.currentTarget.value))}
								class="slider"
								aria-label="Trail"
							/>
							<span class="value">{activeSpecies?.trailLength ?? 30}</span>
						</div>
						<div class="row">
							<span class="label">Colorize</span>
							<div class="relative flex-1" bind:this={colorizeDropdownRef}>
								<button
									class="sel flex w-full items-center gap-2 text-left"
									onclick={() => (colorizeDropdownOpen = !colorizeDropdownOpen)}
									aria-label="Colorize Mode"
									aria-expanded={colorizeDropdownOpen}
								>
									{#if currentParams.colorMode === ColorMode.None}
										<!-- Lucide: minus -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12" /></svg
										>
									{:else if currentParams.colorMode === ColorMode.Orientation}
										<!-- Lucide: compass -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><circle cx="12" cy="12" r="10" /><polygon
												points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"
												fill="currentColor"
												stroke="none"
											/></svg
										>
									{:else if currentParams.colorMode === ColorMode.Speed}
										<!-- Lucide: gauge -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><path d="m12 14 4-4" /><path d="M3.34 19a10 10 0 1 1 17.32 0" /></svg
										>
									{:else if currentParams.colorMode === ColorMode.Neighbors}
										<!-- Lucide: users -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle
												cx="9"
												cy="7"
												r="4"
											/><path d="M22 21v-2a4 4 0 0 0-3-3.87" /><path
												d="M16 3.13a4 4 0 0 1 0 7.75"
											/></svg
										>
									{:else if currentParams.colorMode === ColorMode.Density}
										<!-- Lucide: grid-3x3 -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><rect width="18" height="18" x="3" y="3" rx="2" /><path d="M3 9h18" /><path
												d="M3 15h18"
											/><path d="M9 3v18" /><path d="M15 3v18" /></svg
										>
									{:else if currentParams.colorMode === ColorMode.Acceleration}
										<!-- Lucide: trending-up -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><polyline points="22 7 13.5 15.5 8.5 10.5 2 17" /><polyline
												points="16 7 22 7 22 13"
											/></svg
										>
									{:else if currentParams.colorMode === ColorMode.Turning}
										<!-- Lucide: rotate-cw -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8" /><path
												d="M21 3v5h-5"
											/></svg
										>
									{:else if currentParams.colorMode === ColorMode.Species}
										<!-- Lucide: shapes (species) -->
										<svg
											class="colorize-icon"
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											stroke-linecap="round"
											stroke-linejoin="round"
											><path
												d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z"
											/><rect x="3" y="14" width="7" height="7" rx="1" /><circle
												cx="17.5"
												cy="17.5"
												r="3.5"
											/></svg
										>
									{/if}
									<span class="flex-1 truncate"
										>{colorOptions.find((o) => o.value === currentParams.colorMode)?.label}</span
									>
									<svg
										class="h-3 w-3 opacity-50 transition-transform"
										class:rotate-180={colorizeDropdownOpen}
										viewBox="0 0 20 20"
										fill="currentColor"
									>
										<path
											fill-rule="evenodd"
											d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
											clip-rule="evenodd"
										/>
									</svg>
								</button>
								{#if colorizeDropdownOpen}
									<div
										class="dropdown-menu absolute top-full right-0 left-0 z-50 mt-1 max-h-[140px] overflow-y-auto rounded-md"
										transition:slide={{ duration: 150, easing: cubicOut }}
									>
										{#each colorOptions as opt (opt.value)}
											<button
												class="dropdown-item flex h-[28px] w-full items-center gap-2 px-[10px] text-left text-[10px]"
												class:active={currentParams.colorMode === opt.value}
												onclick={() => selectColorize(opt.value)}
											>
												{#if opt.value === ColorMode.None}
													<!-- Lucide: minus -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12" /></svg
													>
												{:else if opt.value === ColorMode.Orientation}
													<!-- Lucide: compass -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><circle cx="12" cy="12" r="10" /><polygon
															points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"
															fill="currentColor"
															stroke="none"
														/></svg
													>
												{:else if opt.value === ColorMode.Speed}
													<!-- Lucide: gauge -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><path d="m12 14 4-4" /><path d="M3.34 19a10 10 0 1 1 17.32 0" /></svg
													>
												{:else if opt.value === ColorMode.Neighbors}
													<!-- Lucide: users -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle
															cx="9"
															cy="7"
															r="4"
														/><path d="M22 21v-2a4 4 0 0 0-3-3.87" /><path
															d="M16 3.13a4 4 0 0 1 0 7.75"
														/></svg
													>
												{:else if opt.value === ColorMode.Density}
													<!-- Lucide: grid-3x3 -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><rect width="18" height="18" x="3" y="3" rx="2" /><path
															d="M3 9h18"
														/><path d="M3 15h18" /><path d="M9 3v18" /><path d="M15 3v18" /></svg
													>
												{:else if opt.value === ColorMode.Acceleration}
													<!-- Lucide: trending-up -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><polyline points="22 7 13.5 15.5 8.5 10.5 2 17" /><polyline
															points="16 7 22 7 22 13"
														/></svg
													>
												{:else if opt.value === ColorMode.Turning}
													<!-- Lucide: rotate-cw -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8" /><path
															d="M21 3v5h-5"
														/></svg
													>
												{:else if opt.value === ColorMode.Species}
													<!-- Lucide: shapes (species) -->
													<svg
														class="colorize-icon"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="2"
														stroke-linecap="round"
														stroke-linejoin="round"
														><path
															d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z"
														/><rect x="3" y="14" width="7" height="7" rx="1" /><circle
															cx="17.5"
															cy="17.5"
															r="3.5"
														/></svg
													>
												{/if}
												<span>{opt.label}</span>
											</button>
										{/each}
									</div>
								{/if}
							</div>
						</div>
						<div class="row">
							{#if currentParams.colorMode === ColorMode.Species && activeSpecies}
								<!-- Color swatch that opens picker -->
								<span class="label">Color</span>
								<div class="relative" bind:this={colorPickerRef}>
									<button
										class="color-swatch-btn"
										style="background: hsl({activeSpecies.hue}, {activeSpecies.saturation}%, {activeSpecies.lightness}%)"
										onclick={() => (colorPickerOpen = !colorPickerOpen)}
										aria-label="Species Color"
									></button>
									{#if colorPickerOpen}
										<div
											class="color-picker-panel"
											transition:slide={{ duration: 150, easing: cubicOut }}
										>
											<!-- 2D Saturation/Lightness picker -->
											<div
												class="sl-picker"
												role="slider"
												aria-label="Saturation and Lightness"
												aria-valuenow={activeSpecies.saturation}
												tabindex={0}
												style="background: linear-gradient(to bottom, white, hsl({activeSpecies.hue}, 100%, 50%), black)"
												onmousedown={(e) => {
													const rect = e.currentTarget.getBoundingClientRect();
													const updateSL = (clientX: number, clientY: number) => {
														const x = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
														const y = Math.max(0, Math.min(1, (clientY - rect.top) / rect.height));
														const saturation = Math.round(x * 100);
														const lightness = Math.round((1 - y) * 100);
														setSpeciesColor(
															activeSpecies.id,
															activeSpecies.hue,
															saturation,
															lightness
														);
													};
													updateSL(e.clientX, e.clientY);
													const onMove = (ev: MouseEvent) => updateSL(ev.clientX, ev.clientY);
													const onUp = () => {
														window.removeEventListener('mousemove', onMove);
														window.removeEventListener('mouseup', onUp);
													};
													window.addEventListener('mousemove', onMove);
													window.addEventListener('mouseup', onUp);
												}}
											>
												<div class="sl-saturation-overlay"></div>
												<div
													class="sl-indicator"
													style="left: {activeSpecies.saturation}%; top: {100 -
														activeSpecies.lightness}%"
												></div>
											</div>
											<!-- Hue strip -->
											<div class="hue-strip-container">
												<input
													type="range"
													class="hue-strip"
													min="0"
													max="360"
													step="1"
													value={activeSpecies.hue}
													oninput={(e) =>
														setSpeciesHue(activeSpecies.id, parseInt(e.currentTarget.value))}
													aria-label="Hue"
												/>
											</div>
										</div>
									{/if}
								</div>
								<!-- Alpha mode dropdown with label -->
								<span class="label" style="width: auto; margin-left: 12px;">Alpha</span>
								<div class="relative flex-1" bind:this={alphaDropdownRef}>
									<button
										class="sel flex w-full items-center gap-1 text-left"
										onclick={() => (alphaDropdownOpen = !alphaDropdownOpen)}
										aria-label="Alpha Mode"
										aria-expanded={alphaDropdownOpen}
									>
										<span class="flex-1 truncate text-[9px]"
											>{alphaModeOptions.find((o) => o.value === activeSpecies.alphaMode)?.label ??
												'Solid'}</span
										>
										<svg
											class="h-3 w-3 opacity-50 transition-transform"
											class:rotate-180={alphaDropdownOpen}
											viewBox="0 0 20 20"
											fill="currentColor"
										>
											<path
												fill-rule="evenodd"
												d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
												clip-rule="evenodd"
											/>
										</svg>
									</button>
									{#if alphaDropdownOpen}
										<div
											class="dropdown-menu absolute top-full right-0 left-0 z-50 mt-1 overflow-y-auto rounded-md"
											transition:slide={{ duration: 150, easing: cubicOut }}
										>
											{#each alphaModeOptions as opt (opt.value)}
												<button
													class="dropdown-item flex w-full items-center gap-2 px-3 py-2 text-left text-[10px]"
													class:active={activeSpecies.alphaMode === opt.value}
													onclick={() => {
														setSpeciesAlphaMode(activeSpecies.id, opt.value);
														alphaDropdownOpen = false;
													}}
												>
													<span>{opt.label}</span>
												</button>
											{/each}
										</div>
									{/if}
								</div>
							{:else}
								<!-- Palette dropdown -->
								<span class="label">Palette</span>
								<div class="relative flex-1" bind:this={paletteDropdownRef}>
									<button
										class="sel flex w-full items-center gap-2 text-left"
										onclick={() => (paletteDropdownOpen = !paletteDropdownOpen)}
										aria-label="Palette"
										aria-expanded={paletteDropdownOpen}
									>
										<PaletteIcon spectrum={currentParams.colorSpectrum} size={18} />
										<span class="flex-1 truncate"
											>{spectrumOptions.find((o) => o.value === currentParams.colorSpectrum)
												?.label}</span
										>
										<svg
											class="h-3 w-3 opacity-50 transition-transform"
											class:rotate-180={paletteDropdownOpen}
											viewBox="0 0 20 20"
											fill="currentColor"
										>
											<path
												fill-rule="evenodd"
												d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
												clip-rule="evenodd"
											/>
										</svg>
									</button>
									{#if paletteDropdownOpen}
										<div
											class="dropdown-menu absolute top-full right-0 left-0 z-50 mt-1 overflow-y-auto rounded-md"
											transition:slide={{ duration: 150, easing: cubicOut }}
										>
											{#each spectrumOptions as opt (opt.value)}
												<button
													class="dropdown-item flex w-full items-center gap-2 px-3 py-2 text-left text-[10px]"
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
							{/if}
						</div>
						<div class="row">
							<span class="label">Rebels</span>
							<input
								type="range"
								min="0"
								max="0.2"
								step="0.01"
								value={activeSpecies?.rebels ?? 0.02}
								oninput={(e) =>
									activeSpecies &&
									setSpeciesRebels(activeSpecies.id, parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Rebels"
							/>
							<span class="value">{((activeSpecies?.rebels ?? 0.02) * 100).toFixed(0)}%</span>
						</div>
					</div>
				{/if}
			</div>

			<div class="section-divider"></div>
			<!-- Interaction - Cursor Controls -->
			<div id="section-interaction">
				<button class="section-header" onclick={() => toggleSection('interaction')}>
					<div class="section-title">
						<svg
							class="section-icon icon-red"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<!-- Magic Wand Icon -->
							<path d="M15 4V2" />
							<path d="M15 16v-2" />
							<path d="M8 9h2" />
							<path d="M20 9h2" />
							<path d="M17.8 11.8L19 13" />
							<path d="M15 9h0" />
							<path d="M17.8 6.2L19 5" />
							<path d="M3 21l9-9" />
							<path d="M12.2 6.2L11 5" />
						</svg>
						<span class="section-label">Interaction</span>
					</div>
					<div class="section-actions">
						{#if openSection === 'interaction'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('interaction');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('interaction'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetInteractionSection}
								onkeydown={(e) => handleKeydown(e, resetInteractionSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'interaction'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'interaction'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Force</span>
							<!-- Force buttons: Attract, Repel, Vortex - controls per-species response -->
							<div class="cursor-toggle cursor-toggle-4">
								<!-- Sliding indicator for attract/repel (hidden when species ignores cursor) -->
								{#if activeSpecies?.cursorResponse !== CursorResponse.Ignore}
									<div
										class="cursor-toggle-indicator"
										style="left: calc(4px + {cursorModeIndex} * 44px)"
									></div>
								{/if}

								<button
									class="cursor-toggle-btn power-btn"
									class:active={activeSpecies?.cursorResponse !== CursorResponse.Ignore ||
										activeSpecies?.cursorVortex}
									onclick={() => handleCursorModeToggle(CursorMode.Off)}
									aria-label="Toggle Cursor"
									title="Toggle interaction on/off for this species"
								>
									<svg
										viewBox="0 0 24 24"
										class="h-5 w-5"
										fill="none"
										stroke="currentColor"
										stroke-width="2.2"
										stroke-linecap="round"
									>
										<path d="M12 3 L12 11" />
										<path d="M6.3 6.3 A8.5 8.5 0 1 0 17.7 6.3" />
									</svg>
								</button>
								<button
									class="cursor-toggle-btn attract"
									class:active={activeSpecies?.cursorResponse === CursorResponse.Attract}
									onclick={() => handleCursorModeToggle(CursorMode.Attract)}
									aria-label="Attract"
									title="Attract this species (click again to turn off)"
								>
									<ForceAnimation
										type="attract"
										active={activeSpecies?.cursorResponse === CursorResponse.Attract}
										size={32}
									/>
								</button>
								<button
									class="cursor-toggle-btn repel"
									class:active={activeSpecies?.cursorResponse === CursorResponse.Repel}
									onclick={() => handleCursorModeToggle(CursorMode.Repel)}
									aria-label="Repel"
									title="Repel this species (click again to turn off)"
								>
									<ForceAnimation
										type="repel"
										active={activeSpecies?.cursorResponse === CursorResponse.Repel}
										size={32}
									/>
								</button>
								<button
									class="cursor-toggle-btn vortex"
									class:active={activeSpecies?.cursorVortex !== VortexDirection.Off}
									class:counter-clockwise={activeSpecies?.cursorVortex ===
										VortexDirection.CounterClockwise}
									onclick={() => activeSpecies && cycleSpeciesCursorVortex(activeSpecies.id)}
									aria-label="Vortex"
									title="Cycle rotation: Off → Clockwise → Counter-clockwise → Off"
								>
									<ForceAnimation
										type="vortex"
										active={activeSpecies?.cursorVortex !== VortexDirection.Off}
										vortexDirection={activeSpecies?.cursorVortex ?? VortexDirection.Off}
										size={32}
									/>
								</button>
							</div>
						</div>
						<div class="row">
							<span class="label">Shape</span>
							<div class="shape-toggle shape-toggle-2">
								<button
									class="shape-btn"
									class:active={currentParams.cursorShape === CursorShape.Ring}
									onclick={() => setCursorShape(CursorShape.Ring)}
									aria-label="Ring"
									title="Ring"
								>
									<svg
										viewBox="0 0 24 24"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										class="h-5 w-5"
									>
										<circle cx="12" cy="12" r="7" />
									</svg>
								</button>
								<button
									class="shape-btn"
									class:active={currentParams.cursorShape === CursorShape.Disk}
									onclick={() => setCursorShape(CursorShape.Disk)}
									aria-label="Disk"
									title="Disk"
								>
									<svg viewBox="0 0 24 24" class="h-5 w-5">
										<circle cx="12" cy="12" r="7" fill="currentColor" opacity="0.4" />
										<circle
											cx="12"
											cy="12"
											r="7"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
										/>
									</svg>
								</button>
							</div>
						</div>
						<div class="row">
							<span class="label">Size</span>
							<input
								type="range"
								min="10"
								max="150"
								step="5"
								value={currentParams.cursorRadius}
								oninput={(e) => setCursorRadius(parseInt(e.currentTarget.value))}
								class="slider"
								aria-label="Cursor Size"
							/>
							<span class="value">{currentParams.cursorRadius}</span>
						</div>
						<div class="row">
							<span class="label">Power</span>
							<input
								type="range"
								min="0"
								max="1"
								step="0.05"
								value={activeSpecies?.cursorForce ?? 0.5}
								oninput={(e) =>
									activeSpecies &&
									setSpeciesCursorForce(activeSpecies.id, parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Cursor Force"
							/>
							<span class="value">{(activeSpecies?.cursorForce ?? 0.5).toFixed(2)}</span>
						</div>
					</div>
				{/if}
			</div>

			<div class="section-divider"></div>
			<!-- Species Interactions -->
			<div id="section-species">
				<button class="section-header" onclick={() => toggleSection('species')}>
					<div class="section-title">
						<svg
							class="section-icon icon-indigo"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<circle cx="12" cy="12" r="3" />
							<path d="M12 2v4m0 12v4M2 12h4m12 0h4" />
							<path
								d="m4.93 4.93 2.83 2.83m8.48 8.48 2.83 2.83m0-14.14-2.83 2.83m-8.48 8.48-2.83 2.83"
							/>
						</svg>
						<span class="section-label">Species</span>
					</div>
					<!-- Quick species selector - only when collapsed and multiple species -->
					{#if openSection !== 'species' && currentParams.species.length > 1}
						<div class="quick-species-selector">
							{#each currentParams.species as species (species.id)}
								<span
									class="quick-species-btn"
									class:selected={species.id === currentParams.activeSpeciesId}
									role="button"
									tabindex="0"
									onclick={(e) => {
										e.stopPropagation();
										setActiveSpecies(species.id);
									}}
									onkeydown={(e) => {
										if (e.key === 'Enter' || e.key === ' ') {
											e.stopPropagation();
											setActiveSpecies(species.id);
										}
									}}
									title={species.name}
									style="--species-color: hsl({species.hue}, {species.saturation ??
										70}%, {species.lightness ?? 55}%)"
								>
									<svg viewBox="0 0 20 20" class="quick-species-icon">
										<path
											d={getQuickBoidPath(species.headShape, 10, 10, 6)}
											fill="var(--species-color)"
										/>
									</svg>
									{#if species.id === currentParams.activeSpeciesId}
										<span class="quick-species-ring"></span>
									{/if}
								</span>
							{/each}
						</div>
					{/if}
					<div class="section-actions">
						{#if openSection === 'species'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('species');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('species'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'species'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'species'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<SpeciesSelector />
						<InteractionsPanel />
					</div>
				{/if}
			</div>

			<div class="section-divider"></div>
			<!-- Flocking -->
			<div id="section-flocking">
				<button class="section-header" onclick={() => toggleSection('flocking')}>
					<div class="section-title">
						<svg
							class="section-icon icon-pink"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
							<circle cx="9" cy="7" r="4" />
							<path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
						</svg>
						<span class="section-label">Flocking</span>
					</div>
					<div class="section-actions">
						{#if openSection === 'flocking'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('flocking');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('flocking'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetFlockingSection}
								onkeydown={(e) => handleKeydown(e, resetFlockingSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'flocking'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'flocking'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Align</span>
							<input
								type="range"
								min="0"
								max="3"
								step="0.1"
								value={activeSpecies?.alignment ?? currentParams.alignment}
								oninput={(e) => {
									const val = parseFloat(e.currentTarget.value);
									if (activeSpecies) {
										updateSpeciesFlocking(activeSpecies.id, 'alignment', val);
									}
									setAlignment(val);
								}}
								class="slider"
								aria-label="Alignment"
							/>
							<span class="value"
								>{(activeSpecies?.alignment ?? currentParams.alignment).toFixed(1)}</span
							>
						</div>
						<div class="row">
							<span class="label">Cohesion</span>
							<input
								type="range"
								min="0"
								max="3"
								step="0.1"
								value={activeSpecies?.cohesion ?? currentParams.cohesion}
								oninput={(e) => {
									const val = parseFloat(e.currentTarget.value);
									if (activeSpecies) {
										updateSpeciesFlocking(activeSpecies.id, 'cohesion', val);
									}
									setCohesion(val);
								}}
								class="slider"
								aria-label="Cohesion"
							/>
							<span class="value"
								>{(activeSpecies?.cohesion ?? currentParams.cohesion).toFixed(1)}</span
							>
						</div>
						<div class="row">
							<span class="label">Separate</span>
							<input
								type="range"
								min="0"
								max="4"
								step="0.1"
								value={activeSpecies?.separation ?? currentParams.separation}
								oninput={(e) => {
									const val = parseFloat(e.currentTarget.value);
									if (activeSpecies) {
										updateSpeciesFlocking(activeSpecies.id, 'separation', val);
									}
									setSeparation(val);
								}}
								class="slider"
								aria-label="Separation"
							/>
							<span class="value"
								>{(activeSpecies?.separation ?? currentParams.separation).toFixed(1)}</span
							>
						</div>
						<div class="row">
							<span class="label">Range</span>
							<input
								type="range"
								min="20"
								max="150"
								step="5"
								value={activeSpecies?.perception ?? currentParams.perception}
								oninput={(e) => {
									const val = parseInt(e.currentTarget.value);
									if (activeSpecies) {
										updateSpeciesFlocking(activeSpecies.id, 'perception', val);
									}
									setPerception(val);
								}}
								class="slider"
								aria-label="Perception"
							/>
							<span class="value">{activeSpecies?.perception ?? currentParams.perception}</span>
						</div>
					</div>
				{/if}
			</div>

			<div class="section-divider"></div>
			<!-- World - 3D Topology Selector -->
			<div id="section-world">
				<button class="section-header" onclick={() => toggleSection('world')}>
					<div class="section-title">
						<svg
							class="section-icon icon-sky"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<circle cx="12" cy="12" r="10" />
							<path
								d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"
							/>
						</svg>
						<span class="section-label"
							>World <span class="section-value"
								>({TOPOLOGY_NAMES[currentParams.boundaryMode] ?? 'Plane'})</span
							></span
						>
					</div>
					<div class="section-actions">
						{#if openSection === 'world'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('world');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('world'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetWorldSection}
								onkeydown={(e) => handleKeydown(e, resetWorldSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'world'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'world'}
					<div
						class="section-content topology-section"
						transition:slide={{ duration: 150, easing: cubicOut }}
					>
						<TopologySelector currentMode={currentParams.boundaryMode} />

						<div class="row">
							<span class="label">Walls</span>
							<div class="cursor-toggle cursor-toggle-4">
								<!-- Power button for wall drawing on/off -->
								<button
									class="cursor-toggle-btn power-btn"
									class:active={currentWallTool !== WallTool.None}
									onclick={() =>
										setWallTool(
											currentWallTool === WallTool.None ? WallTool.Pencil : WallTool.None
										)}
									aria-label="Toggle wall drawing"
									title="Toggle wall drawing on/off"
								>
									<svg
										viewBox="0 0 24 24"
										class="h-5 w-5"
										fill="none"
										stroke="currentColor"
										stroke-width="2.2"
										stroke-linecap="round"
									>
										<path d="M12 3 L12 11" />
										<path d="M6.3 6.3 A8.5 8.5 0 1 0 17.7 6.3" />
									</svg>
								</button>
								<!-- Pencil -->
								<button
									class="cursor-toggle-btn"
									class:active={currentWallTool === WallTool.Pencil}
									onclick={() => setWallTool(WallTool.Pencil)}
									aria-label="Pencil"
									title="Draw walls"
								>
									<svg
										viewBox="0 0 24 24"
										class="h-5 w-5"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										stroke-linecap="round"
										stroke-linejoin="round"
									>
										<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
										<path d="m15 5 4 4" />
									</svg>
								</button>
								<!-- Eraser -->
								<button
									class="cursor-toggle-btn"
									class:active={currentWallTool === WallTool.Eraser}
									onclick={() => setWallTool(WallTool.Eraser)}
									aria-label="Eraser"
									title="Erase walls"
								>
									<svg
										viewBox="0 0 24 24"
										class="h-5 w-5"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										stroke-linecap="round"
										stroke-linejoin="round"
									>
										<path
											d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21"
										/>
										<path d="M22 21H7" />
										<path d="m5 11 9 9" />
									</svg>
								</button>
								<!-- Clear all walls -->
								<button
									class="cursor-toggle-btn clear-btn"
									onclick={() => clearWalls()}
									aria-label="Clear walls"
									title="Clear all walls"
								>
									<svg
										viewBox="0 0 24 24"
										class="h-5 w-5"
										fill="none"
										stroke="currentColor"
										stroke-width="2"
										stroke-linecap="round"
										stroke-linejoin="round"
									>
										<path d="M3 6h18" />
										<path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" />
										<path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" />
									</svg>
								</button>
							</div>
						</div>
						{#if currentWallTool !== WallTool.None}
							<div class="row">
								<span class="label">Shape</span>
								<div class="shape-toggle shape-toggle-2">
									<button
										class="shape-btn"
										class:active={currentParams.wallBrushShape === WallBrushShape.Solid}
										onclick={() => setWallBrushShape(WallBrushShape.Solid)}
										aria-label="Solid"
										title="Solid"
									>
										<svg viewBox="0 0 24 24" class="h-5 w-5">
											<circle cx="12" cy="12" r="7" fill="currentColor" opacity="0.4" />
											<circle
												cx="12"
												cy="12"
												r="7"
												fill="none"
												stroke="currentColor"
												stroke-width="2"
											/>
										</svg>
									</button>
									<button
										class="shape-btn"
										class:active={currentParams.wallBrushShape === WallBrushShape.Ring}
										onclick={() => setWallBrushShape(WallBrushShape.Ring)}
										aria-label="Ring"
										title="Ring (auto-hollows on release)"
									>
										<svg
											viewBox="0 0 24 24"
											fill="none"
											stroke="currentColor"
											stroke-width="2"
											class="h-5 w-5"
										>
											<circle cx="12" cy="12" r="7" />
										</svg>
									</button>
								</div>
							</div>
							<div class="row">
								<span class="label">Size</span>
								<input
									type="range"
									min="10"
									max="100"
									step="5"
									value={currentParams.wallBrushSize}
									oninput={(e) => setWallBrushSize(parseInt(e.currentTarget.value))}
									class="slider"
									aria-label="Brush Size"
								/>
								<span class="value">{currentParams.wallBrushSize}</span>
							</div>
						{/if}
					</div>
				{/if}
			</div>

			<div class="section-divider"></div>
			<!-- Dynamics -->
			<div id="section-dynamics">
				<button class="section-header" onclick={() => toggleSection('dynamics')}>
					<div class="section-title">
						<svg
							class="section-icon icon-amber"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
						</svg>
						<span class="section-label">Dynamics</span>
					</div>
					<div class="section-actions">
						{#if openSection === 'dynamics'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('dynamics');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('dynamics'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetDynamicsSection}
								onkeydown={(e) => handleKeydown(e, resetDynamicsSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'dynamics'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'dynamics'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Speed</span>
							<input
								type="range"
								min="1"
								max="15"
								step="0.5"
								value={currentParams.maxSpeed}
								oninput={(e) => setMaxSpeed(parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Speed"
							/>
							<span class="value">{currentParams.maxSpeed.toFixed(1)}</span>
						</div>
						<div class="row">
							<span class="label">Force</span>
							<input
								type="range"
								min="0.01"
								max="0.5"
								step="0.01"
								value={currentParams.maxForce}
								oninput={(e) => setMaxForce(parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Force"
							/>
							<span class="value">{currentParams.maxForce.toFixed(2)}</span>
						</div>
						<div class="row">
							<span class="label">Noise</span>
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
							<span class="value">{currentParams.noise.toFixed(2)}</span>
						</div>
						<div class="row">
							<span class="label">Time</span>
							<input
								type="range"
								min="0.25"
								max="2"
								step="0.05"
								value={currentParams.timeScale}
								oninput={(e) => setTimeScale(parseFloat(e.currentTarget.value))}
								class="slider"
								aria-label="Time Scale"
							/>
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
						<svg
							class="section-icon icon-emerald"
							viewBox="0 0 24 24"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							stroke-linejoin="round"
						>
							<rect x="4" y="4" width="16" height="16" rx="2" ry="2" />
							<rect x="9" y="9" width="6" height="6" />
							<line x1="9" y1="1" x2="9" y2="4" />
							<line x1="15" y1="1" x2="15" y2="4" />
							<line x1="9" y1="20" x2="9" y2="23" />
							<line x1="15" y1="20" x2="15" y2="23" />
							<line x1="20" y1="9" x2="23" y2="9" />
							<line x1="20" y1="14" x2="23" y2="14" />
							<line x1="1" y1="9" x2="4" y2="9" />
							<line x1="1" y1="14" x2="4" y2="14" />
						</svg>
						<span class="section-label">Algorithm</span>
					</div>
					<div class="section-actions">
						{#if openSection === 'algorithm'}
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={(e) => {
									e.stopPropagation();
									startTourAtSection('algorithm');
								}}
								onkeydown={(e) => handleKeydown(e, () => startTourAtSection('algorithm'))}
								title="Help"
							>
								<svg viewBox="0 0 20 20" fill="currentColor"
									><path
										fill-rule="evenodd"
										d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM8.94 6.94a.75.75 0 11-1.061-1.061 3 3 0 112.871 5.026v.345a.75.75 0 01-1.5 0v-.5c0-.72.57-1.172 1.081-1.287A1.5 1.5 0 108.94 6.94zM10 15a1 1 0 100-2 1 1 0 000 2z"
										clip-rule="evenodd"
									/></svg
								>
							</span>
							<span
								class="section-action-btn"
								role="button"
								tabindex="0"
								onclick={resetAlgorithmSection}
								onkeydown={(e) => handleKeydown(e, resetAlgorithmSection)}
								title="Reset"
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" /><path
										d="M3 3v5h5"
									/></svg
								>
							</span>
						{/if}
						<svg
							class="section-chevron"
							class:open={openSection === 'algorithm'}
							viewBox="0 0 20 20"
							fill="currentColor"
						>
							<path
								fill-rule="evenodd"
								d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
								clip-rule="evenodd"
							/>
						</svg>
					</div>
				</button>
				{#if openSection === 'algorithm'}
					<div class="section-content" transition:slide={{ duration: 150, easing: cubicOut }}>
						<div class="row">
							<span class="label">Mode</span>
							<div class="relative flex-1" bind:this={algorithmDropdownRef}>
								<button
									class="sel flex w-full items-center gap-2 text-left"
									onclick={() => (algorithmDropdownOpen = !algorithmDropdownOpen)}
									aria-label="Algorithm"
									aria-expanded={algorithmDropdownOpen}
								>
									<span class="flex-1 truncate"
										>{algorithmOptions.find((o) => o.value === currentParams.algorithmMode)
											?.label}</span
									>
									<svg
										class="h-3 w-3 opacity-50 transition-transform"
										class:rotate-180={algorithmDropdownOpen}
										viewBox="0 0 20 20"
										fill="currentColor"
									>
										<path
											fill-rule="evenodd"
											d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
											clip-rule="evenodd"
										/>
									</svg>
								</button>
								{#if algorithmDropdownOpen}
									<div
										class="dropdown-menu dropdown-up absolute right-0 bottom-full left-0 z-50 mb-1 max-h-48 overflow-y-auto rounded-md"
										transition:slide={{ duration: 150, easing: cubicOut }}
									>
										{#each algorithmOptions as opt (opt.value)}
											<button
												class="dropdown-item flex w-full items-center gap-2 px-3 py-2 text-left text-[10px]"
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
								<input
									type="range"
									min="4"
									max="24"
									step="1"
									value={currentParams.kNeighbors}
									oninput={(e) => setKNeighbors(parseInt(e.currentTarget.value))}
									class="slider"
									aria-label="Neighbors"
								/>
								<span class="value">{currentParams.kNeighbors}</span>
							</div>
						{:else if currentParams.algorithmMode === AlgorithmMode.StochasticSample}
							<div class="row">
								<span class="label">Samples</span>
								<input
									type="range"
									min="8"
									max="64"
									step="4"
									value={currentParams.sampleCount}
									oninput={(e) => setSampleCount(parseInt(e.currentTarget.value))}
									class="slider"
									aria-label="Sample Count"
								/>
								<span class="value">{currentParams.sampleCount}</span>
							</div>
						{:else if currentParams.algorithmMode === AlgorithmMode.DensityAdaptive}
							<div class="row">
								<span class="label">Density</span>
								<input
									type="range"
									min="1"
									max="10"
									step="0.5"
									value={currentParams.idealDensity}
									oninput={(e) => setIdealDensity(parseFloat(e.currentTarget.value))}
									class="slider"
									aria-label="Ideal Density"
								/>
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
	/* Remove focus outlines - shortcuts should not highlight buttons */
	button:focus,
	input:focus,
	[role='button']:focus {
		outline: none;
	}

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
		transition:
			opacity 0.2s ease,
			transform 0.2s ease;
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
		0%,
		100% {
			opacity: 1;
			transform: scale(1);
		}
		50% {
			opacity: 0.6;
			transform: scale(0.85);
		}
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
		0%,
		100% {
			color: #ef4444;
		}
		50% {
			color: #fca5a5;
		}
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
	.section-icon.icon-purple {
		color: #a78bfa;
	}
	.section-icon.icon-sky {
		color: #38bdf8;
	}
	.section-icon.icon-red {
		color: #f87171;
	}
	.section-icon.icon-pink {
		color: #f472b6;
	}
	.section-icon.icon-amber {
		color: #fbbf24;
	}
	.section-icon.icon-emerald {
		color: #34d399;
	}
	.section-icon.icon-indigo {
		color: #818cf8;
	}

	.topology-section {
		padding: 0;
	}

	.section-label {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: rgb(161 161 170);
	}
	.section-value {
		font-weight: 500;
		text-transform: none;
		letter-spacing: 0.02em;
		color: rgb(113 113 122);
	}
	.section-actions {
		display: flex;
		align-items: center;
		gap: 4px;
	}
	.section-action-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 18px;
		height: 18px;
		padding: 0;
		background: transparent;
		border: none;
		border-radius: 4px;
		color: rgb(113 113 122);
		cursor: pointer;
		transition:
			color 0.15s,
			background 0.15s;
	}
	.section-action-btn:hover {
		color: rgb(161 161 170);
		background: rgba(255, 255, 255, 0.05);
	}
	.section-action-btn svg {
		width: 12px;
		height: 12px;
	}

	/* Quick species selector in collapsed section header */
	.quick-species-selector {
		display: flex;
		align-items: center;
		gap: 2px;
		margin-left: auto;
		margin-right: 8px;
	}
	.quick-species-btn {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 16px;
		height: 16px;
		padding: 0;
		background: transparent;
		border: none;
		border-radius: 3px;
		cursor: pointer;
		transition: transform 0.1s ease;
	}
	.quick-species-btn:hover {
		transform: scale(1.15);
	}
	.quick-species-icon {
		width: 100%;
		height: 100%;
	}
	.quick-species-ring {
		position: absolute;
		inset: -1px;
		border: 1px solid var(--species-color);
		border-radius: 3px;
		opacity: 1;
		pointer-events: none;
	}
	.quick-species-btn.selected {
		transform: scale(1);
	}
	.quick-species-btn.selected:hover {
		transform: scale(1.15);
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
		transition:
			transform 0.1s,
			border-color 0.1s,
			box-shadow 0.1s;
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
		transition:
			border-color 0.15s,
			background 0.15s;
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
		transition:
			background 0.1s,
			color 0.1s;
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

	.color-swatch-btn {
		width: 28px;
		height: 28px;
		border-radius: 4px;
		border: 1px solid rgba(255, 255, 255, 0.2);
		cursor: pointer;
		transition: all 0.15s ease;
	}

	.color-swatch-btn:hover {
		border-color: rgba(255, 255, 255, 0.4);
		transform: scale(1.05);
	}

	.color-picker-panel {
		position: absolute;
		top: 100%;
		left: 0;
		margin-top: 4px;
		padding: 10px;
		background: rgba(15, 15, 20, 0.98);
		border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 8px;
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
		z-index: 60;
		width: 160px;
	}

	.sl-picker {
		position: relative;
		width: 100%;
		height: 100px;
		border-radius: 6px;
		cursor: crosshair;
		overflow: hidden;
	}

	.sl-saturation-overlay {
		position: absolute;
		inset: 0;
		background: linear-gradient(to right, rgba(128, 128, 128, 1), rgba(128, 128, 128, 0));
		mix-blend-mode: saturation;
		pointer-events: none;
	}

	.sl-indicator {
		position: absolute;
		width: 12px;
		height: 12px;
		border-radius: 50%;
		border: 2px solid white;
		box-shadow:
			0 0 0 1px rgba(0, 0, 0, 0.3),
			0 2px 4px rgba(0, 0, 0, 0.3);
		transform: translate(-50%, -50%);
		pointer-events: none;
	}

	.hue-strip-container {
		margin-top: 8px;
	}

	.hue-strip {
		width: 100%;
		height: 12px;
		-webkit-appearance: none;
		appearance: none;
		background: linear-gradient(
			to right,
			hsl(0, 100%, 50%),
			hsl(60, 100%, 50%),
			hsl(120, 100%, 50%),
			hsl(180, 100%, 50%),
			hsl(240, 100%, 50%),
			hsl(300, 100%, 50%),
			hsl(360, 100%, 50%)
		);
		border-radius: 6px;
		cursor: pointer;
	}

	.hue-strip::-webkit-slider-thumb {
		-webkit-appearance: none;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: white;
		border: 2px solid rgba(0, 0, 0, 0.2);
		box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
		cursor: pointer;
	}

	.hue-strip::-moz-range-thumb {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: white;
		border: 2px solid rgba(0, 0, 0, 0.2);
		box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
		cursor: pointer;
	}

	/* Premium Cursor Toggle */
	.cursor-toggle {
		display: grid;
		grid-template-columns: repeat(3, 36px);
		position: relative;
		height: 44px;
		background: rgba(0, 0, 0, 0.4);
		border-radius: 8px;
		padding: 4px;
		gap: 8px;
		border: 1px solid rgba(255, 255, 255, 0.06);
	}
	.cursor-toggle.cursor-toggle-4 {
		grid-template-columns: repeat(4, 36px);
	}
	.cursor-toggle-indicator {
		position: absolute;
		top: 4px;
		width: 36px;
		height: 36px;
		background: rgba(255, 255, 255, 0.1);
		border-radius: 50%;
		transition: left 0.2s cubic-bezier(0.4, 0, 0.2, 1);
		pointer-events: none;
	}
	.cursor-toggle-4 .cursor-toggle-indicator {
		width: 36px;
	}
	.cursor-toggle-btn {
		position: relative;
		z-index: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: none;
		border-radius: 50%;
		color: rgb(113 113 122);
		cursor: pointer;
		transition: color 0.15s;
		aspect-ratio: 1;
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
	/* Vortex button - orange when active (independent toggle) */
	.cursor-toggle-btn.vortex {
		color: rgb(113 113 122);
	}
	.cursor-toggle-btn.vortex:hover {
		color: rgb(161 161 170);
	}
	.cursor-toggle-btn.vortex.active {
		color: rgb(249 115 22);
		background: rgba(249, 115, 22, 0.15);
		box-shadow: 0 0 12px rgba(249, 115, 22, 0.2);
		border-radius: 50%;
	}
	/* Counter-clockwise vortex - purple tint to distinguish from clockwise */
	.cursor-toggle-btn.vortex.active.counter-clockwise {
		color: rgb(168 85 247);
		background: rgba(168, 85, 247, 0.15);
		box-shadow: 0 0 12px rgba(168, 85, 247, 0.2);
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
	.shape-toggle.shape-toggle-2 {
		grid-template-columns: repeat(2, 1fr);
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

	/* Clear button in wall tools row */
	.cursor-toggle-btn.clear-btn:hover {
		color: rgb(252, 165, 165);
		background: rgba(239, 68, 68, 0.2);
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
