// Pass 5: Main boid simulation with flocking rules
// Supports multiple algorithm modes including grid-free approaches

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
}

// Cursor shapes
const CURSOR_RING: u32 = 0u;
const CURSOR_DISK: u32 = 1u;
const CURSOR_DOT: u32 = 2u;
const CURSOR_VORTEX: u32 = 3u;

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

// Algorithm modes
const ALG_TOPOLOGICAL_KNN: u32 = 0u;
const ALG_SMOOTH_METRIC: u32 = 1u;
const ALG_HASH_FREE: u32 = 2u;
const ALG_STOCHASTIC: u32 = 3u;
const ALG_DENSITY_ADAPTIVE: u32 = 4u;

const K_NEIGHBORS: u32 = 12u;
const MAX_CANDIDATES: u32 = 128u;

// Maximum trail length for buffer stride (must match CPU-side MAX_TRAIL_LENGTH)
const MAX_TRAIL_LENGTH: u32 = 100u;

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positionsIn: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read_write> positionsOut: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> velocitiesIn: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read_write> velocitiesOut: array<vec2<f32>>;
@group(0) @binding(5) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(6) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(7) var<storage, read> sortedIndices: array<u32>;
@group(0) @binding(8) var<storage, read_write> trails: array<vec2<f32>>;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

fn hash(n: u32) -> f32 {
    var x = n;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return f32(x) / f32(0xffffffffu);
}

fn hash2(n: u32) -> u32 {
    var x = n;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return x;
}

fn random2(seed: u32) -> vec2<f32> {
    return vec2<f32>(
        hash(seed) * 2.0 - 1.0,
        hash(seed + 1u) * 2.0 - 1.0
    );
}

fn limitMagnitude(v: vec2<f32>, maxMag: f32) -> vec2<f32> {
    let mag = length(v);
    if (mag > maxMag && mag > 0.0) {
        return v * (maxMag / mag);
    }
    return v;
}

// Smooth cubic kernel
fn smoothKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius) { return 0.0; }
    let q = dist / radius;
    let t = 1.0 - q;
    return t * t * t;
}

// Stronger separation kernel
fn separationKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius || dist < 0.001) { return 0.0; }
    let q = dist / radius;
    return (1.0 - q) * (1.0 - q) / (q * q + 0.01);
}

fn wrappedDelta(delta: f32, size: f32, wrap: bool) -> f32 {
    if (!wrap) { return delta; }
    let halfSize = size * 0.5;
    if (delta > halfSize) { return delta - size; }
    else if (delta < -halfSize) { return delta + size; }
    return delta;
}

fn getWrapFlags() -> vec2<bool> {
    let wrapX = uniforms.boundaryMode == TORUS || 
                uniforms.boundaryMode == CYLINDER_X || 
                uniforms.boundaryMode == MOBIUS_X ||
                uniforms.boundaryMode == KLEIN_X ||
                uniforms.boundaryMode == PROJECTIVE_PLANE;
    let wrapY = uniforms.boundaryMode == TORUS || 
                uniforms.boundaryMode == CYLINDER_Y || 
                uniforms.boundaryMode == MOBIUS_Y ||
                uniforms.boundaryMode == KLEIN_Y ||
                uniforms.boundaryMode == PROJECTIVE_PLANE;
    return vec2<bool>(wrapX, wrapY);
}

fn getNeighborDelta(myPos: vec2<f32>, otherPos: vec2<f32>) -> vec2<f32> {
    var delta = otherPos - myPos;
    let wrap = getWrapFlags();
    delta.x = wrappedDelta(delta.x, uniforms.canvasWidth, wrap.x);
    delta.y = wrappedDelta(delta.y, uniforms.canvasHeight, wrap.y);
    return delta;
}

fn getCellIndex(cx: i32, cy: i32) -> u32 {
    let wcx = ((cx % i32(uniforms.gridWidth)) + i32(uniforms.gridWidth)) % i32(uniforms.gridWidth);
    let wcy = ((cy % i32(uniforms.gridHeight)) + i32(uniforms.gridHeight)) % i32(uniforms.gridHeight);
    return u32(wcy) * uniforms.gridWidth + u32(wcx);
}

// Helper: robust bounce that handles any position, even far outside bounds
fn bounceCoord(val: f32, size: f32) -> f32 {
    if (val < 0.0) {
        // Reflect back into bounds
        let reflected = -val;
        // If still out of bounds (went very far), use modulo
        if (reflected >= size) {
            return size - 1.0 - (reflected % size);
        }
        return reflected;
    } else if (val >= size) {
        // Reflect back into bounds
        let overshoot = val - size;
        let reflected = size - 1.0 - overshoot;
        // If still out of bounds, use modulo
        if (reflected < 0.0) {
            return (-reflected) % size;
        }
        return reflected;
    }
    return val;
}

fn applyBoundary(pos: vec2<f32>) -> vec2<f32> {
    var newPos = pos;
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    
    // Safety margin to keep boids slightly inside bounds
    let safeMargin = 1.0;
    let safeW = w - safeMargin;
    let safeH = h - safeMargin;
    
    switch (uniforms.boundaryMode) {
        case PLANE: {
            // Robust bounce with helper function
            newPos.x = bounceCoord(newPos.x, w);
            newPos.y = bounceCoord(newPos.y, h);
        }
        case CYLINDER_X: {
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            newPos.y = bounceCoord(newPos.y, h);
        }
        case CYLINDER_Y: {
            newPos.x = bounceCoord(newPos.x, w);
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case TORUS: {
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case MOBIUS_X: {
            if (newPos.x < 0.0) { newPos.x += w; newPos.y = h - newPos.y; }
            else if (newPos.x >= w) { newPos.x -= w; newPos.y = h - newPos.y; }
            newPos.y = bounceCoord(newPos.y, h);
        }
        case MOBIUS_Y: {
            newPos.x = bounceCoord(newPos.x, w);
            if (newPos.y < 0.0) { newPos.y += h; newPos.x = w - newPos.x; }
            else if (newPos.y >= h) { newPos.y -= h; newPos.x = w - newPos.x; }
        }
        case KLEIN_X: {
            if (newPos.x < 0.0) { newPos.x += w; newPos.y = h - newPos.y; }
            else if (newPos.x >= w) { newPos.x -= w; newPos.y = h - newPos.y; }
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case KLEIN_Y: {
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            if (newPos.y < 0.0) { newPos.y += h; newPos.x = w - newPos.x; }
            else if (newPos.y >= h) { newPos.y -= h; newPos.x = w - newPos.x; }
        }
        case PROJECTIVE_PLANE: {
            if (newPos.x < 0.0) { newPos.x += w; newPos.y = h - newPos.y; }
            else if (newPos.x >= w) { newPos.x -= w; newPos.y = h - newPos.y; }
            if (newPos.y < 0.0) { newPos.y += h; newPos.x = w - newPos.x; }
            else if (newPos.y >= h) { newPos.y -= h; newPos.x = w - newPos.x; }
        }
        default: {
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
    }
    
    // HARD CLAMP: Absolute guarantee boids stay inside bounds
    // This catches any edge cases the above logic might miss
    newPos.x = clamp(newPos.x, safeMargin, safeW);
    newPos.y = clamp(newPos.y, safeMargin, safeH);
    
    return newPos;
}

fn applyBoundaryVelocity(pos: vec2<f32>, vel: vec2<f32>) -> vec2<f32> {
    var newVel = vel;
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    let margin = 50.0;
    let turnForce = 0.5;
    
    // Emergency margin - very strong force when extremely close to edge
    let emergencyMargin = 10.0;
    let emergencyForce = 3.0;
    
    if (uniforms.boundaryMode == PLANE) {
        // Corner avoidance zone - larger than normal margin for smooth corner navigation
        let cornerZone = margin * 2.0;
        
        // Check if in a corner danger zone (both close to X and Y edges)
        let nearLeft = pos.x < cornerZone;
        let nearRight = pos.x > w - cornerZone;
        let nearBottom = pos.y < cornerZone;
        let nearTop = pos.y > h - cornerZone;
        
        let inCorner = (nearLeft || nearRight) && (nearBottom || nearTop);
        
        if (inCorner) {
            // In corner: apply diagonal steering force away from corner
            let cornerForce = turnForce * 2.0;
            
            var cornerPoint = vec2<f32>(0.0, 0.0);
            if (nearLeft && nearBottom) { cornerPoint = vec2<f32>(0.0, 0.0); }
            else if (nearRight && nearBottom) { cornerPoint = vec2<f32>(w, 0.0); }
            else if (nearLeft && nearTop) { cornerPoint = vec2<f32>(0.0, h); }
            else if (nearRight && nearTop) { cornerPoint = vec2<f32>(w, h); }
            
            let awayFromCorner = normalize(vec2<f32>(w * 0.5, h * 0.5) - cornerPoint);
            let distToCorner = length(pos - cornerPoint);
            let maxCornerDist = cornerZone * 1.414;
            let cornerStrength = cornerForce * (1.0 - distToCorner / maxCornerDist);
            
            newVel += awayFromCorner * max(cornerStrength, 0.0);
        }
        
        // Standard edge forces (soft steering)
        if (pos.x < margin) { newVel.x += turnForce * (1.0 - pos.x / margin); }
        if (pos.x > w - margin) { newVel.x -= turnForce * (1.0 - (w - pos.x) / margin); }
        if (pos.y < margin) { newVel.y += turnForce * (1.0 - pos.y / margin); }
        if (pos.y > h - margin) { newVel.y -= turnForce * (1.0 - (h - pos.y) / margin); }
        
        // Emergency edge forces (very strong when too close)
        if (pos.x < emergencyMargin) { newVel.x += emergencyForce; }
        if (pos.x > w - emergencyMargin) { newVel.x -= emergencyForce; }
        if (pos.y < emergencyMargin) { newVel.y += emergencyForce; }
        if (pos.y > h - emergencyMargin) { newVel.y -= emergencyForce; }
        
    } else if (uniforms.boundaryMode == CYLINDER_X || uniforms.boundaryMode == MOBIUS_X) {
        if (pos.y < margin) { newVel.y += turnForce * (1.0 - pos.y / margin); }
        if (pos.y > h - margin) { newVel.y -= turnForce * (1.0 - (h - pos.y) / margin); }
        if (pos.y < emergencyMargin) { newVel.y += emergencyForce; }
        if (pos.y > h - emergencyMargin) { newVel.y -= emergencyForce; }
    } else if (uniforms.boundaryMode == CYLINDER_Y || uniforms.boundaryMode == MOBIUS_Y) {
        if (pos.x < margin) { newVel.x += turnForce * (1.0 - pos.x / margin); }
        if (pos.x > w - margin) { newVel.x -= turnForce * (1.0 - (w - pos.x) / margin); }
        if (pos.x < emergencyMargin) { newVel.x += emergencyForce; }
        if (pos.x > w - emergencyMargin) { newVel.x -= emergencyForce; }
    }
    
    return newVel;
}

// ============================================================================
// SHARED CONSTANTS FOR CONSISTENT BEHAVIOR ACROSS ALL ALGORITHMS
// ============================================================================

const SEPARATION_RADIUS_FACTOR: f32 = 0.4;  // Separation radius = 40% of perception
const SEPARATION_FORCE_MULT: f32 = 3.5;     // Separation force multiplier
const OVERLAP_PUSH_STRENGTH: f32 = 5.0;     // Force when boids overlap

// ============================================================================
// ALGORITHM 0: TOPOLOGICAL K-NN
// ============================================================================

fn algorithmTopologicalKNN(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let wrap = getWrapFlags();
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    var knnDistSq: array<f32, 12>;
    var knnIndex: array<u32, 12>;
    for (var i = 0u; i < K_NEIGHBORS; i++) {
        knnDistSq[i] = 1e10;
        knnIndex[i] = 0xFFFFFFFFu;
    }
    
    var separationSum = vec2<f32>(0.0);
    var separationCount = 0u;
    let separationRadius = uniforms.perception * SEPARATION_RADIUS_FACTOR;
    
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!wrap.x && (cx < 0i || cx >= i32(uniforms.gridWidth))) { continue; }
            if (!wrap.y && (cy < 0i || cy >= i32(uniforms.gridHeight))) { continue; }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            let maxPerCell = min(cellCount, 64u); // Cap iterations per cell
            for (var i = 0u; i < maxPerCell; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq < 1.0) {
                    // Deterministic push direction for overlapping boids
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                if (distSq < separationRadius * separationRadius) {
                    let dist = sqrt(distSq);
                    separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
                    separationCount++;
                }
                
                if (distSq < knnDistSq[K_NEIGHBORS - 1u]) {
                    var insertPos = K_NEIGHBORS - 1u;
                    for (var j = 0u; j < K_NEIGHBORS - 1u; j++) {
                        if (distSq < knnDistSq[j]) { insertPos = j; break; }
                    }
                    for (var j = K_NEIGHBORS - 1u; j > insertPos; j--) {
                        knnDistSq[j] = knnDistSq[j - 1u];
                        knnIndex[j] = knnIndex[j - 1u];
                    }
                    knnDistSq[insertPos] = distSq;
                    knnIndex[insertPos] = otherIdx;
                }
            }
        }
    }
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    
    for (var i = 0u; i < K_NEIGHBORS; i++) {
        if (knnIndex[i] == 0xFFFFFFFFu) { continue; }
        let dist = sqrt(knnDistSq[i]);
        let weight = smoothKernel(dist, uniforms.perception);
        if (weight > 0.0) {
            alignmentSum += velocitiesIn[knnIndex[i]] * weight;
            cohesionSum += getNeighborDelta(myPos, positionsIn[knnIndex[i]]) * weight;
            totalWeight += weight;
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            acceleration += limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce) * uniforms.alignment * rebelFactor;
        }
        if (uniforms.cohesion > 0.0) {
            acceleration += limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce) * uniforms.cohesion * rebelFactor;
        }
    }
    
    if (separationCount > 0u && uniforms.separation > 0.0) {
        acceleration += limitMagnitude(separationSum, uniforms.maxForce * SEPARATION_FORCE_MULT) * uniforms.separation;
    }
    
    return acceleration;
}

// ============================================================================
// ALGORITHM 1: SMOOTH METRIC
// ============================================================================

fn algorithmSmoothMetric(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let wrap = getWrapFlags();
    
    let jitterSeed = uniforms.frameCount * 7u;
    let jitterX = (hash(jitterSeed) - 0.5) * uniforms.cellSize * 0.3;
    let jitterY = (hash(jitterSeed + 1u) - 0.5) * uniforms.cellSize * 0.3;
    let jitteredPos = myPos + vec2<f32>(jitterX, jitterY);
    let myCellX = i32(jitteredPos.x / uniforms.cellSize);
    let myCellY = i32(jitteredPos.y / uniforms.cellSize);
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    let separationRadius = uniforms.perception * SEPARATION_RADIUS_FACTOR;
    
    for (var dy = -1i; dy <= 1i; dy++) {
        for (var dx = -1i; dx <= 1i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!wrap.x && (cx < 0i || cx >= i32(uniforms.gridWidth))) { continue; }
            if (!wrap.y && (cy < 0i || cy >= i32(uniforms.gridHeight))) { continue; }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            for (var i = 0u; i < cellCount && totalWeight < 80.0; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq < 1.0) {
                    // Deterministic push direction for overlapping boids
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, uniforms.perception);
                
                if (weight > 0.0) {
                    alignmentSum += velocitiesIn[otherIdx] * weight;
                    cohesionSum += delta * weight;
                    totalWeight += weight;
                    
                    if (dist < separationRadius) {
                        separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
                        separationCount++;
                    }
                }
            }
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            acceleration += limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce) * uniforms.alignment * rebelFactor;
        }
        if (uniforms.cohesion > 0.0) {
            acceleration += limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce) * uniforms.cohesion * rebelFactor;
        }
    }
    
    if (separationCount > 0u && uniforms.separation > 0.0) {
        acceleration += limitMagnitude(separationSum, uniforms.maxForce * SEPARATION_FORCE_MULT) * uniforms.separation;
    }
    
    return acceleration;
}

// ============================================================================
// ALGORITHM 2: HASH-FREE (Per-boid randomized grid - no global seams)
// Each boid has its own random offset to the grid, so cell boundaries
// are different for every boid - eliminating coherent grid artifacts
// ============================================================================

fn algorithmHashFree(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let wrap = getWrapFlags();
    
    // Each boid gets a unique, stable grid offset based on its index
    let offsetX = hash(boidIndex * 73856093u) * uniforms.cellSize;
    let offsetY = hash(boidIndex * 19349663u) * uniforms.cellSize;
    
    let shiftedPos = myPos + vec2<f32>(offsetX, offsetY);
    let myCellX = i32(shiftedPos.x / uniforms.cellSize);
    let myCellY = i32(shiftedPos.y / uniforms.cellSize);
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    
    let perception = uniforms.perception;
    let separationRadius = perception * SEPARATION_RADIUS_FACTOR;
    
    // Search area
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!wrap.x && (cx < 0i || cx >= i32(uniforms.gridWidth))) { continue; }
            if (!wrap.y && (cy < 0i || cy >= i32(uniforms.gridHeight))) { continue; }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            let maxPerCell2 = min(cellCount, 64u); // Cap iterations per cell
            
            for (var i = 0u; i < maxPerCell2; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                // Handle overlapping boids with deterministic push
                if (distSq < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                
                // Smooth kernel weight
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    alignmentSum += velocitiesIn[otherIdx] * weight;
                    cohesionSum += delta * weight;
                    totalWeight += weight;
                }
                
                // Separation using consistent kernel
                if (dist < separationRadius) {
                    separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
                    separationCount++;
                }
            }
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            let alignForce = limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce);
            acceleration += alignForce * uniforms.alignment * rebelFactor;
        }
        if (uniforms.cohesion > 0.0) {
            let cohesionForce = limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce);
            acceleration += cohesionForce * uniforms.cohesion * rebelFactor;
        }
    }
    
    if (separationCount > 0u && uniforms.separation > 0.0) {
        acceleration += limitMagnitude(separationSum, uniforms.maxForce * SEPARATION_FORCE_MULT) * uniforms.separation;
    }
    
    return acceleration;
}

// ============================================================================
// ALGORITHM 3: STOCHASTIC SAMPLING
// Randomly sample cells around the boid with distance-weighted probability
// No fixed cell boundaries - samples from random positions around the boid
// ============================================================================

fn algorithmStochastic(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let wrap = getWrapFlags();
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    
    let perception = uniforms.perception;
    let separationRadius = perception * SEPARATION_RADIUS_FACTOR;
    
    // Sample multiple random points within perception radius
    // For each point, check the cell it falls in
    let numSamples = 32u;
    var baseSeed = boidIndex * 1000003u + uniforms.frameCount * 31337u;
    
    // Also check immediate neighbors to ensure we don't miss close boids
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // First pass: check immediate vicinity (3x3) for close neighbors
    for (var dy = -1i; dy <= 1i; dy++) {
        for (var dx = -1i; dx <= 1i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!wrap.x && (cx < 0i || cx >= i32(uniforms.gridWidth))) { continue; }
            if (!wrap.y && (cy < 0i || cy >= i32(uniforms.gridHeight))) { continue; }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            // Sample up to 3 boids from each nearby cell
            let sampleCount = min(cellCount, 3u);
            for (var i = 0u; i < sampleCount; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq < 1.0) {
                    // Deterministic push direction for overlapping boids
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    alignmentSum += velocitiesIn[otherIdx] * weight;
                    cohesionSum += delta * weight;
                    totalWeight += weight;
                }
                
                if (dist < separationRadius) {
                    separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
                    separationCount++;
                }
            }
        }
    }
    
    // Second pass: random sampling from perception area
    for (var s = 0u; s < numSamples; s++) {
        // Generate random point within perception radius using rejection sampling
        let seed = baseSeed + s * 7u;
        let angle = hash(seed) * 6.283185307;
        let r = sqrt(hash(seed + 1u)) * perception; // sqrt for uniform disk distribution
        
        let sampleOffset = vec2<f32>(cos(angle), sin(angle)) * r;
        var samplePos = myPos + sampleOffset;
        
        // Wrap sample position
        if (wrap.x) { samplePos.x = samplePos.x - floor(samplePos.x / uniforms.canvasWidth) * uniforms.canvasWidth; }
        if (wrap.y) { samplePos.y = samplePos.y - floor(samplePos.y / uniforms.canvasHeight) * uniforms.canvasHeight; }
        
        // Clamp to valid range
        samplePos.x = clamp(samplePos.x, 0.0, uniforms.canvasWidth - 1.0);
        samplePos.y = clamp(samplePos.y, 0.0, uniforms.canvasHeight - 1.0);
        
        let sampleCellX = i32(samplePos.x / uniforms.cellSize);
        let sampleCellY = i32(samplePos.y / uniforms.cellSize);
        
        let cellIdx = getCellIndex(sampleCellX, sampleCellY);
        let cellStart = prefixSums[cellIdx];
        let cellCount = cellCounts[cellIdx];
        
        if (cellCount == 0u) { continue; }
        
        // Pick a random boid from this cell
        let pickIdx = hash2(seed + 2u) % cellCount;
        let otherIdx = sortedIndices[cellStart + pickIdx];
        
        if (otherIdx == boidIndex) { continue; }
        
        let otherPos = positionsIn[otherIdx];
        let delta = getNeighborDelta(myPos, otherPos);
        let distSq = dot(delta, delta);
        
        if (distSq > perception * perception) { continue; }
        
        let dist = sqrt(distSq);
        let weight = smoothKernel(dist, perception);
        
        if (weight > 0.0) {
            alignmentSum += velocitiesIn[otherIdx] * weight;
            cohesionSum += delta * weight;
            totalWeight += weight;
        }
        
        if (dist < separationRadius && dist > 0.1) {
            separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
            separationCount++;
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            acceleration += limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce) * uniforms.alignment * rebelFactor;
        }
        if (uniforms.cohesion > 0.0) {
            acceleration += limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce) * uniforms.cohesion * rebelFactor;
        }
    }
    
    if (separationCount > 0u && uniforms.separation > 0.0) {
        acceleration += limitMagnitude(separationSum, uniforms.maxForce * SEPARATION_FORCE_MULT) * uniforms.separation;
    }
    
    return acceleration;
}

// ============================================================================
// ALGORITHM 4: DENSITY ADAPTIVE
// Combines hash-free approach with density-based force adaptation
// High density areas get slightly reduced cohesion to prevent over-crowding
// ============================================================================

fn algorithmDensityAdaptive(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let wrap = getWrapFlags();
    
    // Per-boid grid offset for hash-free behavior
    let offsetX = hash(boidIndex * 73856093u) * uniforms.cellSize;
    let offsetY = hash(boidIndex * 19349663u) * uniforms.cellSize;
    let shiftedPos = myPos + vec2<f32>(offsetX, offsetY);
    let myCellX = i32(shiftedPos.x / uniforms.cellSize);
    let myCellY = i32(shiftedPos.y / uniforms.cellSize);
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    var localDensity = 0.0; // Measure of how crowded this area is
    
    let perception = uniforms.perception;
    let separationRadius = perception * SEPARATION_RADIUS_FACTOR;
    
    // Collect neighbor data and measure local density
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!wrap.x && (cx < 0i || cx >= i32(uniforms.gridWidth))) { continue; }
            if (!wrap.y && (cy < 0i || cy >= i32(uniforms.gridHeight))) { continue; }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            let maxPerCell3 = min(cellCount, 64u); // Cap iterations per cell
            
            for (var i = 0u; i < maxPerCell3; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq > perception * perception) { continue; }
                
                let dist = sqrt(distSq);
                
                // Density contribution - closer boids contribute more
                let densityWeight = smoothKernel(dist, perception);
                localDensity += densityWeight;
                
                // Handle overlapping boids with deterministic push
                if (dist < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                // Alignment and cohesion with smooth weights
                let weight = smoothKernel(dist, perception);
                if (weight > 0.0) {
                    alignmentSum += velocitiesIn[otherIdx] * weight;
                    cohesionSum += delta * weight;
                    totalWeight += weight;
                }
                
                // Separation using consistent kernel
                if (dist < separationRadius) {
                    separationSum -= normalize(delta) * separationKernel(dist, separationRadius);
                    separationCount++;
                }
            }
        }
    }
    
    // Mild density-adaptive cohesion scaling (unique to this algorithm)
    // High density: slightly reduce cohesion to prevent over-crowding
    let idealDensity = 5.0;
    let densityRatio = localDensity / idealDensity;
    let cohesionMod = 1.0 / (1.0 + max(0.0, densityRatio - 1.0) * 0.3);
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            let alignForce = limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce);
            acceleration += alignForce * uniforms.alignment * rebelFactor;
        }
        
        if (uniforms.cohesion > 0.0) {
            let cohesionForce = limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce);
            // Apply mild density-based cohesion reduction
            acceleration += cohesionForce * uniforms.cohesion * rebelFactor * cohesionMod;
        }
    }
    
    if (separationCount > 0u && uniforms.separation > 0.0) {
        acceleration += limitMagnitude(separationSum, uniforms.maxForce * SEPARATION_FORCE_MULT) * uniforms.separation;
    }
    
    return acceleration;
}

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let boidIndex = global_id.x;
    if (boidIndex >= uniforms.boidCount) { return; }
    
    let myPos = positionsIn[boidIndex];
    let myVel = velocitiesIn[boidIndex];
    
    // Rebel behavior
    let rebelPeriod = 180u;
    let rebelDuration = 60u;
    let boidPhase = u32(hash(boidIndex * 12345u) * f32(rebelPeriod));
    let timeInCycle = (uniforms.frameCount + boidPhase) % rebelPeriod;
    let isRebel = hash(boidIndex * 7919u) < uniforms.rebels * 5.0 && timeInCycle < rebelDuration;
    let rebelFactor = select(1.0, 0.2, isRebel);
    
    // Select algorithm
    var acceleration: vec2<f32>;
    switch (uniforms.algorithmMode) {
        case ALG_TOPOLOGICAL_KNN: { acceleration = algorithmTopologicalKNN(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_SMOOTH_METRIC: { acceleration = algorithmSmoothMetric(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_HASH_FREE: { acceleration = algorithmHashFree(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_STOCHASTIC: { acceleration = algorithmStochastic(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_DENSITY_ADAPTIVE: { acceleration = algorithmDensityAdaptive(boidIndex, myPos, myVel, rebelFactor); }
        default: { acceleration = algorithmHashFree(boidIndex, myPos, myVel, rebelFactor); }
    }
    
    // Cursor interaction - Multiple cursor shapes
    if (uniforms.cursorMode != 0u && uniforms.cursorActive != 0u) {
        let cursorPos = vec2<f32>(uniforms.cursorX, uniforms.cursorY);
        let toCursor = getNeighborDelta(myPos, cursorPos);
        let cursorDist = length(toCursor);
        
        // Use cursorRadius from params (in CSS pixels, scale by DPR)
        let dpr = 2.0;
        let radius = uniforms.cursorRadius * dpr;
        let influenceRange = radius * 2.0;
        
        let strength = select(0.5, 1.0, uniforms.cursorPressed != 0u);
        var cursorForce = vec2<f32>(0.0);
        
        if (cursorDist > 0.5) {
            let towardCenter = normalize(toCursor);
            let awayFromCenter = -towardCenter;
            
            // Perpendicular vector for vortex (tangential) - clockwise rotation
            let tangent = vec2<f32>(towardCenter.y, -towardCenter.x);
            
            switch (uniforms.cursorShape) {
                case CURSOR_RING: {
                    // Ring attractor: boids orbit the circumference
                    if (cursorDist < radius + influenceRange) {
                        let distFromRing = cursorDist - radius;
                        
                        if (uniforms.cursorMode == 1u) {
                            if (distFromRing > 0.0) {
                                // Outside: pull inward toward ring
                                let pull = smoothKernel(distFromRing, influenceRange);
                                cursorForce = towardCenter * pull * strength * uniforms.cursorForce * 2.5;
                            } else {
                                // Inside: push outward toward ring
                                let push = smoothKernel(-distFromRing, radius);
                                cursorForce = awayFromCenter * push * strength * uniforms.cursorForce * 3.0;
                            }
                        } else {
                            // Repel: push away from entire area
                            let repel = smoothKernel(cursorDist, radius + influenceRange);
                            cursorForce = awayFromCenter * repel * strength * uniforms.cursorForce * 3.0;
                        }
                    }
                }
                case CURSOR_DISK: {
                    // Disk: containment area - keeps boids inside (attract) or clears area (repel)
                    let diskRadius = radius;
                    let edgeWidth = radius * 0.5;
                    
                    if (uniforms.cursorMode == 1u) {
                        // Attract: contain boids within disk
                        if (cursorDist > diskRadius) {
                            // Outside disk: pull toward the edge
                            let distFromEdge = cursorDist - diskRadius;
                            let pull = smoothKernel(distFromEdge, edgeWidth * 2.0);
                            cursorForce = towardCenter * pull * strength * uniforms.cursorForce * 3.0;
                        } else if (cursorDist < diskRadius * 0.3) {
                            // Too close to center: gentle push outward to distribute
                            let push = 1.0 - (cursorDist / (diskRadius * 0.3));
                            cursorForce = awayFromCenter * push * strength * uniforms.cursorForce * 0.5;
                        }
                    } else {
                        // Repel: clear boids from disk area
                        if (cursorDist < diskRadius + edgeWidth) {
                            let weight = smoothKernel(cursorDist, diskRadius + edgeWidth);
                            cursorForce = awayFromCenter * weight * strength * uniforms.cursorForce * 3.0;
                        }
                    }
                }
                case CURSOR_DOT: {
                    // Dot: small intense point attractor
                    let dotRange = radius * 3.0;
                    if (cursorDist < dotRange) {
                        // Stronger falloff for more focused effect
                        let weight = smoothKernel(cursorDist, dotRange);
                        let intensity = weight * weight; // Squared for sharper falloff
                        if (uniforms.cursorMode == 1u) {
                            cursorForce = towardCenter * intensity * strength * uniforms.cursorForce * 4.0;
                        } else {
                            cursorForce = awayFromCenter * intensity * strength * uniforms.cursorForce * 4.0;
                        }
                    }
                }
                case CURSOR_VORTEX: {
                    // Vortex: swirling force - boids rotate around cursor
                    if (cursorDist < influenceRange) {
                        let weight = smoothKernel(cursorDist, influenceRange);
                        
                        // Tangential force creates rotation
                        let rotationForce = tangent * weight * strength * uniforms.cursorForce * 3.0;
                        
                        // Small radial component to maintain orbit distance
                        var radialForce = vec2<f32>(0.0);
                        let targetOrbit = radius;
                        let orbitDiff = cursorDist - targetOrbit;
                        
                        if (uniforms.cursorMode == 1u) {
                            // Attract mode: spiral inward (clockwise)
                            if (orbitDiff > 0.0) {
                                radialForce = towardCenter * smoothKernel(orbitDiff, influenceRange) * strength * uniforms.cursorForce;
                            } else {
                                radialForce = awayFromCenter * smoothKernel(-orbitDiff, targetOrbit) * strength * uniforms.cursorForce * 0.5;
                            }
                            cursorForce = rotationForce + radialForce;
                        } else {
                            // Repel mode: spiral outward (counter-clockwise)
                            cursorForce = -rotationForce + awayFromCenter * weight * strength * uniforms.cursorForce;
                        }
                    }
                }
                default: {
                    // Fallback to disk behavior
                    if (cursorDist < influenceRange) {
                        let weight = smoothKernel(cursorDist, influenceRange);
                        cursorForce = towardCenter * weight * strength * uniforms.cursorForce * 2.0;
                    }
                }
            }
            
            acceleration += cursorForce;
        }
    }
    
    // Noise
    if (uniforms.noise > 0.0) {
        acceleration += random2(boidIndex * 31u + uniforms.frameCount * 17u) * uniforms.noise * uniforms.maxForce;
    }
    
    // Apply forces
    var newVel = applyBoundaryVelocity(myPos, myVel + acceleration);
    newVel = limitMagnitude(newVel, uniforms.maxSpeed);
    
    // Minimum speed
    let speed = length(newVel);
    if (speed < uniforms.maxSpeed * 0.3) {
        if (speed > 0.001) {
            newVel = normalize(newVel) * uniforms.maxSpeed * 0.3;
        } else {
            newVel = normalize(random2(boidIndex * 13u + uniforms.frameCount * 23u)) * uniforms.maxSpeed * 0.3;
        }
    }
    
    // Update position
    var newPos = myPos + newVel * uniforms.deltaTime * 60.0;
    newPos = applyBoundary(newPos);
    
    // Write output
    positionsOut[boidIndex] = newPos;
    velocitiesOut[boidIndex] = newVel;
    
    // Update trail - store at the BASE of the boid (x = -0.7 in local space), not the center
    // This ensures trails connect seamlessly to the triangle's back edge
    let finalSpeed = length(newVel);
    var trailPos = newPos;
    if (finalSpeed > 0.001) {
        let trailDir = newVel / finalSpeed;
        // Offset to the triangle's base: 0.7 * boidSize * 6.0
        trailPos = newPos - trailDir * 0.7 * uniforms.boidSize * 6.0;
    }
    // Use MAX_TRAIL_LENGTH for buffer stride so changing trailLength doesn't shift data
    trails[boidIndex * MAX_TRAIL_LENGTH + uniforms.trailHead] = trailPos;
}
