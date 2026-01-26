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
    // Simulation timing
    timeScale: f32,       // Simulation speed multiplier
    // Color control sources
    saturationSource: u32,
    brightnessSource: u32,
    spectralMode: u32,
    // Locally perfect hashing
    reducedWidth: u32,
    totalSlots: u32,
    // Dynamics
    globalCollision: f32,
}

// Cursor shapes
const CURSOR_RING: u32 = 0u;
const CURSOR_DISK: u32 = 1u;

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

const MAX_TRAIL_LENGTH: u32 = 50u;

// ============================================================================
// BOUNDARY SYSTEM - Modular configuration for all topology types
// ============================================================================
// 
// Boundary Configuration:
//   wrapX/wrapY     - axis wraps around (no hard edge)
//   flipOnWrapX     - when X wraps, Y coordinate and velocity flip
//   flipOnWrapY     - when Y wraps, X coordinate and velocity flip
//   bounceX/bounceY - axis has soft bouncy boundary (with inset)
//
// Topology Summary:
//   PLANE:      bounce both axes
//   CYLINDER_X: wrap X, bounce Y
//   CYLINDER_Y: bounce X, wrap Y  
//   TORUS:      wrap both axes
//   MOBIUS_X:   wrap X with Y-flip, bounce Y
//   MOBIUS_Y:   bounce X, wrap Y with X-flip
//   KLEIN_X:    wrap X with Y-flip, wrap Y (no flip)
//   KLEIN_Y:    wrap X (no flip), wrap Y with X-flip
//   PROJECTIVE: wrap X with Y-flip, wrap Y with X-flip
// ============================================================================

struct BoundaryConfig {
    wrapX: bool,
    wrapY: bool,
    flipOnWrapX: bool,  // Y flips when X wraps
    flipOnWrapY: bool,  // X flips when Y wraps
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
            cfg.wrapX = true; cfg.wrapY = true;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = false; cfg.bounceY = false;
        }
    }
    return cfg;
}

// Boundary inset for bouncy edges
const BOUNDARY_INSET: f32 = 30.0;
const SOFT_MARGIN: f32 = 120.0;
const EMERGENCY_ZONE: f32 = 15.0;

// Wall texture scale (must match CPU side)
const WALL_TEXTURE_SCALE: f32 = 4.0;
const WALL_DETECT_RADIUS: f32 = 60.0;  // How far ahead to look for walls
const WALL_FORCE_STRENGTH: f32 = 0.8;  // Strength of wall avoidance

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positionsIn: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read_write> positionsOut: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> velocitiesIn: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read_write> velocitiesOut: array<vec2<f32>>;
@group(0) @binding(5) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(6) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(7) var<storage, read> sortedIndices: array<u32>;
@group(0) @binding(8) var<storage, read_write> trails: array<vec2<f32>>;
@group(0) @binding(9) var wallTexture: texture_2d<f32>;
@group(0) @binding(10) var wallSampler: sampler;

// Multi-species buffers (separate bind group to stay under storage buffer limit)
@group(1) @binding(0) var<storage, read> speciesIds: array<u32>;
@group(1) @binding(1) var<uniform> speciesParams: array<vec4<f32>, 35>;  // 7 species * 5 vec4s per species
@group(1) @binding(2) var<uniform> interactionMatrix: array<vec4<f32>, 49>;  // 7*7 entries
@group(1) @binding(3) var<storage, read_write> metricsOut: array<vec4<f32>>;  // per-boid metrics [density, anisotropy, 0, 0]

// Species constants
const MAX_SPECIES: u32 = 7u;

// Species params layout: 2 vec4s per species (8 floats total)
// vec4[0]: [alignment, cohesion, separation, perception]
// vec4[1]: [maxSpeed, maxForce, hue, headShape]

// Interaction matrix indices
const IM_BEHAVIOR: u32 = 0u;
const IM_STRENGTH: u32 = 1u;
const IM_RANGE: u32 = 2u;

// Interaction behaviors (must match InteractionBehavior enum in types.ts)
const BEHAVIOR_IGNORE: u32 = 0u;
const BEHAVIOR_FLEE: u32 = 1u;      // Strong escape response - prey behavior
const BEHAVIOR_CHASE: u32 = 2u;     // Predatory pursuit with prediction
const BEHAVIOR_COHERE: u32 = 3u;    // Gentle attraction + partial alignment (mutualistic)
const BEHAVIOR_ALIGN: u32 = 4u;     // Pure velocity matching - information transfer
const BEHAVIOR_ORBIT: u32 = 5u;     // Circular motion - territorial/escort
const BEHAVIOR_FOLLOW: u32 = 6u;    // Trail behind - leader-follower
const BEHAVIOR_GUARD: u32 = 7u;     // Maintain optimal distance - protective
const BEHAVIOR_DISPERSE: u32 = 8u;  // Explosive scatter - confusion effect
const BEHAVIOR_MOB: u32 = 9u;       // Aggressive swarming - counter-attack

// Get species parameter by index (0-15)
// 4 vec4s per species: 
// [0]: [alignment, cohesion, separation, perception]
// [1]: [maxSpeed, maxForce, hue, headShape]
// [2]: [saturation, lightness, size, trailLength]
// [3]: [rebels, cursorForce, cursorResponse, unused]
fn getSpeciesParam(speciesId: u32, paramIdx: u32) -> f32 {
    let vec4Idx = speciesId * 4u + paramIdx / 4u;
    let componentIdx = paramIdx % 4u;
    let v = speciesParams[vec4Idx];
    switch (componentIdx) {
        case 0u: { return v.x; }
        case 1u: { return v.y; }
        case 2u: { return v.z; }
        default: { return v.w; }
    }
}

// Convenience functions for per-species parameters
fn getSpeciesAlignment(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 0u].x;
}

fn getSpeciesCohesion(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 0u].y;
}

fn getSpeciesSeparation(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 0u].z;
}

fn getSpeciesPerception(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 0u].w;
}

fn getSpeciesMaxSpeed(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 1u].x;
}

fn getSpeciesMaxForce(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 1u].y;
}

fn getSpeciesSize(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].z;
}

fn getSpeciesRebels(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 3u].x;
}

fn getSpeciesCursorForce(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 3u].y;
}

fn getSpeciesCursorResponse(speciesId: u32) -> u32 {
    return u32(speciesParams[speciesId * 5u + 3u].z);
}

// Returns vortex direction: -1.0 = counter-clockwise, 0.0 = off, 1.0 = clockwise
fn getSpeciesCursorVortexDir(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 3u].w;
}

// Get interaction matrix entry: [behavior, strength, range, padding]
fn getInteraction(fromSpecies: u32, toSpecies: u32, entryIdx: u32) -> f32 {
    let matrixIdx = fromSpecies * MAX_SPECIES + toSpecies;
    let v = interactionMatrix[matrixIdx];
    switch (entryIdx) {
        case 0u: { return v.x; }  // behavior
        case 1u: { return v.y; }  // strength
        case 2u: { return v.z; }  // range
        default: { return v.w; }  // padding
    }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

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
    return vec2<f32>(hash(seed) * 2.0 - 1.0, hash(seed + 1u) * 2.0 - 1.0);
}

fn limitMagnitude(v: vec2<f32>, maxMag: f32) -> vec2<f32> {
    let mag = length(v);
    if (mag > maxMag && mag > 0.0) { return v * (maxMag / mag); }
    return v;
}

fn smoothKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius) { return 0.0; }
    let t = 1.0 - dist / radius;
    return t * t * t;
}

fn separationKernel(dist: f32, radius: f32) -> f32 {
    if (dist >= radius || dist < 0.001) { return 0.0; }
    let q = dist / radius;
    let t = 1.0 - q;
    return t * t * (2.0 / (q + 0.5));
}

// ============================================================================
// BOUNDARY FUNCTIONS - Clean, modular boundary handling
// ============================================================================

// Simple modulo wrap for a coordinate
fn wrapCoord(val: f32, size: f32) -> f32 {
    return val - floor(val / size) * size;
}

// Bounce coordinate within [0, size) - reflects off boundaries
fn bounceCoord(val: f32, size: f32) -> f32 {
    if (val < 0.0) {
        let reflected = -val;
        if (reflected >= size) { return size - 0.5 - (reflected % size); }
        return reflected;
    } else if (val >= size) {
        let overshoot = val - size;
        let reflected = size - 0.5 - overshoot;
        if (reflected < 0.0) { return (-reflected) % size; }
        return reflected;
    }
    return val;
}

// Get the effective bounds for a given axis (with inset if bouncy)
fn getBounds(cfg: BoundaryConfig) -> vec4<f32> {
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    let inset = BOUNDARY_INSET;
    
    var minX = 0.0; var maxX = w;
    var minY = 0.0; var maxY = h;
    
    if (cfg.bounceX) { minX = inset; maxX = w - inset; }
    if (cfg.bounceY) { minY = inset; maxY = h - inset; }
    
    return vec4<f32>(minX, minY, maxX, maxY);
}

// Apply position wrapping/bouncing with proper flip handling
// Returns: (newPosition, velocityMultiplier) where velocityMultiplier.x/y is -1 if that axis flipped
fn applyBoundaryWithVelFix(pos: vec2<f32>, vel: vec2<f32>) -> vec4<f32> {
    let cfg = getBoundaryConfig();
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    let bounds = getBounds(cfg);
    let inset = BOUNDARY_INSET;
    
    var newPos = pos;
    var velMult = vec2<f32>(1.0, 1.0);  // Track velocity flips
    
    // Handle X axis
    if (cfg.wrapX) {
        if (newPos.x < 0.0) {
            newPos.x += w;
            if (cfg.flipOnWrapX) { 
                newPos.y = h - newPos.y; 
                velMult.y = -1.0;
            }
        } else if (newPos.x >= w) {
            newPos.x -= w;
            if (cfg.flipOnWrapX) { 
                newPos.y = h - newPos.y; 
                velMult.y = -1.0;
            }
        }
    } else if (cfg.bounceX) {
        let localX = newPos.x - inset;
        let bounceW = w - 2.0 * inset;
        newPos.x = bounceCoord(localX, bounceW) + inset;
    }
    
    // Handle Y axis (after X, so flipped Y is processed correctly)
    if (cfg.wrapY) {
        if (newPos.y < 0.0) {
            newPos.y += h;
            if (cfg.flipOnWrapY) { 
                newPos.x = w - newPos.x; 
                velMult.x = -1.0;
            }
        } else if (newPos.y >= h) {
            newPos.y -= h;
            if (cfg.flipOnWrapY) { 
                newPos.x = w - newPos.x; 
                velMult.x = -1.0;
            }
        }
    } else if (cfg.bounceY) {
        let localY = newPos.y - inset;
        let bounceH = h - 2.0 * inset;
        newPos.y = bounceCoord(localY, bounceH) + inset;
    }
    
    // Safety clamp - only for bouncy (non-wrapped) edges
    // For wrapped edges, the wrapping logic handles everything
    let safeMargin = 1.0;
    if (cfg.bounceX) {
        newPos.x = clamp(newPos.x, bounds.x + safeMargin, bounds.z - safeMargin);
    }
    if (cfg.bounceY) {
        newPos.y = clamp(newPos.y, bounds.y + safeMargin, bounds.w - safeMargin);
    }
    
    return vec4<f32>(newPos, velMult);
}

// Compute shortest delta between two positions, accounting for wrapping AND flipping
// This is critical for correct neighbor detection on Möbius/Klein/Projective
fn getNeighborDelta(myPos: vec2<f32>, otherPos: vec2<f32>) -> vec2<f32> {
    let cfg = getBoundaryConfig();
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    
    var delta = otherPos - myPos;
    
    // For simple wrap (no flip), use standard toroidal distance
    if (cfg.wrapX && !cfg.flipOnWrapX) {
        if (delta.x > w * 0.5) { delta.x -= w; }
        else if (delta.x < -w * 0.5) { delta.x += w; }
    }
    
    if (cfg.wrapY && !cfg.flipOnWrapY) {
        if (delta.y > h * 0.5) { delta.y -= h; }
        else if (delta.y < -h * 0.5) { delta.y += h; }
    }
    
    // For flip-wrap boundaries, we need to check both direct path and flipped path
    if (cfg.flipOnWrapX) {
        // Direct delta
        let directDist = abs(delta.x);
        // Flipped path: go through edge, flip Y
        let flippedOtherY = h - otherPos.y;
        let flippedDeltaX = (w - myPos.x) + otherPos.x;  // Distance going right through edge
        let flippedDeltaX2 = myPos.x + (w - otherPos.x); // Distance going left through edge
        let flippedDeltaY = flippedOtherY - myPos.y;
        
        // Check if going through the X edge (with Y flip) is shorter
        if (flippedDeltaX < directDist) {
            delta.x = flippedDeltaX;
            delta.y = flippedDeltaY;
        } else if (flippedDeltaX2 < directDist) {
            delta.x = -flippedDeltaX2;
            delta.y = flippedDeltaY;
        }
    }
    
    if (cfg.flipOnWrapY) {
        // Direct delta (possibly already modified by X flip)
        let directDist = abs(delta.y);
        // Flipped path: go through edge, flip X
        let flippedOtherX = w - otherPos.x;
        let flippedDeltaY = (h - myPos.y) + otherPos.y;
        let flippedDeltaY2 = myPos.y + (h - otherPos.y);
        let flippedDeltaX = flippedOtherX - myPos.x;
        
        if (flippedDeltaY < directDist) {
            delta.y = flippedDeltaY;
            delta.x = flippedDeltaX;
        } else if (flippedDeltaY2 < directDist) {
            delta.y = -flippedDeltaY2;
            delta.x = flippedDeltaX;
        }
    }
    
    return delta;
}

// Transform a neighbor's velocity to our reference frame (for alignment across flip boundaries)
fn transformNeighborVelocity(myPos: vec2<f32>, otherPos: vec2<f32>, otherVel: vec2<f32>) -> vec2<f32> {
    let cfg = getBoundaryConfig();
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    
    var vel = otherVel;
    
    // Check if the shortest path goes through a flip boundary
    if (cfg.flipOnWrapX) {
        let directDistX = abs(otherPos.x - myPos.x);
        let wrappedDistX = w - directDistX;
        if (wrappedDistX < directDistX) {
            // Neighbor is "across" the flip boundary - flip their Y velocity
            vel.y = -vel.y;
        }
    }
    
    if (cfg.flipOnWrapY) {
        let directDistY = abs(otherPos.y - myPos.y);
        let wrappedDistY = h - directDistY;
        if (wrappedDistY < directDistY) {
            // Neighbor is "across" the flip boundary - flip their X velocity
            vel.x = -vel.x;
        }
    }
    
    return vel;
}

// Locally perfect hashing constant
const M: u32 = 9u;

// Get cell index with proper wrapping (for spatial hash grid)
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
// When looking across a flip boundary, we need to look at the mirrored cell
// Uses locally perfect hashing to eliminate grid artifacts
fn getCellIndexWithFlip(cx: i32, cy: i32, myCellY: i32) -> u32 {
    let cfg = getBoundaryConfig();
    var wcx = cx;
    var wcy = cy;
    let gw = i32(uniforms.gridWidth);
    let gh = i32(uniforms.gridHeight);
    
    // Check if X wrapped and if flip is needed
    if (cfg.flipOnWrapX && (cx < 0 || cx >= gw)) {
        wcx = ((cx % gw) + gw) % gw;
        // Flip Y cell coordinate
        wcy = gh - 1 - wcy;
    } else {
        wcx = ((cx % gw) + gw) % gw;
    }
    
    // Check if Y wrapped and if flip is needed
    if (cfg.flipOnWrapY && (cy < 0 || cy >= gh)) {
        wcy = ((wcy % gh) + gh) % gh;
        // Flip X cell coordinate  
        wcx = gw - 1 - wcx;
    } else {
        wcy = ((wcy % gh) + gh) % gh;
    }
    
    // Apply locally perfect hash AFTER flip adjustments
    let kappa = 3u * (u32(wcx) % 3u) + (u32(wcy) % 3u);
    let beta = (u32(wcy) / 3u) * uniforms.reducedWidth + (u32(wcx) / 3u);
    
    return M * beta + kappa;
}

// Check if we should search this neighboring cell (respects boundary config)
fn shouldSearchCell(cx: i32, cy: i32) -> bool {
    let cfg = getBoundaryConfig();
    let gw = i32(uniforms.gridWidth);
    let gh = i32(uniforms.gridHeight);
    
    // If axis doesn't wrap and cell is out of bounds, skip
    if (!cfg.wrapX && (cx < 0 || cx >= gw)) { return false; }
    if (!cfg.wrapY && (cy < 0 || cy >= gh)) { return false; }
    
    return true;
}

// Soft steering force for bouncy boundaries
fn applySoftSteering(pos: vec2<f32>, vel: vec2<f32>) -> vec2<f32> {
    let cfg = getBoundaryConfig();
    var newVel = vel;
    
    let bounds = getBounds(cfg);
    let minX = bounds.x;
    let minY = bounds.y;
    let maxX = bounds.z;
    let maxY = bounds.w;
    
    let maxTurnForce = 0.25;
    let emergencyForce = 1.5;
    
    // X-axis soft steering (only if bouncy)
    if (cfg.bounceX) {
        // Left boundary
        if (pos.x < minX + SOFT_MARGIN) {
            let dist = max(0.0, pos.x - minX);
            let t = clamp(1.0 - dist / SOFT_MARGIN, 0.0, 1.0);
            var force = t * t * maxTurnForce;
            if (dist < EMERGENCY_ZONE) {
                force += (1.0 - dist / EMERGENCY_ZONE) * emergencyForce;
            }
            newVel.x += force;
        }
        // Right boundary
        if (pos.x > maxX - SOFT_MARGIN) {
            let dist = max(0.0, maxX - pos.x);
            let t = clamp(1.0 - dist / SOFT_MARGIN, 0.0, 1.0);
            var force = t * t * maxTurnForce;
            if (dist < EMERGENCY_ZONE) {
                force += (1.0 - dist / EMERGENCY_ZONE) * emergencyForce;
            }
            newVel.x -= force;
        }
    }
    
    // Y-axis soft steering (only if bouncy)
    if (cfg.bounceY) {
        // Bottom boundary
        if (pos.y < minY + SOFT_MARGIN) {
            let dist = max(0.0, pos.y - minY);
            let t = clamp(1.0 - dist / SOFT_MARGIN, 0.0, 1.0);
            var force = t * t * maxTurnForce;
            if (dist < EMERGENCY_ZONE) {
                force += (1.0 - dist / EMERGENCY_ZONE) * emergencyForce;
            }
            newVel.y += force;
        }
        // Top boundary
        if (pos.y > maxY - SOFT_MARGIN) {
            let dist = max(0.0, maxY - pos.y);
            let t = clamp(1.0 - dist / SOFT_MARGIN, 0.0, 1.0);
            var force = t * t * maxTurnForce;
            if (dist < EMERGENCY_ZONE) {
                force += (1.0 - dist / EMERGENCY_ZONE) * emergencyForce;
            }
            newVel.y -= force;
        }
    }
    
    return newVel;
}

// Sample wall texture at a position (returns 0-1 wall density)
fn sampleWall(pos: vec2<f32>) -> f32 {
    // Convert canvas position to texture UV coordinates
    let uv = vec2<f32>(
        pos.x / uniforms.canvasWidth,
        pos.y / uniforms.canvasHeight
    );
    // Clamp to valid range
    let clampedUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    return textureSampleLevel(wallTexture, wallSampler, clampedUV, 0.0).r;
}

// Wall avoidance - sample wall texture and compute steering force
fn applyWallAvoidance(pos: vec2<f32>, vel: vec2<f32>) -> vec2<f32> {
    var avoidanceForce = vec2<f32>(0.0);
    
    // Sample walls at current position
    let centerWall = sampleWall(pos);
    
    // If we're inside a wall, push out strongly
    if (centerWall > 0.1) {
        // Sample in 8 directions to find escape direction
        let sampleDist = 20.0;
        var escapeDir = vec2<f32>(0.0);
        var minWall = centerWall;
        
        for (var i = 0; i < 8; i++) {
            let angle = f32(i) * 0.785398; // PI/4
            let dir = vec2<f32>(cos(angle), sin(angle));
            let samplePos = pos + dir * sampleDist;
            let wallVal = sampleWall(samplePos);
            if (wallVal < minWall) {
                minWall = wallVal;
                escapeDir = dir;
            }
        }
        
        // Strong escape force proportional to wall density
        avoidanceForce += escapeDir * centerWall * WALL_FORCE_STRENGTH * 3.0;
    }
    
    // Look ahead in velocity direction for walls
    let speed = length(vel);
    if (speed > 0.1) {
        let velDir = vel / speed;
        
        // Sample multiple points ahead
        for (var d = 1; d <= 3; d++) {
            let lookDist = f32(d) * WALL_DETECT_RADIUS / 3.0;
            let lookPos = pos + velDir * lookDist;
            let wallAhead = sampleWall(lookPos);
            
            if (wallAhead > 0.1) {
                // Steer perpendicular to velocity to avoid wall
                // Choose direction based on which side has less wall
                let leftDir = vec2<f32>(-velDir.y, velDir.x);
                let rightDir = vec2<f32>(velDir.y, -velDir.x);
                let leftWall = sampleWall(pos + leftDir * 30.0);
                let rightWall = sampleWall(pos + rightDir * 30.0);
                
                var avoidDir: vec2<f32>;
                if (leftWall < rightWall) {
                    avoidDir = leftDir;
                } else {
                    avoidDir = rightDir;
                }
                
                // Force strength based on wall density and distance
                let distFactor = 1.0 - f32(d - 1) / 3.0;
                avoidanceForce += avoidDir * wallAhead * WALL_FORCE_STRENGTH * distFactor;
            }
        }
    }
    
    // Also sample walls to the sides for proactive avoidance
    let leftSample = sampleWall(pos + vec2<f32>(-25.0, 0.0));
    let rightSample = sampleWall(pos + vec2<f32>(25.0, 0.0));
    let topSample = sampleWall(pos + vec2<f32>(0.0, -25.0));
    let bottomSample = sampleWall(pos + vec2<f32>(0.0, 25.0));
    
    // Push away from nearby walls
    avoidanceForce.x += (leftSample - rightSample) * WALL_FORCE_STRENGTH * 0.5;
    avoidanceForce.y += (topSample - bottomSample) * WALL_FORCE_STRENGTH * 0.5;
    
    return vel + avoidanceForce;
}

// ============================================================================
// SHARED CONSTANTS FOR CONSISTENT BEHAVIOR ACROSS ALL ALGORITHMS
// ============================================================================

const SEPARATION_BASE_RADIUS: f32 = 25.0;   // Fixed base separation radius (independent of perception)
const SEPARATION_FORCE_MULT: f32 = 4.0;     // Separation force multiplier (higher cap for slider range)
const OVERLAP_PUSH_STRENGTH: f32 = 2.0;     // Force when boids overlap
const GLOBAL_COLLISION_RADIUS_MULT: f32 = 32.0;  // Collision radius = avg size * this
const GLOBAL_COLLISION_STRENGTH: f32 = 3.0;     // Base strength multiplier for collision force

// ============================================================================
// FLOCKING ALGORITHM: HASH-FREE (Per-boid randomized grid - no global seams)
// ============================================================================

fn computeFlockingForces(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, speciesId: u32, rebelFactor: f32) -> vec4<f32> {
    // Get per-species parameters
    let spAlignment = getSpeciesAlignment(speciesId);
    let spCohesion = getSpeciesCohesion(speciesId);
    let spSeparation = getSpeciesSeparation(speciesId);
    let spPerception = getSpeciesPerception(speciesId);
    let spMaxForce = getSpeciesMaxForce(speciesId);
    let spSize = getSpeciesSize(speciesId);
    
    let offsetX = hash(boidIndex * 73856093u) * uniforms.cellSize;
    let offsetY = hash(boidIndex * 19349663u) * uniforms.cellSize;
    let shiftedPos = myPos + vec2<f32>(offsetX, offsetY);
    let myCellX = i32(shiftedPos.x / uniforms.cellSize);
    let myCellY = i32(shiftedPos.y / uniforms.cellSize);
    
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var globalCollisionSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    let perception = spPerception;
    let separationRadius = max(SEPARATION_BASE_RADIUS, spSize * 12.0);
    
    // Metrics accumulators (all species for visualization)
    var densitySum: f32 = 0.0;
    var metricWeight: f32 = 0.0;
    var cxx: f32 = 0.0;
    var cxy: f32 = 0.0;
    var cyy: f32 = 0.0;
    
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!shouldSearchCell(cx, cy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(cx, cy, myCellY);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            let maxPerCell = min(cellCount, 64u);
            
            for (var i = 0u; i < maxPerCell; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                let otherSpecies = speciesIds[otherIdx];
                let isSameSpecies = otherSpecies == speciesId;
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                // Metrics accumulation (all species for density visualization)
                if (weight > 0.0) {
                    densitySum += weight;
                    metricWeight += weight;
                    cxx += weight * delta.x * delta.x;
                    cxy += weight * delta.x * delta.y;
                    cyy += weight * delta.y * delta.y;
                }
                
                // Global collision (cross-species only) - prevents overlap
                if (uniforms.globalCollision > 0.0 && !isSameSpecies) {
                    let otherSize = getSpeciesSize(otherSpecies);
                    let collisionRadius = (spSize + otherSize) * 0.5 * GLOBAL_COLLISION_RADIUS_MULT;
                    if (dist < collisionRadius && dist > 0.001) {
                        let dir = delta / dist;
                        // Use same kernel as separation for consistent behavior
                        globalCollisionSum -= dir * separationKernel(dist, collisionRadius) * GLOBAL_COLLISION_STRENGTH;
                    }
                }
                
                // Overlap push (same-species only)
                if (distSq < 1.0 && isSameSpecies) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                // Flocking forces (same-species only)
                if (weight > 0.0 && isSameSpecies) {
                    let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                    alignmentSum += otherVel * weight;
                    cohesionSum += delta * weight;
                    totalWeight += weight;
                }
                
                // Separation (same-species only)
                if (dist < separationRadius && isSameSpecies) {
                    // Manual normalize: reuse already-computed dist instead of sqrt again
                    let dir = delta / dist;
                    separationSum -= dir * separationKernel(dist, separationRadius);
                    separationCount++;
                }
            }
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (spAlignment > 0.0) {
            acceleration += limitMagnitude(alignmentSum / totalWeight - myVel, spMaxForce) * spAlignment * rebelFactor;
        }
        if (spCohesion > 0.0) {
            acceleration += limitMagnitude(cohesionSum / totalWeight, spMaxForce) * spCohesion * rebelFactor;
        }
    }
    
    if (separationCount > 0u && spSeparation > 0.0) {
        acceleration += limitMagnitude(separationSum, spMaxForce * SEPARATION_FORCE_MULT) * spSeparation;
    }
    
    // Global collision force (cross-species only)
    if (uniforms.globalCollision > 0.0) {
        acceleration += limitMagnitude(globalCollisionSum, spMaxForce * SEPARATION_FORCE_MULT) * uniforms.globalCollision;
    }
    
    // Compute and write metrics
    var aniso: f32 = 0.0;
    if (metricWeight > 1e-6) {
        let inv = 1.0 / metricWeight;
        let ncxx = cxx * inv;
        let ncxy = cxy * inv;
        let ncyy = cyy * inv;
        
        // 2×2 eigensolve (closed form)
        let tr = ncxx + ncyy;
        let det = ncxx * ncyy - ncxy * ncxy;
        let disc = sqrt(max(tr * tr - 4.0 * det, 0.0));
        let l1 = 0.5 * (tr + disc);
        let l2 = 0.5 * (tr - disc);
        aniso = (l1 - l2) / (l1 + l2 + 1e-6);
    }
    // Return acceleration in xy, metrics (density, anisotropy) in zw
    // Metrics written in main() so we can add angular velocity
    return vec4<f32>(acceleration.x, acceleration.y, densitySum, aniso);
}

// ============================================================================
// INTER-SPECIES FORCE CALCULATION
// ============================================================================

fn calculateInterSpeciesForce(
    boidIndex: u32,
    myPos: vec2<f32>,
    myVel: vec2<f32>,
    mySpecies: u32
) -> vec2<f32> {
    var interForce = vec2<f32>(0.0);
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // Per-behavior accumulators for all 10 behaviors
    var fleeSum = vec2<f32>(0.0);
    var fleeCount = 0u;
    var chaseSum = vec2<f32>(0.0);
    var chasePredictSum = vec2<f32>(0.0);  // For predicted position
    var chaseCount = 0u;
    var cohereSum = vec2<f32>(0.0);
    var cohereVelSum = vec2<f32>(0.0);
    var cohereWeight = 0.0;
    var alignSum = vec2<f32>(0.0);
    var alignWeight = 0.0;
    var orbitSum = vec2<f32>(0.0);
    var orbitCount = 0u;
    var followSum = vec2<f32>(0.0);
    var followCount = 0u;
    var guardSum = vec2<f32>(0.0);
    var guardCount = 0u;
    var disperseSum = vec2<f32>(0.0);
    var disperseCount = 0u;
    var mobSum = vec2<f32>(0.0);
    var mobOrbitSum = vec2<f32>(0.0);
    var mobCount = 0u;
    
    // Search neighbors in 5x5 grid (needed for cellSize = perception/2)
    for (var dy = -2i; dy <= 2i; dy++) {
        for (var dx = -2i; dx <= 2i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!shouldSearchCell(cx, cy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(cx, cy, myCellY);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            for (var i = 0u; i < cellCount && i < 32u; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherSpecies = speciesIds[otherIdx];
                if (otherSpecies == mySpecies) { continue; } // Skip same species
                
                // Get interaction rule for my species -> other species
                let behavior = u32(getInteraction(mySpecies, otherSpecies, IM_BEHAVIOR));
                let strength = getInteraction(mySpecies, otherSpecies, IM_STRENGTH);
                var range = getInteraction(mySpecies, otherSpecies, IM_RANGE);
                
                if (behavior == BEHAVIOR_IGNORE || strength < 0.01) { continue; }
                
                // Use 1.5x species perception if range not specified (auto)
                // Inter-species interactions need longer range than same-species flocking
                if (range < 1.0) { range = getSpeciesPerception(mySpecies) * 1.5; }
                
                let otherPos = positionsIn[otherIdx];
                let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                let rangeSq = range * range;
                
                if (distSq > rangeSq || distSq < 0.1) { continue; }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, range);
                let dir = delta / dist;
                
                switch (behavior) {
                    case BEHAVIOR_FLEE: {
                        // Strong escape response - prey behavior
                        // Uses stronger close-range kernel for urgent escape
                        let fleeWeight = separationKernel(dist, range) * strength;
                        fleeSum -= dir * fleeWeight;
                        fleeCount++;
                    }
                    case BEHAVIOR_CHASE: {
                        // Predatory pursuit - target predicted future position
                        let prediction = otherPos + otherVel * 0.5;  // Predict 0.5s ahead
                        let predictDelta = getNeighborDelta(myPos, prediction);
                        chaseSum += delta * weight * strength;
                        chasePredictSum += predictDelta * weight * strength;
                        chaseCount++;
                    }
                    case BEHAVIOR_COHERE: {
                        // Mutualistic flocking - attraction + partial alignment
                        cohereSum += delta * weight * strength;
                        cohereVelSum += otherVel * weight * strength * 0.5;  // Partial alignment
                        cohereWeight += weight;
                    }
                    case BEHAVIOR_ALIGN: {
                        // Pure velocity matching - information transfer
                        alignSum += otherVel * weight * strength;
                        alignWeight += weight;
                    }
                    case BEHAVIOR_ORBIT: {
                        // Circular motion around target - territorial/escort
                        let perpDir = vec2<f32>(-dir.y, dir.x);
                        orbitSum += perpDir * weight * strength;
                        orbitCount++;
                    }
                    case BEHAVIOR_FOLLOW: {
                        // Trail behind - leader-follower dynamics
                        // Target position behind the other's velocity vector
                        let otherSpeed = length(otherVel);
                        var followOffset = delta;
                        if (otherSpeed > 0.1) {
                            let otherDir = otherVel / otherSpeed;
                            // Position 30 units behind the leader
                            let targetPos = otherPos - otherDir * 30.0;
                            followOffset = getNeighborDelta(myPos, targetPos);
                        }
                        followSum += followOffset * weight * strength;
                        followCount++;
                    }
                    case BEHAVIOR_GUARD: {
                        // Maintain optimal distance - protective escort
                        // Attracted when far, repelled when close (homeostatic)
                        let optimalDist = range * 0.5;  // Stay at half the perception range
                        let distError = dist - optimalDist;
                        if (distError > 0.0) {
                            // Too far: move closer
                            guardSum += dir * smoothKernel(abs(distError), range * 0.5) * strength;
                        } else {
                            // Too close: move away
                            guardSum -= dir * separationKernel(dist, optimalDist) * strength;
                        }
                        guardCount++;
                    }
                    case BEHAVIOR_DISPERSE: {
                        // Explosive scatter - confusion effect
                        // Strong repulsion + random perturbation
                        let disperseWeight = separationKernel(dist, range) * strength * 2.0;
                        disperseSum -= dir * disperseWeight;
                        // Add randomized component for confusion
                        let randAngle = hash(boidIndex * 17u + otherIdx * 31u + uniforms.frameCount) * 6.283185;
                        disperseSum += vec2<f32>(cos(randAngle), sin(randAngle)) * disperseWeight * 0.3;
                        disperseCount++;
                    }
                    case BEHAVIOR_MOB: {
                        // Aggressive swarming - counter-attack behavior
                        // Rapid approach + tight chaotic orbiting
                        mobSum += delta * weight * strength * 1.5;  // Stronger attraction
                        // Add tight orbit component
                        let perpDir = vec2<f32>(-dir.y, dir.x);
                        // Alternate orbit direction based on boid index for chaos
                        let orbitDir = select(-1.0, 1.0, (boidIndex % 2u) == 0u);
                        mobOrbitSum += perpDir * weight * strength * orbitDir;
                        mobCount++;
                    }
                    default: {}
                }
            }
        }
    }
    
    // Combine forces using per-species maxForce
    let maxForce = getSpeciesMaxForce(mySpecies);
    
    // Flee: strong escape (4x force multiplier)
    if (fleeCount > 0u) {
        interForce += limitMagnitude(fleeSum, maxForce * 4.0);
    }
    
    // Chase: predatory pursuit (blend direct + predicted)
    if (chaseCount > 0u) {
        let directChase = chaseSum / f32(chaseCount);
        let predictChase = chasePredictSum / f32(chaseCount);
        let blendedChase = directChase * 0.3 + predictChase * 0.7;  // Favor prediction
        interForce += limitMagnitude(blendedChase, maxForce * 2.0);
    }
    
    // Cohere: mutualistic flocking (attraction + partial alignment)
    if (cohereWeight > 0.0) {
        let cohereAttract = cohereSum / cohereWeight;
        let cohereAlign = cohereVelSum / cohereWeight - myVel;
        interForce += limitMagnitude(cohereAttract, maxForce);
        interForce += limitMagnitude(cohereAlign, maxForce * 0.5);
    }
    
    // Align: pure velocity matching
    if (alignWeight > 0.0) {
        let targetVel = alignSum / alignWeight;
        interForce += limitMagnitude(targetVel - myVel, maxForce);
    }
    
    // Orbit: circular motion
    if (orbitCount > 0u) {
        interForce += limitMagnitude(orbitSum / f32(orbitCount), maxForce * 2.0);
    }
    
    // Follow: leader-follower dynamics
    if (followCount > 0u) {
        interForce += limitMagnitude(followSum / f32(followCount), maxForce * 1.5);
    }
    
    // Guard: maintain optimal distance
    if (guardCount > 0u) {
        interForce += limitMagnitude(guardSum, maxForce * 1.5);
    }
    
    // Disperse: explosive scatter (strong force)
    if (disperseCount > 0u) {
        interForce += limitMagnitude(disperseSum, maxForce * 5.0);
    }
    
    // Mob: aggressive swarming (approach + orbit)
    if (mobCount > 0u) {
        interForce += limitMagnitude(mobSum / f32(mobCount), maxForce * 2.0);
        interForce += limitMagnitude(mobOrbitSum / f32(mobCount), maxForce * 1.5);
    }
    
    return interForce;
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
    let mySpecies = speciesIds[boidIndex];
    
    // Get per-species parameters
    let speciesRebels = getSpeciesRebels(mySpecies);
    let speciesMaxSpeed = getSpeciesMaxSpeed(mySpecies);
    let speciesMaxForce = getSpeciesMaxForce(mySpecies);
    
    // Rebel behavior - different boids become rebels each cycle
    let rebelPeriod = 300u;   // ~5 seconds at 60fps per cycle
    let rebelDuration = 90u;  // ~1.5 seconds of rebel behavior
    let cycleNumber = uniforms.frameCount / rebelPeriod;
    let timeInCycle = uniforms.frameCount % rebelPeriod;
    
    // Hash includes cycle number so DIFFERENT boids are selected each cycle
    let rebelHash = hash(boidIndex * 7919u + cycleNumber * 104729u);
    let isRebel = rebelHash < speciesRebels && timeInCycle < rebelDuration;
    let rebelFactor = select(1.0, 0.1, isRebel);
    
    // Compute flocking forces (returns acceleration in xy, metrics in zw)
    let flockResult = computeFlockingForces(boidIndex, myPos, myVel, mySpecies, rebelFactor);
    var acceleration = flockResult.xy;
    let density = flockResult.z;
    let anisotropy = flockResult.w;
    
    // Add inter-species forces
    acceleration += calculateInterSpeciesForce(boidIndex, myPos, myVel, mySpecies);
    
    // Cursor interaction - Shape determines radial force, Vortex adds rotation
    // Per-species cursor response: 0 = Attract, 1 = Repel, 2 = Ignore
    let speciesCursorResponse = getSpeciesCursorResponse(mySpecies);
    let speciesCursorForce = getSpeciesCursorForce(mySpecies);
    let speciesVortexDir = getSpeciesCursorVortexDir(mySpecies);
    let hasVortex = speciesVortexDir != 0.0;
    
    // Skip cursor interaction if species ignores cursor AND vortex is off for this species
    // Allow interaction if species responds OR if vortex is enabled for this species
    if ((speciesCursorResponse != 2u || hasVortex) && uniforms.cursorActive != 0u) {
        let cursorPos = vec2<f32>(uniforms.cursorX, uniforms.cursorY);
        let toCursor = getNeighborDelta(myPos, cursorPos);
        let cursorDist = length(toCursor);
        
        // Use cursorRadius from params (in CSS pixels, scale by DPR)
        let dpr = 2.0;
        let radius = uniforms.cursorRadius * dpr;
        let influenceRange = radius * 2.0;
        
        // When pressed: stronger force AND extended soft falloff beyond normal range
        let isPressed = uniforms.cursorPressed != 0u;
        let strength = select(0.5, 1.0, isPressed);
        
        // Extended falloff multiplier when pressed (force extends further with decay)
        let extendedRange = select(1.0, 2.0, isPressed);  // 2x range when pressed
        var cursorForce = vec2<f32>(0.0);
        
        // Determine effective cursor mode from per-species response
        // Species cursorResponse: 0 = Attract, 1 = Repel, 2 = Ignore
        // Map to effectiveCursorMode: 0 = Off, 1 = Attract, 2 = Repel
        var effectiveCursorMode = 0u;
        if (speciesCursorResponse == 0u) {
            effectiveCursorMode = 1u;  // Attract
        } else if (speciesCursorResponse == 1u) {
            effectiveCursorMode = 2u;  // Repel
        }
        // speciesCursorResponse == 2u (Ignore) leaves effectiveCursorMode as 0 (Off)
        
        if (cursorDist > 0.5) {
            let towardCenter = normalize(toCursor);
            let awayFromCenter = -towardCenter;
            
            // Perpendicular vector for vortex (tangential) - clockwise rotation
            let tangent = vec2<f32>(towardCenter.y, -towardCenter.x);
            
            // Step 1: Calculate radial force based on shape (Ring or Disk)
            // Only apply radial forces if effective mode is Attract or Repel (not Off)
            if (effectiveCursorMode != 0u) {
            switch (uniforms.cursorShape) {
                case CURSOR_RING: {
                    // Ring attractor: boids orbit the circumference
                    let totalRadius = radius + influenceRange;
                    if (cursorDist < totalRadius) {
                        let distFromRing = cursorDist - radius;
                        
                        if (effectiveCursorMode == 1u) {
                            if (distFromRing > 0.0) {
                                // Outside: pull inward toward ring
                                let pull = smoothKernel(distFromRing, influenceRange);
                                cursorForce = towardCenter * pull * strength * speciesCursorForce * 2.5;
                            } else {
                                // Inside: push outward toward ring
                                let push = smoothKernel(-distFromRing, radius);
                                cursorForce = awayFromCenter * push * strength * speciesCursorForce * 3.0;
                            }
                        } else {
                            // Repel: push away from entire ring area
                            // Strong uniform push inside, smooth falloff only at outer edge
                            var repelWeight: f32;
                            if (cursorDist < radius) {
                                // Inside the ring radius: full strength
                                repelWeight = 1.0;
                            } else {
                                // Outside ring but in influence zone: smooth falloff
                                let outerDist = cursorDist - radius;
                                repelWeight = 1.0 - (outerDist / influenceRange);
                                repelWeight = repelWeight * repelWeight;
                            }
                            cursorForce = awayFromCenter * repelWeight * strength * speciesCursorForce * 4.0;
                        }
                    }
                }
                case CURSOR_DISK: {
                    // Disk: containment area - keeps boids inside (attract) or clears area (repel)
                    let diskRadius = radius;
                    let edgeWidth = radius * 0.5;
                    
                    if (effectiveCursorMode == 1u) {
                        // Attract: contain boids within disk
                        if (cursorDist > diskRadius) {
                            // Outside disk: pull toward the edge
                            let distFromEdge = cursorDist - diskRadius;
                            let pull = smoothKernel(distFromEdge, edgeWidth * 2.0);
                            cursorForce = towardCenter * pull * strength * speciesCursorForce * 3.0;
                        } else if (cursorDist < diskRadius * 0.3) {
                            // Too close to center: gentle push outward to distribute
                            let push = 1.0 - (cursorDist / (diskRadius * 0.3));
                            cursorForce = awayFromCenter * push * strength * speciesCursorForce * 0.5;
                        }
                    } else {
                        // Repel: clear boids from disk area
                        // Use inverted falloff - strongest at the edge, still strong at center
                        let totalRadius = diskRadius + edgeWidth;
                        if (cursorDist < totalRadius) {
                            // Base repulsion that's strong across the entire disk
                            var weight: f32;
                            if (cursorDist < diskRadius) {
                                // Inside disk: strong uniform push
                                weight = 1.0;
                            } else {
                                // In edge zone: smooth falloff only at outer boundary
                                let edgeDist = cursorDist - diskRadius;
                                weight = 1.0 - (edgeDist / edgeWidth);
                                weight = weight * weight; // Quadratic falloff at edge
                            }
                            cursorForce = awayFromCenter * weight * strength * speciesCursorForce * 4.0;
                        }
                    }
                }
                default: {
                    // Fallback to disk behavior
                    if (cursorDist < influenceRange) {
                        let weight = smoothKernel(cursorDist, influenceRange);
                        cursorForce = towardCenter * weight * strength * speciesCursorForce * 2.0;
                    }
                }
            }
            
            // Step 1.5: When pressed, add extended soft falloff beyond normal range
            if (isPressed && length(cursorForce) < 0.01) {
                // Boid is outside normal range - apply gradual decay force
                let maxExtendedRange = influenceRange * extendedRange;
                if (cursorDist < maxExtendedRange) {
                    // Smooth cubic falloff from normal range edge to extended range
                    let normalEdge = radius + influenceRange * 0.5;
                    if (cursorDist > normalEdge) {
                        let extendedDist = cursorDist - normalEdge;
                        let extendedWidth = maxExtendedRange - normalEdge;
                        let t = 1.0 - (extendedDist / extendedWidth);
                        let falloff = t * t * t;  // Cubic falloff for smooth decay
                        
                        if (effectiveCursorMode == 1u) {
                            // Attract: gentle pull
                            cursorForce = towardCenter * falloff * strength * speciesCursorForce * 1.5;
                        } else {
                            // Repel: gentle push
                            cursorForce = awayFromCenter * falloff * strength * speciesCursorForce * 2.0;
                        }
                    }
                }
            }
            } // End of cursorMode != 0 check for radial forces
            
            // Step 2: Add vortex (rotation) force if enabled for this species
            // speciesVortexDir: 1.0 = clockwise, -1.0 = counter-clockwise, 0.0 = off
            if (hasVortex) {
                // Direction-aware tangent (user controls clockwise vs counter-clockwise)
                let directedTangent = tangent * speciesVortexDir;
                
                // Different behavior based on cursor mode:
                // - Attract (1): vortex applies INSIDE - boids spiral inward
                // - Repel (2): vortex applies OUTSIDE - boids spiral around the perimeter
                // - Off (0): pure vortex - rotation around cursor with smooth falloff
                if (effectiveCursorMode == 1u) {
                    // Attract + vortex: rotate inside the influence area
                    if (cursorDist < influenceRange) {
                        let vortexWeight = smoothKernel(cursorDist, influenceRange);
                        cursorForce += directedTangent * vortexWeight * strength * speciesCursorForce * 3.0;
                    }
                } else if (effectiveCursorMode == 2u) {
                    // Repel + vortex: rotate OUTSIDE the cursor area
                    // Apply rotation to boids that are outside the main radius but within an outer ring
                    let innerRadius = radius;
                    let outerRadius = radius + influenceRange * 1.5;
                    if (cursorDist > innerRadius * 0.5 && cursorDist < outerRadius) {
                        var vortexWeight: f32;
                        if (cursorDist < innerRadius) {
                            // Inside: weaker rotation (they're being pushed out anyway)
                            vortexWeight = cursorDist / innerRadius;
                        } else {
                            // Outside: strong rotation that fades at outer edge
                            let outerDist = cursorDist - innerRadius;
                            let outerRange = outerRadius - innerRadius;
                            vortexWeight = 1.0 - (outerDist / outerRange);
                            vortexWeight = vortexWeight * vortexWeight; // Quadratic falloff
                        }
                        cursorForce += directedTangent * vortexWeight * strength * speciesCursorForce * 4.0;
                    }
                } else {
                    // Vortex only (mode Off): pure rotation around cursor
                    // Full strength inside, smooth falloff outside
                    // When pressed: extend range and boost force significantly
                    let vortexRadius = radius + influenceRange * extendedRange;
                    if (cursorDist < vortexRadius) {
                        var vortexWeight: f32;
                        if (cursorDist < radius) {
                            // Inside: full strength rotation (no hole)
                            vortexWeight = 1.0;
                        } else {
                            // Outside: smooth falloff to extended range
                            let outerDist = cursorDist - radius;
                            let outerRange = influenceRange * extendedRange;
                            vortexWeight = 1.0 - (outerDist / outerRange);
                            vortexWeight = vortexWeight * vortexWeight;
                        }
                        // Stronger force when pressed: 4.0 normal, 8.0 when pressed
                        let pressedBoost = select(1.0, 2.0, isPressed);
                        cursorForce += directedTangent * vortexWeight * strength * speciesCursorForce * 4.0 * pressedBoost;
                    }
                }
            }
            
            acceleration += cursorForce;
        }
    }
    
    // Noise - adds random perturbation for more organic movement
    // Uses maxSpeed as scale (not maxForce) so the effect is actually visible
    if (uniforms.noise > 0.0) {
        let noiseVec = random2(boidIndex * 31u + uniforms.frameCount * 17u);
        // Scale by maxSpeed * 0.15 so noise=1 gives substantial perturbation
        acceleration += noiseVec * uniforms.noise * speciesMaxSpeed * 0.15;
    }
    
    // Apply soft steering for bouncy boundaries
    var newVel = applySoftSteering(myPos, myVel + acceleration);
    
    // Apply wall avoidance (user-drawn obstacles)
    newVel = applyWallAvoidance(myPos, newVel);
    
    newVel = limitMagnitude(newVel, speciesMaxSpeed);
    
    // Minimum speed
    let speed = length(newVel);
    if (speed < speciesMaxSpeed * 0.3) {
        if (speed > 0.001) {
            newVel = normalize(newVel) * speciesMaxSpeed * 0.3;
        } else {
            newVel = normalize(random2(boidIndex * 13u + uniforms.frameCount * 23u)) * speciesMaxSpeed * 0.3;
        }
    }
    
    // Update position (timeScale controls simulation speed)
    var newPos = myPos + newVel * uniforms.deltaTime * 60.0 * uniforms.timeScale;
    
    // Apply boundary wrapping/bouncing with velocity correction for flip boundaries
    let boundaryResult = applyBoundaryWithVelFix(newPos, newVel);
    newPos = boundaryResult.xy;
    let velMult = boundaryResult.zw;
    newVel = newVel * velMult;  // Flip velocity components when crossing flip boundaries
    
    // Compute angular velocity (true turning rate) for visualization
    // Compare heading angle change between old and new velocity
    let oldSpeed = length(myVel);
    let newSpeed = length(newVel);
    var rawTurnRate = 0.0;
    if (oldSpeed > 0.01 && newSpeed > 0.01) {
        let oldAngle = atan2(myVel.y, myVel.x);
        let newAngle = atan2(newVel.y, newVel.x);
        var angleDiff = newAngle - oldAngle;
        // Normalize to [-PI, PI] to handle wraparound
        if (angleDiff > 3.14159265) { angleDiff -= 6.28318530; }
        if (angleDiff < -3.14159265) { angleDiff += 6.28318530; }
        // Convert to 0-1 with sqrt compression to amplify small turns
        // Linear input: 90° turn = 1.0, then sqrt to lift small values
        let linear = clamp(abs(angleDiff) / 1.5708, 0.0, 1.0);  // PI/2 = 90° = full intensity
        rawTurnRate = sqrt(linear);  // sqrt amplifies small values: 0.1 → 0.316, 0.25 → 0.5
    }
    
    // Temporal smoothing: blend with previous frame's value to reduce jitter
    // Read previous value before overwriting
    let prevTurnRate = metricsOut[boidIndex].z;
    let smoothingFactor = 0.3;  // 0.3 = responsive but smooth, lower = smoother but laggier
    let turnRate = mix(prevTurnRate, rawTurnRate, smoothingFactor);
    
    // Write metrics: density, anisotropy, angular velocity, (reserved for spectral/flow)
    metricsOut[boidIndex] = vec4<f32>(density, anisotropy, turnRate, 0.0);
    
    // Write output
    positionsOut[boidIndex] = newPos;
    velocitiesOut[boidIndex] = newVel;
    
    // Update trail - skip entirely when trailLength is 0 for max performance
    if (uniforms.trailLength > 0u) {
        // Store at the BASE of the boid (x = -0.7 in local space), not the center
        // This ensures trails connect seamlessly to the triangle's back edge
        let speciesSize = getSpeciesSize(mySpecies);
        let finalSpeed = length(newVel);
        var trailPos = newPos;
        if (finalSpeed > 0.001) {
            let trailDir = newVel / finalSpeed;
            // Offset to the triangle's base: 0.7 * boidSize * 6.0
            trailPos = newPos - trailDir * 0.7 * speciesSize * 6.0;
        }
        // Use MAX_TRAIL_LENGTH for buffer stride so changing trailLength doesn't shift data
        trails[boidIndex * MAX_TRAIL_LENGTH + uniforms.trailHead] = trailPos;
    }
}
