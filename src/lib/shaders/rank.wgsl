// Local structure and flow metrics with temporal smoothing.
// Each boid's target depends on positions/velocities, never on neighbours' ranks.
// Note: This shader requires common.wgsl to be prepended at load time

// Spectral modes (unique to this shader)
const SPECTRAL_ANGULAR: u32 = 0u;
const SPECTRAL_RADIAL: u32 = 1u;
const SPECTRAL_ASYMMETRY: u32 = 2u;
const SPECTRAL_FLOW_ANGULAR: u32 = 3u;
const SPECTRAL_FLOW_RADIAL: u32 = 4u;
const SPECTRAL_FLOW_DIVERGENCE: u32 = 5u;

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

// Each invocation owns one rank, so local smoothing can update it in place.
@group(2) @binding(0) var<storage, read_write> ranks: array<f32>;

const SMOOTHING: f32 = 0.85;

// Preserve the former sequence of f32 blends without rebuilding the same
// neighbourhood for every step. The CPU retains the old even-step rounding.
fn smoothScalar(previous: f32, desiredValue: f32) -> f32 {
    var value = previous;
    for (var i = 0u; i < uniforms.influenceIterations; i++) {
        value = SMOOTHING * value + (1.0 - SMOOTHING) * desiredValue;
    }
    return value;
}

fn smoothAngle(previous: f32, angle: f32) -> f32 {
    var value = previous;
    let desiredVector = vec2<f32>(cos(angle), sin(angle));
    for (var i = 0u; i < uniforms.influenceIterations; i++) {
        let previousAngle = (value - 0.5) * 6.283185;
        let previousVector = vec2<f32>(cos(previousAngle), sin(previousAngle));
        let blended = SMOOTHING * previousVector + (1.0 - SMOOTHING) * desiredVector;
        value = atan2(blended.y, blended.x) / 6.283185 + 0.5;
    }
    return value;
}

// Smooth kernel for neighbor weighting
fn smoothKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius) { return 0.0; }
    let t = 1.0 - dist / radius;
    return t * t * t;
}

// getNeighborDelta and transformNeighborVelocity now live in common.wgsl so this
// shader and simulate.wgsl cannot drift apart again.

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
    ranks[boidIndex] = atan2(cy, cx) / 6.283185 + 0.5;
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

    // Same surface metric the simulation runs on - see metricFrameAt in
    // embed.wgsl. Every quantity below is a shape or a direction read off the
    // local neighbourhood, so measuring it in domain pixels would report the
    // chart's distortion as structure in the flock: a perfectly round cluster
    // in the neck of a Klein bottle would come out as an ellipse.
    let metric = metricFrameAt(myPos);
    let toSurface = metric.toSurface;
    let toDomain = metric.toDomain;

    let myVel = toSurface * velocities[boidIndex];
    let mySpeed = length(myVel);
    let perception = uniforms.perception;

    // Reshape the search block to the neighbourhood's domain-space aspect,
    // matching simulate.wgsl so both passes see the same neighbours.
    let reachX = length(vec2<f32>(toDomain[0][0], toDomain[1][0]));
    let reachY = length(vec2<f32>(toDomain[0][1], toDomain[1][1]));
    let reachRatio = sqrt(reachX / max(reachY, 1e-6));
    let cellRadiusX = clamp(i32(round(2.0 * reachRatio)), 1, 5);
    let cellRadiusY = clamp(i32(round(2.0 / max(reachRatio, 1e-6))), 1, 5);

    // Offset from this boid to the neighbourhood's weighted centre, in surface
    // units. Accumulated as a relative vector rather than an absolute position
    // because a wrapped neighbour has no meaningful absolute one.
    var centerOffset = vec2<f32>(0.0);
    var avgVelocity = vec2<f32>(0.0);
    var totalWeight: f32 = 0.0;
    var neighborCount: u32 = 0u;
    var maxDist: f32 = 0.0;
    
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // Iterate over the neighbourhood block (5x5 when unembedded)
    for (var dy = -cellRadiusY; dy <= cellRadiusY; dy++) {
        for (var dx = -cellRadiusX; dx <= cellRadiusX; dx++) {
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
                let delta = toSurface * getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq >= perception * perception) { continue; }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    // Relative, so wrapping is already handled by the delta
                    centerOffset += delta * weight;
                    // A neighbour reached across a flipping seam is stored in a
                    // mirrored frame, so its raw velocity points the wrong way.
                    // Averaging those directly is what made the flow metrics
                    // disagree with themselves along Mobius and Klein seams.
                    avgVelocity += toSurface * transformNeighborVelocity(myPos, otherPos, velocities[otherIdx]) * weight;
                    totalWeight += weight;
                    neighborCount++;
                    maxDist = max(maxDist, dist);
                }
            }
        }
    }
    
    var result: f32;
    let prevVal = ranks[boidIndex];
    
    if (totalWeight > 1e-6 && neighborCount >= 3u) {
        // Compute center of mass and average velocity
        centerOffset /= totalWeight;
        avgVelocity /= totalWeight;

        // Vector from center of mass to this boid
        let relativePos = -centerOffset;
        let distFromCenter = length(relativePos);
        
        // For flow modes
        let myVelDir = normalize(myVel + vec2<f32>(0.0001, 0.0001));
        
        switch (uniforms.spectralMode) {
            case SPECTRAL_ANGULAR: {
                // Angular position relative to local center (0-1 range)
                let angle = atan2(relativePos.y, relativePos.x);
                result = smoothAngle(prevVal, angle);
            }
            case SPECTRAL_RADIAL: {
                // Distance from local center normalized by perception
                let normalizedDist = clamp(distFromCenter / (perception * 0.5), 0.0, 1.0);
                result = smoothScalar(prevVal, normalizedDist);
            }
            case SPECTRAL_ASYMMETRY: {
                // How far the center of mass is from us
                let asymmetry = clamp(distFromCenter / (perception * 0.3), 0.0, 1.0);
                result = smoothScalar(prevVal, asymmetry);
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
                    result = smoothAngle(prevVal, flowAngle);
                } else {
                    // Near center - use velocity direction directly
                    let velAngle = atan2(myVel.y, myVel.x);
                    result = smoothAngle(prevVal, velAngle);
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
                    result = smoothScalar(prevVal, newVal);
                } else {
                    result = smoothScalar(prevVal, 0.5);
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
                    result = smoothScalar(prevVal, newVal);
                } else if (mySpeed > 0.01) {
                    // Neighbors slow but I'm moving - bright
                    result = smoothScalar(prevVal, 1.0);
                } else {
                    // Both slow - dark
                    result = smoothScalar(prevVal, 0.0);
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
                result = smoothAngle(prevVal, newAngle);
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
                result = smoothAngle(prevVal, flowAngle);
            }
            case SPECTRAL_FLOW_RADIAL: {
                // Radial velocity relative to canvas center (inverted)
                let posDir = normalize(vec2<f32>(cx, cy) + vec2<f32>(0.0001, 0.0001));
                let radialVel = dot(myVel, posDir);
                let normalizedRadial = clamp(-radialVel / (uniforms.maxSpeed * 0.5), -1.0, 1.0);
                result = smoothScalar(prevVal, normalizedRadial * 0.5 + 0.5);
            }
            case SPECTRAL_FLOW_DIVERGENCE: {
                // Isolated boids: use speed relative to max, cubed for sensitivity
                let speedRatio = mySpeed / uniforms.maxSpeed;
                let newVal = speedRatio * speedRatio * speedRatio; // Cubed: more sensitive
                result = smoothScalar(prevVal, clamp(newVal, 0.0, 1.0));
            }
            default: {
                result = 0.5;
            }
        }
    }
    
    ranks[boidIndex] = result;
}
