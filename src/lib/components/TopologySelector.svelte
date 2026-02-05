<script lang="ts">
	import * as THREE from 'three';
	import { Line2 } from 'three/addons/lines/Line2.js';
	import { LineGeometry } from 'three/addons/lines/LineGeometry.js';
	import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
	import {
		getTopologyGeometry,
		getTopologyColor,
		getTopologyGridGeometry,
		getTopologyEdgeGeometries
	} from '$lib/utils/topologyMeshes';
	import { setBoundaryMode, BoundaryMode } from '$lib/stores/simulation';

	interface Props {
		currentMode: BoundaryMode;
	}

	let { currentMode }: Props = $props();

	// Grid layout: rows = Y behavior, cols = X behavior
	const GRID: { mode: BoundaryMode; name: string }[][] = [
		[
			{ mode: BoundaryMode.Plane, name: 'Plane' },
			{ mode: BoundaryMode.CylinderX, name: 'Cylinder X' },
			{ mode: BoundaryMode.MobiusX, name: 'Möbius X' }
		],
		[
			{ mode: BoundaryMode.CylinderY, name: 'Cylinder Y' },
			{ mode: BoundaryMode.Torus, name: 'Torus' },
			{ mode: BoundaryMode.KleinX, name: 'Klein X' }
		],
		[
			{ mode: BoundaryMode.MobiusY, name: 'Möbius Y' },
			{ mode: BoundaryMode.KleinY, name: 'Klein Y' },
			{ mode: BoundaryMode.ProjectivePlane, name: 'Roman' }
		]
	];

	const FLAT_GRID = GRID.flat();

	// Single shared renderer and camera
	let renderer: THREE.WebGLRenderer | null = null;
	let camera: THREE.PerspectiveCamera | null = null;
	let mainCanvas: HTMLCanvasElement | null = null;

	// Per-cell scene data (loaded progressively)
	interface CellData {
		scene: THREE.Scene;
		mesh: THREE.Mesh;
		gridLines: THREE.LineSegments;
		edgeLines: Line2[];
		edgeMaterial: LineMaterial;
		mode: BoundaryMode;
		loaded: boolean;
	}

	let cells: (CellData | null)[] = Array(9).fill(null);
	let animationId: number | null = null;
	let startTime = 0;
	let rotationY = 0;
	let loadIndex = 0;
	let isInitialized = false;

	// Shared lighting setup - create once, clone to each scene
	function addLightsToScene(scene: THREE.Scene) {
		const ambientLight = new THREE.AmbientLight(0xffffff, 0.8);
		scene.add(ambientLight);

		const keyLight = new THREE.DirectionalLight(0xffffff, 1.2);
		keyLight.position.set(2, 3, 4);
		scene.add(keyLight);

		const fillLight = new THREE.DirectionalLight(0x99bbff, 0.5);
		fillLight.position.set(-2, -1, 1.5);
		scene.add(fillLight);

		const rimLight = new THREE.DirectionalLight(0xffffff, 0.4);
		rimLight.position.set(0, -2, -3);
		scene.add(rimLight);
	}

	// Per-topology scale and rotation adjustments
	function getTopologyAdjustments(mode: BoundaryMode): {
		scale: number;
		rotationX: number;
		rotationZ: number;
	} {
		switch (mode) {
			case BoundaryMode.Plane:
				return { scale: 0.68, rotationX: 0, rotationZ: 0 };
			case BoundaryMode.CylinderX:
			case BoundaryMode.CylinderY:
				return { scale: 0.55, rotationX: 0, rotationZ: 0 };
			case BoundaryMode.Torus:
				return { scale: 0.78, rotationX: 0.5, rotationZ: 0 }; // Tilted to show spin
			case BoundaryMode.MobiusX:
			case BoundaryMode.MobiusY:
				return { scale: 0.85, rotationX: 0, rotationZ: 0 };
			case BoundaryMode.KleinX:
				return { scale: 0.85, rotationX: 0, rotationZ: 0 };
			case BoundaryMode.KleinY:
				return { scale: 0.85, rotationX: Math.PI / 2, rotationZ: 0 }; // Vertical
			case BoundaryMode.ProjectivePlane:
				return { scale: 1.2, rotationX: 0, rotationZ: 0 }; // Larger Roman
			default:
				return { scale: 0.75, rotationX: 0, rotationZ: 0 };
		}
	}

	// Create a single cell's scene (called progressively)
	function createCellScene(mode: BoundaryMode): CellData {
		const scene = new THREE.Scene();
		addLightsToScene(scene);

		const adjustments = getTopologyAdjustments(mode);

		// Create mesh
		const geometry = getTopologyGeometry(mode);
		const bbox = new THREE.Box3().setFromBufferAttribute(
			geometry.getAttribute('position') as THREE.BufferAttribute
		);
		const center = bbox.getCenter(new THREE.Vector3());
		geometry.translate(-center.x, -center.y, -center.z);

		// Apply initial rotation to geometry if needed
		if (adjustments.rotationX !== 0 || adjustments.rotationZ !== 0) {
			geometry.rotateX(adjustments.rotationX);
			geometry.rotateZ(adjustments.rotationZ);
		}

		const color = getTopologyColor(mode);
		const material = new THREE.MeshPhysicalMaterial({
			color: color,
			vertexColors: true,
			metalness: 0.1,
			roughness: 0.4,
			clearcoat: 0.1,
			emissive: new THREE.Color(0x101520),
			emissiveIntensity: 0.2,
			transparent: false,
			side: THREE.DoubleSide,
			polygonOffset: true,
			polygonOffsetFactor: 1,
			polygonOffsetUnits: 1
		});

		const mesh = new THREE.Mesh(geometry, material);
		mesh.scale.setScalar(adjustments.scale);
		scene.add(mesh);

		// Grid lines
		const gridGeometry = getTopologyGridGeometry(mode);
		gridGeometry.translate(-center.x, -center.y, -center.z);
		if (adjustments.rotationX !== 0 || adjustments.rotationZ !== 0) {
			gridGeometry.rotateX(adjustments.rotationX);
			gridGeometry.rotateZ(adjustments.rotationZ);
		}
		const gridMaterial = new THREE.LineBasicMaterial({
			color: 0xffffff,
			transparent: true,
			opacity: 0.25,
			depthTest: true,
			depthWrite: false
		});
		const gridLines = new THREE.LineSegments(gridGeometry, gridMaterial);
		gridLines.scale.setScalar(adjustments.scale * 0.998);
		scene.add(gridLines);

		// Edge lines
		const edgeGeometries = getTopologyEdgeGeometries(mode);

		// Apply transformations to edge geometries
		if (edgeGeometries.free) {
			edgeGeometries.free.translate(-center.x, -center.y, -center.z);
			if (adjustments.rotationX !== 0 || adjustments.rotationZ !== 0) {
				edgeGeometries.free.rotateX(adjustments.rotationX);
				edgeGeometries.free.rotateZ(adjustments.rotationZ);
			}
		}
		if (edgeGeometries.stitch) {
			edgeGeometries.stitch.translate(-center.x, -center.y, -center.z);
			if (adjustments.rotationX !== 0 || adjustments.rotationZ !== 0) {
				edgeGeometries.stitch.rotateX(adjustments.rotationX);
				edgeGeometries.stitch.rotateZ(adjustments.rotationZ);
			}
		}

		const edgeMaterial = new LineMaterial({
			color: 0xffffff,
			transparent: true,
			opacity: 1.0,
			linewidth: 0.4,
			worldUnits: false,
			depthTest: true,
			depthWrite: true
		});

		const cellSize = Math.floor((mainCanvas?.clientWidth || 210) / 3);
		edgeMaterial.resolution.set(cellSize, cellSize);

		const edgeLines: Line2[] = [];

		const createEdgeLines = (positions: Float32Array | number[]) => {
			const arr = Array.from(positions);
			if (arr.length < 6) return;

			const epsilon = 0.0001;
			let polylinePoints: number[] = [];

			const finishCurve = () => {
				if (polylinePoints.length >= 6) {
					const lineGeometry = new LineGeometry();
					lineGeometry.setPositions(polylinePoints);
					const line = new Line2(lineGeometry, edgeMaterial);
					line.computeLineDistances();
					line.scale.setScalar(adjustments.scale * 1.002);
					scene.add(line);
					edgeLines.push(line);
				}
				polylinePoints = [];
			};

			for (let segIdx = 0; segIdx < arr.length / 6; segIdx++) {
				const base = segIdx * 6;
				// Positions are already transformed, just use them directly
				const p1 = [arr[base], arr[base + 1], arr[base + 2]];
				const p2 = [arr[base + 3], arr[base + 4], arr[base + 5]];

				if (polylinePoints.length === 0) {
					polylinePoints.push(...p1, ...p2);
				} else {
					const lastIdx = polylinePoints.length - 3;
					const dist = Math.sqrt(
						(p1[0] - polylinePoints[lastIdx]) ** 2 +
							(p1[1] - polylinePoints[lastIdx + 1]) ** 2 +
							(p1[2] - polylinePoints[lastIdx + 2]) ** 2
					);
					if (dist < epsilon) {
						polylinePoints.push(...p2);
					} else {
						finishCurve();
						polylinePoints.push(...p1, ...p2);
					}
				}
			}
			finishCurve();
		};

		if (edgeGeometries.free) {
			const pos = edgeGeometries.free.getAttribute('position') as THREE.BufferAttribute;
			createEdgeLines(pos.array as Float32Array);
		}
		if (edgeGeometries.stitch) {
			const pos = edgeGeometries.stitch.getAttribute('position') as THREE.BufferAttribute;
			createEdgeLines(pos.array as Float32Array);
		}

		return {
			scene,
			mesh,
			gridLines,
			edgeLines,
			edgeMaterial,
			mode,
			loaded: true
		};
	}

	// Progressive loading - load one cell per frame
	function loadNextCell() {
		if (loadIndex >= 9) return;

		const mode = FLAT_GRID[loadIndex].mode;
		cells[loadIndex] = createCellScene(mode);
		loadIndex++;

		// Schedule next load
		if (loadIndex < 9) {
			requestAnimationFrame(loadNextCell);
		}
	}

	function initRenderer(canvas: HTMLCanvasElement) {
		if (isInitialized) return;
		isInitialized = true;
		mainCanvas = canvas;

		renderer = new THREE.WebGLRenderer({
			canvas,
			antialias: true,
			alpha: true
		});
		renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
		renderer.setSize(canvas.clientWidth, canvas.clientHeight, false);
		renderer.setClearColor(0x000000, 0);
		renderer.setScissorTest(true);

		camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
		camera.position.set(0, 0.8, 2.6); // Slightly above, looking down
		camera.lookAt(0, 0, 0);

		startTime = performance.now();
		rotationY = 0;
		loadIndex = 0;

		// Start progressive loading
		requestAnimationFrame(loadNextCell);

		// Start animation loop
		animate();
	}

	function animate() {
		animationId = requestAnimationFrame(animate);

		if (!renderer || !camera || !mainCanvas) return;

		const canvasWidth = mainCanvas.clientWidth;
		const canvasHeight = mainCanvas.clientHeight;
		const cellWidth = Math.floor(canvasWidth / 3);
		const cellHeight = Math.floor(canvasHeight / 3);

		rotationY += 0.012;
		const elapsed = (performance.now() - startTime) * 0.001;
		const rotationX = 0.25 + Math.sin(elapsed * 0.4) * 0.15;

		// Clear the entire canvas
		renderer.setScissor(0, 0, canvasWidth, canvasHeight);
		renderer.setViewport(0, 0, canvasWidth, canvasHeight);
		renderer.clear();

		// Render each cell
		for (let i = 0; i < 9; i++) {
			const cell = cells[i];
			if (!cell) continue;

			const row = Math.floor(i / 3);
			const col = i % 3;

			// Calculate viewport (Y is flipped in WebGL)
			const x = col * cellWidth;
			const y = (2 - row) * cellHeight;

			const isSelected = cell.mode === currentMode;

			// Update material brightness based on selection
			const mat = cell.mesh.material as THREE.MeshPhysicalMaterial;
			const targetEmissive = isSelected ? 0.35 : 0.15;
			mat.emissiveIntensity = THREE.MathUtils.lerp(mat.emissiveIntensity, targetEmissive, 0.1);

			// Adjust color saturation for selected vs unselected
			const baseColor = new THREE.Color(getTopologyColor(cell.mode));
			if (isSelected) {
				mat.color.copy(baseColor);
			} else {
				// Keep more of the original color - only slightly desaturate
				const desaturated = baseColor.clone();
				const hsl = { h: 0, s: 0, l: 0 };
				desaturated.getHSL(hsl);
				desaturated.setHSL(hsl.h, hsl.s * 0.75, hsl.l * 0.9);
				mat.color.copy(desaturated);
			}

			// Grid opacity
			const gridMat = cell.gridLines.material as THREE.LineBasicMaterial;
			gridMat.opacity = isSelected ? 0.25 : 0.12;

			// Edge opacity
			cell.edgeMaterial.opacity = isSelected ? 1.0 : 0.5;

			// Rotate
			cell.mesh.rotation.x = rotationX;
			cell.mesh.rotation.y = rotationY;
			cell.gridLines.rotation.x = rotationX;
			cell.gridLines.rotation.y = rotationY;
			for (const line of cell.edgeLines) {
				line.rotation.x = rotationX;
				line.rotation.y = rotationY;
			}

			// Render this cell
			renderer.setScissor(x, y, cellWidth, cellHeight);
			renderer.setViewport(x, y, cellWidth, cellHeight);
			renderer.render(cell.scene, camera);
		}
	}

	function disposeAll() {
		if (animationId) {
			cancelAnimationFrame(animationId);
			animationId = null;
		}

		for (const cell of cells) {
			if (cell) {
				cell.mesh.geometry.dispose();
				(cell.mesh.material as THREE.Material).dispose();
				cell.gridLines.geometry.dispose();
				(cell.gridLines.material as THREE.Material).dispose();
				for (const line of cell.edgeLines) {
					line.geometry.dispose();
				}
				cell.edgeMaterial.dispose();
			}
		}
		cells = Array(9).fill(null);

		renderer?.dispose();
		renderer = null;
		camera = null;
		mainCanvas = null;
		isInitialized = false;
		loadIndex = 0;
	}

	function canvasAction(node: HTMLCanvasElement) {
		initRenderer(node);
		return {
			destroy() {
				disposeAll();
			}
		};
	}

	function handleSelect(mode: BoundaryMode) {
		if (mode !== currentMode) {
			setBoundaryMode(mode);
		}
	}

	function handleKeydown(event: KeyboardEvent, mode: BoundaryMode) {
		if (event.key === 'Enter' || event.key === ' ') {
			event.preventDefault();
			handleSelect(mode);
		}
	}

	// Get cell position for click handling
	function handleCanvasClick(event: MouseEvent) {
		if (!mainCanvas) return;

		const rect = mainCanvas.getBoundingClientRect();
		const x = event.clientX - rect.left;
		const y = event.clientY - rect.top;

		const cellWidth = rect.width / 3;
		const cellHeight = rect.height / 3;

		const col = Math.floor(x / cellWidth);
		const row = Math.floor(y / cellHeight);

		if (col >= 0 && col < 3 && row >= 0 && row < 3) {
			const mode = GRID[row][col].mode;
			handleSelect(mode);
		}
	}

	// Cleanup on destroy
	$effect(() => {
		return () => {
			disposeAll();
		};
	});
</script>

<div class="topology-grid">
	<canvas
		class="grid-canvas"
		use:canvasAction
		onclick={handleCanvasClick}
		onkeydown={(e) => {
			if (e.key === 'Enter' || e.key === ' ') handleCanvasClick(e as unknown as MouseEvent);
		}}
		role="grid"
		tabindex="0"
		aria-label="Topology selection grid"
	></canvas>

	<!-- Overlay for labels and selection indicators -->
	<div class="labels-overlay">
		{#each GRID as row, rowIdx (rowIdx)}
			<div class="label-row">
				{#each row as cell (cell.mode)}
					{@const isSelected = cell.mode === currentMode}
					<div
						class="label-cell"
						class:selected={isSelected}
						onclick={() => handleSelect(cell.mode)}
						onkeydown={(e) => handleKeydown(e, cell.mode)}
						role="button"
						tabindex="0"
						title={cell.name}
					>
						<span class="cell-label">{cell.name}</span>
					</div>
				{/each}
			</div>
		{/each}
	</div>
</div>

<style>
	.topology-grid {
		position: relative;
		width: 100%;
		aspect-ratio: 1;
	}

	.grid-canvas {
		width: 100%;
		height: 100%;
		display: block;
		border-radius: 8px;
		cursor: pointer;
	}

	.labels-overlay {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		bottom: 0;
		display: flex;
		flex-direction: column;
		pointer-events: none;
	}

	.label-row {
		flex: 1;
		display: flex;
	}

	.label-cell {
		flex: 1;
		display: flex;
		align-items: flex-end;
		justify-content: center;
		padding-bottom: 2px;
		border: 1.5px solid transparent;
		border-radius: 6px;
		margin: 1px;
		pointer-events: auto;
		cursor: pointer;
		transition: all 0.2s ease;
	}

	.label-cell:hover {
		background: rgba(255, 255, 255, 0.04);
		border-color: rgba(255, 255, 255, 0.12);
	}

	.label-cell.selected {
		border-color: rgba(124, 154, 255, 0.5);
		box-shadow: 0 0 10px rgba(124, 154, 255, 0.15);
	}

	.cell-label {
		font-size: 6px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.4);
		text-transform: uppercase;
		letter-spacing: 0.2px;
		transition: color 0.2s ease;
	}

	.label-cell.selected .cell-label {
		color: rgba(185, 199, 255, 0.9);
	}

	.label-cell:hover .cell-label {
		color: rgba(255, 255, 255, 0.7);
	}
</style>
