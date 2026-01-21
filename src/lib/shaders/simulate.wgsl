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
    algorithmMode: u32,
    // Algorithm-specific parameters
    kNeighbors: u32,      // Topological K-NN: number of neighbors to track
    sampleCount: u32,     // Stochastic: random samples per frame
    idealDensity: f32,    // Density Adaptive: target neighbor density
    // Simulation timing
    timeScale: f32,       // Simulation speed multiplier
    // CA System parameters
    caEnabled: u32,       // Master toggle for CA system
    agingEnabled: u32,    // Natural death by time
    maxAge: f32,          // Maximum lifespan in seconds
    vitalityGain: f32,    // Gain multiplier for neighbor influence
    birthVitalityThreshold: f32,  // Parent vitality required to birth
    birthFieldThreshold: f32,     // Weighted field strength required
    vitalityConservation: f32,    // How much vitality preserved in birth
    birthSplit: f32,      // Fraction of vitality given to child (0-1)
    ageSpread: f32,       // Initial age spread as fraction of maxAge
    populationCap: u32,   // 0=none, 1=soft, 2=hard
    maxPopulation: u32,   // Maximum allowed population
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

// Algorithm modes
const ALG_TOPOLOGICAL_KNN: u32 = 0u;
const ALG_SMOOTH_METRIC: u32 = 1u;
const ALG_HASH_FREE: u32 = 2u;
const ALG_STOCHASTIC: u32 = 3u;
const ALG_DENSITY_ADAPTIVE: u32 = 4u;

const MAX_K_NEIGHBORS: u32 = 24u;
const MAX_CANDIDATES: u32 = 128u;
const MAX_TRAIL_LENGTH: u32 = 100u;

// ============================================================================
// CA SYSTEM CONSTANTS
// ============================================================================

const CA_CURVE_SAMPLES: u32 = 128u;
const CA_CURVE_VITALITY_INFLUENCE: u32 = 0u;
const CA_CURVE_ALIGNMENT: u32 = 1u;
const CA_CURVE_COHESION: u32 = 2u;
const CA_CURVE_SEPARATION: u32 = 3u;
const CA_CURVE_BIRTH: u32 = 4u;

// Population cap modes
const POP_CAP_NONE: u32 = 0u;
const POP_CAP_SOFT: u32 = 1u;
const POP_CAP_HARD: u32 = 2u;

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

// CA System bindings (separate bind group to stay within storage buffer limits)
// Using single read_write buffer for state - small race conditions acceptable for visual effects
@group(1) @binding(0) var<storage, read_write> boidState: array<vec4<f32>>;  // [age, vitality, alive, padding]
@group(1) @binding(1) var caCurvesTexture: texture_1d<f32>;  // 4 curves × 128 samples as 1D texture
// Birth colors - updated when child is born so they get position-based color
@group(1) @binding(3) var<storage, read_write> birthColors: array<f32>;
@group(1) @binding(2) var caCurvesSampler: sampler;  // Sampler for curve lookup

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
// CA SYSTEM FUNCTIONS
// ============================================================================

// Look up a value from a CA curve using linear interpolation
fn lookupCACurve(curveIndex: u32, t: f32) -> f32 {
    let base = i32(curveIndex * CA_CURVE_SAMPLES);
    let curvePos = clamp(t, 0.0, 1.0) * 127.0;
    let idxLow = i32(floor(curvePos));
    let idxHigh = min(idxLow + 1, 127);
    let frac = curvePos - f32(idxLow);
    
    // Use textureLoad for 1D texture (returns vec4, we use .r channel)
    let valLow = textureLoad(caCurvesTexture, base + idxLow, 0).r;
    let valHigh = textureLoad(caCurvesTexture, base + idxHigh, 0).r;
    return mix(valLow, valHigh, frac);
}

// Get boid state: returns vec4(age, vitality, alive, padding)
fn getBoidState(boidIndex: u32) -> vec4<f32> {
    return boidState[boidIndex];
}

// Check if boid is alive
fn isBoidAlive(boidIndex: u32) -> bool {
    return boidState[boidIndex].z > 0.5;  // alive is stored in z component as 0.0 or 1.0
}

// Get boid vitality (0-1)
fn getBoidVitality(boidIndex: u32) -> f32 {
    return boidState[boidIndex].y;
}

// Calculate vitality contribution from a neighbor (uses vitality influence curve!)
fn getVitalityContribution(neighborVitality: f32) -> f32 {
    // Look up the vitality influence curve
    // x = neighbor's vitality (0-1)
    // y = contribution to influence sum (can be negative!)
    return lookupCACurve(CA_CURVE_VITALITY_INFLUENCE, neighborVitality);
}

// Calculate birth field contribution from a neighbor (uses birth curve!)
// x = neighbor's vitality (0-1)
// y = contribution to birth field sum
// Separate from vitality influence - allows independent control of birth dynamics
fn getBirthContribution(neighborVitality: f32) -> f32 {
    return lookupCACurve(CA_CURVE_BIRTH, neighborVitality);
}

// Get force modulation multiplier based on own vitality
// Curves return OFFSET from 1.0, so y=0 means multiplier=1 (no change)
// y>0 means stronger force, y<0 means weaker force
fn getAlignmentModulation(vitality: f32) -> f32 {
    return 1.0 + lookupCACurve(CA_CURVE_ALIGNMENT, vitality);
}

fn getCohesionModulation(vitality: f32) -> f32 {
    return 1.0 + lookupCACurve(CA_CURVE_COHESION, vitality);
}

fn getSeparationModulation(vitality: f32) -> f32 {
    return 1.0 + lookupCACurve(CA_CURVE_SEPARATION, vitality);
}

// Note: Birth queueing disabled for now to stay within storage buffer limits
// TODO: Re-implement birth with a CPU-side or texture-based approach

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

// Get cell index with proper wrapping (for spatial hash grid)
fn getCellIndex(cx: i32, cy: i32) -> u32 {
    let wcx = ((cx % i32(uniforms.gridWidth)) + i32(uniforms.gridWidth)) % i32(uniforms.gridWidth);
    let wcy = ((cy % i32(uniforms.gridHeight)) + i32(uniforms.gridHeight)) % i32(uniforms.gridHeight);
    return u32(wcy) * uniforms.gridWidth + u32(wcx);
}

// Get cell index accounting for flip boundaries
// When looking across a flip boundary, we need to look at the mirrored cell
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
    
    return u32(wcy) * uniforms.gridWidth + u32(wcx);
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

// ============================================================================
// ALGORITHM 0: TOPOLOGICAL K-NN
// ============================================================================

fn algorithmTopologicalKNN(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    let k = min(uniforms.kNeighbors, MAX_K_NEIGHBORS);
    
    var knnDistSq: array<f32, 24>;
    var knnIndex: array<u32, 24>;
    for (var i = 0u; i < MAX_K_NEIGHBORS; i++) {
        knnDistSq[i] = 1e10;
        knnIndex[i] = 0xFFFFFFFFu;
    }
    
    var separationSum = vec2<f32>(0.0);
    var separationCount = 0u;
    let separationRadius = max(SEPARATION_BASE_RADIUS, uniforms.boidSize * 12.0);
    
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
                
                if (distSq < 1.0) {
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
                
                if (distSq < knnDistSq[k - 1u]) {
                    var insertPos = k - 1u;
                    for (var j = 0u; j < k - 1u; j++) {
                        if (distSq < knnDistSq[j]) { insertPos = j; break; }
                    }
                    for (var j = k - 1u; j > insertPos; j--) {
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
    
    for (var i = 0u; i < k; i++) {
        if (knnIndex[i] == 0xFFFFFFFFu) { continue; }
        let otherIdx = knnIndex[i];
        let otherPos = positionsIn[otherIdx];
        let dist = sqrt(knnDistSq[i]);
        let weight = smoothKernel(dist, uniforms.perception);
        if (weight > 0.0) {
            // Transform neighbor velocity for alignment across flip boundaries
            let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
            alignmentSum += otherVel * weight;
            cohesionSum += getNeighborDelta(myPos, otherPos) * weight;
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
    let separationRadius = max(SEPARATION_BASE_RADIUS, uniforms.boidSize * 12.0);
    
    for (var dy = -1i; dy <= 1i; dy++) {
        for (var dx = -1i; dx <= 1i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!shouldSearchCell(cx, cy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(cx, cy, myCellY);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            for (var i = 0u; i < cellCount && totalWeight < 80.0; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, uniforms.perception);
                
                if (weight > 0.0) {
                    // Transform neighbor velocity for alignment across flip boundaries
                    let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                    alignmentSum += otherVel * weight;
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
// ============================================================================

fn algorithmHashFree(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
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
    let separationRadius = max(SEPARATION_BASE_RADIUS, uniforms.boidSize * 12.0);
    
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
                
                if (distSq < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                    alignmentSum += otherVel * weight;
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
// ALGORITHM 3: STOCHASTIC SAMPLING
// ============================================================================

fn algorithmStochastic(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
    let cfg = getBoundaryConfig();
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var totalWeight = 0.0;
    var separationCount = 0u;
    
    let perception = uniforms.perception;
    let separationRadius = max(SEPARATION_BASE_RADIUS, uniforms.boidSize * 12.0);
    let numSamples = uniforms.sampleCount;
    var baseSeed = boidIndex * 1000003u + uniforms.frameCount * 31337u;
    
    let myCellX = i32(myPos.x / uniforms.cellSize);
    let myCellY = i32(myPos.y / uniforms.cellSize);
    
    // First pass: check immediate vicinity (3x3)
    for (var dy = -1i; dy <= 1i; dy++) {
        for (var dx = -1i; dx <= 1i; dx++) {
            let cx = myCellX + dx;
            let cy = myCellY + dy;
            
            if (!shouldSearchCell(cx, cy)) { continue; }
            
            let cellIdx = getCellIndexWithFlip(cx, cy, myCellY);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            let sampleCount = min(cellCount, 3u);
            
            for (var i = 0u; i < sampleCount; i++) {
                let otherIdx = sortedIndices[cellStart + i];
                if (otherIdx == boidIndex) { continue; }
                
                let otherPos = positionsIn[otherIdx];
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                if (distSq < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let dist = sqrt(distSq);
                let weight = smoothKernel(dist, perception);
                
                if (weight > 0.0) {
                    let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                    alignmentSum += otherVel * weight;
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
        let seed = baseSeed + s * 7u;
        let angle = hash(seed) * 6.283185307;
        let r = sqrt(hash(seed + 1u)) * perception;
        
        let sampleOffset = vec2<f32>(cos(angle), sin(angle)) * r;
        var samplePos = myPos + sampleOffset;
        
        // Simple wrap for sample position
        if (cfg.wrapX) { samplePos.x = wrapCoord(samplePos.x, uniforms.canvasWidth); }
        if (cfg.wrapY) { samplePos.y = wrapCoord(samplePos.y, uniforms.canvasHeight); }
        
        samplePos.x = clamp(samplePos.x, 0.0, uniforms.canvasWidth - 1.0);
        samplePos.y = clamp(samplePos.y, 0.0, uniforms.canvasHeight - 1.0);
        
        let sampleCellX = i32(samplePos.x / uniforms.cellSize);
        let sampleCellY = i32(samplePos.y / uniforms.cellSize);
        
        let cellIdx = getCellIndex(sampleCellX, sampleCellY);
        let cellStart = prefixSums[cellIdx];
        let cellCount = cellCounts[cellIdx];
        
        if (cellCount == 0u) { continue; }
        
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
            let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
            alignmentSum += otherVel * weight;
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
// ============================================================================

fn algorithmDensityAdaptive(boidIndex: u32, myPos: vec2<f32>, myVel: vec2<f32>, rebelFactor: f32) -> vec2<f32> {
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
    var localDensity = 0.0;
    
    let perception = uniforms.perception;
    let separationRadius = max(SEPARATION_BASE_RADIUS, uniforms.boidSize * 12.0);
    
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
                
                if (distSq > perception * perception) { continue; }
                
                let dist = sqrt(distSq);
                let densityWeight = smoothKernel(dist, perception);
                localDensity += densityWeight;
                
                if (dist < 1.0) {
                    let pushAngle = f32(boidIndex ^ otherIdx) * 0.618033988749;
                    let pushDir = vec2<f32>(cos(pushAngle * 6.283185), sin(pushAngle * 6.283185));
                    separationSum += pushDir * OVERLAP_PUSH_STRENGTH;
                    separationCount++;
                    continue;
                }
                
                let weight = smoothKernel(dist, perception);
                if (weight > 0.0) {
                    let otherVel = transformNeighborVelocity(myPos, otherPos, velocitiesIn[otherIdx]);
                    alignmentSum += otherVel * weight;
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
    
    let densityRatio = localDensity / uniforms.idealDensity;
    let cohesionMod = 1.0 / (1.0 + max(0.0, densityRatio - 1.0) * 0.3);
    
    var acceleration = vec2<f32>(0.0);
    
    if (totalWeight > 0.0) {
        if (uniforms.alignment > 0.0) {
            acceleration += limitMagnitude(alignmentSum / totalWeight - myVel, uniforms.maxForce) * uniforms.alignment * rebelFactor;
        }
        if (uniforms.cohesion > 0.0) {
            acceleration += limitMagnitude(cohesionSum / totalWeight, uniforms.maxForce) * uniforms.cohesion * rebelFactor * cohesionMod;
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
    
    // ========================================================================
    // CA SYSTEM: Read current state (only when CA is enabled)
    // ========================================================================
    var myAge = 0.0;
    var myVitality = 1.0;
    var myAlive = true;
    
    if (uniforms.caEnabled != 0u) {
        let myState = getBoidState(boidIndex);
        myAge = myState.x;
        myVitality = myState.y;
        myAlive = myState.z > 0.5;
        
        // Dead boids: Skip simulation entirely.
        // IMPORTANT: We do NOT write to position/velocity/trail buffers here.
        // If this boid gets resurrected by a parent, the parent will write all
        // necessary data. If not resurrected, the trail shader will hide it
        // based on the alive flag in boidState.
        // This avoids race conditions between dead boid writes and parent birth writes.
        if (!myAlive) {
            // Only update boidState to keep dead status
            // Position/velocity buffers are intentionally NOT written to avoid
            // race conditions with potential parent birth writes
            return;
        }
    }
    
    // Rebel behavior - different boids become rebels each cycle
    let rebelPeriod = 300u;   // ~5 seconds at 60fps per cycle
    let rebelDuration = 90u;  // ~1.5 seconds of rebel behavior
    let cycleNumber = uniforms.frameCount / rebelPeriod;
    let timeInCycle = uniforms.frameCount % rebelPeriod;
    
    // Hash includes cycle number so DIFFERENT boids are selected each cycle
    let rebelHash = hash(boidIndex * 7919u + cycleNumber * 104729u);
    let isRebel = rebelHash < uniforms.rebels && timeInCycle < rebelDuration;
    let rebelFactor = select(1.0, 0.1, isRebel);
    
    // Select algorithm - returns (acceleration, neighborInfluenceSum) when CA is enabled
    var acceleration: vec2<f32>;
    var neighborInfluenceSum: f32 = 0.0;
    
    switch (uniforms.algorithmMode) {
        case ALG_TOPOLOGICAL_KNN: { acceleration = algorithmTopologicalKNN(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_SMOOTH_METRIC: { acceleration = algorithmSmoothMetric(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_HASH_FREE: { acceleration = algorithmHashFree(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_STOCHASTIC: { acceleration = algorithmStochastic(boidIndex, myPos, myVel, rebelFactor); }
        case ALG_DENSITY_ADAPTIVE: { acceleration = algorithmDensityAdaptive(boidIndex, myPos, myVel, rebelFactor); }
        default: { acceleration = algorithmHashFree(boidIndex, myPos, myVel, rebelFactor); }
    }
    
    // ========================================================================
    // CA SYSTEM: Force modulation based on own vitality (DISABLED FOR DEBUGGING)
    // ========================================================================
    // NOTE: Force modulation is disabled when force curves are at y=0 (default).
    // The curves must be explicitly adjusted to enable vitality-based force changes.
    // This prevents any unintended motion effects from CA alone.
    //
    // Uncomment below to enable force modulation:
    // if (uniforms.caEnabled != 0u) {
    //     let alignMod = getAlignmentModulation(myVitality);
    //     let cohesionMod = getCohesionModulation(myVitality);
    //     let sepMod = getSeparationModulation(myVitality);
    //     let avgMod = (alignMod + cohesionMod + sepMod) / 3.0;
    //     acceleration *= avgMod;
    // }
    
    // Cursor interaction - Shape determines radial force, Vortex adds rotation
    // Allow interaction if mode is Attract/Repel OR if Vortex is enabled independently
    if ((uniforms.cursorMode != 0u || uniforms.cursorVortex != 0u) && uniforms.cursorActive != 0u) {
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
        
        if (cursorDist > 0.5) {
            let towardCenter = normalize(toCursor);
            let awayFromCenter = -towardCenter;
            
            // Perpendicular vector for vortex (tangential) - clockwise rotation
            let tangent = vec2<f32>(towardCenter.y, -towardCenter.x);
            
            // Step 1: Calculate radial force based on shape (Ring or Disk)
            // Only apply radial forces if mode is Attract or Repel (not Off)
            if (uniforms.cursorMode != 0u) {
            switch (uniforms.cursorShape) {
                case CURSOR_RING: {
                    // Ring attractor: boids orbit the circumference
                    let totalRadius = radius + influenceRange;
                    if (cursorDist < totalRadius) {
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
                            cursorForce = awayFromCenter * repelWeight * strength * uniforms.cursorForce * 4.0;
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
                            cursorForce = awayFromCenter * weight * strength * uniforms.cursorForce * 4.0;
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
                        
                        if (uniforms.cursorMode == 1u) {
                            // Attract: gentle pull
                            cursorForce = towardCenter * falloff * strength * uniforms.cursorForce * 1.5;
                        } else {
                            // Repel: gentle push
                            cursorForce = awayFromCenter * falloff * strength * uniforms.cursorForce * 2.0;
                        }
                    }
                }
            }
            } // End of cursorMode != 0 check for radial forces
            
            // Step 2: Add vortex (rotation) force if enabled - independent of shape
            if (uniforms.cursorVortex != 0u) {
                // Different behavior based on cursor mode:
                // - Attract (1): vortex applies INSIDE - boids spiral inward
                // - Repel (2): vortex applies OUTSIDE - boids spiral around the perimeter
                // - Off (0): pure vortex - rotation around cursor with smooth falloff
                if (uniforms.cursorMode == 1u) {
                    // Attract + vortex: rotate inside the influence area
                    if (cursorDist < influenceRange) {
                        let vortexWeight = smoothKernel(cursorDist, influenceRange);
                        cursorForce += tangent * vortexWeight * strength * uniforms.cursorForce * 3.0;
                    }
                } else if (uniforms.cursorMode == 2u) {
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
                        cursorForce += -tangent * vortexWeight * strength * uniforms.cursorForce * 4.0;
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
                        cursorForce += tangent * vortexWeight * strength * uniforms.cursorForce * 4.0 * pressedBoost;
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
        acceleration += noiseVec * uniforms.noise * uniforms.maxSpeed * 0.15;
    }
    
    // Apply soft steering for bouncy boundaries
    var newVel = applySoftSteering(myPos, myVel + acceleration);
    
    // Apply wall avoidance (user-drawn obstacles)
    newVel = applyWallAvoidance(myPos, newVel);
    
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
    
    // Update position (timeScale controls simulation speed)
    var newPos = myPos + newVel * uniforms.deltaTime * 60.0 * uniforms.timeScale;
    
    // Apply boundary wrapping/bouncing with velocity correction for flip boundaries
    let boundaryResult = applyBoundaryWithVelFix(newPos, newVel);
    newPos = boundaryResult.xy;
    let velMult = boundaryResult.zw;
    newVel = newVel * velMult;  // Flip velocity components when crossing flip boundaries
    
    // Write position and velocity output
    positionsOut[boidIndex] = newPos;
    velocitiesOut[boidIndex] = newVel;
    
    // ========================================================================
    // CA SYSTEM: Update state (age, vitality, death, birth)
    // ========================================================================
    var newAge = myAge;
    var newVitality = myVitality;
    var newAlive = myAlive;
    
    if (uniforms.caEnabled != 0u) {
        // Update age
        newAge = myAge + uniforms.deltaTime * uniforms.timeScale;
        
        // ========================================================================
        // CONTINUOUS FIELD CALCULATIONS (VITALITY + BIRTH)
        // ========================================================================
        // Use smooth kernel weighting (same as flocking forces) for continuous fields.
        //
        // vitalityInfluence = Σ smoothKernel(dist) × vitality × vitalityCurve(vitality)
        // birthField = Σ smoothKernel(dist) × birthCurve(vitality)
        //
        // These are SEPARATE curves so you can control vitality dynamics and birth independently.
        //
        let myCellX = i32(newPos.x / uniforms.cellSize);
        let myCellY = i32(newPos.y / uniforms.cellSize);
        var weightedVitalitySum: f32 = 0.0;
        var birthFieldSum: f32 = 0.0;
        var totalWeight: f32 = 0.0;
        
        // 5x5 grid search (matching flocking algorithms)
        for (var dy = -2i; dy <= 2i; dy++) {
            for (var dx = -2i; dx <= 2i; dx++) {
                let ncx = myCellX + dx;
                let ncy = myCellY + dy;
                if (ncx >= 0 && ncx < i32(uniforms.gridWidth) && ncy >= 0 && ncy < i32(uniforms.gridHeight)) {
                    let nCellIdx = u32(ncy) * uniforms.gridWidth + u32(ncx);
                    let cellStart = prefixSums[nCellIdx];
                    let cellCount = cellCounts[nCellIdx];
                    
                    for (var i = 0u; i < min(cellCount, 64u); i++) {
                        let otherIdx = sortedIndices[cellStart + i];
                        if (otherIdx != boidIndex) {
                            let otherPos = positionsIn[otherIdx];
                            let dist = distance(newPos, otherPos);
                            
                            if (dist < uniforms.perception) {
                                let otherState = boidState[otherIdx];
                                let otherVitality = otherState.y;
                                
                                // Smooth kernel weight (same as flocking alignment/cohesion)
                                let kernelWeight = smoothKernel(dist, uniforms.perception);
                                
                                // Accumulate weighted vitality for averaging
                                weightedVitalitySum += kernelWeight * otherVitality;
                                
                                // Birth field: separate curve for birth dynamics
                                let birthCurveWeight = getBirthContribution(otherVitality);
                                birthFieldSum += kernelWeight * birthCurveWeight;
                                
                                totalWeight += kernelWeight;
                            }
                        }
                    }
                }
            }
        }
        
        // ========================================================================
        // VITALITY DYNAMICS - Continuous Field Model
        // ========================================================================
        // Two independent mechanisms:
        // 1. Vitality Influence curve: maps average neighborhood vitality → your vitality change
        // 2. Birth Field: determines if you can reproduce (also helps survival)
        //
        // The birth field provides a survival bonus - clustered boids decay slower.
        // This ensures populations can sustain even with vitality influence at 0.
        
        let dt = uniforms.deltaTime * uniforms.timeScale;
        
        // Calculate average neighborhood vitality (normalized to 0-1)
        var avgNeighborVitality: f32 = 0.0;
        if (totalWeight > 0.001) {
            avgNeighborVitality = weightedVitalitySum / totalWeight;
        }
        
        // Look up the vitality influence curve ONCE with the average
        // X = average neighbor vitality (0-1), Y = influence multiplier (-1 to 1)
        let curveInfluence = getVitalityContribution(avgNeighborVitality);
        
        // Gain multiplier controls overall sensitivity to neighbors
        let gainMultiplier = uniforms.vitalityGain;
        
        // Neighbor influence: curve output scaled by gain and time
        // Positive curve = neighbors boost your vitality, negative = drain
        let neighborInfluence = curveInfluence * gainMultiplier * dt;
        
        // Natural decay (aging) - base death rate
        var decay = 0.0;
        if (uniforms.maxAge > 0.0) {
            decay = dt / uniforms.maxAge;
        }
        
        // Birth field provides survival bonus - being in a cluster slows decay
        // This allows populations to sustain even with vitality influence curve at 0
        // birthFieldSum > 0.5 means strong cluster = 50% slower decay
        let survivalBonus = clamp(birthFieldSum, 0.0, 1.0) * 0.5;
        let adjustedDecay = decay * (1.0 - survivalBonus);
        
        // Vitality update: neighbor influence minus adjusted decay
        newVitality = clamp(myVitality + neighborInfluence - adjustedDecay, 0.0, 1.0);
        
        // Death when vitality depleted
        if (newVitality <= 0.001) {
            newAlive = false;
            newVitality = 0.0;
        }
        
        // ========================================================================
        // BIRTH - Simple cluster-based reproduction
        // ========================================================================
        // Birth happens automatically when:
        // 1. Boid's vitality exceeds birthVitalityThreshold
        // 2. Birth field sum exceeds birthFieldThreshold
        // 3. A dead slot is available (searches multiple candidates)
        //
        // birthFieldSum uses a SEPARATE curve from vitality influence,
        // allowing independent control of birth vs vitality dynamics.
        
        // Use birthFieldThreshold for BOTH conditions (single slider controls birth ease)
        // Lower threshold = easier birth (both lower vitality required AND lower field required)
        let canBirth = myAlive && 
                       newVitality > uniforms.birthFieldThreshold && 
                       birthFieldSum > uniforms.birthFieldThreshold;
        
        if (canBirth) {
            // Search for a dead slot across the entire population pool (including headroom)
            // With 50k slots and starting population of ~5k, there's plenty of room for growth
            var childSlot = 0xFFFFFFFFu; // Invalid
            let maxSlots = uniforms.maxPopulation;
            let baseSlot = (boidIndex + maxSlots / 2u) % maxSlots;
            
            // Try up to 16 different slots for better chance of finding dead slot
            for (var attempt = 0u; attempt < 16u; attempt++) {
                let candidateSlot = (baseSlot + attempt * 1031u) % maxSlots; // Prime stride for spread
                let candidateState = boidState[candidateSlot];
                if (candidateState.z < 0.5) { // Dead
                    childSlot = candidateSlot;
                    break;
                }
            }
            
            if (childSlot != 0xFFFFFFFFu) {
                // Split vitality based on birthSplit parameter
                let childVitality = newVitality * uniforms.birthSplit;
                newVitality = newVitality * (1.0 - uniforms.birthSplit);
                
                // Offset both parent and child symmetrically to avoid overlap
                // Their average position = original parent position (center of mass preserved)
                let parentSpeed = length(newVel);
                let offsetDist = uniforms.boidSize * 5.0;
                var parentNewPos = newPos;
                var childPos = newPos;
                
                if (parentSpeed > 0.001) {
                    let dir = newVel / parentSpeed;
                    // Parent moves forward, child moves backward
                    parentNewPos = newPos + dir * offsetDist;
                    childPos = newPos - dir * offsetDist;
                } else {
                    // No velocity - use random-ish offset based on boid index
                    let angle = f32(boidIndex) * 0.618033988749 * 6.283185;
                    let offsetDir = vec2<f32>(cos(angle), sin(angle));
                    parentNewPos = newPos + offsetDir * offsetDist;
                    childPos = newPos - offsetDir * offsetDist;
                }
                
                // Update parent position (will be written below)
                newPos = parentNewPos;
                
                // Child inherits parent's velocity
                positionsOut[childSlot] = childPos;
                velocitiesOut[childSlot] = newVel;
                boidState[childSlot] = vec4<f32>(0.0, childVitality, 1.0, 0.0);
                
                // Update child's birth color based on spawn position (angle from canvas center)
                // This ensures newborns get proper position-based coloring
                let canvasCenterX = f32(uniforms.canvasWidth) * 0.5;
                let canvasCenterY = f32(uniforms.canvasHeight) * 0.5;
                let childAngle = atan2(childPos.y - canvasCenterY, childPos.x - canvasCenterX);
                birthColors[childSlot] = (childAngle + 3.14159265) / (2.0 * 3.14159265); // Normalize to [0, 1]
                
                // Reset child's trail to proper base position (offset from center)
                // This matches how trails are normally written
                var childTrailPos = childPos;
                let childSpeed = length(newVel);
                if (childSpeed > 0.001) {
                    let childDir = newVel / childSpeed;
                    childTrailPos = childPos - childDir * 0.7 * uniforms.boidSize * 6.0;
                }
                for (var t = 0u; t < MAX_TRAIL_LENGTH; t++) {
                    trails[childSlot * MAX_TRAIL_LENGTH + t] = childTrailPos;
                }
            }
        }
    }
    
    // Write CA state (in-place update)
    boidState[boidIndex] = vec4<f32>(newAge, newVitality, select(0.0, 1.0, newAlive), 0.0);
    
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
