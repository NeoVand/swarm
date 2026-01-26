// Spectral structure shader - computes approximate Fiedler vector (2nd eigenvector of graph Laplacian)
// Creates beautiful structural colorization that reveals graph partitions and clusters

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

// Spectral modes
const SPECTRAL_ANGULAR: u32 = 0u;
const SPECTRAL_RADIAL: u32 = 1u;
const SPECTRAL_ASYMMETRY: u32 = 2u;
const SPECTRAL_FLOW_ANGULAR: u32 = 3u;
const SPECTRAL_FLOW_RADIAL: u32 = 4u;
const SPECTRAL_FLOW_DIVERGENCE: u32 = 5u;

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

// Bind group 0: Spatial hash and position data (read-only)
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> velocities: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(4) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(5) var<storage, read> sortedIndices: array<u32>;

// Bind group 1: Species and metrics (metrics.x = density used as degree estimate)
@group(1) @binding(0) var<storage, read> speciesIds: array<u32>;
@group(1) @binding(1) var<storage, read> metrics: array<vec4<f32>>;

// Bind group 2: Rank ping-pong buffers
@group(2) @binding(0) var<storage, read> ranksIn: array<f32>;
@group(2) @binding(1) var<storage, read_write> ranksOut: array<f32>;

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

// Initialize with position-based angle
@compute @workgroup_size(256)
fn init_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let boidIndex = id.x;
    if (boidIndex >= uniforms.boidCount) { return; }
    
    let pos = positions[boidIndex];
    let cx = pos.x / uniforms.canvasWidth - 0.5;
    let cy = pos.y / uniforms.canvasHeight - 0.5;
    ranksOut[boidIndex] = atan2(cy, cx) / 6.283185 + 0.5;
}

// Local cluster structure - computes various structural metrics relative to neighborhood
// Mode 0 (Angular): Which direction from local center (color wheel effect)
// Mode 1 (Radial): Distance from local center (edge vs core)
// Mode 2 (Asymmetry): How lopsided is the neighborhood (boundary detection)
// Mode 3 (Flow Angular): Velocity angle relative to local average flow
// Mode 4 (Flow Radial): Moving toward/away from cluster center
// Mode 5 (Flow Divergence): Velocity alignment with neighbors
@compute @workgroup_size(256)
fn iter_main(@builtin(global_invocation_id) id: vec3<u32>) {
    let boidIndex = id.x;
    if (boidIndex >= uniforms.boidCount) { return; }
    
    let myPos = positions[boidIndex];
    let myVel = velocities[boidIndex];
    let mySpeed = length(myVel);
    let perception = uniforms.perception;
    
    // Compute weighted center of mass, average velocity, and other statistics
    var centerOfMass = vec2<f32>(0.0);
    var avgVelocity = vec2<f32>(0.0);
    var totalWeight: f32 = 0.0;
    var neighborCount: u32 = 0u;
    var maxDist: f32 = 0.0;
    
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // Iterate over 5x5 cell neighborhood (needed for cellSize = perception/2)
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let ncx = myCellX + dx;
            let ncy = myCellY + dy;
            
            if (!shouldSearchCell(ncx, ncy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(ncx, ncy, myCellY);
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
                    centerOfMass += otherPos * weight;
                    avgVelocity += velocities[otherIdx] * weight;
                    totalWeight += weight;
                    neighborCount++;
                    maxDist = max(maxDist, dist);
                }
            }
        }
    }
    
    var result: f32;
    let prevVal = ranksIn[boidIndex];
    
    // Smoothing factor - higher = more smoothing (less jitter but slower response)
    let smoothing = 0.85;  // 85% previous, 15% new
    
    if (totalWeight > 1e-6 && neighborCount >= 3u) {
        // Compute center of mass and average velocity
        centerOfMass /= totalWeight;
        avgVelocity /= totalWeight;
        
        // Vector from center of mass to this boid
        let relativePos = myPos - centerOfMass;
        let distFromCenter = length(relativePos);
        
        // For flow modes
        let avgFlowDir = normalize(avgVelocity + vec2<f32>(0.0001, 0.0001));
        let myVelDir = normalize(myVel + vec2<f32>(0.0001, 0.0001));
        
        switch (uniforms.spectralMode) {
            case SPECTRAL_ANGULAR: {
                // Angular position relative to local center (0-1 range)
                let angle = atan2(relativePos.y, relativePos.x);
                // Circular smoothing
                let prevAngle = (prevVal - 0.5) * 6.283185;
                let prevVec = vec2<f32>(cos(prevAngle), sin(prevAngle));
                let newVec = vec2<f32>(cos(angle), sin(angle));
                let avgVec = smoothing * prevVec + (1.0 - smoothing) * newVec;
                let smoothedAngle = atan2(avgVec.y, avgVec.x);
                result = smoothedAngle / 6.283185 + 0.5;
            }
            case SPECTRAL_RADIAL: {
                // Distance from local center normalized by perception
                let normalizedDist = clamp(distFromCenter / (perception * 0.5), 0.0, 1.0);
                result = smoothing * prevVal + (1.0 - smoothing) * normalizedDist;
            }
            case SPECTRAL_ASYMMETRY: {
                // How far the center of mass is from us
                let asymmetry = clamp(distFromCenter / (perception * 0.3), 0.0, 1.0);
                result = smoothing * prevVal + (1.0 - smoothing) * asymmetry;
            }
            case SPECTRAL_FLOW_ANGULAR: {
                // Angle of velocity relative to radial direction from center
                // Shows tangential (circling) vs radial (expanding/contracting) motion
                // Creates beautiful spiral/vortex patterns
                if (distFromCenter > 0.001) {
                    let radialDir = relativePos / distFromCenter;
                    // Angle between velocity and radial direction
                    let tangential = myVelDir.x * radialDir.y - myVelDir.y * radialDir.x;
                    let radial = dot(myVelDir, radialDir);
                    let flowAngle = atan2(tangential, radial);
                    // Circular smoothing
                    let prevAngle = (prevVal - 0.5) * 6.283185;
                    let prevVec = vec2<f32>(cos(prevAngle), sin(prevAngle));
                    let newVec = vec2<f32>(cos(flowAngle), sin(flowAngle));
                    let avgVec = smoothing * prevVec + (1.0 - smoothing) * newVec;
                    let smoothedAngle = atan2(avgVec.y, avgVec.x);
                    result = smoothedAngle / 6.283185 + 0.5;
                } else {
                    // Near center - use velocity direction directly
                    let velAngle = atan2(myVel.y, myVel.x);
                    let prevAngle = (prevVal - 0.5) * 6.283185;
                    let prevVec = vec2<f32>(cos(prevAngle), sin(prevAngle));
                    let newVec = vec2<f32>(cos(velAngle), sin(velAngle));
                    let avgVec = smoothing * prevVec + (1.0 - smoothing) * newVec;
                    let smoothedAngle = atan2(avgVec.y, avgVec.x);
                    result = smoothedAngle / 6.283185 + 0.5;
                }
            }
            case SPECTRAL_FLOW_RADIAL: {
                // Radial velocity: moving toward or away from local center
                // Inverted for better visual intuition: toward center = high (warm), away = low (cool)
                if (distFromCenter > 0.001) {
                    let radialDir = relativePos / distFromCenter;
                    let radialVel = dot(myVel, radialDir);
                    // Invert: moving toward center (-radialVel) = high value
                    // Scale by speed for better sensitivity
                    let normalizedRadial = clamp(-radialVel / (uniforms.maxSpeed * 0.5), -1.0, 1.0);
                    let newVal = normalizedRadial * 0.5 + 0.5;
                    result = smoothing * prevVal + (1.0 - smoothing) * newVal;
                } else {
                    result = smoothing * prevVal + (1.0 - smoothing) * 0.5;
                }
            }
            case SPECTRAL_FLOW_DIVERGENCE: {
                // Speed contrast: my speed relative to local average speed
                // More sensitive: cubed penalty for slow, steeper boost for fast
                let avgSpeed = length(avgVelocity);
                if (avgSpeed > 0.01) {
                    let speedRatio = mySpeed / avgSpeed;
                    var newVal: f32;
                    if (speedRatio <= 1.0) {
                        // Slower boids: cubed penalty toward 0 (very dark)
                        // 0→0, 0.5→0.0625, 0.8→0.256, 1→0.5
                        newVal = speedRatio * speedRatio * speedRatio * 0.5;
                    } else {
                        // Faster boids: steep boost, saturates at 1.5x speed
                        // 1→0.5, 1.25→0.75, 1.5+→1.0
                        let t = min(speedRatio, 1.5);
                        newVal = 0.5 + (t - 1.0) * 1.0;
                    }
                    result = smoothing * prevVal + (1.0 - smoothing) * newVal;
                } else if (mySpeed > 0.01) {
                    // Neighbors slow but I'm moving - bright
                    result = smoothing * prevVal + (1.0 - smoothing) * 1.0;
                } else {
                    // Both slow - dark
                    result = smoothing * prevVal + (1.0 - smoothing) * 0.0;
                }
            }
            default: {
                result = prevVal;
            }
        }
    } else {
        // Isolated or sparse - use global metrics
        let cx = myPos.x / uniforms.canvasWidth - 0.5;
        let cy = myPos.y / uniforms.canvasHeight - 0.5;
        
        switch (uniforms.spectralMode) {
            case SPECTRAL_ANGULAR: {
                let newAngle = atan2(cy, cx);
                let prevAngle = (prevVal - 0.5) * 6.283185;
                let prevVec = vec2<f32>(cos(prevAngle), sin(prevAngle));
                let newVec = vec2<f32>(cos(newAngle), sin(newAngle));
                let avgVec = smoothing * prevVec + (1.0 - smoothing) * newVec;
                let smoothedAngle = atan2(avgVec.y, avgVec.x);
                result = smoothedAngle / 6.283185 + 0.5;
            }
            case SPECTRAL_RADIAL: {
                result = clamp(sqrt(cx * cx + cy * cy) * 2.0, 0.0, 1.0);
            }
            case SPECTRAL_ASYMMETRY: {
                result = 0.5;
            }
            case SPECTRAL_FLOW_ANGULAR: {
                // Velocity angle relative to position from canvas center
                let posDir = normalize(vec2<f32>(cx, cy) + vec2<f32>(0.0001, 0.0001));
                let tangential = myVel.x * posDir.y - myVel.y * posDir.x;
                let radial = dot(myVel, posDir);
                let flowAngle = atan2(tangential, radial);
                let prevAngle = (prevVal - 0.5) * 6.283185;
                let prevVec = vec2<f32>(cos(prevAngle), sin(prevAngle));
                let newVec = vec2<f32>(cos(flowAngle), sin(flowAngle));
                let avgVec = smoothing * prevVec + (1.0 - smoothing) * newVec;
                let smoothedAngle = atan2(avgVec.y, avgVec.x);
                result = smoothedAngle / 6.283185 + 0.5;
            }
            case SPECTRAL_FLOW_RADIAL: {
                // Radial velocity relative to canvas center (inverted)
                let posDir = normalize(vec2<f32>(cx, cy) + vec2<f32>(0.0001, 0.0001));
                let radialVel = dot(myVel, posDir);
                let normalizedRadial = clamp(-radialVel / (uniforms.maxSpeed * 0.5), -1.0, 1.0);
                result = smoothing * prevVal + (1.0 - smoothing) * (normalizedRadial * 0.5 + 0.5);
            }
            case SPECTRAL_FLOW_DIVERGENCE: {
                // Isolated boids: use speed relative to max, cubed for sensitivity
                let speedRatio = mySpeed / uniforms.maxSpeed;
                let newVal = speedRatio * speedRatio * speedRatio; // Cubed: more sensitive
                result = smoothing * prevVal + (1.0 - smoothing) * clamp(newVal, 0.0, 1.0);
            }
            default: {
                result = 0.5;
            }
        }
    }
    
    ranksOut[boidIndex] = result;
}
