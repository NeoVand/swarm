# GPU Parallelism Lessons for L-System Visualization

*A knowledge transfer document from the Swarm boid simulation to guide building a parallel L-system renderer*

---

## Part 1: Core GPU Architecture Patterns

### The Golden Rule: Keep Everything on the GPU

The single most important lesson: **never read data back from GPU to CPU during runtime**. Our simulation achieves 60 FPS with 15,000 particles because all computation and visualization happens entirely on the GPU. The CPU only sends small uniform updates (~256 bytes/frame).

```
CPU → GPU (per frame):     ~256 bytes uniforms
GPU → CPU (per frame):     0 bytes (fire-and-forget)
```

For L-systems, this means: **derive, interpret, AND render entirely in compute/render shaders**. Don't fall into the trap of deriving on CPU and uploading geometry each frame.

### Ping-Pong Buffers for Iterative Algorithms

Any iterative algorithm (like L-system derivation over multiple generations) needs read/write isolation:

```wgsl
// Frame N: read from bufferA, write to bufferB
// Frame N+1: read from bufferB, write to bufferA
```

Create dual buffer sets and swap bindings each iteration. This eliminates race conditions without locks. For L-systems, you'll want ping-pong buffers for the symbol string as it expands through generations.

### Workgroup Size: Start with 256

All our compute shaders use `@workgroup_size(256)`. This is the sweet spot for most GPUs:
- Fills GPU wavefronts efficiently (AMD=64, NVIDIA=32, Apple=32)
- Allows good shared memory usage
- Works well on both desktop and mobile

```wgsl
@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    if (idx >= uniforms.count) { return; }  // Early exit for excess threads
    // ... work
}
```

### Parallel Prefix Sum (Essential for L-Systems!)

This is **the most important algorithm** for parallel L-systems. When you apply production rules, each symbol may expand to different lengths. You need prefix sum to know where each thread should write its output.

**Our implementation uses Blelloch scan:**

1. **Up-sweep (reduce)**: Build partial sums in shared memory
2. **Down-sweep**: Propagate prefix sums back down

```wgsl
// Per-workgroup prefix sum with block aggregation
var<workgroup> sharedData: array<u32, 512>;  // 2 elements per thread

// Phase 1: Local prefix sum within workgroup
// Phase 2: Store workgroup total to blockSums[]
// Phase 3: Single-thread cumulative sum of blockSums
// Phase 4: Add block offsets back to get global prefix
```

For L-systems: compute output length per symbol → prefix sum → parallel scatter to correct positions.

### Spatial Hashing for Neighbor Queries

If your L-system interpretation needs local context (nearby branches, collision detection), use **locally perfect hashing**:

```wgsl
// M=9 equivalence classes guarantee no collision in any 3×3 neighborhood
let kappa = 3u * (cellX % 3u) + (cellY % 3u);
let beta = (cellY / 3u) * reducedWidth + (cellX / 3u);
let cellIndex = 9u * beta + kappa;
```

This gives O(1) neighbor lookup with zero hash collisions in the search window.

---

## Part 2: Rendering at Scale

### GPU Instancing: One Draw Call for Everything

We render 15,000 boids × 4 edge-wrap copies = 60,000 instances in **one draw call**:

```typescript
renderPass.draw(18, boidCount * 4);  // 18 vertices per shape, 60k instances
```

For L-systems: batch all line segments or geometry into a single instanced draw. Each instance reads its transform from a storage buffer:

```wgsl
@vertex
fn vs_main(@builtin(instance_index) instanceId: u32) -> VertexOutput {
    let segment = segments[instanceId];  // Read from storage buffer
    // Transform local vertex by segment's position/rotation/scale
}
```

### Vertex Generation in Shader

Don't upload vertex arrays—generate geometry procedurally in the vertex shader:

```wgsl
fn getShapeVertex(shape: u32, vertexIndex: u32) -> vec2<f32> {
    // Generate triangle fan vertices mathematically
    let angle = f32(vertexIndex) * TAU / f32(sides);
    return vec2<f32>(cos(angle), sin(angle));
}
```

For L-system branches: generate tube/line geometry from a single line segment definition.

### Alpha Blending, No Depth Buffer

For organic visuals with many overlapping elements, we skip depth testing entirely:

```typescript
fragment: {
    targets: [{
        blend: {
            color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' },
            alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' }
        }
    }]
},
primitive: { cullMode: 'none' }
```

This is faster and creates beautiful layered visuals. Consider additive blending (`dstFactor: 'one'`) for glowing effects.

---

## Part 3: Data-Driven Visualization

### Three-Channel HSL in Shader

Our killer feature: **any data metric can drive any visual channel**. Users map different L-system properties (depth, age, branch angle, growth rate) to hue, saturation, or brightness independently:

```wgsl
// Each channel reads from different data source
let hue = selectMetric(uniforms.hueSource, symbolData);
let sat = selectMetric(uniforms.satSource, symbolData);  
let light = selectMetric(uniforms.lightSource, symbolData);

// Apply user curves for remapping
hue = lookupCurve(CURVE_HUE, hue);
sat = lookupCurve(CURVE_SAT, sat);
light = lookupCurve(CURVE_LIGHT, light);

output.color = hslToRgb(hue, sat, light);
```

### Curve-Based Remapping (User-Controlled)

Sample user-drawn curves to 64 floats and upload once:

```typescript
// CPU: Sample curve to 64 values
const samples = new Float32Array(64);
for (let i = 0; i < 64; i++) {
    samples[i] = monotonicCubicInterpolation(userPoints, i / 63);
}
device.queue.writeBuffer(curveBuffer, 0, samples);
```

```wgsl
// GPU: Fast linear interpolation lookup
fn lookupCurve(curveId: u32, t: f32) -> f32 {
    let pos = clamp(t, 0.0, 1.0) * 63.0;
    let idx = u32(floor(pos));
    return mix(curves[curveId * 64 + idx], curves[curveId * 64 + idx + 1], fract(pos));
}
```

This lets users create S-curves, thresholds, inversions—any remapping they want.

---

## Part 4: Mobile & Performance Optimization

### Adaptive Complexity

Detect mobile and scale down:

```typescript
const isMobile = /Android|iPhone|iPad/i.test(navigator.userAgent) || width < 768;
const maxSymbols = isMobile ? 50_000 : 200_000;
const maxIterations = isMobile ? 6 : 10;
```

### Lazy GPU Resource Creation

Don't create everything upfront. Use dirty flags:

```typescript
export const needsBufferReallocation = writable(false);

// Only reallocate when user changes max iterations
function setMaxIterations(n: number) {
    params.update(p => ({ ...p, maxIterations: n }));
    needsBufferReallocation.set(true);
}
```

### Single Command Buffer Per Frame

Batch all compute + render passes into one submission:

```typescript
const encoder = device.createCommandEncoder();
encodeDerivationPass(encoder, ...);   // L-system rules
encodeInterpretPass(encoder, ...);    // Turtle interpretation
encodeRenderPass(encoder, ...);       // Final render
device.queue.submit([encoder.finish()]);
```

---

## Part 5: L-System Specific Strategies

### Parallel Derivation Algorithm

Based on academic research achieving **17.7 billion symbols/second**:

1. **Symbol Expansion**: Each thread reads one input symbol, looks up production rule
2. **Length Prefix Sum**: Compute where each thread's output starts
3. **Parallel Write**: All threads write their production in parallel

```wgsl
@compute @workgroup_size(256)
fn derive(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    let symbol = inputSymbols[idx];
    let rule = productionRules[symbol];
    let outputStart = prefixSums[idx];
    
    // Write rule.length symbols starting at outputStart
    for (var i = 0u; i < rule.length; i++) {
        outputSymbols[outputStart + i] = rule.symbols[i];
    }
}
```

### Parallel Turtle Interpretation

The hard part: turtle state depends on previous commands. Solution: **parallel scan** on turtle state:

1. Each command becomes a transform matrix
2. Prefix multiply (matrix scan) gives absolute transform at each point
3. All geometry generation happens in parallel

```wgsl
// Each command has a local transform
fn commandToMatrix(cmd: u32, params: vec4<f32>) -> mat3x3<f32> {
    switch(cmd) {
        case CMD_FORWARD: return translateMatrix(params.x);
        case CMD_ROTATE: return rotateMatrix(params.x);
        case CMD_PUSH: return identityMatrix();  // Branch handled differently
        // ...
    }
}
```

### Branch Stack Handling

The `[` and `]` brackets in L-systems create a tree structure. Parallel approach:

1. First pass: compute bracket nesting depth at each position
2. Second pass: match brackets (parallel parenthesis matching)
3. Use depth + matched bracket info to compute correct transforms

---

## Part 6: UI Architecture

### Svelte Store Pattern

Centralize all parameters in typed stores with setter functions:

```typescript
export const params = writable<LSystemParams>(DEFAULT_PARAMS);

export function setAxiom(value: string) {
    params.update(p => ({ ...p, axiom: value }));
    needsRegeneration.set(true);
}
```

### Reactive Derivation (Svelte 5 Runes)

```svelte
let currentParams = $derived($params);
let symbolCount = $derived(calculateSymbolCount(currentParams));
```

### Dirty Flags for Expensive Operations

```typescript
export const needsRegeneration = writable(false);  // Full re-derive
export const needsRerender = writable(false);       // Just redraw
export const rulesDirty = writable(false);          // Upload new rules
```

---

## What We Could Have Done Better

1. **Subgroup Operations**: WebGPU now supports `subgroupAdd`, `subgroupBroadcast` for faster reductions within warps—use these instead of full workgroup barriers when possible.

2. **Indirect Dispatch**: For variable-length L-systems, use `dispatchWorkgroupsIndirect` so the GPU determines workgroup count from a buffer, avoiding CPU readback.

3. **Timestamp Queries**: WebGPU supports `GPUQuerySet` for profiling—we should have used this to identify bottlenecks earlier.

4. **Storage Texture**: For trail rendering, storage textures might be faster than our buffer approach.

5. **Persistent Threads**: For very long iterative algorithms, a persistent thread model (threads loop until work is done) can reduce dispatch overhead.

---

## Quick Reference: Buffer Layout for L-Systems

| Buffer | Type | Size | Purpose |
|--------|------|------|---------|
| symbolsA/B | u32[] | maxSymbols | Ping-pong symbol storage |
| prefixSums | u32[] | maxSymbols | Output write positions |
| rules | struct[] | 256 × maxRuleLength | Production rules lookup |
| transforms | mat3x3[] | maxSymbols | Computed turtle transforms |
| geometry | vec4[] | maxSymbols × 2 | Line segment endpoints |
| uniforms | struct | 256 bytes | Frame-varying parameters |
| curves | f32[] | 64 × numCurves | Color remapping curves |

---

*Remember: The GPU wants to do the same thing to millions of elements simultaneously. Design your data structures and algorithms to feed that hunger. When in doubt, add another compute pass rather than reading back to CPU.*
