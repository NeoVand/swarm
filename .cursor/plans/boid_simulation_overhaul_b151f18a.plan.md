---
name: Boid Simulation Overhaul
overview: Fix critical bugs in species flocking, synchronize shader uniforms, and implement "Locally Perfect Spatial Hashing" to eliminate grid artifacts. This is a multi-phase refactoring that requires careful ordering to avoid breaking changes.
todos:
  - id: phase0-uniforms
    content: "CRITICAL PREREQUISITE: Synchronize all Uniform structs across all 12 shader files to match CPU-side layout"
    status: pending
  - id: phase1-species-knn
    content: "Fix species bug in algorithmTopologicalKNN: Filter by species when BUILDING K-NN list, not just consuming"
    status: pending
  - id: phase1-species-others
    content: "Fix species bug in other 4 algorithms: Add species check in neighbor iteration loops"
    status: pending
  - id: phase2-buffer-sizing
    content: "Update buffer sizing for locally perfect hash: totalSlots = 9 * reducedWidth * reducedHeight"
    status: pending
  - id: phase2-uniforms-field
    content: Add reducedWidth and totalSlots to Uniforms struct and update all shaders
    status: pending
  - id: phase2-hash-function
    content: Implement locally perfect hash in count.wgsl, simulate.wgsl, diffuse.wgsl, rank.wgsl
    status: pending
  - id: phase2-clear-shaders
    content: Update clear.wgsl and clear_offsets.wgsl to iterate over totalSlots instead of gridWidth*gridHeight
    status: pending
  - id: phase2-boundary-verify
    content: Verify locally perfect hash works correctly with flip boundaries (Möbius, Klein, Projective)
    status: pending
  - id: phase3-performance
    content: "Benchmark performance: compare old vs new at 10k, 30k, 50k boids"
    status: pending
  - id: phase4-consolidate
    content: After validation passes, consolidate to single algorithm and remove algorithm selector
    status: pending
isProject: false
---

# Boid Simulation Algorithm Overhaul

## Important Context for Implementers

This plan addresses multiple interconnected issues in a WebGPU-based boid simulation. The codebase has:

- **5 different flocking algorithms** (TopologicalKNN, SmoothMetric, HashFree, Stochastic, DensityAdaptive)
- **9 boundary topology modes** (Plane, Cylinder, Torus, Möbius, Klein, Projective)
- **Multi-species support** with inter-species interactions (flee, chase, cohere, etc.)
- **12 WGSL shader files** that share a Uniforms struct (currently inconsistent!)

**DO NOT skip phases or reorder them.** Phase 0 is a critical prerequisite.

---

## Problem Summary

### Problem 1: Species Flocking Bug (Behavioral)

All 5 flocking algorithms apply alignment, cohesion, and separation forces to ALL neighbors regardless of species. This causes:

- Species to flock together even when they should ignore each other
- Predator/prey dynamics to be broken (prey flocks WITH predators)
- Inter-species "flee" interactions to fight against same-species "cohesion"

**Location**: `src/lib/shaders/simulate.wgsl` - all 5 `algorithm*` functions

**Root cause**: The neighbor iteration loops accumulate `alignmentSum`, `cohesionSum`, `separationSum` without checking `speciesIds[otherIdx] == mySpecies`.

### Problem 2: Grid Artifacts (Visual)

At high densities (10k+ boids), visible square grid patterns appear. This is caused by:

- `cellSize = perception` (cells exactly match perception radius)
- Simple floor-division hashing: `hash = y * gridWidth + x`
- Boids near cell boundaries see different neighbor sets than boids just across the boundary

**Current mitigations that DON'T fully work**:

- Hash-free algorithm: per-boid random offset (deterministic, doesn't vary per frame)
- Smooth metric algorithm: global jitter (shifts entire grid, doesn't help relative boundaries)

### Problem 3: Uniform Struct Inconsistency (CRITICAL)

**This was discovered during code review and is a blocker for all other work.**

The `Uniforms` struct is defined differently across shader files:

| Shader | cursorVortex | saturationSource | brightnessSource | spectralMode |

|--------|--------------|------------------|------------------|--------------|

| simulate.wgsl | YES | NO | NO | NO |

| boid.wgsl | YES | YES | YES | YES |

| trail.wgsl | YES | YES | YES | YES |

| rank.wgsl | YES | YES | YES | YES |

| count.wgsl | NO | NO | NO | NO |

| scatter.wgsl | NO | NO | NO | NO |

| diffuse.wgsl | YES | NO | NO | NO |

| clear.wgsl | NO | NO | NO | NO |

| clear_offsets.wgsl | NO | NO | NO | NO |

| prefix_sum.wgsl | NO | NO | NO | NO |

| write_metrics.wgsl | YES | NO | NO | NO |

The CPU-side `updateUniforms()` in `buffers.ts` writes fields in a specific order. Shaders with mismatched structs read garbage for fields at wrong offsets. **This causes undefined behavior.**

---

## Solution: Locally Perfect Spatial Hashing

Based on research by Steffen Haug (2024): https://haug.codes/blog/locally-perfect-hashing/

### Core Concept

Traditional hashing: `hash = y * gridWidth + x` (row-major)

- Problem: Two cells in a 3x3 neighborhood CAN hash to the same bucket in a compact table

Locally perfect hashing: `hash = M * beta + kappa`

- `M = 9` (number of equivalence classes for 3x3 neighborhoods)
- `kappa = 3 * (x % 3) + (y % 3)` (position within repeating 3x3 pattern)
- `beta = (y / 3) * reducedWidth + (x / 3)` (which 3x3 block)

**Guarantee**: In ANY 3x3 neighborhood, the 9 cells have kappa values {0,1,2,3,4,5,6,7,8} - all different. Since `hash % 9 = kappa`, no two neighbors can collide.

### Visual Representation

```
Grid cells with their kappa values (3x3 pattern repeats infinitely):
┌───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ 0 │ 3 │ 6 │ 0 │ 3 │ 6 │ 0 │ 3 │ 6 │
├───┼───┼───┼───┼───┼───┼───┼───┼───┤
│ 1 │ 4 │ 7 │ 1 │ 4 │ 7 │ 1 │ 4 │ 7 │
├───┼───┼───┼───┼───┼───┼───┼───┼───┤
│ 2 │ 5 │ 8 │ 2 │ 5 │ 8 │ 2 │ 5 │ 8 │
├───┼───┼───┼───┼───┼───┼───┼───┼───┤
│ 0 │ 3 │ 6 │ 0 │ 3 │ 6 │ 0 │ 3 │ 6 │
└───┴───┴───┴───┴───┴───┴───┴───┴───┘

Any 3x3 window contains exactly one of each kappa value.
```

---

## Phase 0: Uniform Struct Synchronization (CRITICAL PREREQUISITE)

**DO THIS FIRST. All other phases depend on this.**

### Files to Update

ALL shader files must have identical Uniforms struct matching this layout:

```wgsl
struct Uniforms {
    canvasWidth: f32,          // 0
    canvasHeight: f32,         // 1
    cellSize: f32,             // 2
    gridWidth: u32,            // 3
    gridHeight: u32,           // 4
    boidCount: u32,            // 5
    trailLength: u32,          // 6
    trailHead: u32,            // 7
    alignment: f32,            // 8
    cohesion: f32,             // 9
    separation: f32,           // 10
    perception: f32,           // 11
    maxSpeed: f32,             // 12
    maxForce: f32,             // 13
    noise: f32,                // 14
    rebels: f32,               // 15
    boundaryMode: u32,         // 16
    cursorMode: u32,           // 17
    cursorShape: u32,          // 18
    cursorVortex: u32,         // 19  <-- MISSING in some shaders
    cursorForce: f32,          // 20
    cursorRadius: f32,         // 21
    cursorX: f32,              // 22
    cursorY: f32,              // 23
    cursorPressed: u32,        // 24
    cursorActive: u32,         // 25
    boidSize: f32,             // 26
    colorMode: u32,            // 27
    colorSpectrum: u32,        // 28
    sensitivity: f32,          // 29
    deltaTime: f32,            // 30
    time: f32,                 // 31
    frameCount: u32,           // 32
    algorithmMode: u32,        // 33
    kNeighbors: u32,           // 34
    sampleCount: u32,          // 35
    idealDensity: f32,         // 36
    timeScale: f32,            // 37
    saturationSource: u32,     // 38  <-- MISSING in some shaders
    brightnessSource: u32,     // 39  <-- MISSING in some shaders
    spectralMode: u32,         // 40  <-- MISSING in some shaders
    // WILL ADD IN PHASE 2:
    // reducedWidth: u32,      // 41
    // totalSlots: u32,        // 42
}
```

### Shaders Requiring Updates

1. `count.wgsl` - Add cursorVortex, saturationSource, brightnessSource, spectralMode
2. `scatter.wgsl` - Add cursorVortex, saturationSource, brightnessSource, spectralMode
3. `clear.wgsl` - Add cursorVortex, saturationSource, brightnessSource, spectralMode
4. `clear_offsets.wgsl` - Add cursorVortex, saturationSource, brightnessSource, spectralMode
5. `prefix_sum.wgsl` - Add cursorVortex, saturationSource, brightnessSource, spectralMode
6. `diffuse.wgsl` - Add saturationSource, brightnessSource, spectralMode
7. `write_metrics.wgsl` - Add saturationSource, brightnessSource, spectralMode
8. `simulate.wgsl` - Add saturationSource, brightnessSource, spectralMode

### Verification

After updating, verify the CPU-side `updateUniforms()` in `buffers.ts` (around line 334) writes fields in the exact same order. The current implementation ends at offset ~40.

---

## Phase 1: Fix Species Flocking Bug

### 1.1 Fix algorithmTopologicalKNN (SPECIAL CASE)

**File**: `src/lib/shaders/simulate.wgsl`, function `algorithmTopologicalKNN`

This algorithm has TWO loops:

1. **Loop 1** (neighbor cell iteration): Builds K-NN list AND computes separation
2. **Loop 2** (K-NN consumption): Computes alignment/cohesion from K-NN list

**CRITICAL**: Filter by species in LOOP 1 when building the K-NN list. Otherwise, a boid surrounded by other-species will have a K-NN list full of wrong-species and zero same-species for flocking.

```wgsl
// In Loop 1, when deciding to add to K-NN list:
let otherSpecies = speciesIds[otherIdx];

// Only add same-species to K-NN list for flocking
if (otherSpecies == mySpecies) {
    if (distSq < knnDistSq[k - 1u]) {
        // ... insertion sort into knnIndex ...
    }
}

// Separation can be same-species only (chosen design decision)
if (otherSpecies == mySpecies && distSq < separationRadius * separationRadius) {
    separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
    separationCount++;
}

// Metrics (density) can include all species for visualization
densitySum += weight;
```

### 1.2 Fix Other 4 Algorithms

**Functions**: `algorithmSmoothMetric`, `algorithmHashFree`, `algorithmStochastic`, `algorithmDensityAdaptive`

These have simpler single-loop structures. Add species check in the neighbor iteration:

```wgsl
// After getting otherIdx in the neighbor loop:
let otherSpecies = speciesIds[otherIdx];

// Flocking forces: same-species only
if (otherSpecies == mySpecies) {
    if (weight > 0.0) {
        alignmentSum += otherVel * weight;
        cohesionSum += delta * weight;
        totalWeight += weight;
    }
    
    if (dist < separationRadius) {
        separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
        separationCount++;
    }
}

// Metrics: all species (for density visualization)
if (weight > 0.0) {
    densitySum += weight;
    metricWeight += weight;
    cxx += weight * delta.x * delta.x;
    cxy += weight * delta.x * delta.y;
    cyy += weight * delta.y * delta.y;
}
```

### Design Decision Made

**Separation**: Same-species only. This allows species to overlap/pass through each other, which may look odd but preserves species isolation. The inter-species interaction system (`calculateInterSpeciesForce`) handles cross-species forces.

---

## Phase 2: Implement Locally Perfect Spatial Hashing

### 2.1 Update Buffer Sizing

**File**: `src/lib/webgpu/buffers.ts`

**CRITICAL**: The hash space size changes!

```typescript
// Old calculation:
const totalCells = gridWidth * gridHeight;

// New calculation:
const reducedWidth = Math.ceil(gridWidth / 3);
const reducedHeight = Math.ceil(gridHeight / 3);
const totalSlots = 9 * reducedWidth * reducedHeight;
```

**WARNING**: `totalSlots` can be LARGER than `totalCells` due to ceiling division.

Example for 1920x1080 canvas with perception=100:

- Old: gridWidth=20, gridHeight=11 → totalCells = 220
- New: reducedWidth=7, reducedHeight=4 → totalSlots = 252

Update buffer allocations:

- `cellCounts`: size = `totalSlots` (was gridWidth * gridHeight)
- `cellOffsets`: size = `totalSlots`
- `prefixSums`: size = `totalSlots`

### 2.2 Add Uniforms Fields

**Files**: All shader files (after Phase 0 sync), `buffers.ts`

Add to Uniforms struct:

```wgsl
reducedWidth: u32,    // ceil(gridWidth / 3)
totalSlots: u32,      // 9 * reducedWidth * reducedHeight
```

Update `updateUniforms()` in `buffers.ts` to write these values.

### 2.3 Update count.wgsl

**Current hash function**:

```wgsl
fn getCellIndex(pos: vec2<f32>) -> u32 {
    let cellX = clamp(u32(pos.x / uniforms.cellSize), 0u, uniforms.gridWidth - 1u);
    let cellY = clamp(u32(pos.y / uniforms.cellSize), 0u, uniforms.gridHeight - 1u);
    return cellY * uniforms.gridWidth + cellX;  // Row-major
}
```

**New hash function**:

```wgsl
const M: u32 = 9u;

fn getCellIndex(pos: vec2<f32>) -> u32 {
    let cellX = clamp(u32(pos.x / uniforms.cellSize), 0u, uniforms.gridWidth - 1u);
    let cellY = clamp(u32(pos.y / uniforms.cellSize), 0u, uniforms.gridHeight - 1u);
    
    // Locally perfect hash
    let kappa = 3u * (cellX % 3u) + (cellY % 3u);
    let beta = (cellY / 3u) * uniforms.reducedWidth + (cellX / 3u);
    
    return M * beta + kappa;
}
```

### 2.4 Update clear.wgsl and clear_offsets.wgsl

These shaders iterate over cells to zero them out. Update iteration bound:

```wgsl
// Old:
let totalCells = uniforms.gridWidth * uniforms.gridHeight;
if (cellIndex >= totalCells) { return; }

// New:
if (cellIndex >= uniforms.totalSlots) { return; }
```

### 2.5 Update simulate.wgsl

Update both `getCellIndex` and `getCellIndexWithFlip` functions:

```wgsl
const M: u32 = 9u;

fn getCellIndex(cx: i32, cy: i32) -> u32 {
    // Wrap coordinates to valid range
    let wcx = ((cx % i32(uniforms.gridWidth)) + i32(uniforms.gridWidth)) % i32(uniforms.gridWidth);
    let wcy = ((cy % i32(uniforms.gridHeight)) + i32(uniforms.gridHeight)) % i32(uniforms.gridHeight);
    
    // Locally perfect hash
    let kappa = 3u * (u32(wcx) % 3u) + (u32(wcy) % 3u);
    let beta = (u32(wcy) / 3u) * uniforms.reducedWidth + (u32(wcx) / 3u);
    
    return M * beta + kappa;
}

fn getCellIndexWithFlip(cx: i32, cy: i32, myCellY: i32) -> u32 {
    let cfg = getBoundaryConfig();
    var wcx = cx;
    var wcy = cy;
    let gw = i32(uniforms.gridWidth);
    let gh = i32(uniforms.gridHeight);
    
    // Handle flip boundaries (Möbius, Klein, Projective)
    if (cfg.flipOnWrapX && (cx < 0 || cx >= gw)) {
        wcx = ((cx % gw) + gw) % gw;
        wcy = gh - 1 - wcy;
    } else {
        wcx = ((wcx % gw) + gw) % gw;
    }
    
    if (cfg.flipOnWrapY && (cy < 0 || cy >= gh)) {
        wcy = ((wcy % gh) + gh) % gh;
        wcx = gw - 1 - wcx;
    } else {
        wcy = ((wcy % gh) + gh) % gh;
    }
    
    // Apply locally perfect hash AFTER flip adjustments
    let kappa = 3u * (u32(wcx) % 3u) + (u32(wcy) % 3u);
    let beta = (u32(wcy) / 3u) * uniforms.reducedWidth + (u32(wcx) / 3u);
    
    return M * beta + kappa;
}
```

### 2.6 Update diffuse.wgsl and rank.wgsl

These shaders also have `getCellIndex` and `getCellIndexWithFlip` functions (duplicated code). Apply the same changes.

**Note**: Consider refactoring to share this code, but that's out of scope for this plan.

### 2.7 Verify Flip Boundary Behavior

**POTENTIAL ISSUE**: When Y coordinate flips (`wcy = gh - 1 - wcy`) on Möbius/Klein boundaries, the kappa value changes. If `gh % 3 != 0`, cells that were "neighbors" might hash to different equivalence classes after the flip.

**Verification steps**:

1. Test with gridHeight divisible by 3 (e.g., perception values that make gh=9, 12, 15)
2. Test with gridHeight NOT divisible by 3
3. Visually inspect Möbius/Klein/Projective modes for artifacts at wrap boundaries

**Fallback**: If flip boundaries break, consider keeping simple row-major hash for flip boundary modes only.

---

## Phase 3: Performance Validation

**DO NOT proceed to Phase 4 until this passes.**

### Benchmarks Required

| Test | Metric | Acceptable |

|------|--------|------------|

| 10k boids, Torus mode | Frame time | < 16ms (60fps) |

| 30k boids, Torus mode | Frame time | < 33ms (30fps) |

| 50k boids, Torus mode | Frame time | < 50ms (20fps) |

| 30k boids, Möbius mode | Visual | No artifacts at boundary |

| 30k boids, Klein mode | Visual | No artifacts at boundary |

### Memory Access Analysis

Locally perfect hashing changes memory layout:

- Old: Cells are contiguous by row (good cache locality for horizontal scans)
- New: Cells are strided by 9 (kappa classes interleaved)

Monitor for:

- Increased cache misses
- GPU memory bandwidth saturation

---

## Phase 4: Algorithm Consolidation

**Only after Phase 3 validation passes.**

### Recommended Final Algorithm

Keep `algorithmHashFree` as the sole production algorithm because:

- Uses 5x5 cell search (thorough neighbor coverage)
- Per-boid grid offset reduces systematic bias
- No stochastic noise (unlike `algorithmStochastic`)
- Good performance (unlike exhaustive K-NN)

With locally perfect hashing added, the per-boid offset becomes less critical but doesn't hurt.

### UI Changes

**File**: `src/lib/components/ControlPanel.svelte`

Options:

1. Remove algorithm selector entirely
2. Hide behind developer/debug flag
3. Keep for A/B comparison during rollout

### Code Cleanup

Either:

- Comment out unused algorithm functions (preserve for reference)
- Delete entirely (cleaner but loses history)

---

## Files Changed Summary

| File | Phase | Changes |

|------|-------|---------|

| `src/lib/shaders/count.wgsl` | 0, 2 | Sync uniforms, new hash function |

| `src/lib/shaders/scatter.wgsl` | 0 | Sync uniforms |

| `src/lib/shaders/clear.wgsl` | 0, 2 | Sync uniforms, update iteration bound |

| `src/lib/shaders/clear_offsets.wgsl` | 0, 2 | Sync uniforms, update iteration bound |

| `src/lib/shaders/prefix_sum.wgsl` | 0 | Sync uniforms |

| `src/lib/shaders/simulate.wgsl` | 0, 1, 2 | Sync uniforms, species fix, new hash |

| `src/lib/shaders/diffuse.wgsl` | 0, 2 | Sync uniforms, new hash |

| `src/lib/shaders/rank.wgsl` | 0, 2 | Sync uniforms, new hash |

| `src/lib/shaders/write_metrics.wgsl` | 0 | Sync uniforms |

| `src/lib/shaders/boid.wgsl` | 0 | Verify uniforms (may already be correct) |

| `src/lib/shaders/trail.wgsl` | 0 | Verify uniforms (may already be correct) |

| `src/lib/webgpu/buffers.ts` | 2 | Buffer sizing, uniforms write |

| `src/lib/webgpu/types.ts` | 2 | Add reducedWidth, totalSlots types |

| `src/lib/components/ControlPanel.svelte` | 4 | Remove/hide algorithm selector |

---

## Risk Mitigation

1. **Uniform sync (Phase 0)**: Test ALL features after sync - cursor interaction, wall drawing, spectral colors, etc.

2. **Species fix (Phase 1)**: Can be deployed independently. Provides immediate behavioral improvement.

3. **Locally perfect hash (Phase 2)**: Keep old hash function commented out. Add runtime flag to switch if needed.

4. **Flip boundaries**: If Möbius/Klein/Projective break, can use simple hash for those modes only.

5. **Performance**: If benchmarks fail, the old algorithm code is preserved.

---

## Testing Checklist

### Phase 0 Tests

- [ ] Cursor attract/repel works
- [ ] Wall drawing works
- [ ] All color modes display correctly
- [ ] Spectral/flow visualizations work

### Phase 1 Tests

- [ ] Single species behaves normally
- [ ] Two species with "ignore" don't flock together
- [ ] Two species with "flee" separate properly
- [ ] Predator/prey dynamics work (chase + flee)

### Phase 2 Tests

- [ ] No grid artifacts at 30k boids
- [ ] No grid artifacts at 50k boids
- [ ] Torus wrapping works correctly
- [ ] Möbius wrapping works correctly (check boundary)
- [ ] Klein wrapping works correctly (check boundary)
- [ ] Projective plane works correctly

### Phase 3 Tests

- [ ] 10k boids: 60fps
- [ ] 30k boids: 30fps
- [ ] 50k boids: 20fps

### Phase 4 Tests

- [ ] Algorithm selector removed/hidden
- [ ] Default algorithm is hash-free with locally perfect hashing