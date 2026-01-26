// Diffusion smoothing shader - smooths random features across the neighbor graph
// Creates spectral-like color patterns by iteratively averaging features with neighbors

struct Uniforms {
    canvasWidth: f32,
    canvasHeight: f32,
    cellSize: f32,
    gridWidth: u32,
    gridHeight: u32,
    boidCount: u32,
    trailLength: u32,
    trailHead: u32,
    alignment: f32,
    cohesion: f32,
    separation: f32,
    perception: f32,
    maxSpeed: f32,
    maxForce: f32,
    noise: f32,
    rebels: f32,
    boundaryMode: u32,
    cursorMode: u32,
    cursorShape: u32,
    cursorVortex: u32,
    cursorForce: f32,
    cursorRadius: f32,
    cursorX: f32,
    cursorY: f32,
    cursorPressed: u32,
    cursorActive: u32,
    boidSize: f32,
    colorMode: u32,
    colorSpectrum: u32,
    sensitivity: f32,
    deltaTime: f32,
    time: f32,
    frameCount: u32,
    algorithmMode: u32,
    kNeighbors: u32,
    sampleCount: u32,
    idealDensity: f32,
    timeScale: f32,
    saturationSource: u32,
    brightnessSource: u32,
    spectralMode: u32,
    // Locally perfect hashing
    reducedWidth: u32,
    totalSlots: u32,
}

// Boundary modes
const PLANE: u32 = 0u;
const CYLINDER_X: u32 = 1u;
const CYLINDER_Y: u32 = 2u;
const TORUS: u32 = 3u;
const MOBIUS_X: u32 = 4u;
const MOBIUS_Y: u32 = 5u;
const KLEIN_X: u32 = 6u;
const KLEIN_Y: u32 = 7u;
const PROJECTIVE_PLANE: u32 = 8u;

struct BoundaryConfig {
    wrapX: bool,
    wrapY: bool,
    flipOnWrapX: bool,
    flipOnWrapY: bool,
    bounceX: bool,
    bounceY: bool,
}

fn getBoundaryConfig() -> BoundaryConfig {
    var cfg: BoundaryConfig;
    switch (uniforms.boundaryMode) {
        case PLANE: {
            cfg.wrapX = false; cfg.wrapY = false;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = true; cfg.bounceY = true;
        }
        case CYLINDER_X: {
            cfg.wrapX = true; cfg.wrapY = false;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = false; cfg.bounceY = true;
        }
        case CYLINDER_Y: {
            cfg.wrapX = false; cfg.wrapY = true;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = true; cfg.bounceY = false;
        }
        case TORUS: {
            cfg.wrapX = true; cfg.wrapY = true;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = false; cfg.bounceY = false;
        }
        case MOBIUS_X: {
            cfg.wrapX = true; cfg.wrapY = false;
            cfg.flipOnWrapX = true; cfg.flipOnWrapY = false;
            cfg.bounceX = false; cfg.bounceY = true;
        }
        case MOBIUS_Y: {
            cfg.wrapX = false; cfg.wrapY = true;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = true;
            cfg.bounceX = true; cfg.bounceY = false;
        }
        case KLEIN_X: {
            cfg.wrapX = true; cfg.wrapY = true;
            cfg.flipOnWrapX = true; cfg.flipOnWrapY = false;
            cfg.bounceX = false; cfg.bounceY = false;
        }
        case KLEIN_Y: {
            cfg.wrapX = true; cfg.wrapY = true;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = true;
            cfg.bounceX = false; cfg.bounceY = false;
        }
        case PROJECTIVE_PLANE: {
            cfg.wrapX = true; cfg.wrapY = true;
            cfg.flipOnWrapX = true; cfg.flipOnWrapY = true;
            cfg.bounceX = false; cfg.bounceY = false;
        }
        default: {
            cfg.wrapX = false; cfg.wrapY = false;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = true; cfg.bounceY = true;
        }
    }
    return cfg;
}

// Bind group 0: Spatial hash and position data (read-only for diffusion)
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(3) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(4) var<storage, read> sortedIndices: array<u32>;

// Bind group 1: Species and metrics
@group(1) @binding(0) var<storage, read> speciesIds: array<u32>;
@group(1) @binding(1) var<storage, read> metrics: array<vec4<f32>>;

// Bind group 2: Feature ping-pong buffers
@group(2) @binding(0) var<storage, read> featuresIn: array<f32>;
@group(2) @binding(1) var<storage, read_write> featuresOut: array<f32>;

// Hash function for random initialization
fn hash(n: u32) -> f32 {
    var x = n;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return f32(x) / f32(0xffffffffu);
}

// Smooth kernel for neighbor weighting
fn smoothKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius) { return 0.0; }
    let t = 1.0 - dist / radius;
    return t * t * t;
}

// Get shortest delta accounting for boundary wrapping
fn getNeighborDelta(myPos: vec2<f32>, otherPos: vec2<f32>) -> vec2<f32> {
    let cfg = getBoundaryConfig();
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    
    var delta = otherPos - myPos;
    
    if (cfg.wrapX && !cfg.flipOnWrapX) {
        if (delta.x > w * 0.5) { delta.x -= w; }
        else if (delta.x < -w * 0.5) { delta.x += w; }
    }
    
    if (cfg.wrapY && !cfg.flipOnWrapY) {
        if (delta.y > h * 0.5) { delta.y -= h; }
        else if (delta.y < -h * 0.5) { delta.y += h; }
    }
    
    return delta;
}

// Locally perfect hashing constant
const M: u32 = 9u;

// Get cell index with proper wrapping
// Uses locally perfect hashing to eliminate grid artifacts
fn getCellIndex(cx: i32, cy: i32) -> u32 {
    let wcx = ((cx % i32(uniforms.gridWidth)) + i32(uniforms.gridWidth)) % i32(uniforms.gridWidth);
    let wcy = ((cy % i32(uniforms.gridHeight)) + i32(uniforms.gridHeight)) % i32(uniforms.gridHeight);
    
    // Locally perfect hash
    let kappa = 3u * (u32(wcx) % 3u) + (u32(wcy) % 3u);
    let beta = (u32(wcy) / 3u) * uniforms.reducedWidth + (u32(wcx) / 3u);
    
    return M * beta + kappa;
}

// Get cell index accounting for flip boundaries
// Uses locally perfect hashing to eliminate grid artifacts
fn getCellIndexWithFlip(cx: i32, cy: i32, myCellY: i32) -> u32 {
    let cfg = getBoundaryConfig();
    var wcx = cx;
    var wcy = cy;
    let gw = i32(uniforms.gridWidth);
    let gh = i32(uniforms.gridHeight);
    
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

// Check if we should search this neighboring cell
fn shouldSearchCell(cx: i32, cy: i32) -> bool {
    let cfg = getBoundaryConfig();
    let gw = i32(uniforms.gridWidth);
    let gh = i32(uniforms.gridHeight);
    
    if (!cfg.wrapX && (cx < 0 || cx >= gw)) { return false; }
    if (!cfg.wrapY && (cy < 0 || cy >= gh)) { return false; }
    
    return true;
}

// Initialize features with position-based values for interesting spatial patterns
@compute @workgroup_size(256)
fn init_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let boidIndex = id.x;
    if (boidIndex >= uniforms.boidCount) { return; }
    
    // Use position to create spatial gradients that diffusion will smooth
    let pos = positions[boidIndex];
    let normalizedX = pos.x / uniforms.canvasWidth;
    let normalizedY = pos.y / uniforms.canvasHeight;
    
    // Add some randomness for variety within spatial regions
    let seed = boidIndex * 1000003u + 12345u;
    let noise = hash(seed) * 0.3;
    
    // Create diagonal gradient pattern with noise
    // Golden ratio (0.618) creates non-repeating pattern
    featuresOut[boidIndex] = fract(normalizedX * 2.0 + normalizedY * 1.236 + noise);
}

// Diffusion iteration - smooth features across same-species neighbors
@compute @workgroup_size(256)
fn iter_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let boidIndex = id.x;
    if (boidIndex >= uniforms.boidCount) { return; }
    
    let myPos = positions[boidIndex];
    let myFeat = featuresIn[boidIndex];
    let perception = uniforms.perception;
    
    var neighborSum: f32 = 0.0;
    var weightSum: f32 = 0.0;
    
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // Iterate over 5x5 cell neighborhood (needed for cellSize = perception/2)
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!shouldSearchCell(cx, cy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(cx, cy, myCellY);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            for (var i = 0u; i < cellCount && i < 64u; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positions[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq >= perception * perception) { continue; }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    neighborSum += featuresIn[otherIdx] * weight;
                    weightSum += weight;
                }
            }
        }
    }
    
    // Pure diffusion: blend own value with neighbor average
    let alpha = 0.3;  // Diffusion rate
    var newFeat = myFeat;
    if (weightSum > 1e-6) {
        let neighborAvg = neighborSum / weightSum;
        newFeat = (1.0 - alpha) * myFeat + alpha * neighborAvg;
    }
    
    featuresOut[boidIndex] = newFeat;
}
