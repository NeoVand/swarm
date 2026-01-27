<script lang="ts">
	import { type CurvePoint, monotonicCubicInterpolation } from '$lib/stores/simulation';
	import { slide } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';

	// Props - simplified: no enabled toggle, curves are always active
	interface Props {
		points: CurvePoint[];
		onPointsChange: (points: CurvePoint[]) => void;
		label?: string;
	}

	let { points, onPointsChange, label = 'Curve' }: Props = $props();

	// SVG dimensions
	const width = 200;
	const height = 120;
	const padding = { top: 8, right: 8, bottom: 14, left: 16 };
	const plotWidth = width - padding.left - padding.right;
	const plotHeight = height - padding.top - padding.bottom;

	// State
	let svgElement: SVGSVGElement | null = $state(null);
	let draggingIndex: number | null = $state(null);
	let presetDropdownOpen = $state(false);

	// Coordinate conversions
	function toSvgX(x: number): number {
		return padding.left + x * plotWidth;
	}

	function toSvgY(y: number): number {
		return padding.top + (1 - y) * plotHeight;
	}

	function fromSvgX(svgX: number): number {
		return Math.max(0, Math.min(1, (svgX - padding.left) / plotWidth));
	}

	function fromSvgY(svgY: number): number {
		return Math.max(0, Math.min(1, 1 - (svgY - padding.top) / plotHeight));
	}

	// Check if a point is an anchor (x=0 or x=1)
	function isAnchorX(index: number): boolean {
		const p = points[index];
		return p.x === 0 || p.x === 1;
	}

	// Generate curve path using monotonic cubic interpolation
	function getCurvePath(): string {
		if (points.length < 2) return '';

		const samples = 50;
		let path = '';

		for (let i = 0; i <= samples; i++) {
			const x = i / samples;
			const y = monotonicCubicInterpolation(points, x);
			const svgX = toSvgX(x);
			const svgY = toSvgY(y);

			if (i === 0) {
				path = `M ${svgX} ${svgY}`;
			} else {
				path += ` L ${svgX} ${svgY}`;
			}
		}

		return path;
	}

	// Grid lines
	const gridLinesX = [0.25, 0.5, 0.75];
	const gridLinesY = [0.25, 0.5, 0.75];

	// Point dragging
	function handlePointMouseDown(index: number, e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();
		draggingIndex = index;
		window.addEventListener('mousemove', handleMouseMove);
		window.addEventListener('mouseup', handleMouseUp);
	}

	function handleMouseMove(e: MouseEvent) {
		if (draggingIndex === null || !svgElement) return;

		const rect = svgElement.getBoundingClientRect();
		const scaleX = width / rect.width;
		const scaleY = height / rect.height;

		const svgX = (e.clientX - rect.left) * scaleX;
		const svgY = (e.clientY - rect.top) * scaleY;

		let newX = fromSvgX(svgX);
		const newY = fromSvgY(svgY);

		// Sort points to find neighbors
		const sortedWithIndex = points
			.map((p, i) => ({ ...p, originalIndex: i }))
			.sort((a, b) => a.x - b.x);
		const sortedPos = sortedWithIndex.findIndex((p) => p.originalIndex === draggingIndex);

		// Constrain X to not cross neighbors (except for anchor points)
		if (!isAnchorX(draggingIndex)) {
			const prevPoint = sortedPos > 0 ? sortedWithIndex[sortedPos - 1] : null;
			const nextPoint =
				sortedPos < sortedWithIndex.length - 1 ? sortedWithIndex[sortedPos + 1] : null;

			const minX = prevPoint ? prevPoint.x + 0.02 : 0.02;
			const maxX = nextPoint ? nextPoint.x - 0.02 : 0.98;
			newX = Math.max(minX, Math.min(maxX, newX));
		} else {
			// Anchor points can only move vertically
			newX = points[draggingIndex].x;
		}

		// Update point
		const newPoints = [...points];
		newPoints[draggingIndex] = { x: newX, y: newY };
		onPointsChange(newPoints);
	}

	function handleMouseUp() {
		draggingIndex = null;
		window.removeEventListener('mousemove', handleMouseMove);
		window.removeEventListener('mouseup', handleMouseUp);
	}

	// Add new point on click
	function handleSvgClick(e: MouseEvent) {
		if (!svgElement || draggingIndex !== null) return;

		const rect = svgElement.getBoundingClientRect();
		const scaleX = width / rect.width;
		const scaleY = height / rect.height;

		const svgX = (e.clientX - rect.left) * scaleX;
		const svgY = (e.clientY - rect.top) * scaleY;

		// Check if click is in plot area
		if (
			svgX < padding.left ||
			svgX > width - padding.right ||
			svgY < padding.top ||
			svgY > height - padding.bottom
		) {
			return;
		}

		const newX = fromSvgX(svgX);
		const newY = fromSvgY(svgY);

		// Don't add if too close to existing point
		if (points.some((p) => Math.abs(p.x - newX) < 0.04)) return;

		// Add new point and sort
		const newPoints = [...points, { x: newX, y: newY }].sort((a, b) => a.x - b.x);
		onPointsChange(newPoints);
	}

	// Delete point on double click
	function handlePointDoubleClick(index: number, e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();

		// Don't delete anchor points (x=0 or x=1)
		if (isAnchorX(index)) return;

		// Don't delete if only 2 points left
		if (points.length <= 2) return;

		const newPoints = points.filter((_, i) => i !== index);
		onPointsChange(newPoints);
	}

	// Presets
	const presets = [
		{ id: 'linear', name: 'Linear', points: [{ x: 0, y: 0 }, { x: 1, y: 1 }] },
		{
			id: 'soft',
			name: 'S-curve',
			points: [
				{ x: 0, y: 0 },
				{ x: 0.25, y: 0.1 },
				{ x: 0.75, y: 0.9 },
				{ x: 1, y: 1 }
			]
		},
		{
			id: 'sqrt',
			name: 'Boost Low',
			points: [
				{ x: 0, y: 0 },
				{ x: 0.25, y: 0.5 },
				{ x: 1, y: 1 }
			]
		},
		{
			id: 'pow',
			name: 'Boost High',
			points: [
				{ x: 0, y: 0 },
				{ x: 0.75, y: 0.5 },
				{ x: 1, y: 1 }
			]
		},
		{ id: 'inverted', name: 'Inverted', points: [{ x: 0, y: 1 }, { x: 1, y: 0 }] }
	];

	function applyPreset(preset: (typeof presets)[0]) {
		onPointsChange([...preset.points]);
		presetDropdownOpen = false;
	}

	// Derived values
	const curvePath = $derived(getCurvePath());
</script>

<div class="curve-editor">
	<div class="header">
		<span class="curve-label">{label}</span>
		<div class="preset-dropdown">
			<button
				class="preset-btn"
				onclick={() => (presetDropdownOpen = !presetDropdownOpen)}
			>
				Presets
			</button>
			{#if presetDropdownOpen}
				<div class="preset-menu" transition:slide={{ duration: 100, easing: cubicOut }}>
					{#each presets as preset}
						<button class="preset-item" onclick={() => applyPreset(preset)}>
							{preset.name}
						</button>
					{/each}
				</div>
			{/if}
		</div>
	</div>

	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<svg
		bind:this={svgElement}
		{width}
		{height}
		viewBox="0 0 {width} {height}"
		class="curve-svg"
		role="application"
		aria-label="Curve editor - click to add points"
		onclick={handleSvgClick}
	>
		<!-- Background -->
		<rect
			x={padding.left}
			y={padding.top}
			width={plotWidth}
			height={plotHeight}
			fill="rgba(0,0,0,0.3)"
			rx="2"
		/>

		<!-- Grid lines -->
		{#each gridLinesX as gx}
			<line
				x1={toSvgX(gx)}
				y1={padding.top}
				x2={toSvgX(gx)}
				y2={height - padding.bottom}
				stroke="rgba(255,255,255,0.1)"
				stroke-width="1"
			/>
		{/each}
		{#each gridLinesY as gy}
			<line
				x1={padding.left}
				y1={toSvgY(gy)}
				x2={width - padding.right}
				y2={toSvgY(gy)}
				stroke="rgba(255,255,255,0.1)"
				stroke-width="1"
			/>
		{/each}

		<!-- Diagonal reference (identity line) -->
		<line
			x1={toSvgX(0)}
			y1={toSvgY(0)}
			x2={toSvgX(1)}
			y2={toSvgY(1)}
			stroke="rgba(255,255,255,0.15)"
			stroke-width="1"
			stroke-dasharray="3,3"
		/>

		<!-- Curve path -->
		<path d={curvePath} fill="none" stroke="#4af" stroke-width="2" />

		<!-- Control points -->
		{#each points as point, index}
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<!-- svelte-ignore a11y_interactive_supports_focus -->
			<circle
				cx={toSvgX(point.x)}
				cy={toSvgY(point.y)}
				r={draggingIndex === index ? 6 : 5}
				fill={isAnchorX(index) ? '#f80' : '#fff'}
				stroke="#000"
				stroke-width="1.5"
				class="control-point"
				class:dragging={draggingIndex === index}
				role="button"
				aria-label="Control point {index + 1}"
				onmousedown={(e) => handlePointMouseDown(index, e)}
				ondblclick={(e) => handlePointDoubleClick(index, e)}
			/>
		{/each}

		<!-- Axis labels -->
		<text x={padding.left} y={height - 2} fill="rgba(255,255,255,0.4)" font-size="8">0</text>
		<text x={width - padding.right} y={height - 2} fill="rgba(255,255,255,0.4)" font-size="8" text-anchor="end">1</text>
		<text x={2} y={toSvgY(0)} fill="rgba(255,255,255,0.4)" font-size="8" dominant-baseline="middle">0</text>
		<text x={2} y={toSvgY(1)} fill="rgba(255,255,255,0.4)" font-size="8" dominant-baseline="middle">1</text>
	</svg>

	<div class="hint">Click to add, double-click to delete</div>
</div>

<style>
	.curve-editor {
		background: rgba(0, 0, 0, 0.2);
		border-radius: 4px;
		padding: 6px;
		margin-top: 4px;
	}

	.header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 4px;
	}

	.curve-label {
		font-size: 9px;
		color: rgba(255, 255, 255, 0.6);
	}

	.preset-dropdown {
		position: relative;
	}

	.preset-btn {
		background: rgba(255, 255, 255, 0.1);
		border: none;
		border-radius: 3px;
		padding: 2px 6px;
		font-size: 9px;
		color: rgba(255, 255, 255, 0.7);
		cursor: pointer;
	}

	.preset-btn:hover {
		background: rgba(255, 255, 255, 0.2);
	}

	.preset-menu {
		position: absolute;
		top: 100%;
		right: 0;
		background: #1a1a1a;
		border: 1px solid rgba(255, 255, 255, 0.2);
		border-radius: 4px;
		padding: 4px;
		z-index: 100;
		min-width: 80px;
	}

	.preset-item {
		display: block;
		width: 100%;
		background: none;
		border: none;
		padding: 4px 8px;
		font-size: 9px;
		color: rgba(255, 255, 255, 0.8);
		text-align: left;
		cursor: pointer;
		border-radius: 2px;
	}

	.preset-item:hover {
		background: rgba(255, 255, 255, 0.1);
	}

	.curve-svg {
		display: block;
		width: 100%;
		height: auto;
		cursor: crosshair;
	}

	.control-point {
		cursor: grab;
		transition: r 0.1s ease;
	}

	.control-point:hover {
		r: 7;
	}

	.control-point.dragging {
		cursor: grabbing;
	}

	.hint {
		font-size: 8px;
		color: rgba(255, 255, 255, 0.35);
		text-align: center;
		margin-top: 2px;
	}
</style>
