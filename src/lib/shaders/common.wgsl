// Shared shader definitions - Uniforms, boundary config, and helper functions
// This file is concatenated with other shader files at load time

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
    timeScale: f32,
    saturationSource: u32,
    brightnessSource: u32,
    spectralMode: u32,
    reducedWidth: u32,
    totalSlots: u32,
    globalCollision: f32,
    hueCurveEnabled: u32,
    saturationCurveEnabled: u32,
    brightnessCurveEnabled: u32,
    hueStrength: f32,
    saturationStrength: f32,
    brightnessStrength: f32,
    // Embedded 3D mode. embedBlend morphs 0 (flat rectangle) -> 1 (full
    // embedding); embedTopology is the surface being embedded onto.
    embedBlend: f32,
    embedTopology: u32,
    // 192 bytes so far - mat4x4 needs 16-byte alignment, which lands exactly here.
    viewProj: mat4x4<f32>,
    // xyz = camera eye in world space (lighting), w = unused
    cameraPos: vec4<f32>,
    // x,y = flat-plane half extents, z = shell fade-in (opaque), w = grid opacity
    embedParams: vec4<f32>,
    // Topology switches cross-fade between two embeddings rather than snapping.
    topologyBlend: f32,
    embedTopologyPrev: u32,
    influenceIterations: u32, // local smoothing steps; reuses the former padding
    _embedPad1: f32,
}

// True when the view should be projected through the 3D embedding at all.
fn isEmbedded() -> bool {
    return uniforms.embedBlend > 0.0001;
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

// Cursor shapes
const CURSOR_RING: u32 = 0u;
const CURSOR_DISK: u32 = 1u;

// Max trail length constant
const MAX_TRAIL_LENGTH: u32 = 50u;

// Max species constant
const MAX_SPECIES: u32 = 7u;

// Boundary configuration for topology handling
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
            // Default to PLANE behavior
            cfg.wrapX = false; cfg.wrapY = false;
            cfg.flipOnWrapX = false; cfg.flipOnWrapY = false;
            cfg.bounceX = true; cfg.bounceY = true;
        }
    }
    return cfg;
}

// Check if X axis wraps for current boundary mode
fn wrapsX() -> bool {
    return uniforms.boundaryMode == TORUS || 
           uniforms.boundaryMode == CYLINDER_X || 
           uniforms.boundaryMode == MOBIUS_X ||
           uniforms.boundaryMode == KLEIN_X ||
           uniforms.boundaryMode == KLEIN_Y ||
           uniforms.boundaryMode == PROJECTIVE_PLANE;
}

// Check if Y axis wraps for current boundary mode
fn wrapsY() -> bool {
    return uniforms.boundaryMode == TORUS || 
           uniforms.boundaryMode == CYLINDER_Y || 
           uniforms.boundaryMode == MOBIUS_Y ||
           uniforms.boundaryMode == KLEIN_X ||
           uniforms.boundaryMode == KLEIN_Y ||
           uniforms.boundaryMode == PROJECTIVE_PLANE;
}


// ============================================================================
// SHARED NEIGHBOURHOOD HELPERS
// ============================================================================
// These live here rather than in each shader because simulate.wgsl and
// rank.wgsl previously carried separate copies, and rank.wgsl's had drifted:
// it skipped unwrapping entirely on any flipping topology, so every metric it
// derived from a neighbourhood (spectral / flow, and anything coloured by them)
// saw garbage deltas near a Mobius or Klein seam.

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
