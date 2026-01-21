<script lang="ts">
	/**
	 * InfluenceCurveEditor - Interactive SVG-based curve editor for CA influence curves.
	 *
	 * Features:
	 * - Draggable control points
	 * - Click to add new points
	 * - Double-click to delete points
	 * - Profile presets for common curve shapes
	 * - Monotonic cubic Hermite interpolation for smooth curves
	 * - Color gradient visualization
	 */

	import type { CurvePoint } from '$lib/webgpu/types';
	import { CURVE_PRESETS, type CurvePresetName } from '$lib/webgpu/types';

	interface Props {
		/** Current curve control points */
		points: CurvePoint[];
		/** Callback when points change */
		onChange: (points: CurvePoint[]) => void;
		/** Editor width in pixels */
		width?: number;
		/** Editor height in pixels */
		height?: number;
		/** Minimum Y value */
		yMin?: number;
		/** Maximum Y value */
		yMax?: number;
		/** Label for the curve */
		label?: string;
		/** X-axis label (what the input represents) */
		xAxisLabel?: string;
		/** Y-axis label (what the output represents) */
		yAxisLabel?: string;
		/** Whether to show the preset dropdown */
		showPresets?: boolean;
		/** Color for the curve line */
		curveColor?: string;
		/** Whether to show a color gradient on the curve */
		showGradient?: boolean;
	}

	let {
		points = $bindable(),
		onChange,
		width = 240,
		height = 120,
		yMin = -2,
		yMax = 2,
		label = '',
		xAxisLabel = 'Input',
		yAxisLabel = 'Output',
		showPresets = true,
		curveColor = '#4ade80',
		showGradient = false
	}: Props = $props();

	// Padding for axes and labels - increased right padding for axis label
	const padding = { top: 12, right: 16, bottom: 28, left: 32 };

	// Computed dimensions
	const plotWidth = $derived(width - padding.left - padding.right);
	const plotHeight = $derived(height - padding.top - padding.bottom);
	const yRange = $derived(yMax - yMin);

	// State
	let draggingIndex = $state<number | null>(null);
	let svgElement = $state<SVGSVGElement | null>(null);
	let hoveredIndex = $state<number | null>(null);
	let hoverValue = $state<{ x: number; y: number } | null>(null);

	// Currently selected preset (for UI feedback)
	let selectedPreset = $state<CurvePresetName | 'custom'>('custom');

	// ========================================================================
	// Coordinate transforms
	// ========================================================================

	function toSvgX(x: number): number {
		return padding.left + x * plotWidth;
	}

	function toSvgY(y: number): number {
		return padding.top + ((yMax - y) * plotHeight) / yRange;
	}

	function fromSvgX(svgX: number): number {
		return Math.max(0, Math.min(1, (svgX - padding.left) / plotWidth));
	}

	function fromSvgY(svgY: number): number {
		return Math.max(yMin, Math.min(yMax, yMax - ((svgY - padding.top) * yRange) / plotHeight));
	}

	// ========================================================================
	// Monotonic cubic Hermite interpolation
	// ========================================================================

	function monotonicCubicInterpolation(pts: CurvePoint[], xVal: number): number {
		const n = pts.length;
		if (n === 0) return 0;
		if (n === 1) return pts[0].y;

		const sorted = [...pts].sort((a, b) => a.x - b.x);

		if (xVal <= sorted[0].x) return sorted[0].y;
		if (xVal >= sorted[n - 1].x) return sorted[n - 1].y;

		let i = 0;
		while (i < n - 1 && sorted[i + 1].x < xVal) i++;

		const deltas: number[] = [];
		const slopes: number[] = [];
		for (let j = 0; j < n - 1; j++) {
			const dx = sorted[j + 1].x - sorted[j].x;
			deltas.push(dx);
			slopes.push(dx === 0 ? 0 : (sorted[j + 1].y - sorted[j].y) / dx);
		}

		const tangents: number[] = [];
		for (let j = 0; j < n; j++) {
			if (j === 0) {
				tangents.push(slopes[0]);
			} else if (j === n - 1) {
				tangents.push(slopes[n - 2]);
			} else {
				const m0 = slopes[j - 1];
				const m1 = slopes[j];
				if (m0 * m1 <= 0) {
					tangents.push(0);
				} else {
					const w0 = 2 * deltas[j] + deltas[j - 1];
					const w1 = deltas[j] + 2 * deltas[j - 1];
					tangents.push((w0 + w1) / (w0 / m0 + w1 / m1));
				}
			}
		}

		// Ensure monotonicity
		for (let j = 0; j < n - 1; j++) {
			const m = slopes[j];
			if (m === 0) {
				tangents[j] = 0;
				tangents[j + 1] = 0;
			} else {
				const alpha = tangents[j] / m;
				const beta = tangents[j + 1] / m;
				const tau = alpha * alpha + beta * beta;
				if (tau > 9) {
					const s = 3 / Math.sqrt(tau);
					tangents[j] = s * alpha * m;
					tangents[j + 1] = s * beta * m;
				}
			}
		}

		const x0 = sorted[i].x;
		const x1 = sorted[i + 1].x;
		const y0 = sorted[i].y;
		const y1 = sorted[i + 1].y;
		const h = x1 - x0;
		const t = (xVal - x0) / h;
		const t2 = t * t;
		const t3 = t2 * t;

		const h00 = 2 * t3 - 3 * t2 + 1;
		const h10 = t3 - 2 * t2 + t;
		const h01 = -2 * t3 + 3 * t2;
		const h11 = t3 - t2;

		return h00 * y0 + h10 * h * tangents[i] + h01 * y1 + h11 * h * tangents[i + 1];
	}

	// ========================================================================
	// Generate SVG path for the curve
	// ========================================================================

	const curvePath = $derived.by(() => {
		if (points.length < 2) return '';

		const segments: string[] = [];
		const numSamples = 100;

		for (let i = 0; i <= numSamples; i++) {
			const x = i / numSamples;
			const y = monotonicCubicInterpolation(points, x);
			const svgX = toSvgX(x);
			const svgY = toSvgY(y);

			if (i === 0) {
				segments.push(`M ${svgX} ${svgY}`);
			} else {
				segments.push(`L ${svgX} ${svgY}`);
			}
		}

		return segments.join(' ');
	});

	// ========================================================================
	// Grid lines
	// ========================================================================

	const gridLinesY = $derived.by(() => {
		const lines: Array<{ y: number; label: string }> = [];
		const step = yRange <= 2 ? 0.5 : 1;
		for (let y = yMin; y <= yMax; y += step) {
			lines.push({ y, label: y.toString() });
		}
		return lines;
	});

	// ========================================================================
	// Point interaction
	// ========================================================================

	function isEndpoint(index: number): boolean {
		if (points.length < 2) return false;
		const sorted = [...points].sort((a, b) => a.x - b.x);
		return points[index].x === sorted[sorted.length - 1].x;
	}

	function isAnchorPoint(index: number): boolean {
		if (points.length < 2) return false;
		const sorted = [...points].sort((a, b) => a.x - b.x);
		return points[index].x === sorted[0].x;
	}

	function handlePointMouseDown(index: number, e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();

		// Don't allow dragging the leftmost anchor point horizontally
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

		updateDraggedPoint(svgX, svgY);
	}

	function updateDraggedPoint(svgX: number, svgY: number) {
		if (draggingIndex === null) return;

		let newX = fromSvgX(svgX);
		const newY = fromSvgY(svgY);

		// Find neighboring points to prevent crossing
		const sortedWithIdx = points.map((p, i) => ({ x: p.x, idx: i })).sort((a, b) => a.x - b.x);
		const sortedPos = sortedWithIdx.findIndex((p) => p.idx === draggingIndex);

		const prevX = sortedPos > 0 ? sortedWithIdx[sortedPos - 1].x : -Infinity;
		const nextX =
			sortedPos < sortedWithIdx.length - 1 ? sortedWithIdx[sortedPos + 1].x : Infinity;

		// Constrain X to prevent crossing
		const minX = Math.max(0.02, prevX + 0.02);
		const maxX = Math.min(0.98, nextX - 0.02);

		// Anchor point (leftmost) can only move vertically
		if (isAnchorPoint(draggingIndex)) {
			newX = points[draggingIndex].x;
		}
		// Endpoint (rightmost) can only move vertically
		else if (isEndpoint(draggingIndex)) {
			newX = points[draggingIndex].x;
		} else {
			newX = Math.max(minX, Math.min(maxX, newX));
		}

		const newPoints = [...points];
		newPoints[draggingIndex] = { x: newX, y: newY };
		points = newPoints;
		selectedPreset = 'custom';
		onChange(newPoints);
	}

	function handleMouseUp() {
		draggingIndex = null;
		window.removeEventListener('mousemove', handleMouseMove);
		window.removeEventListener('mouseup', handleMouseUp);
	}

	function handleSvgClick(e: MouseEvent) {
		if (!svgElement || draggingIndex !== null) return;

		const rect = svgElement.getBoundingClientRect();
		const scaleX = width / rect.width;
		const scaleY = height / rect.height;

		const svgX = (e.clientX - rect.left) * scaleX;
		const svgY = (e.clientY - rect.top) * scaleY;

		const newX = fromSvgX(svgX);
		const newY = fromSvgY(svgY);

		// Clamp X away from edges
		const clampedX = Math.max(0.03, Math.min(0.97, newX));

		// Don't add if too close to existing point
		if (points.some((p) => Math.abs(p.x - clampedX) < 0.04)) return;

		const newPoint = { x: clampedX, y: newY };
		const newPoints = [...points, newPoint].sort((a, b) => a.x - b.x);
		points = newPoints;
		selectedPreset = 'custom';
		onChange(newPoints);
	}

	function handleSvgMouseMove(e: MouseEvent) {
		if (!svgElement || draggingIndex !== null) return;

		const rect = svgElement.getBoundingClientRect();
		const scaleX = width / rect.width;
		const svgX = (e.clientX - rect.left) * scaleX;
		const x = fromSvgX(svgX);

		// Only show value when within plot area
		if (x >= 0 && x <= 1) {
			const y = monotonicCubicInterpolation(points, x);
			hoverValue = { x, y };
		} else {
			hoverValue = null;
		}
	}

	function handleSvgMouseLeave() {
		hoverValue = null;
	}

	function handlePointDoubleClick(index: number, e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();

		// Don't delete anchor or endpoint
		if (isAnchorPoint(index) || isEndpoint(index)) return;
		// Need at least 2 points
		if (points.length <= 2) return;

		const newPoints = points.filter((_, i) => i !== index);
		points = newPoints;
		selectedPreset = 'custom';
		onChange(newPoints);
	}

	// ========================================================================
	// Preset selection
	// ========================================================================

	function applyPreset(presetName: CurvePresetName) {
		const preset = CURVE_PRESETS[presetName];
		if (preset) {
			points = preset.map((p) => ({ ...p }));
			selectedPreset = presetName;
			onChange(points);
		}
	}

	// Available presets with display names
	const presetOptions: Array<{ id: CurvePresetName; name: string }> = [
		{ id: 'linear', name: 'Linear' },
		{ id: 'constant', name: 'Constant' },
		{ id: 'soft', name: 'Soft (S-curve)' },
		{ id: 'step', name: 'Step' },
		{ id: 'decay', name: 'Decay' },
		{ id: 'boost', name: 'Boost' },
		{ id: 'inhibit', name: 'Inhibit' },
		{ id: 'wave', name: 'Wave' }
	];
</script>

<div class="curve-editor" style="width: 100%; max-width: {width}px;">
	{#if label || showPresets}
		<div class="header">
			{#if label}
				<span class="label">{label}</span>
			{/if}
			{#if showPresets}
				<select
					class="preset-select"
					value={selectedPreset}
					onchange={(e) => {
						const target = e.target as HTMLSelectElement;
						if (target.value !== 'custom') {
							applyPreset(target.value as CurvePresetName);
						}
					}}
				>
					<option value="custom">Custom</option>
					{#each presetOptions as preset}
						<option value={preset.id}>{preset.name}</option>
					{/each}
				</select>
			{/if}
		</div>
	{/if}

	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<svg
		bind:this={svgElement}
		{width}
		{height}
		class="curve-svg"
		onclick={handleSvgClick}
		onmousemove={handleSvgMouseMove}
		onmouseleave={handleSvgMouseLeave}
		role="application"
		aria-label="Curve editor - click to add points, drag to move, double-click to remove"
	>
		<!-- Background -->
		<rect x="0" y="0" {width} {height} fill="rgba(0,0,0,0.3)" rx="4" />

		<!-- Plot area background -->
		<rect
			x={padding.left}
			y={padding.top}
			width={plotWidth}
			height={plotHeight}
			fill="rgba(0,0,0,0.2)"
		/>

		<!-- Vertical grid lines -->
		{#each [0.25, 0.5, 0.75] as xVal}
			<line
				x1={toSvgX(xVal)}
				y1={padding.top}
				x2={toSvgX(xVal)}
				y2={padding.top + plotHeight}
				stroke="rgba(255,255,255,0.05)"
				stroke-width="1"
			/>
		{/each}

		<!-- Horizontal grid lines -->
		{#each gridLinesY as line}
			<line
				x1={padding.left}
				y1={toSvgY(line.y)}
				x2={padding.left + plotWidth}
				y2={toSvgY(line.y)}
				stroke="rgba(255,255,255,0.1)"
				stroke-width="1"
			/>
			<text x={padding.left - 4} y={toSvgY(line.y) + 3} class="axis-label" text-anchor="end">
				{line.label}
			</text>
		{/each}

		<!-- Zero line (highlighted) -->
		{#if yMin < 0 && yMax > 0}
			<line
				x1={padding.left}
				y1={toSvgY(0)}
				x2={padding.left + plotWidth}
				y2={toSvgY(0)}
				stroke="rgba(255,255,255,0.25)"
				stroke-width="1"
				stroke-dasharray="4,4"
			/>
		{/if}

		<!-- X-axis labels -->
		<text x={padding.left} y={height - 14} class="axis-label" text-anchor="start">0</text>
		<text x={padding.left + plotWidth} y={height - 14} class="axis-label" text-anchor="end">1</text>
		<text x={padding.left + plotWidth / 2} y={height - 2} class="axis-title" text-anchor="middle">{xAxisLabel}</text>

		<!-- Y-axis title (rotated) -->
		<text
			x={8}
			y={padding.top + plotHeight / 2}
			class="axis-title"
			text-anchor="middle"
			transform="rotate(-90, 8, {padding.top + plotHeight / 2})"
		>{yAxisLabel}</text>

		<!-- Hover indicator -->
		{#if hoverValue}
			<line
				x1={toSvgX(hoverValue.x)}
				y1={padding.top}
				x2={toSvgX(hoverValue.x)}
				y2={padding.top + plotHeight}
				stroke="rgba(255,255,255,0.2)"
				stroke-width="1"
				stroke-dasharray="2,2"
			/>
			<circle
				cx={toSvgX(hoverValue.x)}
				cy={toSvgY(hoverValue.y)}
				r="3"
				fill={curveColor}
				opacity="0.7"
			/>
		{/if}

		<!-- Curve path -->
		{#if curvePath}
			{#if showGradient}
				<defs>
					<linearGradient id="curve-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
						<stop offset="0%" stop-color="hsl(0, 70%, 60%)" />
						<stop offset="25%" stop-color="hsl(30, 70%, 60%)" />
						<stop offset="50%" stop-color="hsl(60, 70%, 60%)" />
						<stop offset="75%" stop-color="hsl(120, 70%, 50%)" />
						<stop offset="100%" stop-color="hsl(200, 70%, 60%)" />
					</linearGradient>
				</defs>
				<path d={curvePath} fill="none" stroke="url(#curve-gradient)" stroke-width="2.5" />
			{:else}
				<path d={curvePath} fill="none" stroke={curveColor} stroke-width="2.5" />
			{/if}
		{/if}

		<!-- Control points -->
		{#each points as point, i}
			{@const isAnchor = isAnchorPoint(i)}
			{@const isEnd = isEndpoint(i)}
			{@const isHovered = hoveredIndex === i}
			{@const isDragging = draggingIndex === i}

			<!-- Point highlight on hover -->
			{#if isHovered || isDragging}
				<circle
					cx={toSvgX(point.x)}
					cy={toSvgY(point.y)}
					r="10"
					fill="rgba(74, 222, 128, 0.2)"
					class="point-highlight"
				/>
			{/if}

			<!-- Point -->
			<circle
				cx={toSvgX(point.x)}
				cy={toSvgY(point.y)}
				r={isDragging ? 7 : isHovered ? 6 : 5}
				fill={isAnchor || isEnd ? '#60a5fa' : '#4ade80'}
				stroke="white"
				stroke-width="2"
				class="control-point"
				class:anchor={isAnchor || isEnd}
				class:dragging={isDragging}
				onmousedown={(e) => handlePointMouseDown(i, e)}
				ondblclick={(e) => handlePointDoubleClick(i, e)}
				onmouseenter={() => (hoveredIndex = i)}
				onmouseleave={() => (hoveredIndex = null)}
				role="button"
				tabindex="0"
				aria-label="Control point at ({point.x.toFixed(2)}, {point.y.toFixed(2)})"
			/>
		{/each}
	</svg>

	<div class="help-text">
		{#if hoverValue}
			x: {hoverValue.x.toFixed(2)} → y: {hoverValue.y.toFixed(2)}
		{:else}
			Click to add • Double-click to remove
		{/if}
	</div>
</div>

<style>
	.curve-editor {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0 2px;
	}

	.label {
		font-size: 11px;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.7);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.preset-select {
		font-size: 11px;
		padding: 2px 6px;
		background: rgba(255, 255, 255, 0.1);
		border: 1px solid rgba(255, 255, 255, 0.2);
		border-radius: 4px;
		color: rgba(255, 255, 255, 0.9);
		cursor: pointer;
		outline: none;
	}

	.preset-select:hover {
		background: rgba(255, 255, 255, 0.15);
	}

	.preset-select:focus {
		border-color: rgba(74, 222, 128, 0.5);
	}

	.curve-svg {
		cursor: crosshair;
		border-radius: 4px;
		user-select: none;
	}

	.axis-label {
		font-size: 9px;
		fill: rgba(255, 255, 255, 0.5);
		font-family: system-ui, sans-serif;
	}

	.axis-title {
		font-size: 8px;
		fill: rgba(255, 255, 255, 0.35);
		font-family: system-ui, sans-serif;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.control-point {
		cursor: grab;
		transition:
			r 0.1s ease,
			fill 0.1s ease;
	}

	.control-point:active,
	.control-point.dragging {
		cursor: grabbing;
	}

	.control-point.anchor {
		cursor: ns-resize;
	}

	.point-highlight {
		pointer-events: none;
	}

	.help-text {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.4);
		text-align: center;
		padding: 2px 0;
	}
</style>
