<script lang="ts">
	import * as THREE from 'three';
	import { Line2 } from 'three/addons/lines/Line2.js';
	import { LineGeometry } from 'three/addons/lines/LineGeometry.js';
	import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
	import { getTopologyGeometry, getTopologyColor, getTopologyGridGeometry, getTopologyEdgeGeometries, TOPOLOGY_NAMES } from '$lib/utils/topologyMeshes';
	import { setBoundaryMode, BoundaryMode } from '$lib/stores/simulation';

	interface Props {
		currentMode: BoundaryMode;
	}

	let { currentMode }: Props = $props();

	// 3D Viewer state
	let renderer: THREE.WebGLRenderer | null = null;
	let scene: THREE.Scene | null = null;
	let camera: THREE.PerspectiveCamera | null = null;
	let mesh: THREE.Mesh | null = null;
	let gridLines: THREE.LineSegments | null = null;
	let edgeLines: Line2[] = [];
	let edgeMaterial: LineMaterial | null = null;
	let animationId: number | null = null;
	let canvasEl: HTMLCanvasElement | null = null;
	let isContextLost = false;
	let rotationX = 0.3;
	let rotationY = 0;
	let lastWidth = 0;
	let lastHeight = 0;
	let startTime = 0;

	// Edge types
	type EdgeType = 'bounce' | 'wrap' | 'wrapFlip';

	// Current displayed mode (non-reactive)
	let displayedMode = -1;

	// Derive edge config from current mode
	function getEdgesFromMode(mode: BoundaryMode): { x: EdgeType; y: EdgeType } {
		switch (mode) {
			case BoundaryMode.Plane:
				return { x: 'bounce', y: 'bounce' };
			case BoundaryMode.CylinderX:
				return { x: 'wrap', y: 'bounce' };
			case BoundaryMode.CylinderY:
				return { x: 'bounce', y: 'wrap' };
			case BoundaryMode.Torus:
				return { x: 'wrap', y: 'wrap' };
			case BoundaryMode.MobiusX:
				return { x: 'wrapFlip', y: 'bounce' };
			case BoundaryMode.MobiusY:
				return { x: 'bounce', y: 'wrapFlip' };
			case BoundaryMode.KleinX:
				return { x: 'wrapFlip', y: 'wrap' };
			case BoundaryMode.KleinY:
				return { x: 'wrap', y: 'wrapFlip' };
			case BoundaryMode.ProjectivePlane:
				return { x: 'wrapFlip', y: 'wrapFlip' };
			default:
				return { x: 'bounce', y: 'bounce' };
		}
	}

	// Derive mode from edge config
	function getModeFromEdges(x: EdgeType, y: EdgeType): BoundaryMode {
		if (x === 'bounce' && y === 'bounce') return BoundaryMode.Plane;
		if (x === 'wrap' && y === 'bounce') return BoundaryMode.CylinderX;
		if (x === 'bounce' && y === 'wrap') return BoundaryMode.CylinderY;
		if (x === 'wrap' && y === 'wrap') return BoundaryMode.Torus;
		if (x === 'wrapFlip' && y === 'bounce') return BoundaryMode.MobiusX;
		if (x === 'bounce' && y === 'wrapFlip') return BoundaryMode.MobiusY;
		if (x === 'wrapFlip' && y === 'wrap') return BoundaryMode.KleinX;
		if (x === 'wrap' && y === 'wrapFlip') return BoundaryMode.KleinY;
		if (x === 'wrapFlip' && y === 'wrapFlip') return BoundaryMode.ProjectivePlane;
		return BoundaryMode.Plane;
	}

	const xEdge = $derived(getEdgesFromMode(currentMode).x);
	const yEdge = $derived(getEdgesFromMode(currentMode).y);

	function setXEdge(type: EdgeType) {
		setBoundaryMode(getModeFromEdges(type, yEdge));
	}

	function setYEdge(type: EdgeType) {
		setBoundaryMode(getModeFromEdges(xEdge, type));
	}

	function initThree(canvas: HTMLCanvasElement) {
		canvasEl = canvas;
		scene = new THREE.Scene();
		camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
		camera.position.z = 2.5;

		renderer = new THREE.WebGLRenderer({
			canvas,
			antialias: true,
			alpha: true
		});
		renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
		resizeRendererToDisplaySize();
		renderer.setClearColor(0x000000, 0);

		// Lighting
		const ambientLight = new THREE.AmbientLight(0xffffff, 0.45);
		scene.add(ambientLight);

		const keyLight = new THREE.DirectionalLight(0xffffff, 0.85);
		keyLight.position.set(2, 3, 4);
		scene.add(keyLight);

		const fillLight = new THREE.DirectionalLight(0x88aaff, 0.35);
		fillLight.position.set(-2, -1, 1.5);
		scene.add(fillLight);

		const rimLight = new THREE.DirectionalLight(0xffffff, 0.3);
		rimLight.position.set(0, 0, -3.5);
		scene.add(rimLight);

		startTime = performance.now();
		updateMesh(currentMode);
		animate();
	}

	function updateMesh(mode: number) {
		if (!scene) return;
		if (displayedMode === mode) return;

		if (mesh) {
			scene.remove(mesh);
			mesh.geometry.dispose();
			(mesh.material as THREE.Material).dispose();
		}
		if (gridLines) {
			scene.remove(gridLines);
			gridLines.geometry.dispose();
			(gridLines.material as THREE.Material).dispose();
			gridLines = null;
		}
		for (const line of edgeLines) {
			scene.remove(line);
			line.geometry.dispose();
		}
		edgeLines = [];
		edgeMaterial?.dispose();
		edgeMaterial = null;

		const geometry = getTopologyGeometry(mode);
		
		// Compute center offset from main geometry
		const bbox = new THREE.Box3().setFromBufferAttribute(geometry.getAttribute('position') as THREE.BufferAttribute);
		const center = bbox.getCenter(new THREE.Vector3());
		geometry.translate(-center.x, -center.y, -center.z);
		
		const color = getTopologyColor(mode);

		const material = new THREE.MeshPhysicalMaterial({
			color: color,
			vertexColors: true,
			metalness: 0.1,
			roughness: 0.38,
			clearcoat: 0.15,
			clearcoatRoughness: 0.35,
			emissive: new THREE.Color(0x1a1d30),
			emissiveIntensity: 0.35,
			transparent: false,
			opacity: 1,
			side: THREE.DoubleSide,
			polygonOffset: true,
			polygonOffsetFactor: 1,
			polygonOffsetUnits: 1
		});

		mesh = new THREE.Mesh(geometry, material);
		mesh.renderOrder = 0;
		mesh.scale.setScalar(0.92);
		scene.add(mesh);

		// Grid lines - apply same center offset, scaled slightly smaller to avoid z-fighting with edges
		const gridGeometry = getTopologyGridGeometry(mode);
		gridGeometry.translate(-center.x, -center.y, -center.z);
		const gridMaterial = new THREE.LineBasicMaterial({
			color: 0xffffff,
			transparent: true,
			opacity: 0.22,
			depthTest: true,
			depthWrite: false
		});
		gridLines = new THREE.LineSegments(gridGeometry, gridMaterial);
		gridLines.renderOrder = 1;
		gridLines.scale.setScalar(0.919); // Slightly smaller than edges (0.922) to prevent z-fighting
		scene.add(gridLines);

		// Edge lines - apply same center offset
		const edgeGeometries = getTopologyEdgeGeometries(mode);
		
		// Create shared material for thick lines
		edgeMaterial = new LineMaterial({
			color: 0xffffff,
			transparent: false,
			opacity: 1.0,
			linewidth: 2,
			worldUnits: false,
			depthTest: true,
			depthWrite: true
		});
		edgeMaterial.resolution.set(lastWidth || 220, lastHeight || 220);
		
		// Helper to create Line2 from segment positions (handles multiple disconnected curves)
		const createEdgeLines = (positions: Float32Array | number[]) => {
			const arr = Array.from(positions);
			if (arr.length < 6) return;
			
			const epsilon = 0.0001;
			let polylinePoints: number[] = [];
			
			const finishCurve = () => {
				if (polylinePoints.length >= 6) {
					const lineGeometry = new LineGeometry();
					lineGeometry.setPositions(polylinePoints);
					const line = new Line2(lineGeometry, edgeMaterial!);
					line.computeLineDistances();
					line.renderOrder = 2;
					line.scale.setScalar(0.922); // Slightly larger than grid (0.92) to prevent z-fighting
					scene!.add(line);
					edgeLines.push(line);
				}
				polylinePoints = [];
			};
			
			// Process segments (each segment is 6 values: 2 points × 3 coords)
			for (let segIdx = 0; segIdx < arr.length / 6; segIdx++) {
				const base = segIdx * 6;
				const p1 = [arr[base] - center.x, arr[base + 1] - center.y, arr[base + 2] - center.z];
				const p2 = [arr[base + 3] - center.x, arr[base + 4] - center.y, arr[base + 5] - center.z];
				
				if (polylinePoints.length === 0) {
					// Start new curve
					polylinePoints.push(...p1, ...p2);
				} else {
					// Check if this segment continues from the last point
					const lastIdx = polylinePoints.length - 3;
					const dist = Math.sqrt(
						(p1[0] - polylinePoints[lastIdx]) ** 2 +
						(p1[1] - polylinePoints[lastIdx + 1]) ** 2 +
						(p1[2] - polylinePoints[lastIdx + 2]) ** 2
					);
					
					if (dist < epsilon) {
						// Continuous - just add the endpoint
						polylinePoints.push(...p2);
					} else {
						// Discontinuity - finish current curve, start new one
						finishCurve();
						polylinePoints.push(...p1, ...p2);
					}
				}
			}
			
			// Finish last curve
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

		displayedMode = mode;
	}

	function resizeRendererToDisplaySize() {
		if (!renderer || !camera || !canvasEl) return;
		const width = canvasEl.clientWidth || 220;
		const height = canvasEl.clientHeight || 220;
		if (width === lastWidth && height === lastHeight) return;
		lastWidth = width;
		lastHeight = height;
		renderer.setSize(width, height, false);
		camera.aspect = width / height;
		camera.updateProjectionMatrix();
		edgeMaterial?.resolution.set(width, height);
	}

	function animate() {
		if (isContextLost) return;
		animationId = requestAnimationFrame(animate);

		if (scene && displayedMode !== currentMode) {
			updateMesh(currentMode);
		}

		resizeRendererToDisplaySize();

		if (!Number.isFinite(rotationX) || !Number.isFinite(rotationY)) {
			rotationX = 0.3;
			rotationY = 0;
		}

		if (mesh && gridLines) {
			rotationY += 0.006;
			const elapsed = (performance.now() - startTime) * 0.001;
			rotationX = 0.25 + Math.sin(elapsed * 0.35) * 0.18;
			mesh.rotation.x = rotationX;
			mesh.rotation.y = rotationY;
			gridLines.rotation.x = rotationX;
			gridLines.rotation.y = rotationY;
			for (const line of edgeLines) {
				line.rotation.x = rotationX;
				line.rotation.y = rotationY;
			}
		}

		if (renderer && scene && camera) {
			renderer.render(scene, camera);
		}
	}

	function handleContextLost(event: Event) {
		event.preventDefault();
		isContextLost = true;
		if (animationId) cancelAnimationFrame(animationId);
	}

	function handleContextRestored() {
		isContextLost = false;
		if (!canvasEl) return;
		disposeThree();
		initThree(canvasEl);
	}

	function disposeThree() {
		if (animationId) cancelAnimationFrame(animationId);
		renderer?.dispose();
		renderer = null;
		scene = null;
		camera = null;
		lastWidth = 0;
		lastHeight = 0;
		if (mesh) {
			mesh.geometry.dispose();
			(mesh.material as THREE.Material).dispose();
			mesh = null;
		}
		if (gridLines) {
			gridLines.geometry.dispose();
			(gridLines.material as THREE.Material).dispose();
			gridLines = null;
		}
		for (const line of edgeLines) {
			line.geometry.dispose();
		}
		edgeLines = [];
		edgeMaterial?.dispose();
		edgeMaterial = null;
	}

	function threeCanvas(node: HTMLCanvasElement) {
		node.addEventListener('webglcontextlost', handleContextLost);
		node.addEventListener('webglcontextrestored', handleContextRestored);
		initThree(node);
		return () => {
			node.removeEventListener('webglcontextlost', handleContextLost);
			node.removeEventListener('webglcontextrestored', handleContextRestored);
			disposeThree();
		};
	}
</script>

<div class="topology-selector">
	<div class="topology-stage">
		<canvas
			class="canvas-container"
			{@attach threeCanvas}
			aria-hidden="true"
		></canvas>

		<!-- Left edge buttons (X axis) -->
		<div class="edge-group vertical left">
			<button
				class="edge-btn"
				class:active={xEdge === 'bounce'}
				onclick={() => setXEdge('bounce')}
				title="Bounce"
			>
				<svg viewBox="0 0 24 24">
					<rect x="5" y="5" width="14" height="14" fill="currentColor" opacity="0.18" />
					<rect x="5" y="5" width="7" height="14" fill="currentColor" opacity="0.6" />
				</svg>
			</button>
			<button
				class="edge-btn"
				class:active={xEdge === 'wrap'}
				onclick={() => setXEdge('wrap')}
				title="Stitch"
			>
				<svg viewBox="0 0 24 24">
					<rect x="5" y="5" width="14" height="14" fill="currentColor" opacity="0.35" />
					<line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2 2" stroke-linecap="butt" />
				</svg>
			</button>
			<button
				class="edge-btn"
				class:active={xEdge === 'wrapFlip'}
				onclick={() => setXEdge('wrapFlip')}
				title="Flip & Stitch"
			>
				<svg viewBox="0 0 24 24">
					<polygon points="5,5 12,12 5,19" fill="currentColor" opacity="0.55" />
					<polygon points="19,5 12,12 19,19" fill="currentColor" opacity="0.55" />
					<line x1="6.5" y1="6.5" x2="17.5" y2="17.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
					<line x1="17.5" y1="6.5" x2="6.5" y2="17.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
				</svg>
			</button>
		</div>

		<!-- Bottom edge buttons (Y axis) -->
		<div class="edge-group horizontal bottom">
			<button
				class="edge-btn"
				class:active={yEdge === 'bounce'}
				onclick={() => setYEdge('bounce')}
				title="Bounce"
			>
				<svg viewBox="0 0 24 24">
					<rect x="5" y="5" width="14" height="14" fill="currentColor" opacity="0.18" />
					<rect x="5" y="12" width="14" height="7" fill="currentColor" opacity="0.6" />
				</svg>
			</button>
			<button
				class="edge-btn"
				class:active={yEdge === 'wrap'}
				onclick={() => setYEdge('wrap')}
				title="Stitch"
			>
				<svg viewBox="0 0 24 24">
					<rect x="5" y="5" width="14" height="14" fill="currentColor" opacity="0.35" />
					<line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2 2" stroke-linecap="butt" />
				</svg>
			</button>
			<button
				class="edge-btn"
				class:active={yEdge === 'wrapFlip'}
				onclick={() => setYEdge('wrapFlip')}
				title="Flip & Stitch"
			>
				<svg viewBox="0 0 24 24">
					<polygon points="5,5 12,12 5,19" fill="currentColor" opacity="0.55" />
					<polygon points="19,5 12,12 19,19" fill="currentColor" opacity="0.55" />
					<line x1="6.5" y1="6.5" x2="17.5" y2="17.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
					<line x1="17.5" y1="6.5" x2="6.5" y2="17.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
				</svg>
			</button>
		</div>

	</div>
</div>

<style>
	.topology-selector {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0;
		padding: 0;
		width: 100%;
	}

	.topology-stage {
		position: relative;
		width: 100%;
		aspect-ratio: 1.1 / 1;
		height: auto;
		padding-left: 36px;
		padding-bottom: 34px;
		box-sizing: border-box;
	}

	.canvas-container {
		width: 100%;
		height: 100%;
		display: block;
		border-radius: 8px;
		overflow: hidden;
		pointer-events: none;
		user-select: none;
		touch-action: none;
		background: transparent;
		border: none;
		box-shadow: none;
	}

	.edge-group.left {
		position: absolute;
		left: 0;
		top: 0;
		height: calc(100% - 36px);
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 4px;
	}

	.edge-group.bottom {
		position: absolute;
		left: 36px;
		right: 0;
		bottom: 0;
		height: 36px;
		display: flex;
		flex-direction: row;
		justify-content: center;
		align-items: center;
		gap: 4px;
	}

	/* Edge button groups */
	.edge-group {
		display: flex;
	}

	.edge-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		background: rgba(255, 255, 255, 0.03);
		border: 1.5px solid transparent;
		border-radius: 6px;
		cursor: pointer;
		transition: all 0.15s ease;
		color: rgba(255, 255, 255, 0.4);
		padding: 4px;
	}

	.edge-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: rgba(255, 255, 255, 0.7);
	}

	.edge-btn.active {
		background: rgba(185, 199, 255, 0.1);
		border-color: rgba(185, 199, 255, 0.5);
		color: #b9c7ff;
	}

	.edge-btn svg {
		width: 100%;
		height: 100%;
	}

</style>
