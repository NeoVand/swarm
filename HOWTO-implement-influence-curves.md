# How to Implement Influence Curves: A Complete Guide

This document explains exactly how the Vitality Influence Curve works in Games of Life—from the user-facing editor to the GPU shader—so that an AI can implement similar curves for a swarm simulation with multiple curve types (distance influence, alignment weight, cohesion weight, etc.).

---

## Table of Contents

1. [What the Curve Does](#1-what-the-curve-does)
2. [The Data Structure](#2-the-data-structure)
3. [The User Interface](#3-the-user-interface)
4. [The Interpolation Algorithm](#4-the-interpolation-algorithm)
5. [Sampling for GPU](#5-sampling-for-gpu)
6. [GPU Shader Lookup](#6-gpu-shader-lookup)
7. [Built-in Profiles](#7-built-in-profiles)
8. [Implementing Multiple Curves for Swarms](#8-implementing-multiple-curves-for-swarms)
9. [Complete Implementation Checklist](#9-complete-implementation-checklist)

---

## 1. What the Curve Does

### The Problem It Solves

In cellular automata with "Generations" rules, cells have multiple states:
- **State 0**: Dead (empty)
- **State 1**: Alive (fully active)
- **States 2+**: Dying (decaying over time)

The fundamental question: **How much should dying cells influence neighbor counts?**

- **Classic CA**: Only state 1 counts → dying cells are invisible to the rules
- **With vitality curves**: Dying cells contribute fractionally based on a user-defined function

### The Transfer Function Concept

The curve maps **vitality** (0.0 to 1.0) to **contribution** (-2.0 to +2.0):

```
Vitality (input):
  0.0 = completely dead
  1.0 = fully alive
  0.5 = halfway through decay

Contribution (output):
  0.0 = no influence on neighbors
  1.0 = full influence (same as alive cell)
  0.5 = half influence
 -1.0 = negative influence (inhibition!)
```

### Why Allow Negative Values?

Negative contributions enable **inhibitory dynamics**:
- Dying cells can *suppress* births in their neighborhood
- Creates wave-like patterns and oscillations
- Enables "midlife crisis" patterns where partially-dead cells inhibit their neighbors

---

## 2. The Data Structure

### Curve Points

The curve is defined by a sparse set of control points:

```typescript
interface CurvePoint {
  x: number;  // Vitality (0.0 to 1.0)
  y: number;  // Contribution (-2.0 to +2.0)
}

// Example: Linear positive curve
const linearCurve: CurvePoint[] = [
  { x: 0, y: 0 },    // Dead → no contribution
  { x: 1, y: 1 }     // Alive → full contribution
];

// Example: Inhibitory curve with oscillation
const midlifeCrisis: CurvePoint[] = [
  { x: 0, y: 0 },           // Dead → none
  { x: 0.372, y: -0.746 },  // Early decay → inhibit
  { x: 0.531, y: 0.321 },   // Mid decay → slight positive
  { x: 0.695, y: -0.669 },  // Late decay → inhibit again
  { x: 1, y: -1 }           // Near-alive → inhibit strongly
];
```

### Storage in Simulation State

```typescript
interface VitalitySpec {
  mode: 'none' | 'threshold' | 'ghost' | 'sigmoid' | 'decay' | 'curve';
  threshold: number;        // For threshold/sigmoid modes
  ghostFactor: number;      // For ghost/decay modes
  sigmoidSharpness: number; // For sigmoid mode
  decayPower: number;       // For decay mode
  curvePoints?: CurvePoint[]; // For curve mode (our custom curves)
}
```

### Key Constraints

1. **Minimum 2 points**: Need at least start and end
2. **X must be unique**: No two points at the same x coordinate
3. **X range**: Points must be within [0, 1]
4. **Y range**: Clamped to [-2, +2] for sanity
5. **Sorted by X**: Points are always kept sorted for interpolation

---

## 3. The User Interface

### The SVG-Based Curve Editor

The `InfluenceCurveEditor.svelte` component provides:

1. **Visual plot**: SVG with vitality (x) vs contribution (y)
2. **Draggable control points**: Users drag points to shape the curve
3. **Click to add**: Click on the curve area to add new points
4. **Double-click to delete**: Remove unnecessary points
5. **Profile presets**: Quick selection of common curve shapes
6. **Color gradient**: The curve line shows vitality colors

### Coordinate System

```typescript
// Plot dimensions
const padding = { top: 15, right: 15, bottom: 20, left: 25 };
const plotWidth = width - padding.left - padding.right;
const plotHeight = height - padding.top - padding.bottom;

// Y-axis range
const yMin = -2;
const yMax = 2;
const yRange = yMax - yMin;  // 4

// Data → SVG coordinate conversion
function toSvgX(x: number): number {
  return padding.left + x * plotWidth;
}

function toSvgY(y: number): number {
  // Y goes from yMin (bottom) to yMax (top)
  return padding.top + (yMax - y) * plotHeight / yRange;
}

// SVG → Data coordinate conversion
function fromSvgX(svgX: number): number {
  return Math.max(0, Math.min(1, (svgX - padding.left) / plotWidth));
}

function fromSvgY(svgY: number): number {
  return Math.max(yMin, Math.min(yMax, yMax - (svgY - padding.top) * yRange / plotHeight));
}
```

### Point Interaction

```typescript
// Start dragging a point
function handlePointMouseDown(index: number, e: MouseEvent) {
  e.preventDefault();
  e.stopPropagation();
  
  // Don't allow dragging the anchor point (x=0)
  if (isAnchorPoint(index)) return;
  
  draggingIndex = index;
  window.addEventListener('mousemove', handleMouseMove);
  window.addEventListener('mouseup', handleMouseUp);
}

// Update point position while dragging
function updateDraggedPoint(svgX: number, svgY: number) {
  if (draggingIndex === null) return;
  
  const newX = fromSvgX(svgX);
  const newY = fromSvgY(svgY);
  
  // Find neighboring points to prevent crossing
  const sortedIndices = curvePoints
    .map((p, i) => ({ x: p.x, i }))
    .sort((a, b) => a.x - b.x)
    .map(p => p.i);
  
  const sortedPos = sortedIndices.indexOf(draggingIndex);
  const prevIndex = sortedPos > 0 ? sortedIndices[sortedPos - 1] : null;
  const nextIndex = sortedPos < sortedIndices.length - 1 ? sortedIndices[sortedPos + 1] : null;
  
  // Constrain X to prevent point order changes
  const minX = prevIndex !== null ? curvePoints[prevIndex].x + 0.02 : 0.02;
  const maxX = nextIndex !== null ? curvePoints[nextIndex].x - 0.02 : 1;
  
  // Endpoint (rightmost) can only move vertically
  const isEndpointDrag = isEndpoint(draggingIndex);
  
  curvePoints[draggingIndex] = {
    x: isEndpointDrag ? curvePoints[draggingIndex].x : Math.max(minX, Math.min(maxX, newX)),
    y: Math.max(yMin, Math.min(yMax, newY))
  };
  
  // Update simulation state
  updateSimState();
}
```

### Adding New Points

```typescript
function handleCurveMouseDown(e: MouseEvent) {
  if (!svgElement || editMode !== 'add') return;
  
  const rect = svgElement.getBoundingClientRect();
  const scaleX = width / rect.width;
  const scaleY = height / rect.height;
  
  const newX = fromSvgX((e.clientX - rect.left) * scaleX);
  const newY = fromSvgY((e.clientY - rect.top) * scaleY);
  
  // Clamp X away from edges
  const clampedX = Math.max(0.03, Math.min(0.97, newX));
  
  // Don't add if too close to existing point
  if (curvePoints.some(p => Math.abs(p.x - clampedX) < 0.04)) return;
  
  // Add new point
  const newPoint = { x: clampedX, y: Math.max(yMin, Math.min(yMax, newY)) };
  curvePoints = [...curvePoints, newPoint].sort((a, b) => a.x - b.x);
  
  // Start dragging the new point immediately
  draggingIndex = curvePoints.findIndex(p => p.x === newPoint.x);
  
  updateSimState();
}
```

---

## 4. The Interpolation Algorithm

### Why Monotonic Cubic Hermite?

We use **Fritsch-Carlson monotonic cubic interpolation** because:

1. **Smooth curves**: Cubic splines produce smooth, visually pleasing curves
2. **No overshoot**: Monotonic variant prevents the curve from oscillating between control points
3. **Predictable**: What you see in the editor is what you get

### The Algorithm

```typescript
function monotonicCubicInterpolation(points: CurvePoint[], xVal: number): number {
  const n = points.length;
  if (n === 0) return 0;
  if (n === 1) return points[0].y;
  
  // Sort points by x
  const sorted = [...points].sort((a, b) => a.x - b.x);
  
  // Handle out-of-range queries
  if (xVal <= sorted[0].x) return sorted[0].y;
  if (xVal >= sorted[n - 1].x) return sorted[n - 1].y;
  
  // Find the segment containing xVal
  let i = 0;
  while (i < n - 1 && sorted[i + 1].x < xVal) i++;
  
  // Calculate deltas (segment lengths) and slopes
  const deltas: number[] = [];
  const slopes: number[] = [];
  for (let j = 0; j < n - 1; j++) {
    const dx = sorted[j + 1].x - sorted[j].x;
    deltas.push(dx);
    slopes.push(dx === 0 ? 0 : (sorted[j + 1].y - sorted[j].y) / dx);
  }
  
  // Calculate tangents at each point (Fritsch-Carlson method)
  const tangents: number[] = [];
  for (let j = 0; j < n; j++) {
    if (j === 0) {
      // First point: use first segment's slope
      tangents.push(slopes[0]);
    } else if (j === n - 1) {
      // Last point: use last segment's slope
      tangents.push(slopes[n - 2]);
    } else {
      const m0 = slopes[j - 1];
      const m1 = slopes[j];
      
      // If slopes have different signs, tangent is 0 (local extremum)
      if (m0 * m1 <= 0) {
        tangents.push(0);
      } else {
        // Weighted harmonic mean of slopes
        const w0 = 2 * deltas[j] + deltas[j - 1];
        const w1 = deltas[j] + 2 * deltas[j - 1];
        tangents.push((w0 + w1) / (w0 / m0 + w1 / m1));
      }
    }
  }
  
  // Ensure monotonicity: limit tangent magnitudes
  for (let j = 0; j < n - 1; j++) {
    const m = slopes[j];
    if (m === 0) {
      // Flat segment: tangents must be 0
      tangents[j] = 0;
      tangents[j + 1] = 0;
    } else {
      const alpha = tangents[j] / m;
      const beta = tangents[j + 1] / m;
      const tau = alpha * alpha + beta * beta;
      
      // If tangents are too large, scale them down
      if (tau > 9) {
        const s = 3 / Math.sqrt(tau);
        tangents[j] = s * alpha * m;
        tangents[j + 1] = s * beta * m;
      }
    }
  }
  
  // Hermite interpolation within the segment
  const x0 = sorted[i].x;
  const x1 = sorted[i + 1].x;
  const y0 = sorted[i].y;
  const y1 = sorted[i + 1].y;
  const h = x1 - x0;
  const t = (xVal - x0) / h;
  const t2 = t * t;
  const t3 = t2 * t;
  
  // Hermite basis functions
  const h00 = 2 * t3 - 3 * t2 + 1;  // Position at start
  const h10 = t3 - 2 * t2 + t;       // Tangent at start
  const h01 = -2 * t3 + 3 * t2;      // Position at end
  const h11 = t3 - t2;               // Tangent at end
  
  return h00 * y0 + h10 * h * tangents[i] + h01 * y1 + h11 * h * tangents[i + 1];
}
```

---

## 5. Sampling for GPU

### Why Pre-Sample?

GPUs don't have access to JavaScript functions. We need to:
1. Sample the curve at fixed intervals
2. Upload samples to a GPU buffer
3. Use linear interpolation in the shader for smooth lookup

### The Sampling Process

```typescript
const VITALITY_CURVE_SAMPLES = 128;

function sampleVitalityCurve(points: CurvePoint[] | undefined): number[] {
  if (!points || points.length < 2) {
    return new Array(VITALITY_CURVE_SAMPLES).fill(0);
  }
  
  const samples: number[] = [];
  for (let i = 0; i < VITALITY_CURVE_SAMPLES; i++) {
    // Map sample index to vitality (0 to 1)
    const vitality = i / (VITALITY_CURVE_SAMPLES - 1);
    
    // Interpolate the curve at this vitality
    const y = monotonicCubicInterpolation(points, vitality);
    
    // Clamp to valid range
    samples.push(Math.max(-2, Math.min(2, y)));
  }
  
  return samples;
}
```

### Uploading to GPU

```typescript
function updateVitalityCurve(): void {
  // Create Float32Array for GPU
  const samples = new Float32Array(128);
  
  // Sample the curve
  const curveData = sampleVitalityCurve(this.view.vitalityCurvePoints);
  for (let i = 0; i < 128; i++) {
    samples[i] = curveData[i] ?? 0;
  }
  
  // Upload to GPU buffer
  this.device.queue.writeBuffer(this.vitalityCurveBuffer, 0, samples);
}
```

### Buffer Creation

```typescript
// Create the buffer (512 bytes for 128 f32 values)
this.vitalityCurveBuffer = device.createBuffer({
  label: 'Vitality Curve Buffer',
  size: 128 * 4,  // 128 float32 values
  usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
});
```

---

## 6. GPU Shader Lookup

### Binding the Buffer

```wgsl
// In the compute shader
@group(0) @binding(3) var<storage, read> vitality_curve: array<f32>;
```

### Linear Interpolation Lookup

```wgsl
// Called during neighbor counting
fn get_neighbor_contribution(state: u32) -> f32 {
    // ... (other modes handled first) ...
    
    // Mode 5: Custom curve lookup
    if (state == 1u) { return 1.0; }  // Alive always contributes 1.0
    if (state == 0u) { return 0.0; }  // Dead always contributes 0.0
    
    // Get vitality for this dying state
    let vitality = get_vitality(state);
    
    // Map vitality (0-1) to curve index (0-127)
    let curve_pos = vitality * 127.0;
    let idx_low = u32(floor(curve_pos));
    let idx_high = min(idx_low + 1u, 127u);
    let frac = curve_pos - f32(idx_low);
    
    // Linear interpolation between adjacent samples
    let val_low = vitality_curve[idx_low];
    let val_high = vitality_curve[idx_high];
    return mix(val_low, val_high, frac);
}
```

### Using the Contribution in Neighbor Counting

```wgsl
fn count_neighbors_moore(x: i32, y: i32) -> u32 {
    var total: f32 = 0.0;
    
    // Sum contributions from all 8 neighbors
    for (var dy: i32 = -1; dy <= 1; dy++) {
        for (var dx: i32 = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            
            let neighbor_state = get_cell(x + dx, y + dy);
            total += get_neighbor_contribution(neighbor_state);
        }
    }
    
    // Round to integer for bitmask lookup
    return neighbor_total_to_count(total, 8.0);
}

fn neighbor_total_to_count(total: f32, max_neighbors: f32) -> u32 {
    let clamped = clamp(total, 0.0, max_neighbors);
    return u32(clamped + 0.5);  // Round to nearest integer
}
```

---

## 7. Built-in Profiles

### Profile Definitions

```typescript
const PROFILES = [
  { id: 'off', name: 'Off', description: 'Standard behavior - dying cells invisible' },
  { id: 'linear', name: 'Linear', description: 'Linear positive influence' },
  { id: 'soft', name: 'Soft', description: 'S-curve smooth transition' },
  { id: 'step', name: 'Step', description: 'Hard threshold at 50%' },
  { id: 'midlife-crisis', name: 'Midlife Crisis', description: 'Oscillating inhibition pattern' },
  { id: 'inhibit', name: 'Inhibit', description: 'Negative influence suppresses growth' },
  { id: 'mixed', name: 'Mixed', description: 'Wave pattern with positive and negative' },
  { id: 'mandala', name: 'Mandala', description: 'Amplified dying influence for mandala patterns' }
];

const PROFILE_CURVES: Record<string, CurvePoint[]> = {
  'off': [{ x: 0, y: 0 }, { x: 1, y: 0 }],
  'linear': [{ x: 0, y: 0 }, { x: 1, y: 1 }],
  'soft': [
    { x: 0, y: 0 },
    { x: 0.25, y: 0.05 },
    { x: 0.5, y: 0.5 },
    { x: 0.75, y: 0.95 },
    { x: 1, y: 1 }
  ],
  'step': [
    { x: 0, y: 0 },
    { x: 0.48, y: 0 },
    { x: 0.50, y: 0.5 },
    { x: 0.52, y: 1 },
    { x: 1, y: 1 }
  ],
  'inhibit': [
    { x: 0, y: 0 },
    { x: 0.3, y: -0.5 },
    { x: 0.7, y: -0.7 },
    { x: 1, y: -0.4 }
  ],
  'mixed': [
    { x: 0, y: 0 },
    { x: 0.25, y: -0.5 },
    { x: 0.5, y: 0 },
    { x: 0.75, y: 0.7 },
    { x: 1, y: 0.5 }
  ],
  'midlife-crisis': [
    { x: 0, y: 0 },
    { x: 0.372, y: -0.746 },
    { x: 0.531, y: 0.321 },
    { x: 0.695, y: -0.669 },
    { x: 1, y: -1 }
  ],
  'mandala': [
    { x: 0, y: 0 },
    { x: 0.148, y: 1.01 },
    { x: 1, y: 0.19 }
  ]
};
```

### Applying a Profile

```typescript
function applyProfile(profileId: string) {
  selectedProfileId = profileId;
  
  if (PROFILE_CURVES[profileId]) {
    // Deep copy to avoid mutation
    curvePoints = PROFILE_CURVES[profileId].map(p => ({ ...p }));
  }
  
  updateSimState();
}
```

---

## 8. Implementing Multiple Curves for Swarms

### The Swarm Use Case

For a boids/swarm simulation, you might want multiple curves:

| Curve | Input | Output | Purpose |
|-------|-------|--------|---------|
| Distance Influence | Distance (0=close, 1=far) | Weight (0-1) | How much far agents influence |
| Vitality Influence | Agent vitality (0-1) | Weight (0-1) | How much "dying" agents influence |
| Alignment Curve | Neighbor density (0-1) | Weight (0-2) | Alignment force vs crowding |
| Cohesion Curve | Neighbor density (0-1) | Weight (0-2) | Cohesion force vs crowding |
| Separation Curve | Neighbor density (0-1) | Weight (0-2) | Separation force vs crowding |
| Size Curve | Vitality (0-1) | Size multiplier | Visual size based on state |
| Speed Curve | Vitality (0-1) | Speed multiplier | Movement speed based on state |

### Multi-Curve Data Structure

```typescript
interface SwarmCurveConfig {
  // Each curve has its own set of control points
  distanceInfluence: CurvePoint[];
  vitalityInfluence: CurvePoint[];
  alignmentModulation: CurvePoint[];
  cohesionModulation: CurvePoint[];
  separationModulation: CurvePoint[];
  sizeModulation: CurvePoint[];
  speedModulation: CurvePoint[];
}

// Default curves (all linear)
const defaultSwarmCurves: SwarmCurveConfig = {
  distanceInfluence: [{ x: 0, y: 1 }, { x: 1, y: 0 }],  // Close=1, far=0
  vitalityInfluence: [{ x: 0, y: 0 }, { x: 1, y: 1 }],  // Dead=0, alive=1
  alignmentModulation: [{ x: 0, y: 1 }, { x: 1, y: 1 }],  // Constant
  cohesionModulation: [{ x: 0, y: 1 }, { x: 1, y: 1 }],
  separationModulation: [{ x: 0, y: 0.5 }, { x: 1, y: 1.5 }],  // More separation when crowded
  sizeModulation: [{ x: 0, y: 0.5 }, { x: 1, y: 1 }],  // Dying = smaller
  speedModulation: [{ x: 0, y: 0.3 }, { x: 1, y: 1 }],  // Dying = slower
};
```

### Multi-Curve GPU Buffer Layout

```typescript
// Each curve needs 128 f32 samples
const CURVE_SAMPLES = 128;
const NUM_CURVES = 7;
const TOTAL_SAMPLES = CURVE_SAMPLES * NUM_CURVES;  // 896 f32 values

// Create unified buffer
const curvesBuffer = device.createBuffer({
  label: 'Swarm Curves Buffer',
  size: TOTAL_SAMPLES * 4,  // 3584 bytes
  usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
});

// Upload all curves
function uploadAllCurves(config: SwarmCurveConfig) {
  const allSamples = new Float32Array(TOTAL_SAMPLES);
  
  let offset = 0;
  for (const curvePoints of [
    config.distanceInfluence,
    config.vitalityInfluence,
    config.alignmentModulation,
    config.cohesionModulation,
    config.separationModulation,
    config.sizeModulation,
    config.speedModulation
  ]) {
    const samples = sampleCurve(curvePoints);
    allSamples.set(samples, offset);
    offset += CURVE_SAMPLES;
  }
  
  device.queue.writeBuffer(curvesBuffer, 0, allSamples);
}
```

### Multi-Curve Shader Lookup

```wgsl
// Buffer contains all curves concatenated
@group(0) @binding(3) var<storage, read> swarm_curves: array<f32>;

// Curve indices
const CURVE_DISTANCE: u32 = 0u;
const CURVE_VITALITY: u32 = 1u;
const CURVE_ALIGNMENT: u32 = 2u;
const CURVE_COHESION: u32 = 3u;
const CURVE_SEPARATION: u32 = 4u;
const CURVE_SIZE: u32 = 5u;
const CURVE_SPEED: u32 = 6u;

fn lookup_curve(curve_id: u32, t: f32) -> f32 {
    // Base offset for this curve (128 samples per curve)
    let base = curve_id * 128u;
    
    // Map t (0-1) to sample index
    let curve_pos = clamp(t, 0.0, 1.0) * 127.0;
    let idx_low = u32(floor(curve_pos));
    let idx_high = min(idx_low + 1u, 127u);
    let frac = curve_pos - f32(idx_low);
    
    // Linear interpolation
    let val_low = swarm_curves[base + idx_low];
    let val_high = swarm_curves[base + idx_high];
    return mix(val_low, val_high, frac);
}

// Usage in agent update
fn calculate_neighbor_influence(agent: Agent, other: Agent) -> f32 {
    let dist = distance(agent.pos, other.pos);
    let normalized_dist = dist / agent.perception_radius;
    
    // Apply both distance and vitality curves
    let dist_weight = lookup_curve(CURVE_DISTANCE, normalized_dist);
    let vitality_weight = lookup_curve(CURVE_VITALITY, other.vitality);
    
    return dist_weight * vitality_weight;
}

fn get_alignment_weight(neighbor_count: f32, max_neighbors: f32) -> f32 {
    let density = neighbor_count / max_neighbors;
    return lookup_curve(CURVE_ALIGNMENT, density);
}

fn get_agent_size(vitality: f32, base_size: f32) -> f32 {
    return base_size * lookup_curve(CURVE_SIZE, vitality);
}
```

### UI: Multiple Curve Editors

Create a tabbed or accordion interface with one editor per curve:

```svelte
<script lang="ts">
  import CurveEditor from './CurveEditor.svelte';
  
  let activeTab = 'distance';
  
  const curveConfigs = [
    { id: 'distance', label: 'Distance Influence', yMin: 0, yMax: 1 },
    { id: 'vitality', label: 'Vitality Influence', yMin: 0, yMax: 1 },
    { id: 'alignment', label: 'Alignment Modulation', yMin: 0, yMax: 2 },
    { id: 'cohesion', label: 'Cohesion Modulation', yMin: 0, yMax: 2 },
    { id: 'separation', label: 'Separation Modulation', yMin: 0, yMax: 2 },
    { id: 'size', label: 'Size Curve', yMin: 0, yMax: 2 },
    { id: 'speed', label: 'Speed Curve', yMin: 0, yMax: 2 }
  ];
</script>

<div class="curve-tabs">
  {#each curveConfigs as config}
    <button 
      class:active={activeTab === config.id}
      onclick={() => activeTab = config.id}
    >
      {config.label}
    </button>
  {/each}
</div>

{#each curveConfigs as config}
  {#if activeTab === config.id}
    <CurveEditor
      title={config.label}
      points={swarmCurves[config.id]}
      yMin={config.yMin}
      yMax={config.yMax}
      onChange={(points) => updateCurve(config.id, points)}
    />
  {/if}
{/each}
```

---

## 9. Complete Implementation Checklist

### Data Layer
- [ ] `CurvePoint` interface with x (input) and y (output)
- [ ] Storage for multiple named curves
- [ ] Serialization/deserialization (JSON export/import)
- [ ] Profile presets for common curve shapes

### Interpolation
- [ ] Monotonic cubic Hermite interpolation function
- [ ] Handle edge cases: 0 points, 1 point, out-of-range queries
- [ ] Ensure no overshoot between control points

### Sampling
- [ ] Sample curves to fixed-size arrays (128 recommended)
- [ ] Clamp values to valid range
- [ ] Efficient batch upload to GPU

### GPU Integration
- [ ] Storage buffer for curve data
- [ ] Binding in compute shader
- [ ] Linear interpolation lookup function
- [ ] Application in agent update logic

### UI Components
- [ ] SVG-based curve visualization
- [ ] Draggable control points
- [ ] Click-to-add new points
- [ ] Delete functionality (double-click or mode toggle)
- [ ] Profile/preset dropdown
- [ ] Color gradient showing curve semantics
- [ ] Y-axis labels and grid lines
- [ ] Save/load curve as JSON

### Integration
- [ ] Connect UI changes to simulation state
- [ ] Trigger GPU buffer updates on curve change
- [ ] Live preview of curve effects

---

## Summary

The Vitality Influence Curve system in Games of Life demonstrates a powerful pattern for user-defined transfer functions:

1. **Sparse control points**: Users edit a few points, not hundreds of samples
2. **Smooth interpolation**: Monotonic cubic splines produce natural curves
3. **GPU-ready sampling**: 128 samples give smooth GPU lookup with linear interpolation
4. **Flexible output range**: Allow negative values for inhibitory effects
5. **Profile presets**: Quick access to common curve shapes

For swarms, this same pattern applies to any parameter that should vary based on some input (distance, density, vitality, etc.). The key is:

1. Define what the input represents (x-axis)
2. Define what the output controls (y-axis range)
3. Provide sensible default curves
4. Let users customize with the same drag-to-edit interface

The GPU shader just needs to know where each curve's samples are stored and how to interpolate between them.
