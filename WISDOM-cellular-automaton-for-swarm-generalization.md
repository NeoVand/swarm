# The Wisdom of Games of Life: A Complete Technical Guide for Generalizing Cellular Automata to Swarm Dynamics

This document captures the complete technical wisdom from the Games of Life codebase—every architectural decision, numerical representation, performance optimization, and design pattern that enabled high-performance, beautiful cellular automaton simulation. The goal is to provide enough detail for a powerful AI to generalize these concepts to swarm/boids simulations where agents use CA-like rules to transform their properties (color, size, speed, perception, alignment, separation, cohesion).

---

## Table of Contents

1. [Executive Summary: The Core Insight](#1-executive-summary-the-core-insight)
2. [The Rule System: Geometry-Independent Neighborhood Aggregation](#2-the-rule-system-geometry-independent-neighborhood-aggregation)
3. [State Representation: The u32 Cell State Model](#3-state-representation-the-u32-cell-state-model)
4. [Vitality: Fractional Influence from Dying Cells](#4-vitality-fractional-influence-from-dying-cells)
5. [Neighborhood Types: Defining Who Influences Whom](#5-neighborhood-types-defining-who-influences-whom)
6. [The Influence Curve: User-Defined Transfer Functions](#6-the-influence-curve-user-defined-transfer-functions)
7. [WebGPU Architecture: Achieving Massive Parallelism](#7-webgpu-architecture-achieving-massive-parallelism)
8. [Double Buffering: The Ping-Pong Pattern](#8-double-buffering-the-ping-pong-pattern)
9. [Numerical Representations and GPU Data Layout](#9-numerical-representations-and-gpu-data-layout)
10. [The Compute Shader: Core CA Logic](#10-the-compute-shader-core-ca-logic)
11. [The Render Shader: Visualization Pipeline](#11-the-render-shader-visualization-pipeline)
12. [Boundary Conditions: Topological Transformations](#12-boundary-conditions-topological-transformations)
13. [Performance Optimizations That Matter](#13-performance-optimizations-that-matter)
14. [Generalizing to Swarms: A Complete Recipe](#14-generalizing-to-swarms-a-complete-recipe)
15. [The Boids-CA Hybrid Architecture](#15-the-boids-ca-hybrid-architecture)
16. [Implementation Checklist for Swarm-CA](#16-implementation-checklist-for-swarm-ca)

---

## 1. Executive Summary: The Core Insight

**The fundamental insight of this codebase is that cellular automaton rules are essentially weighted spatial aggregations that are geometry-independent.**

In classical CA:
- Each cell sums contributions from its neighborhood
- The sum determines the next state via lookup (bitmask)
- The geometry (square grid, hex grid) only defines *which* cells are neighbors

**This pattern generalizes perfectly to swarms:**
- Each agent sums contributions from nearby agents (within perception radius)
- The sum determines property changes (color, speed, size, behavior weights)
- The "neighborhood" is defined by spatial proximity and perception, not grid adjacency

The key operations are:
1. **Aggregation**: Sum weighted contributions from neighbors
2. **Transformation**: Map the aggregate to a new state/property
3. **Application**: Apply the new state atomically

Everything else—visualization, interaction, performance—builds on this foundation.

---

## 2. The Rule System: Geometry-Independent Neighborhood Aggregation

### 2.1 The Birth/Survival Bitmask Representation

Classical CA rules like Conway's Game of Life use B/S notation: `B3/S23` means:
- **Birth**: A dead cell becomes alive if it has exactly 3 alive neighbors
- **Survival**: An alive cell survives if it has 2 or 3 alive neighbors

We encode this as **bitmasks** for ultra-fast GPU evaluation:

```typescript
interface RuleSpec {
  birthMask: number;    // Bit i = 1 means birth with i neighbors
  surviveMask: number;  // Bit i = 1 means survive with i neighbors
  numStates: number;    // 2 for binary, 3+ for "Generations" decay
  neighborhood: NeighborhoodId;
}
```

**Example: B3/S23 (Conway's Life)**
```
birthMask   = 0b00001000 = 8   (bit 3 set)
surviveMask = 0b00001100 = 12  (bits 2 and 3 set)
```

**GPU evaluation (single bitwise operation!):**
```wgsl
let neighbors: u32 = count_neighbors(x, y);
let should_birth = (params.birth_mask & (1u << neighbors)) != 0u;
let should_survive = (params.survive_mask & (1u << neighbors)) != 0u;
```

### 2.2 Why Bitmasks Are Brilliant

1. **O(1) lookup**: No conditionals, no arrays—just bit shift and AND
2. **Arbitrary rules**: Any combination of neighbor counts can be encoded
3. **Extended neighborhoods**: Works up to 31 neighbors (single u32)
4. **GPU-friendly**: No branching, no memory access, pure ALU

### 2.3 Parsing and Serialization

```typescript
// Parse "B3/S23" or "B9-17/S5-12/C8" (extended + generations)
function parseRuleString(ruleString: string): RuleSpec {
  const match = ruleString.match(/^B([\d,-]*)\/S([\d,-]*)(?:\/C(\d+))?$/);
  // Parse ranges like "9-17" or single digits "23"
  // Return masks and optional generation count
}

// Convert mask to readable spec
function formatMaskToNeighborSpec(mask: number, maxNeighbors: number): string {
  const values: number[] = [];
  for (let i = 0; i <= maxNeighbors; i++) {
    if ((mask & (1 << i)) !== 0) values.push(i);
  }
  // Compact format: "23" for single digits, "9,10,11,12" for larger
  return values.every(n => n < 10) ? values.join('') : values.join(',');
}
```

### 2.4 Generalization for Swarms

For swarms, the "rule" becomes a **property transformation function**:

```typescript
interface SwarmPropertyRule {
  // Input: aggregated neighborhood value (0.0 to 1.0 normalized)
  // Output: property change (could be delta or absolute)
  
  // Option 1: Threshold-based (like CA birth/survival)
  thresholds: { min: number; max: number; outputValue: number }[];
  
  // Option 2: Continuous curve (like vitality curves)
  curve: CurvePoint[];
  
  // Option 3: Sigmoid/smooth transition
  sigmoid: { center: number; sharpness: number; minOut: number; maxOut: number };
}
```

---

## 3. State Representation: The u32 Cell State Model

### 3.1 The Three-State Model

Every cell is a single `u32` with these semantics:

| State | Meaning | Visual | Neighbor Contribution |
|-------|---------|--------|----------------------|
| 0 | Dead | Background | 0 |
| 1 | Alive | Full color | 1 |
| 2..n-1 | Dying | Gradient/spectrum | Depends on vitality mode |

### 3.2 Generations Rules (Multi-State CA)

"Generations" rules add visual trails:
- When an alive cell fails survival, it becomes state 2 (not 0)
- State 2 → 3 → 4 → ... → numStates-1 → 0
- Creates beautiful comet-like trails

```wgsl
if (current_state == 0u) {
    // Dead: check birth
    if (should_birth) { new_state = 1u; }
} else if (current_state == 1u) {
    // Alive: check survival
    if (should_survive) { new_state = 1u; }
    else { new_state = 2u; }  // Start dying
} else {
    // Dying: increment towards death
    new_state = current_state + 1u;
    if (new_state >= params.num_states) { new_state = 0u; }
}
```

### 3.3 Calculating Vitality from State

```wgsl
fn get_vitality(state: u32) -> f32 {
    if (state == 0u) { return 0.0; }  // Dead
    if (state == 1u) { return 1.0; }  // Fully alive
    // Dying: linear decay from 1.0 to near 0.0
    return f32(params.num_states - state) / f32(params.num_states - 1u);
}
```

**Example with numStates = 8:**
| State | Vitality |
|-------|----------|
| 0 | 0.0 |
| 1 | 1.0 |
| 2 | 0.857 |
| 3 | 0.714 |
| 4 | 0.571 |
| 5 | 0.428 |
| 6 | 0.285 |
| 7 | 0.142 |

### 3.4 Generalization for Swarms

For swarms, each agent has multiple properties:

```typescript
interface SwarmAgent {
  // Position and motion
  x: number;
  y: number;
  vx: number;
  vy: number;
  
  // CA-influenced properties
  vitality: number;      // 0-1, analogous to cell state
  color: [r, g, b];      // Can be derived from vitality
  size: number;          // Visual size
  perceptionRadius: number;
  
  // Boids weights (can be CA-modulated)
  alignmentWeight: number;
  cohesionWeight: number;
  separationWeight: number;
}
```

---

## 4. Vitality: Fractional Influence from Dying Cells

**This is one of the most powerful features for creating emergent complexity.**

### 4.1 The Problem

In basic CA, only alive cells (state=1) count as neighbors. But with Generations rules, dying cells exist in states 2..n-1. Should they influence neighbor counts?

### 4.2 Six Vitality Modes

```wgsl
fn get_neighbor_contribution(state: u32) -> f32 {
    let mode = params.vitality_mode;
    let vitality = get_vitality(state);
    
    // Mode 0: Standard - only state 1 counts
    if (mode == 0u) {
        return select(0.0, 1.0, state == 1u);
    }
    
    // Mode 1: Threshold - cells above vitality threshold count as 1
    if (mode == 1u) {
        return select(0.0, 1.0, vitality >= params.vitality_threshold);
    }
    
    // Mode 2: Ghost - dying cells contribute vitality * ghost_factor
    if (mode == 2u) {
        if (state == 1u) { return 1.0; }
        if (state == 0u) { return 0.0; }
        return vitality * params.vitality_ghost;
    }
    
    // Mode 3: Sigmoid - smooth S-curve transition
    if (mode == 3u) {
        let x = (vitality - params.vitality_threshold) * params.vitality_sigmoid;
        return 1.0 / (1.0 + exp(-x));
    }
    
    // Mode 4: Decay - power curve: vitality^power * ghost_factor
    if (mode == 4u) {
        if (state == 1u) { return 1.0; }
        if (state == 0u) { return 0.0; }
        return pow(vitality, params.vitality_decay) * params.vitality_ghost;
    }
    
    // Mode 5: Custom curve - 128-sample lookup table
    // (see detailed curve implementation below)
}
```

### 4.3 The Custom Curve Mode (Most Flexible)

Users can define arbitrary influence curves via control points:

```typescript
interface CurvePoint {
  x: number;  // Vitality input (0-1)
  y: number;  // Contribution output (-2 to 2, clamped)
}
```

**Curve Sampling:**
```typescript
const VITALITY_CURVE_SAMPLES = 128;

function sampleVitalityCurve(points: CurvePoint[]): number[] {
  if (!points || points.length < 2) return new Array(128).fill(0);
  
  const samples: number[] = [];
  for (let i = 0; i < 128; i++) {
    const vitality = i / 127;
    const y = monotonicCubicInterpolation(points, vitality);
    samples.push(clamp(y, -2, 2));  // Allow negative influence!
  }
  return samples;
}
```

**GPU Lookup with Linear Interpolation:**
```wgsl
fn curve_lookup(vitality: f32) -> f32 {
    let curve_pos = vitality * 127.0;
    let idx_low = u32(floor(curve_pos));
    let idx_high = min(idx_low + 1u, 127u);
    let frac = curve_pos - f32(idx_low);
    
    let val_low = vitality_curve[idx_low];
    let val_high = vitality_curve[idx_high];
    return mix(val_low, val_high, frac);
}
```

### 4.4 Why This Matters for Swarms

The vitality influence system provides:

1. **Decay effects**: Recently "dead" agents still influence neighbors
2. **Memory**: The swarm has a kind of short-term memory through dying states
3. **Smooth transitions**: Sigmoid/curve modes prevent abrupt behavior changes
4. **User control**: Artists can sculpt exactly how influence propagates

**Swarm application example:**
- Agent A's "alignment influence" decays over time after it "dies" (leaves a region)
- Other agents continue to be slightly influenced by A's last direction
- Creates cohesive, organic-looking swarm behavior

---

## 5. Neighborhood Types: Defining Who Influences Whom

### 5.1 Built-in Neighborhoods

```typescript
type NeighborhoodId = 
  | 'moore'           // 8 neighbors (3x3 minus center)
  | 'vonNeumann'      // 4 neighbors (orthogonal only)
  | 'extendedMoore'   // 24 neighbors (5x5 minus center)
  | 'hexagonal'       // 6 neighbors (hex grid)
  | 'extendedHexagonal'; // 18 neighbors (two hex rings)
```

### 5.2 Implementation Strategy

Each neighborhood is implemented as a separate counting function:

```wgsl
fn count_neighbors_moore(x: i32, y: i32) -> u32 {
    var total: f32 = 0.0;
    for (var dy: i32 = -1; dy <= 1; dy++) {
        for (var dx: i32 = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            total += get_neighbor_contribution(get_cell(x + dx, y + dy));
        }
    }
    return neighbor_total_to_count(total, 8.0);
}

fn count_neighbors_von_neumann(x: i32, y: i32) -> u32 {
    var total: f32 = 0.0;
    total += get_neighbor_contribution(get_cell(x, y - 1));  // North
    total += get_neighbor_contribution(get_cell(x, y + 1));  // South
    total += get_neighbor_contribution(get_cell(x - 1, y));  // West
    total += get_neighbor_contribution(get_cell(x + 1, y));  // East
    return neighbor_total_to_count(total, 4.0);
}

// Extended Moore: radius 2 (24 neighbors)
fn count_neighbors_extended(x: i32, y: i32) -> u32 {
    var total: f32 = 0.0;
    for (var dy: i32 = -2; dy <= 2; dy++) {
        for (var dx: i32 = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            total += get_neighbor_contribution(get_cell(x + dx, y + dy));
        }
    }
    return neighbor_total_to_count(total, 24.0);
}
```

### 5.3 Hexagonal Neighborhoods (Offset Coordinates)

We use "odd-r" offset coordinates where odd rows shift right by 0.5:

```wgsl
fn count_neighbors_hexagonal(x: i32, y: i32) -> u32 {
    var total: f32 = 0.0;
    let is_odd_row = (y & 1) == 1;
    
    // Top neighbors
    if (is_odd_row) {
        total += get_neighbor_contribution(get_cell(x, y - 1));
        total += get_neighbor_contribution(get_cell(x + 1, y - 1));
    } else {
        total += get_neighbor_contribution(get_cell(x - 1, y - 1));
        total += get_neighbor_contribution(get_cell(x, y - 1));
    }
    
    // Side neighbors (same for both)
    total += get_neighbor_contribution(get_cell(x - 1, y));
    total += get_neighbor_contribution(get_cell(x + 1, y));
    
    // Bottom neighbors
    if (is_odd_row) {
        total += get_neighbor_contribution(get_cell(x, y + 1));
        total += get_neighbor_contribution(get_cell(x + 1, y + 1));
    } else {
        total += get_neighbor_contribution(get_cell(x - 1, y + 1));
        total += get_neighbor_contribution(get_cell(x, y + 1));
    }
    
    return neighbor_total_to_count(total, 6.0);
}
```

### 5.4 Converting Float Totals to Integer Counts

Since vitality modes produce fractional contributions, we need to round:

```wgsl
fn neighbor_total_to_count(total: f32, max_neighbors: f32) -> u32 {
    let clamped = clamp(total, 0.0, max_neighbors);
    return u32(clamped + 0.5);  // Round to nearest integer
}
```

### 5.5 Generalization for Swarms

In swarms, "neighborhood" becomes **perception**:

```typescript
function countNeighborsForAgent(agent: Agent, allAgents: Agent[]): NeighborInfo {
  let total = 0;
  let alignmentSum = { x: 0, y: 0 };
  let positionSum = { x: 0, y: 0 };
  let count = 0;
  
  for (const other of allAgents) {
    if (other === agent) continue;
    
    const dist = distance(agent, other);
    if (dist > agent.perceptionRadius) continue;
    
    // Distance-weighted contribution (like vitality)
    const weight = 1.0 - (dist / agent.perceptionRadius);
    // Or use a custom curve!
    const contribution = lookupInfluenceCurve(weight);
    
    total += contribution;
    alignmentSum.x += other.vx * contribution;
    alignmentSum.y += other.vy * contribution;
    positionSum.x += other.x * contribution;
    positionSum.y += other.y * contribution;
    count++;
  }
  
  return { total, alignmentSum, positionSum, count };
}
```

---

## 6. The Influence Curve: User-Defined Transfer Functions

### 6.1 Monotonic Cubic Hermite Interpolation

We use Fritsch-Carlson monotonic interpolation to prevent overshooting:

```typescript
function monotonicCubicInterpolation(points: CurvePoint[], xVal: number): number {
  const n = points.length;
  if (n === 0) return 0;
  if (n === 1) return points[0].y;
  
  const sorted = [...points].sort((a, b) => a.x - b.x);
  if (xVal <= sorted[0].x) return sorted[0].y;
  if (xVal >= sorted[n - 1].x) return sorted[n - 1].y;
  
  // Find segment
  let i = 0;
  while (i < n - 1 && sorted[i + 1].x < xVal) i++;
  
  // Calculate deltas and slopes
  const deltas: number[] = [];
  const slopes: number[] = [];
  for (let j = 0; j < n - 1; j++) {
    const dx = sorted[j + 1].x - sorted[j].x;
    deltas.push(dx);
    slopes.push(dx === 0 ? 0 : (sorted[j + 1].y - sorted[j].y) / dx);
  }
  
  // Calculate tangents (Fritsch-Carlson method)
  const tangents: number[] = [];
  for (let j = 0; j < n; j++) {
    if (j === 0) tangents.push(slopes[0]);
    else if (j === n - 1) tangents.push(slopes[n - 2]);
    else {
      const m0 = slopes[j - 1];
      const m1 = slopes[j];
      if (m0 * m1 <= 0) tangents.push(0);
      else {
        const w0 = 2 * deltas[j] + deltas[j - 1];
        const w1 = deltas[j] + 2 * deltas[j - 1];
        tangents.push((w0 + w1) / (w0 / m0 + w1 / m1));
      }
    }
  }
  
  // Ensure monotonicity
  for (let j = 0; j < n - 1; j++) {
    const dk = slopes[j];
    if (dk === 0) {
      tangents[j] = 0;
      tangents[j + 1] = 0;
    } else {
      const alpha = tangents[j] / dk;
      const beta = tangents[j + 1] / dk;
      const tau = alpha * alpha + beta * beta;
      if (tau > 9) {
        const scale = 3 / Math.sqrt(tau);
        tangents[j] = scale * alpha * dk;
        tangents[j + 1] = scale * beta * dk;
      }
    }
  }
  
  // Hermite interpolation
  const x0 = sorted[i].x, x1 = sorted[i + 1].x;
  const y0 = sorted[i].y, y1 = sorted[i + 1].y;
  const h = x1 - x0;
  const t = (xVal - x0) / h;
  const t2 = t * t, t3 = t2 * t;
  
  const h00 = 2 * t3 - 3 * t2 + 1;
  const h10 = t3 - 2 * t2 + t;
  const h01 = -2 * t3 + 3 * t2;
  const h11 = t3 - t2;
  
  return h00 * y0 + h10 * h * tangents[i] + h01 * y1 + h11 * h * tangents[i + 1];
}
```

### 6.2 Pre-Sampling for GPU

We sample the curve to 128 points once on CPU, then upload to GPU:

```typescript
const samples = new Float32Array(128);
for (let i = 0; i < 128; i++) {
  const vitality = i / 127;
  samples[i] = clamp(interpolate(points, vitality), -2, 2);
}
device.queue.writeBuffer(vitalityCurveBuffer, 0, samples);
```

### 6.3 Why 128 Samples?

- **Sufficient resolution**: 128 samples gives smooth interpolation for any practical curve
- **Efficient**: Fits in L1 cache on most GPUs
- **Power of 2**: Efficient memory alignment

---

## 7. WebGPU Architecture: Achieving Massive Parallelism

### 7.1 Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        COMPUTE PIPELINE                          │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │ Cell Buffer A│───▶│ Compute      │───▶│ Cell Buffer B│       │
│  │ (read only)  │    │ Shader       │    │ (write)      │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         ▲                   ▲                                    │
│         │                   │                                    │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │ Params       │    │ Vitality     │                           │
│  │ (uniforms)   │    │ Curve (LUT)  │                           │
│  └──────────────┘    └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        RENDER PIPELINE                           │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │ Cell Buffer  │───▶│ Fragment     │───▶│ Canvas       │       │
│  │ (current)    │    │ Shader       │    │ Texture      │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         ▲                   ▲                                    │
│         │                   │                                    │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │ View Params  │    │ Text Bitmap  │                           │
│  │ (uniforms)   │    │ (brush)      │                           │
│  └──────────────┘    └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Device and Context Initialization

```typescript
async function requestWebGPUDevice(): Promise<{ device: GPUDevice; format: GPUTextureFormat }> {
  if (!navigator.gpu) throw new Error('WebGPU not supported');
  
  const adapter = await navigator.gpu.requestAdapter({
    powerPreference: 'high-performance'
  });
  if (!adapter) throw new Error('No GPU adapter');
  
  const device = await adapter.requestDevice({
    requiredFeatures: [],
    requiredLimits: {
      maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
      maxBufferSize: adapter.limits.maxBufferSize
    }
  });
  
  // Handle device loss
  device.lost.then(info => {
    console.error('WebGPU device lost:', info.message);
    // Could implement recovery here
  });
  
  const format = navigator.gpu.getPreferredCanvasFormat();
  return { device, format };
}
```

### 7.3 Buffer Creation

```typescript
// Cell state buffers (2 for ping-pong)
const cellBufferSize = width * height * 4;  // u32 per cell
const cellBuffers = [
  device.createBuffer({
    label: 'Cell State A',
    size: cellBufferSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC
  }),
  device.createBuffer({
    label: 'Cell State B',
    size: cellBufferSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC
  })
];

// Compute params (must be 16-byte aligned!)
const computeParamsBuffer = device.createBuffer({
  label: 'Compute Params',
  size: 64,  // Padded for alignment
  usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
});

// Vitality curve (128 f32 samples)
const vitalityCurveBuffer = device.createBuffer({
  label: 'Vitality Curve',
  size: 128 * 4,  // 512 bytes
  usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
});
```

### 7.4 Pipeline Creation

```typescript
const computeBindGroupLayout = device.createBindGroupLayout({
  entries: [
    { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
    { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
    { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
    { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }
  ]
});

const computePipeline = device.createComputePipeline({
  layout: device.createPipelineLayout({ bindGroupLayouts: [computeBindGroupLayout] }),
  compute: {
    module: device.createShaderModule({ code: computeShaderWGSL }),
    entryPoint: 'main'
  }
});
```

### 7.5 Workgroup Sizing

```wgsl
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let x = i32(global_id.x);
    let y = i32(global_id.y);
    
    // Bounds check (workgroups may overshoot grid)
    if (global_id.x >= params.width || global_id.y >= params.height) {
        return;
    }
    
    // ... compute logic ...
}
```

**Dispatch:**
```typescript
const workgroupsX = Math.ceil(width / 8);
const workgroupsY = Math.ceil(height / 8);
computePass.dispatchWorkgroups(workgroupsX, workgroupsY);
```

**Why 8x8?**
- Good balance for most GPUs
- 64 threads per workgroup (fits in one wave on most architectures)
- Power of 2 for efficient division

---

## 8. Double Buffering: The Ping-Pong Pattern

### 8.1 The Problem

GPU computation is massively parallel. If we read and write the same buffer simultaneously:
- Thread A reads neighbors, including cell B
- Thread B writes to its cell
- Thread A gets stale or inconsistent data

### 8.2 The Solution: Ping-Pong Buffers

```
Step 0: Read A, Write B
Step 1: Read B, Write A
Step 2: Read A, Write B
...
```

**Implementation:**
```typescript
private stepCount = 0;
private computeBindGroups: [GPUBindGroup, GPUBindGroup];

// Create both bind groups upfront
this.computeBindGroups = [
  // A->B: read from cellBuffers[0], write to cellBuffers[1]
  device.createBindGroup({
    entries: [
      { binding: 1, resource: { buffer: cellBuffers[0] } },
      { binding: 2, resource: { buffer: cellBuffers[1] } },
      // ...
    ]
  }),
  // B->A: read from cellBuffers[1], write to cellBuffers[0]
  device.createBindGroup({
    entries: [
      { binding: 1, resource: { buffer: cellBuffers[1] } },
      { binding: 2, resource: { buffer: cellBuffers[0] } },
      // ...
    ]
  })
];

step() {
  const bindGroup = this.computeBindGroups[this.stepCount % 2];
  computePass.setBindGroup(0, bindGroup);
  computePass.dispatchWorkgroups(...);
  this.stepCount++;
}
```

### 8.3 Rendering Reads the Current Buffer

```typescript
render() {
  const currentBuffer = this.cellBuffers[this.stepCount % 2];
  // Use renderBindGroups[stepCount % 2] which reads the current buffer
}
```

---

## 9. Numerical Representations and GPU Data Layout

### 9.1 The Compute Params Buffer

**Critical: GPU buffers must be 16-byte aligned!**

```wgsl
struct Params {
    width: u32,           // offset 0
    height: u32,          // offset 4
    birth_mask: u32,      // offset 8
    survive_mask: u32,    // offset 12
    num_states: u32,      // offset 16
    boundary_mode: u32,   // offset 20
    neighborhood: u32,    // offset 24
    vitality_mode: u32,   // offset 28
    vitality_threshold: f32,  // offset 32
    vitality_ghost: f32,      // offset 36
    vitality_sigmoid: f32,    // offset 40
    vitality_decay: f32,      // offset 44
    _padding1: u32,       // offset 48 (padding for 16-byte alignment)
    _padding2: u32,       // offset 52
    _padding3: u32,       // offset 56
    _padding4: u32,       // offset 60
}
```

**Writing mixed types with DataView:**
```typescript
private updateComputeParams(): void {
  const buffer = new ArrayBuffer(64);
  const view = new DataView(buffer);
  
  view.setUint32(0, this.width, true);  // true = little-endian
  view.setUint32(4, this.height, true);
  view.setUint32(8, this.rule.birthMask, true);
  view.setUint32(12, this.rule.surviveMask, true);
  view.setUint32(16, this.rule.numStates, true);
  view.setUint32(20, boundaryToIndex(this.view.boundaryMode), true);
  view.setUint32(24, this.getNeighborhoodIndex(), true);
  view.setUint32(28, this.getVitalityModeIndex(), true);
  view.setFloat32(32, this.view.vitalityThreshold, true);
  view.setFloat32(36, this.view.vitalityGhostFactor, true);
  view.setFloat32(40, this.view.vitalitySigmoidSharpness, true);
  view.setFloat32(44, this.view.vitalityDecayPower, true);
  // Padding bytes don't need explicit writes
  
  this.device.queue.writeBuffer(this.computeParamsBuffer, 0, buffer);
}
```

### 9.2 The Render Params Buffer

Similarly structured, 128 bytes total:

```typescript
const params = new Float32Array([
  this.width,
  this.height,
  canvasWidth,
  canvasHeight,
  this.view.offsetX,
  this.view.offsetY,
  this.view.zoom,
  this.rule.numStates,
  this.view.showGrid ? 1.0 : 0.0,
  this.view.isLightTheme ? 1.0 : 0.0,
  this.view.aliveColor[0],
  this.view.aliveColor[1],
  this.view.aliveColor[2],
  this.view.brushX,
  this.view.brushY,
  this.view.brushRadius,
  this.getNeighborhoodIndex(),
  this.view.spectrumMode,
  this.view.spectrumFrequency,
  this.view.neighborShading,
  boundaryToIndex(this.view.boundaryMode),
  this.view.brushShape,
  this.view.brushRotation,
  this.view.brushAspectRatio,
  this.view.axisProgress,
  this.textBitmapWidth,
  this.textBitmapHeight
]);
```

### 9.3 Why u32 for Cell State?

- **Single word access**: Atomic, cache-friendly
- **Room for growth**: Could encode additional data in upper bits
- **Alignment**: Natural 4-byte alignment
- **Future**: Could pack multiple cells (u8 per cell = 4 cells per u32)

### 9.4 Memory Layout for Cell Grid

```
Linear array: cells[y * width + x]

Example 4x3 grid:
[0,0] [1,0] [2,0] [3,0]
[0,1] [1,1] [2,1] [3,1]
[0,2] [1,2] [2,2] [3,2]

Memory: [0,0][1,0][2,0][3,0][0,1][1,1][2,1][3,1][0,2][1,2][2,2][3,2]
Index:    0    1    2    3    4    5    6    7    8    9   10   11
```

---

## 10. The Compute Shader: Core CA Logic

### 10.1 Complete Shader Structure

```wgsl
struct Params {
    width: u32,
    height: u32,
    birth_mask: u32,
    survive_mask: u32,
    num_states: u32,
    boundary_mode: u32,
    neighborhood: u32,
    vitality_mode: u32,
    vitality_threshold: f32,
    vitality_ghost: f32,
    vitality_sigmoid: f32,
    vitality_decay: f32,
    _padding1: u32,
    _padding2: u32,
    _padding3: u32,
    _padding4: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> cell_state_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> cell_state_out: array<u32>;
@group(0) @binding(3) var<storage, read> vitality_curve: array<f32>;

// ... helper functions from sections above ...

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let x = i32(global_id.x);
    let y = i32(global_id.y);
    
    // Bounds check
    if (global_id.x >= params.width || global_id.y >= params.height) {
        return;
    }
    
    let idx = global_id.x + global_id.y * params.width;
    let current_state = cell_state_in[idx];
    let neighbors = count_neighbors(x, y);
    
    var new_state: u32 = 0u;
    
    if (params.num_states == 2u) {
        // Standard Life-like rules (2-state)
        if (current_state == 0u) {
            if ((params.birth_mask & (1u << neighbors)) != 0u) {
                new_state = 1u;
            }
        } else {
            if ((params.survive_mask & (1u << neighbors)) != 0u) {
                new_state = 1u;
            }
        }
    } else {
        // Generations rules (multi-state)
        if (current_state == 0u) {
            if ((params.birth_mask & (1u << neighbors)) != 0u) {
                new_state = 1u;
            }
        } else if (current_state == 1u) {
            if ((params.survive_mask & (1u << neighbors)) != 0u) {
                new_state = 1u;
            } else {
                new_state = 2u;  // Start dying
            }
        } else {
            new_state = current_state + 1u;
            if (new_state >= params.num_states) {
                new_state = 0u;  // Dead
            }
        }
    }
    
    cell_state_out[idx] = new_state;
}
```

### 10.2 The Key Insight: Decoupled Aggregation and Transformation

The compute shader cleanly separates:
1. **Aggregation**: `count_neighbors(x, y)` → integer
2. **Transformation**: Bitmask lookup → new state

This separation is what makes generalization possible!

---

## 11. The Render Shader: Visualization Pipeline

### 11.1 Full-Screen Triangle Technique

Instead of drawing a quad (2 triangles, 6 vertices), we draw one oversized triangle:

```wgsl
@vertex
fn vertex_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var pos: vec2<f32>;
    switch (vertex_index) {
        case 0u: { pos = vec2<f32>(-1.0, -1.0); }  // bottom-left
        case 1u: { pos = vec2<f32>(3.0, -1.0); }   // far right (off screen)
        case 2u: { pos = vec2<f32>(-1.0, 3.0); }   // far top (off screen)
        default: { pos = vec2<f32>(0.0, 0.0); }
    }
    
    output.position = vec4<f32>(pos, 0.0, 1.0);
    output.uv = (pos + 1.0) * 0.5;
    output.uv.y = 1.0 - output.uv.y;  // Flip Y
    
    return output;
}
```

**Why?**
- One triangle = 3 vertices, one draw call
- No vertex buffer needed
- GPU clips the excess automatically

### 11.2 State-to-Color Mapping

```wgsl
fn state_to_color(state: u32, num_states: u32) -> vec3<f32> {
    let alive_color = vec3<f32>(params.alive_r, params.alive_g, params.alive_b);
    let bg = get_bg_color();
    
    if (state == 0u) { return bg; }
    if (num_states == 2u) { return alive_color; }
    if (state == 1u) { return alive_color; }
    
    // Dying states: apply spectrum mode
    let dying_progress = f32(state - 1u) / f32(num_states - 1u);
    
    // Apply spectrum frequency (how many times to repeat)
    let spectrum_progress = fract(dying_progress * params.spectrum_frequency);
    
    // Convert alive color to HSL, shift hue based on mode
    let alive_hsl = rgb_to_hsl(alive_color);
    
    // ... 18 different spectrum modes ...
    // Each mode calculates dying_hue, dying_sat, dying_light differently
    
    let dying_rgb = hsl_to_rgb(vec3<f32>(dying_hue, dying_sat, dying_light));
    
    // Blend with background at the very end
    let bg_blend = dying_progress * dying_progress * dying_progress;
    return mix(dying_rgb, bg, bg_blend * 0.6);
}
```

### 11.3 Neighbor Shading for Depth

```wgsl
fn apply_neighbor_shading(color: vec3<f32>, cell_x: i32, cell_y: i32) -> vec3<f32> {
    let mode = i32(params.neighbor_shading);
    if (mode == 0) { return color; }
    
    // Skip expensive counting when extremely zoomed out
    let pixels_per_cell = params.canvas_width / params.zoom;
    if (pixels_per_cell < 0.5) { return color; }
    
    var neighbor_ratio: f32;
    if (mode == 1) {
        neighbor_ratio = count_active_neighbors_normalized(cell_x, cell_y);
    } else {
        neighbor_ratio = sum_neighbor_vitality_normalized(cell_x, cell_y);
    }
    
    // Convert to HSL, adjust saturation/lightness based on neighbor density
    let hsl = rgb_to_hsl(color);
    var new_sat = hsl.y * (0.92 + neighbor_ratio * 0.08);
    // ... theme-aware lightness adjustment ...
    
    return hsl_to_rgb(vec3<f32>(hsl.x, new_sat, new_light));
}
```

---

## 12. Boundary Conditions: Topological Transformations

### 12.1 Nine Supported Topologies

| ID | Mode | X Behavior | Y Behavior |
|----|------|------------|------------|
| 0 | plane | No wrap | No wrap |
| 1 | cylinderX | Wrap | No wrap |
| 2 | cylinderY | No wrap | Wrap |
| 3 | torus | Wrap | Wrap |
| 4 | mobiusX | Wrap + flip Y | No wrap |
| 5 | mobiusY | No wrap | Wrap + flip X |
| 6 | kleinX | Wrap + flip Y | Wrap |
| 7 | kleinY | Wrap | Wrap + flip X |
| 8 | projectivePlane | Wrap + flip Y | Wrap + flip X |

### 12.2 Unified Coordinate Transform

```wgsl
fn get_cell(x: i32, y: i32) -> u32 {
    let w = i32(params.width);
    let h = i32(params.height);
    let mode = params.boundary_mode;
    
    // Determine wrap/flip behavior from mode
    let wraps_x = mode == 1u || mode == 3u || mode == 4u || mode == 6u || mode == 7u || mode == 8u;
    let wraps_y = mode == 2u || mode == 3u || mode == 5u || mode == 6u || mode == 7u || mode == 8u;
    let flips_x = mode == 4u || mode == 6u || mode == 8u;
    let flips_y = mode == 5u || mode == 7u || mode == 8u;
    
    var fx = x;
    var fy = y;
    var x_wraps = 0;
    var y_wraps = 0;
    
    // Handle X coordinate
    if (fx < 0 || fx >= w) {
        if (!wraps_x) { return 0u; }  // Out of bounds = dead
        if (fx < 0) {
            x_wraps = (-fx - 1) / w + 1;
            fx = ((fx % w) + w) % w;
        } else {
            x_wraps = fx / w;
            fx = fx % w;
        }
    }
    
    // Handle Y coordinate (similar)
    if (fy < 0 || fy >= h) {
        if (!wraps_y) { return 0u; }
        // ... same wrapping logic ...
    }
    
    // Apply flips based on wrap count parity
    if (flips_x && (x_wraps & 1) == 1) { fy = h - 1 - fy; }
    if (flips_y && (y_wraps & 1) == 1) { fx = w - 1 - fx; }
    
    let idx = u32(fx) + u32(fy) * params.width;
    return cell_state_in[idx];
}
```

### 12.3 Generalization for Swarms

For swarms, boundaries typically mean:
- **Bounce**: Reverse velocity at edge
- **Wrap**: Teleport to opposite side
- **Attract/Repel**: Force toward/away from center

The same principle applies: abstract the boundary behavior into a transform function.

---

## 13. Performance Optimizations That Matter

### 13.1 Bitmask Rules (O(1) Lookup)

```wgsl
// BAD: Array lookup or conditionals
if (neighbors == 2 || neighbors == 3) { ... }

// GOOD: Single bitwise operation
if ((params.survive_mask & (1u << neighbors)) != 0u) { ... }
```

### 13.2 Workgroup Size Selection

- **8x8 = 64 threads**: Fits in one SIMD wave on most GPUs
- **Power of 2**: Efficient memory coalescing
- **Not too large**: Avoids wasting threads at grid edges

### 13.3 Buffer Alignment

All uniform buffers must be 16-byte aligned. Failing this causes:
- Silent corruption on some GPUs
- Performance degradation on others

### 13.4 Avoiding Dynamic Branching

```wgsl
// BAD: Long if-else chain (divergent branches)
if (mode == 0u) { ... }
else if (mode == 1u) { ... }
else if (mode == 2u) { ... }

// BETTER: Switch statement (compiler can optimize)
switch (mode) {
    case 0u: { ... }
    case 1u: { ... }
    case 2u: { ... }
}

// BEST for simple cases: Branchless math
let contribution = select(0.0, 1.0, state == 1u);
```

### 13.5 Texture vs Buffer for Read-Only Data

For the vitality curve (128 floats, read-only):
- **Storage buffer**: Simple, works well
- **Texture with sampler**: Could enable hardware interpolation

We chose storage buffer for simplicity, with manual linear interpolation.

### 13.6 Step Budgeting

```typescript
const MAX_STEPS_PER_FRAME = 64;
const TIME_BUDGET_MS = 6;

let stepsRun = 0;
const startTime = performance.now();

while (
  simAccMs >= stepMs &&
  stepsRun < MAX_STEPS_PER_FRAME &&
  (performance.now() - startTime) < TIME_BUDGET_MS
) {
  simulation.step();
  simAccMs -= stepMs;
  stepsRun++;
}
```

This prevents frame drops when running at high simulation speeds.

---

## 14. Generalizing to Swarms: A Complete Recipe

### 14.1 The Core Mapping

| CA Concept | Swarm Equivalent |
|------------|------------------|
| Cell position | Agent position (x, y) |
| Cell state (0/1/dying) | Agent vitality/activity |
| Neighbor count | Nearby agent count (within perception) |
| Birth mask | Property increase thresholds |
| Survival mask | Property maintain thresholds |
| Vitality influence | Distance-weighted contributions |
| Custom curve | Arbitrary influence function |

### 14.2 Agent State Structure

```typescript
interface SwarmAgent {
  // Core position/motion
  x: number;
  y: number;
  vx: number;
  vy: number;
  
  // CA-analogous state
  state: number;           // 0 = inactive, 1 = active, 2+ = decaying
  vitality: number;        // 0.0 to 1.0 (derived from state)
  
  // Visual properties (can be CA-modulated)
  color: { h: number; s: number; l: number };
  size: number;
  opacity: number;
  
  // Behavioral properties (can be CA-modulated)
  perceptionRadius: number;
  maxSpeed: number;
  alignmentWeight: number;
  cohesionWeight: number;
  separationWeight: number;
}
```

### 14.3 The Aggregation Step

```typescript
function aggregateNeighborhood(agent: SwarmAgent, allAgents: SwarmAgent[], config: AggregationConfig): NeighborhoodSummary {
  let totalInfluence = 0;
  let alignmentX = 0, alignmentY = 0;
  let cohesionX = 0, cohesionY = 0;
  let separationX = 0, separationY = 0;
  let count = 0;
  
  for (const other of allAgents) {
    if (other === agent) continue;
    
    const dx = other.x - agent.x;
    const dy = other.y - agent.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    
    if (dist > agent.perceptionRadius) continue;
    if (dist < 0.001) continue;  // Avoid division by zero
    
    // Calculate influence based on distance and other's vitality
    const normalizedDist = dist / agent.perceptionRadius;
    const distInfluence = config.useDistanceCurve
      ? lookupCurve(config.distanceCurve, normalizedDist)
      : 1.0 - normalizedDist;
    
    const vitalityInfluence = config.useVitalityCurve
      ? lookupCurve(config.vitalityCurve, other.vitality)
      : other.state === 1 ? 1.0 : other.vitality * config.ghostFactor;
    
    const influence = distInfluence * vitalityInfluence;
    totalInfluence += influence;
    count++;
    
    // Weighted boids components
    alignmentX += other.vx * influence;
    alignmentY += other.vy * influence;
    cohesionX += other.x * influence;
    cohesionY += other.y * influence;
    
    // Separation (inverse distance weighting)
    const sepFactor = influence / (dist * dist);
    separationX -= dx * sepFactor;
    separationY -= dy * sepFactor;
  }
  
  return {
    totalInfluence,
    count,
    avgAlignment: count > 0 ? { x: alignmentX / count, y: alignmentY / count } : { x: 0, y: 0 },
    avgPosition: count > 0 ? { x: cohesionX / count, y: cohesionY / count } : agent,
    separation: { x: separationX, y: separationY }
  };
}
```

### 14.4 The Transformation Step

```typescript
function applyCATransformation(agent: SwarmAgent, summary: NeighborhoodSummary, rules: SwarmCARule): void {
  // Convert total influence to "neighbor count" equivalent
  const neighborEquivalent = Math.round(summary.totalInfluence);
  
  // State transitions (like CA birth/survival)
  if (agent.state === 0) {
    // "Dead" agent: check for "birth"
    if ((rules.birthMask & (1 << neighborEquivalent)) !== 0) {
      agent.state = 1;
      agent.vitality = 1.0;
    }
  } else if (agent.state === 1) {
    // "Alive" agent: check for "survival"
    if ((rules.surviveMask & (1 << neighborEquivalent)) === 0) {
      agent.state = 2;  // Start decay
    }
  } else {
    // Decaying: increment towards "death"
    agent.state++;
    if (agent.state >= rules.numStates) {
      agent.state = 0;
    }
    agent.vitality = (rules.numStates - agent.state) / (rules.numStates - 1);
  }
  
  // Property modulation based on influence
  const influenceNormalized = clamp(summary.totalInfluence / rules.maxExpectedInfluence, 0, 1);
  
  // Modulate behavioral weights
  agent.alignmentWeight = lerp(rules.minAlignment, rules.maxAlignment, 
    lookupCurve(rules.alignmentCurve, influenceNormalized));
  agent.cohesionWeight = lerp(rules.minCohesion, rules.maxCohesion,
    lookupCurve(rules.cohesionCurve, influenceNormalized));
  agent.separationWeight = lerp(rules.minSeparation, rules.maxSeparation,
    lookupCurve(rules.separationCurve, influenceNormalized));
  
  // Modulate visual properties
  agent.size = lerp(rules.minSize, rules.maxSize,
    lookupCurve(rules.sizeCurve, agent.vitality));
  
  // Color from vitality (like CA spectrum modes)
  agent.color = vitalityToColor(agent.vitality, agent.color, rules.spectrumMode);
}
```

### 14.5 The Motion Update

```typescript
function updateMotion(agent: SwarmAgent, summary: NeighborhoodSummary): void {
  // Classic boids steering forces
  let steerX = 0, steerY = 0;
  
  // Alignment: steer towards average heading
  if (summary.count > 0) {
    steerX += (summary.avgAlignment.x - agent.vx) * agent.alignmentWeight;
    steerY += (summary.avgAlignment.y - agent.vy) * agent.alignmentWeight;
  }
  
  // Cohesion: steer towards average position
  if (summary.count > 0) {
    steerX += (summary.avgPosition.x - agent.x) * agent.cohesionWeight;
    steerY += (summary.avgPosition.y - agent.y) * agent.cohesionWeight;
  }
  
  // Separation: steer away from crowding
  steerX += summary.separation.x * agent.separationWeight;
  steerY += summary.separation.y * agent.separationWeight;
  
  // Apply steering
  agent.vx += steerX;
  agent.vy += steerY;
  
  // Limit speed
  const speed = Math.sqrt(agent.vx * agent.vx + agent.vy * agent.vy);
  if (speed > agent.maxSpeed) {
    agent.vx = (agent.vx / speed) * agent.maxSpeed;
    agent.vy = (agent.vy / speed) * agent.maxSpeed;
  }
  
  // Update position
  agent.x += agent.vx;
  agent.y += agent.vy;
}
```

---

## 15. The Boids-CA Hybrid Architecture

### 15.1 GPU Implementation Strategy

For maximum performance, implement on GPU with spatial hashing:

```wgsl
// Spatial hash grid for O(1) neighbor lookup
struct SpatialGrid {
    cell_start: array<u32>,     // Start index for each grid cell
    cell_count: array<u32>,     // Agent count per cell
    agent_indices: array<u32>,  // Sorted agent indices
}

@compute @workgroup_size(64)
fn update_agents(@builtin(global_invocation_id) id: vec3<u32>) {
    let agent_idx = id.x;
    if (agent_idx >= params.num_agents) { return; }
    
    let agent = agents_in[agent_idx];
    
    // Get grid cell
    let cell_x = i32(agent.x / params.cell_size);
    let cell_y = i32(agent.y / params.cell_size);
    
    // Aggregate from neighboring cells
    var summary: NeighborhoodSummary;
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let neighbor_cell = get_cell_index(cell_x + dx, cell_y + dy);
            // ... iterate agents in cell, accumulate influence ...
        }
    }
    
    // Apply CA transformation
    var new_agent = agent;
    apply_ca_rules(&new_agent, summary);
    
    // Update motion
    update_boids_motion(&new_agent, summary);
    
    agents_out[agent_idx] = new_agent;
}
```

### 15.2 Memory Layout for Agents

```typescript
// Structure of Arrays (SoA) for GPU efficiency
interface AgentBuffers {
  positions: Float32Array;     // [x0, y0, x1, y1, ...]
  velocities: Float32Array;    // [vx0, vy0, vx1, vy1, ...]
  states: Uint32Array;         // [state0, state1, ...]
  properties: Float32Array;    // [alignment, cohesion, separation, size, ...]
  colors: Float32Array;        // [h, s, l, h, s, l, ...]
}
```

### 15.3 Double Buffering for Agents

Same ping-pong pattern as CA:

```typescript
step() {
  // Phase 1: Build spatial hash (parallel)
  buildSpatialHash(agentsIn);
  
  // Phase 2: Compute new states (parallel)
  computePass.setBindGroup(0, bindGroups[stepCount % 2]);
  computePass.dispatchWorkgroups(Math.ceil(numAgents / 64));
  
  stepCount++;
}
```

---

## 16. Implementation Checklist for Swarm-CA

### 16.1 Core Data Structures

- [ ] Agent state structure (position, velocity, CA state, properties)
- [ ] Influence curve lookup table (128 samples)
- [ ] Rule specification (birth/survival masks, or continuous curves)
- [ ] Spatial hash grid for efficient neighbor queries

### 16.2 Aggregation Functions

- [ ] Distance-weighted influence calculation
- [ ] Vitality-weighted influence (ghost mode)
- [ ] Custom curve lookup with linear interpolation
- [ ] Boids component aggregation (alignment, cohesion, separation)

### 16.3 Transformation Functions

- [ ] State transition logic (birth/survival/decay)
- [ ] Property modulation from influence
- [ ] Color mapping from vitality (spectrum modes)
- [ ] Behavioral weight modulation

### 16.4 Motion Update

- [ ] Steering force combination
- [ ] Speed limiting
- [ ] Position update
- [ ] Boundary handling

### 16.5 GPU Pipeline

- [ ] Spatial hash build pass
- [ ] Agent update compute pass
- [ ] Render pass (instanced rendering)
- [ ] Double buffer management

### 16.6 Configuration Interface

```typescript
interface SwarmCAConfig {
  // Rule configuration
  rules: {
    birthMask: number;
    surviveMask: number;
    numStates: number;
    maxExpectedInfluence: number;
  };
  
  // Influence configuration
  influence: {
    distanceCurve: CurvePoint[];    // How distance affects influence
    vitalityCurve: CurvePoint[];    // How decay affects influence
    ghostFactor: number;             // Fallback if no curve
  };
  
  // Property modulation curves
  modulation: {
    alignmentCurve: CurvePoint[];
    cohesionCurve: CurvePoint[];
    separationCurve: CurvePoint[];
    sizeCurve: CurvePoint[];
    speedCurve: CurvePoint[];
  };
  
  // Visual
  visual: {
    spectrumMode: number;
    spectrumFrequency: number;
    baseColor: [number, number, number];
  };
}
```

---

## Conclusion

The Games of Life codebase demonstrates that **cellular automaton rules are fundamentally about weighted spatial aggregation followed by lookup-based transformation**. This pattern is:

1. **Geometry-independent**: Works on grids, hex grids, or continuous space
2. **Highly parallelizable**: Each cell/agent can be computed independently
3. **Expressive**: Simple rules create emergent complexity
4. **Efficient**: Bitmask operations and pre-sampled curves enable O(1) transformations

To generalize this to swarms:

1. Replace grid adjacency with **spatial proximity** (perception radius)
2. Replace binary neighbor count with **weighted influence sum**
3. Replace state transition with **property modulation**
4. Add **motion physics** (boids steering) that respects CA-modulated weights

The key architectural decisions:
- **Double buffering** prevents race conditions
- **Workgroup sizing** (8x8 or 64 threads) maximizes GPU utilization
- **16-byte alignment** is mandatory for GPU buffers
- **Bitmask rules** provide O(1) lookup
- **Pre-sampled curves** enable complex influence functions without branching

The result is a system where simple, tunable rules create beautiful emergent behavior—whether on a grid of cells or a swarm of agents.

---

*This document was generated from the Games of Life codebase to enable AI-assisted generalization to swarm dynamics. May your simulations be performant and your emergent behavior be beautiful.*
