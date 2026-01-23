// Trail rendering shader - instanced line segments with fading

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
}

// Color modes
const COLOR_SPEED: u32 = 0u;
const COLOR_ORIENTATION: u32 = 1u;
const COLOR_NEIGHBORS: u32 = 2u;
const COLOR_ACCELERATION: u32 = 3u;
const COLOR_TURNING: u32 = 4u;
const COLOR_NONE: u32 = 5u;
const COLOR_DENSITY: u32 = 6u;
const COLOR_SPECIES: u32 = 7u;

// Get species color params from speciesParams buffer (4 vec4s per species)
fn getSpeciesHue(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 4u + 1u].z;  // vec4[1].z = hue (normalized 0-1)
}

fn getSpeciesSaturation(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 4u + 2u].x;  // vec4[2].x = saturation
}

fn getSpeciesLightness(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 4u + 2u].y;  // vec4[2].y = lightness
}

fn getSpeciesTrailLength(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 4u + 2u].w;  // vec4[2].w = trailLength
}

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_OCEAN: u32 = 1u;
const SPECTRUM_BANDS: u32 = 2u;
const SPECTRUM_RAINBOW: u32 = 3u;
const SPECTRUM_MONO: u32 = 4u;

// Maximum trail length for buffer stride (must match CPU-side MAX_TRAIL_LENGTH)
const MAX_TRAIL_LENGTH: u32 = 100u;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
    @location(1) alpha: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> velocities: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> trails: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read> birthColors: array<f32>;
@group(0) @binding(5) var<storage, read> speciesIds: array<u32>;
@group(0) @binding(6) var<uniform> speciesParams: array<vec4<f32>, 28>;  // 7 species * 4 vec4s

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x;
    let s = hsv.y;
    let v = hsv.z;
    
    let c = v * s;
    let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = v - c;
    
    var rgb: vec3<f32>;
    let hi = i32(h * 6.0) % 6;
    
    switch (hi) {
        case 0: { rgb = vec3<f32>(c, x, 0.0); }
        case 1: { rgb = vec3<f32>(x, c, 0.0); }
        case 2: { rgb = vec3<f32>(0.0, c, x); }
        case 3: { rgb = vec3<f32>(0.0, x, c); }
        case 4: { rgb = vec3<f32>(x, 0.0, c); }
        default: { rgb = vec3<f32>(c, 0.0, x); }
    }
    
    return rgb + m;
}

// HSL to RGB conversion
fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var rgb: vec3<f32>;
    let hi = i32(h * 6.0) % 6;
    
    switch (hi) {
        case 0: { rgb = vec3<f32>(c, x, 0.0); }
        case 1: { rgb = vec3<f32>(x, c, 0.0); }
        case 2: { rgb = vec3<f32>(0.0, c, x); }
        case 3: { rgb = vec3<f32>(0.0, x, c); }
        case 4: { rgb = vec3<f32>(x, 0.0, c); }
        default: { rgb = vec3<f32>(c, 0.0, x); }
    }
    
    return rgb + m;
}

fn getColorFromSpectrum(t: f32, spectrum: u32) -> vec3<f32> {
    let tt = clamp(t, 0.0, 1.0);
    
    switch (spectrum) {
        case SPECTRUM_CHROME: {
            if (tt < 0.25) {
                return mix(vec3<f32>(0.2, 0.4, 0.9), vec3<f32>(0.3, 0.8, 0.9), tt * 4.0);
            } else if (tt < 0.5) {
                return mix(vec3<f32>(0.3, 0.8, 0.9), vec3<f32>(0.95, 0.95, 0.9), (tt - 0.25) * 4.0);
            } else if (tt < 0.75) {
                return mix(vec3<f32>(0.95, 0.95, 0.9), vec3<f32>(0.95, 0.6, 0.2), (tt - 0.5) * 4.0);
            } else {
                return mix(vec3<f32>(0.95, 0.6, 0.2), vec3<f32>(0.9, 0.2, 0.2), (tt - 0.75) * 4.0);
            }
        }
        case SPECTRUM_OCEAN: {
            // Sophisticated circular palette - loops back to start
            // Deep Blue -> Teal -> Seafoam -> Gold -> Coral -> Mauve -> Deep Blue
            if (tt < 0.167) {
                return mix(vec3<f32>(0.3, 0.42, 0.78), vec3<f32>(0.25, 0.65, 0.7), tt * 6.0);
            } else if (tt < 0.333) {
                return mix(vec3<f32>(0.25, 0.65, 0.7), vec3<f32>(0.35, 0.75, 0.55), (tt - 0.167) * 6.0);
            } else if (tt < 0.5) {
                return mix(vec3<f32>(0.35, 0.75, 0.55), vec3<f32>(0.92, 0.78, 0.35), (tt - 0.333) * 6.0);
            } else if (tt < 0.667) {
                return mix(vec3<f32>(0.92, 0.78, 0.35), vec3<f32>(0.88, 0.5, 0.45), (tt - 0.5) * 6.0);
            } else if (tt < 0.833) {
                return mix(vec3<f32>(0.88, 0.5, 0.45), vec3<f32>(0.65, 0.42, 0.65), (tt - 0.667) * 6.0);
            } else {
                return mix(vec3<f32>(0.65, 0.42, 0.65), vec3<f32>(0.3, 0.42, 0.78), (tt - 0.833) * 6.0);
            }
        }
        case SPECTRUM_BANDS: {
            // Distinct color bands - sharp transitions for maximum contrast
            // 6 distinct colors with minimal blending
            let band = u32(tt * 6.0);
            let bandT = fract(tt * 6.0);
            // Quick transition only at band edges (last 15%)
            let blend = smoothstep(0.85, 1.0, bandT);
            
            var c1: vec3<f32>;
            var c2: vec3<f32>;
            switch (band) {
                case 0u: { c1 = vec3<f32>(0.9, 0.2, 0.3); c2 = vec3<f32>(0.95, 0.6, 0.1); }  // Red -> Orange
                case 1u: { c1 = vec3<f32>(0.95, 0.6, 0.1); c2 = vec3<f32>(0.95, 0.9, 0.2); } // Orange -> Yellow
                case 2u: { c1 = vec3<f32>(0.95, 0.9, 0.2); c2 = vec3<f32>(0.2, 0.8, 0.4); }  // Yellow -> Green
                case 3u: { c1 = vec3<f32>(0.2, 0.8, 0.4); c2 = vec3<f32>(0.2, 0.6, 0.9); }   // Green -> Blue
                case 4u: { c1 = vec3<f32>(0.2, 0.6, 0.9); c2 = vec3<f32>(0.6, 0.3, 0.8); }   // Blue -> Purple
                default: { c1 = vec3<f32>(0.6, 0.3, 0.8); c2 = vec3<f32>(0.9, 0.2, 0.3); }   // Purple -> Red
            }
            return mix(c1, c2, blend);
        }
        case SPECTRUM_RAINBOW: {
            return hsv2rgb(vec3<f32>(tt, 0.85, 0.9));
        }
        case SPECTRUM_MONO: {
            let brightness = 0.4 + tt * 0.6;
            return vec3<f32>(brightness, brightness * 0.95, brightness * 0.9);
        }
        default: {
            return vec3<f32>(1.0);
        }
    }
}

// Boundary modes (must match simulate.wgsl)
const PLANE: u32 = 0u;
const CYLINDER_X: u32 = 1u;
const CYLINDER_Y: u32 = 2u;
const TORUS: u32 = 3u;
const MOBIUS_X: u32 = 4u;
const MOBIUS_Y: u32 = 5u;
const KLEIN_X: u32 = 6u;
const KLEIN_Y: u32 = 7u;
const PROJECTIVE_PLANE: u32 = 8u;

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

// Check if a segment wraps across boundary and calculate edge intersection
// Returns: (isWrapped, clampedP2) - if wrapped, p2 is clamped to edge
fn handleWrap(p1: vec2<f32>, p2: vec2<f32>) -> vec2<f32> {
    let dx = p2.x - p1.x;
    let dy = p2.y - p1.y;
    
    var clampedP2 = p2;
    let threshold = 0.4; // Threshold for detecting wrap (40% of canvas)
    
    // Check for X wrap
    if (wrapsX() && abs(dx) > uniforms.canvasWidth * threshold) {
        // Segment wraps in X - clamp to edge
        if (dx > 0.0) {
            // p1 is on the right, p2 wrapped to left - clamp p2 to left edge
            // Actually p1 is leaving through right edge
            let t = (uniforms.canvasWidth - p1.x) / (p1.x + uniforms.canvasWidth - p2.x);
            clampedP2.x = uniforms.canvasWidth;
            clampedP2.y = p1.y + t * (p2.y - p1.y + select(0.0, uniforms.canvasHeight, abs(dy) > uniforms.canvasHeight * threshold));
        } else {
            // p1 is on the left, p2 wrapped to right - clamp p2 to right edge
            let t = p1.x / (p1.x + uniforms.canvasWidth - p2.x);
            clampedP2.x = 0.0;
            clampedP2.y = p1.y + t * (p2.y - p1.y);
        }
    }
    
    // Check for Y wrap
    if (wrapsY() && abs(dy) > uniforms.canvasHeight * threshold) {
        // Segment wraps in Y - clamp to edge
        if (dy > 0.0) {
            // p1 is at bottom, p2 wrapped to top
            let t = (uniforms.canvasHeight - p1.y) / (p1.y + uniforms.canvasHeight - p2.y);
            clampedP2.y = uniforms.canvasHeight;
            if (abs(dx) <= uniforms.canvasWidth * threshold) {
                clampedP2.x = p1.x + t * dx;
            }
        } else {
            // p1 is at top, p2 wrapped to bottom
            let t = p1.y / (p1.y + uniforms.canvasHeight - p2.y);
            clampedP2.y = 0.0;
            if (abs(dx) <= uniforms.canvasWidth * threshold) {
                clampedP2.x = p1.x + t * dx;
            }
        }
    }
    
    return clampedP2;
}

// Check if two positions are too far apart (indicates boundary wrap)
fn isWrapped(p1: vec2<f32>, p2: vec2<f32>) -> bool {
    let dx = abs(p1.x - p2.x);
    let dy = abs(p1.y - p2.y);
    return dx > uniforms.canvasWidth * 0.4 || dy > uniforms.canvasHeight * 0.4;
}

@vertex
fn vs_main(
    @builtin(vertex_index) vertexIndex: u32,
    @builtin(instance_index) instanceIndex: u32
) -> VertexOutput {
    var output: VertexOutput;
    
    // Each instance is one trail segment (line between two consecutive trail points)
    // instanceIndex = boidIndex * (trailLength - 1) + segmentIndex
    // We use global uniforms.trailLength for instance calculation (max trail length)
    let boidIndex = instanceIndex / (uniforms.trailLength - 1u);
    let segmentIndex = instanceIndex % (uniforms.trailLength - 1u);
    
    if (boidIndex >= uniforms.boidCount) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    // Get per-species trail length
    let speciesId = speciesIds[boidIndex];
    let speciesTrailLen = u32(getSpeciesTrailLength(speciesId));
    
    // If this segment is beyond this species' trail length, skip it
    if (segmentIndex >= speciesTrailLen - 1u) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    // Calculate trail indices (ring buffer)
    // Use MAX_TRAIL_LENGTH for buffer stride since that's the actual buffer size
    let trailBase = boidIndex * MAX_TRAIL_LENGTH;
    let head = uniforms.trailHead;
    
    // segmentIndex 0 is the oldest segment, speciesTrailLen-2 is the newest
    // We render from old to new
    let age = speciesTrailLen - 2u - segmentIndex;
    
    // Get the two endpoints of this segment
    // Use MAX_TRAIL_LENGTH for modulo since head wraps at MAX_TRAIL_LENGTH
    let idx1 = (head + MAX_TRAIL_LENGTH - age - 1u) % MAX_TRAIL_LENGTH;
    let idx2 = (head + MAX_TRAIL_LENGTH - age) % MAX_TRAIL_LENGTH;
    
    var p1 = trails[trailBase + idx1];
    var p2 = trails[trailBase + idx2];
    
    // For the newest segment (age == 0), connect to the current boid's base position
    // The boid triangle has vertices at (1.0, 0.0), (-0.7, ±0.5) in local space
    // The base center is at (-0.7, 0), which is 0.7 * scale behind the boid center
    if (age == 0u) {
        let currentPos = positions[boidIndex];
        let vel = velocities[boidIndex];
        let speed = length(vel);
        if (speed > 0.001) {
            let dir = vel / speed;
            // Offset exactly to the triangle's base: 0.7 * boidSize * 6.0
            let boidSize = speciesParams[speciesId * 4u + 2u].z;  // vec4[2].z = size
            let baseOffset = 0.7 * boidSize * 6.0;
            p2 = currentPos - dir * baseOffset;
        } else {
            p2 = currentPos;
        }
    }
    
    // Skip if points are at origin (uninitialized)
    if ((p1.x == 0.0 && p1.y == 0.0) || (p2.x == 0.0 && p2.y == 0.0)) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    // Handle boundary wrapping - clamp p2 to edge if segment crosses boundary
    if (isWrapped(p1, p2)) {
        p2 = handleWrap(p1, p2);
        // If still wrapped after handling (shouldn't happen), skip
        if (isWrapped(p1, p2)) {
            output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            output.color = vec3<f32>(0.0);
            output.alpha = 0.0;
            return output;
        }
    }
    
    // Each segment is a quad (2 triangles, 6 vertices)
    // vertexIndex: 0-5 for the quad
    let quadVertex = vertexIndex % 6u;
    
    // Direction and perpendicular
    let dir = p2 - p1;
    let len = length(dir);
    
    if (len < 0.001) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    let normDir = dir / len;
    let perp1 = vec2<f32>(-normDir.y, normDir.x);
    
    // For the newest segment, use the current velocity direction for p2's perpendicular
    // This ensures the trail width aligns exactly with the triangle's base orientation
    var perp2 = perp1;
    if (age == 0u) {
        let vel = velocities[boidIndex];
        let speed = length(vel);
        if (speed > 0.001) {
            let velDir = vel / speed;
            perp2 = vec2<f32>(-velDir.y, velDir.x);
        }
    }
    
    // Width tapers from head (thick) to tail (thin)
    // Slightly narrower than triangle base to fit inside the dark edge shading
    let ageRatio = f32(age) / f32(speciesTrailLen - 1u);
    let speciesSize = speciesParams[speciesId * 4u + 2u].z;  // vec4[2].z = size
    let baseWidth = speciesSize * 2.4;  // Narrower to fit within triangle's bright center
    let width1 = baseWidth * (1.0 - ageRatio * 0.95);
    
    // For newest segment, width2 connects to triangle
    var width2: f32;
    if (age == 0u) {
        width2 = baseWidth;
    } else {
        width2 = baseWidth * (1.0 - (ageRatio + 1.0 / f32(speciesTrailLen - 1u)) * 0.9);
    }
    
    // Build quad vertices - use perp1 for p1 end, perp2 for p2 end
    var worldPos: vec2<f32>;
    var alpha: f32;
    
    // Alpha at p2 should be 1.0 for newest segment to match boid opacity
    let alpha1 = 1.0 - ageRatio;
    var alpha2: f32;
    if (age == 0u) {
        alpha2 = 1.0; // Exact match with boid
    } else {
        alpha2 = 1.0 - ageRatio - 1.0 / f32(speciesTrailLen - 1u);
    }
    
    switch (quadVertex) {
        case 0u: { worldPos = p1 + perp1 * width1; alpha = alpha1; }
        case 1u: { worldPos = p1 - perp1 * width1; alpha = alpha1; }
        case 2u: { worldPos = p2 + perp2 * width2; alpha = alpha2; }
        case 3u: { worldPos = p2 + perp2 * width2; alpha = alpha2; }
        case 4u: { worldPos = p1 - perp1 * width1; alpha = alpha1; }
        case 5u: { worldPos = p2 - perp2 * width2; alpha = alpha2; }
        default: { worldPos = p1; alpha = 0.0; }
    }
    
    // Convert to clip space
    let clipX = (worldPos.x / uniforms.canvasWidth) * 2.0 - 1.0;
    let clipY = 1.0 - (worldPos.y / uniforms.canvasHeight) * 2.0;
    
    output.position = vec4<f32>(clipX, clipY, 0.0, 1.0);
    
    // Color based on current velocity of the boid
    let vel = velocities[boidIndex];
    let pos = positions[boidIndex];
    let speed = length(vel);
    let angle = atan2(vel.y, vel.x);
    
    var colorValue: f32;
    switch (uniforms.colorMode) {
        case COLOR_SPEED: { 
            colorValue = speed / uniforms.maxSpeed; 
        }
        case COLOR_ORIENTATION: { 
            colorValue = (angle + 3.14159265) / (2.0 * 3.14159265); 
        }
        case COLOR_NEIGHBORS: {
            // Fast density estimation using spatial hash
            // Creates smooth color variation based on local position clustering
            let cellX = floor(pos.x / uniforms.perception);
            let cellY = floor(pos.y / uniforms.perception);
            let cellHash = fract(sin(cellX * 12.9898 + cellY * 78.233) * 43758.5453);
            // Combine with velocity for more variation
            let velFactor = length(vel) / uniforms.maxSpeed;
            colorValue = fract(cellHash + velFactor * 0.3);
        }
        case COLOR_ACCELERATION: {
            // Use velocity magnitude relative to max as proxy for acceleration state
            let speedRatio = speed / uniforms.maxSpeed;
            // Boids moving fast are likely accelerating or maintaining, slow ones decelerating
            colorValue = speedRatio;
        }
        case COLOR_TURNING: {
            // Create distinct color bands based on heading angle
            // As boids turn, they smoothly transition between color bands
            let angleNorm = (angle + 3.14159265) / (2.0 * 3.14159265);
            colorValue = fract(angleNorm * 3.0); // 3 color cycles per full rotation
        }
        case COLOR_NONE: {
            // Solid color - use middle of spectrum
            colorValue = 0.5;
        }
        case COLOR_DENSITY: {
            // POSITION MODE - Ultra fast, just read pre-computed birth color
            colorValue = birthColors[boidIndex];
        }
        case COLOR_SPECIES: {
            // Use species hue
            let speciesId = speciesIds[boidIndex];
            colorValue = getSpeciesHue(speciesId);
        }
        default: { 
            colorValue = 0.5; 
        }
    }
    
    // Get the base color from spectrum
    var baseColor: vec3<f32>;
    if (uniforms.colorMode == COLOR_NONE) {
        baseColor = getColorFromSpectrum(0.5, uniforms.colorSpectrum);
    } else if (uniforms.colorMode == COLOR_SPECIES) {
        // For Species mode, use full HSL with species saturation and lightness
        let speciesId = speciesIds[boidIndex];
        let sat = getSpeciesSaturation(speciesId);
        let light = getSpeciesLightness(speciesId);
        baseColor = hslToRgb(colorValue, sat, light);
    } else {
        colorValue = pow(colorValue, 1.0 / uniforms.sensitivity);
        baseColor = getColorFromSpectrum(colorValue, uniforms.colorSpectrum);
    }
    
    // Fade to dark AND transparent as trail ages
    // Head: bright & opaque, Tail: darker & semi-transparent
    // Use linear fade for color (less aggressive than squared)
    let fadeFactor = 0.3 + alpha * 0.7;  // Range: 0.3 to 1.0 (not too dark at tail)
    output.color = baseColor * fadeFactor;
    // Alpha fades with age for smooth trail effect
    output.alpha = 0.6 + alpha * 0.4;  // Range: 0.6 to 1.0
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color, input.alpha);
}
