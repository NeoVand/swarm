# GPU Boids Simulation: Technical Architecture

This document describes the GPU-accelerated flocking simulation implemented in this codebase. It is intended for scientists and developers who want to understand, extend, or build upon this implementation.

## Overview

The simulation runs entirely on the GPU using WebGPU compute shaders. Each frame executes a **5-pass compute pipeline** (with 2 conditional sub-passes) followed by a **single render pass** with 3 draw calls (walls, trails, boids). The system supports up to 15,000 boids at 60 FPS on modern hardware, with 7 species, 10 inter-species behaviors, and 9 boundary topologies.

## Parallelization Strategy

### Core Principle: One Thread Per Boid

The simulation is parallelized at the boid level. Each compute shader invocation handles exactly one boid, identified by `global_invocation_id.x`. Workgroups contain 256 threads (`@workgroup_size(256)`), and the CPU dispatches `ceil(boidCount / 256)` workgroups.

### The Neighbor Query Problem

Naively, each boid checking all other boids would be O(n²) — prohibitively expensive. We solve this using a **spatial hash grid**, reducing complexity to O(n × k) where k is the average neighbors per cell (typically 10-50).

## The Compute Pipeline

Each frame executes these passes in strict sequence:

### Pass 1: Clear Cell Counts
```
Input:  cellCounts buffer (atomic u32[])
Output: All cells set to 0
Work:   ceil(totalCells / 256) workgroups
```
Resets the per-cell boid counters using parallel writes.

### Pass 1b: Clear Cell Offsets
```
Input:  cellOffsets buffer (atomic u32[])
Output: All offsets set to 0
Work:   ceil(totalCells / 256) workgroups
```
Resets the per-cell scatter offsets (used in Pass 4). This runs in parallel with Pass 1 conceptually, but must complete before Pass 4.

### Pass 2: Count Boids Per Cell
```
Input:  positions buffer, grid dimensions, perception radius
Output: cellCounts (atomically incremented), boidCellIndices (cell ID per boid)
Work:   ceil(boidCount / 256) workgroups
```
Each boid computes its cell index as `clamp(floor(position / cellSize), 0, gridDim - 1)` and atomically increments that cell's count. The clamping prevents out-of-bounds access for boids at canvas edges. The cell size equals the perception radius, ensuring neighbors are within a 3×3 cell neighborhood.

### Pass 3: Parallel Prefix Sum (Blelloch Scan)
```
Input:  cellCounts
Output: prefixSums (exclusive scan), blockSums (intermediate)
Work:   ceil(totalCells / 512) workgroups
```
Computes exclusive prefix sums so `prefixSums[cell]` gives the starting index for that cell in the sorted array. Uses the Blelloch algorithm with workgroup shared memory (512 elements per workgroup, 256 threads each loading 2 elements).

### Pass 3b: Aggregate Block Sums (Conditional)
```
Input:  prefixSums, blockSums
Output: prefixSums (adjusted with block offsets)
Work:   ceil(totalCells / 256) workgroups
Runs:   Only when prefixSumWorkgroups > 1 (i.e., totalCells > 512)
```
For grids larger than 512 cells, the initial prefix sum produces per-block results. This pass adds accumulated block sums to finalize the global prefix sum.

### Pass 4: Scatter Boids to Sorted Array
```
Input:  prefixSums, cellOffsets, boidCellIndices
Output: sortedIndices (boid indices sorted by cell)
Work:   ceil(boidCount / 256) workgroups
```
Each boid writes its index to `sortedIndices[prefixSums[myCell] + atomicAdd(cellOffsets[myCell], 1)]`. The `cellOffsets` buffer (cleared in Pass 1b) tracks how many boids have been placed in each cell so far. After this pass, all boids in the same cell are contiguous in memory.

### Pass 5: Simulate Flocking
```
Input:  positionsIn, velocitiesIn, prefixSums, cellCounts, sortedIndices, species data, wall texture
Output: positionsOut, velocitiesOut, trails
Work:   ceil(boidCount / 256) workgroups
```
The main simulation kernel. Each boid:
1. Queries neighbors in a 3×3 (or 5×5 for some algorithms) cell neighborhood
2. Computes alignment, cohesion, and separation forces
3. Applies inter-species interaction forces
4. Applies cursor interaction forces
5. Applies wall avoidance forces
6. Updates velocity and position with boundary handling

### Double Buffering (Ping-Pong)

Position and velocity buffers are double-buffered. Frame N reads from buffer A and writes to buffer B; frame N+1 reads from B and writes to A. This prevents race conditions where a boid reads another boid's updated (rather than current-frame) position.

## Algorithm Variants

Five flocking algorithms are available, selectable at runtime:

| Algorithm | Neighbor Selection | Cell Search | Use Case |
|-----------|-------------------|-------------|----------|
| **Topological K-NN** | k nearest (max 24) | 5×5 cells | Realistic animal behavior |
| **Smooth Metric** | All within perception | 3×3 cells + jitter | Default, good balance |
| **Hash-Free** | All within perception | 5×5 cells, per-boid offset | No grid artifacts |
| **Stochastic** | Random sampling | 3×3 + random samples | Large populations |
| **Density Adaptive** | All within perception | 5×5 cells | Prevents over-clustering |

All algorithms use **smooth weighting kernels** rather than hard cutoffs:
- `smoothKernel(d, r) = (1 - d/r)³` for alignment/cohesion
- `separationKernel(d, r) = (1 - d/r)² × 2/(d/r + 0.5)` for separation (stronger at close range)

## Boundary Topologies

The simulation supports 9 boundary configurations via a modular `BoundaryConfig` system:

| Mode | X-Axis | Y-Axis | Notes |
|------|--------|--------|-------|
| Plane | Bounce | Bounce | Standard bounded box |
| Cylinder X/Y | Wrap/Bounce | Bounce/Wrap | Single wrapping axis |
| Torus | Wrap | Wrap | Classic wrap-around |
| Möbius X/Y | Wrap+flip | Bounce/Wrap+flip | Y-velocity flips on X-wrap |
| Klein X/Y | Wrap+flip | Wrap / Wrap+flip | One flip axis, one normal |
| Projective Plane | Wrap+flip | Wrap+flip | Both axes flip on wrap |

For flip boundaries, neighbor queries use `getCellIndexWithFlip()` to correctly search mirrored cells, and `transformNeighborVelocity()` flips neighbor velocities when seen across a flip boundary.

## Data Layout and GPU Buffers

### Per-Boid Buffers
| Buffer | Type | Size | Purpose |
|--------|------|------|---------|
| positionA/B | vec2<f32>[] | boidCount × 8 bytes | Ping-pong positions |
| velocityA/B | vec2<f32>[] | boidCount × 8 bytes | Ping-pong velocities |
| speciesIds | u32[] | boidCount × 4 bytes | Species assignment |
| boidCellIndices | u32[] | boidCount × 4 bytes | Cell index per boid |
| sortedIndices | u32[] | boidCount × 4 bytes | Cell-sorted boid indices |
| trails | vec2<f32>[][] | boidCount × 100 × 8 bytes | Ring buffer of past positions |

### Grid Buffers (Pre-allocated for minimum perception)

Grid buffers are sized for the **maximum possible grid**, calculated using `MIN_PERCEPTION = 20` pixels. This means `maxCells = ceil(canvasWidth/20) × ceil(canvasHeight/20)`. Pre-allocation avoids buffer reallocation when the user changes perception radius.

| Buffer | Type | Size | Purpose |
|--------|------|------|---------|
| cellCounts | atomic<u32>[] | maxCells × 4 bytes | Boids per cell |
| prefixSums | u32[] | maxCells × 4 bytes | Cell start indices |
| cellOffsets | atomic<u32>[] | maxCells × 4 bytes | Scatter atomics |

### Species Buffers (Uniform)
| Buffer | Layout | Purpose |
|--------|--------|---------|
| speciesParams | 7 × 5 × vec4<f32> | Per-species flocking, visual, cursor params |
| interactionMatrix | 7 × 7 × vec4<f32> | Behavior, strength, range per species pair |

## Constraints for Extension

### Storage Buffer Limits
WebGPU limits storage buffers per bind group (typically 8). The simulation uses **2 bind groups** in the simulate pass to stay within limits. Adding new per-boid storage buffers may require creating a third bind group.

### Workgroup Memory
The prefix sum shader uses 512 × 4 = 2048 bytes of shared memory. Workgroup shared memory is limited (typically 16-32 KB). New algorithms using shared memory must respect this.

### Atomic Operations
Cell counting and scattering use `atomicAdd`. WebGPU atomics are limited to `u32` and `i32`. For floating-point reduction (e.g., computing flock center-of-mass on GPU), you'd need to implement fixed-point encoding or use multiple passes.

### Uniform Buffer Alignment
The uniform buffer must be 256-byte aligned and is currently 256 bytes. Adding parameters requires updating:
1. The WGSL `Uniforms` struct (in all shaders that use it)
2. The TypeScript `updateUniforms()` function
3. Potentially increasing buffer size to next 256-byte boundary

### Adding New Species Parameters
Currently, each species has 5 × vec4 (20 floats). To add parameters:
1. Extend the `Species` interface in `types.ts`
2. Update `updateSpeciesParams()` in `buffers.ts`
3. Add getter functions in `simulate.wgsl` (e.g., `getSpeciesNewParam()`)

### Adding New Interaction Behaviors
The interaction matrix stores behavior ID (0-9), strength, and range. To add behavior 10+:
1. Add to `InteractionBehavior` enum in `types.ts`
2. Add a new case in `calculateInterSpeciesForce()` in `simulate.wgsl`

### Performance Considerations
- **Cell size = perception radius**: Smaller perception means more cells and more prefix sum work, but fewer neighbors per cell. The sweet spot is 60-100 pixels.
- **Population limits**: Beyond ~20,000 boids, prefix sum becomes a bottleneck. For larger populations, consider hierarchical grids or GPU-side spatial data structures.
- **Trail rendering**: Trails use instanced rendering with 6 vertices per segment × trailLength segments. Long trails (>50) with many boids can become render-bound.

## Render Pipeline

After compute, a single render pass executes three draw calls in order:

1. **Walls**: Full-screen quad (6 vertices) sampling wall texture with edge detection for stroke effect
2. **Trails**: Instanced quads (6 vertices × `boidCount × (trailLength - 1)` instances) with age-based fading and width tapering
3. **Boids**: Instanced triangles (18 vertices × `boidCount × 4` instances) — 4× instances provide ghost copies for wrapped boundary rendering; unused ghosts are discarded by moving them off-screen

All draw calls use standard alpha blending and read from the current-frame position/velocity buffers (the "output" side of the ping-pong).

## File Structure

```
src/lib/
├── shaders/
│   ├── simulate.wgsl       # Main flocking simulation (Pass 5)
│   ├── count.wgsl          # Spatial hash counting (Pass 2)
│   ├── prefix_sum.wgsl     # Blelloch scan (Pass 3, 3b)
│   ├── scatter.wgsl        # Cell-sorted scattering (Pass 4)
│   ├── clear.wgsl          # Cell count reset (Pass 1)
│   ├── clear_offsets.wgsl  # Cell offset reset (Pass 1b)
│   ├── boid.wgsl           # Boid rendering
│   ├── trail.wgsl          # Trail rendering
│   └── wall.wgsl           # Wall rendering
├── webgpu/
│   ├── simulation.ts       # Main loop orchestration
│   ├── compute.ts          # Compute pipeline/bind group setup
│   ├── render.ts           # Render pipeline setup
│   ├── buffers.ts          # Buffer creation and uniform packing
│   └── types.ts            # TypeScript types, enums, defaults
└── stores/
    └── simulation.ts       # Svelte stores for reactive state
```

## Summary

This implementation achieves high performance through:
1. **Spatial hashing** to reduce neighbor queries from O(n²) to O(n × k)
2. **Parallel prefix sum** for efficient cell-to-index mapping
3. **Double buffering** to prevent read/write hazards
4. **Pre-allocated buffers** sized for worst-case grid dimensions
5. **Smooth kernels** for continuous, artifact-free flocking behavior

Extensions should respect the storage buffer limits, uniform alignment requirements, and the strict pass ordering that ensures correct spatial hash construction before simulation.
