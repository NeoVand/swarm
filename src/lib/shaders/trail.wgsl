// Trail rendering shader - instanced line segments with fading
// Note: This shader requires common.wgsl and color.wgsl to be prepended at load time

// Get species color params from speciesParams buffer (5 vec4s per species)
fn getSpeciesHue(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 1u].z;  // vec4[1].z = hue (normalized 0-1)
}

fn getSpeciesSaturation(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].x;  // vec4[2].x = saturation
}

fn getSpeciesLightness(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].y;  // vec4[2].y = lightness
}

fn getSpeciesTrailLength(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].w;  // vec4[2].w = trailLength
}

fn getSpeciesHeadShape(speciesId: u32) -> u32 {
    return u32(speciesParams[speciesId * 5u + 1u].w);  // vec4[1].w = headShape
}

// Get the back offset multiplier for each head shape
// This is how far back from center the tail of each shape is
fn getShapeBackOffset(shape: u32) -> f32 {
    switch (shape) {
        case 0u: { return 0.7; }   // Triangle: back at -0.7
        case 1u: { return 0.7; }   // Square: back corner at -0.7
        case 2u: { return 0.57; }  // Pentagon: back vertices at ~-0.57
        case 3u: { return 0.7; }   // Hexagon: back vertex at -0.7
        case 4u: { return 0.5; }   // Arrow: back corners at -0.5
        default: { return 0.7; }
    }
}

// Get the back width multiplier for each head shape
// This is the half-width at the back of each shape for trail connection
fn getShapeBackWidth(shape: u32) -> f32 {
    switch (shape) {
        case 0u: { return 0.4; }   // Triangle: back width ±0.5, use 0.4 for slight inset
        case 1u: { return 0.35; }  // Square: narrow at corner
        case 2u: { return 0.35; }  // Pentagon: varies
        case 3u: { return 0.35; }  // Hexagon: narrow at vertex
        case 4u: { return 0.5; }   // Arrow: back width ±0.6, use 0.5 for slight inset
        default: { return 0.4; }
    }
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
    @location(1) alpha: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> velocities: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> trails: array<vec4<f32>>;  // (pos.x, pos.y, vel.x, vel.y) for gradient colors
@group(0) @binding(4) var<storage, read> birthColors: array<f32>;
@group(0) @binding(5) var<storage, read> speciesIds: array<u32>;
@group(0) @binding(6) var<uniform> speciesParams: array<vec4<f32>, 35>;  // 7 species * 5 vec4s
@group(0) @binding(7) var<storage, read> metrics: array<vec4<f32>>;  // per-boid metrics [density, anisotropy, 0, 0]
@group(0) @binding(8) var<storage, read> curveSamples: array<f32>;  // 3 curves × 64 samples

// Linear interpolation lookup into curve samples buffer (shader-specific, uses curveSamples binding)
fn lookupCurve(curveId: u32, t: f32) -> f32 {
    let base = curveId * 64u;
    let pos = clamp(t, 0.0, 1.0) * 63.0;
    let idx0 = u32(floor(pos));
    let idx1 = min(idx0 + 1u, 63u);
    let frac = pos - f32(idx0);
    return mix(curveSamples[base + idx0], curveSamples[base + idx1], frac);
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
    
    // Read trail data: vec4(pos.x, pos.y, vel.x, vel.y)
    let trail1 = trails[trailBase + idx1];
    let trail2 = trails[trailBase + idx2];
    var p1 = trail1.xy;
    var p2 = trail2.xy;
    
    // Historical velocity for this segment (used for gradient trail colors)
    var historicalVel: vec2<f32>;
    
    // For the newest segment (age == 0), connect to the current boid's base position
    // Different head shapes have different back positions, so we use shape-aware offsets
    if (age == 0u) {
        let currentPos = positions[boidIndex];
        let vel = velocities[boidIndex];
        let speed = length(vel);
        if (speed > 0.001) {
            let dir = vel / speed;
            // Get shape-aware offset to connect exactly at the shape's back
            let boidSize = speciesParams[speciesId * 5u + 2u].z;  // vec4[2].z = size
            let headShape = getSpeciesHeadShape(speciesId);
            let backOffset = getShapeBackOffset(headShape);
            let baseOffset = backOffset * boidSize * 6.0;
            p2 = currentPos - dir * baseOffset;
        } else {
            p2 = currentPos;
        }
        // For newest segment, use current velocity
        historicalVel = vel;
    } else {
        // For older segments, use stored historical velocity
        historicalVel = trail2.zw;
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
    // Use shape-aware width for connection point
    let ageRatio = f32(age) / f32(speciesTrailLen - 1u);
    let speciesSize = speciesParams[speciesId * 5u + 2u].z;  // vec4[2].z = size
    let headShape = getSpeciesHeadShape(speciesId);
    let shapeBackWidth = getShapeBackWidth(headShape);
    let baseWidth = speciesSize * 6.0 * shapeBackWidth;  // Match shape's back width
    let width1 = baseWidth * (1.0 - ageRatio * 0.95);
    
    // For newest segment, width2 connects to shape's back
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
    
    // Color based on historical velocity for gradient trail effect
    // historicalVel was computed earlier from trail buffer (or current vel for newest segment)
    let speed = length(historicalVel);
    let angle = atan2(historicalVel.y, historicalVel.x);
    let pos = positions[boidIndex];  // Position still needed for some color modes
    
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
            let velFactor = speed / uniforms.maxSpeed;
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
            colorValue = fract(angleNorm * 2.0); // 2 color cycles per full rotation (must match boid.wgsl)
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
        case COLOR_LOCAL_DENSITY: {
            // Raw neighbor density (sum of kernel weights)
            // Linear normalization - curve handles all non-linear mapping
            let m = metrics[boidIndex];
            let density = m.x;
            colorValue = clamp(density / 20.0, 0.0, 1.0);
        }
        case COLOR_ANISOTROPY: {
            // Structure - direct value
            let m = metrics[boidIndex];
            colorValue = m.y;
        }
        case COLOR_INFLUENCE: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_SPECTRAL_RADIAL: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_SPECTRAL_ASYMMETRY: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_FLOW_ANGULAR: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_FLOW_RADIAL: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_FLOW_DIVERGENCE: {
            let m = metrics[boidIndex];
            colorValue = fract(m.w);
        }
        case COLOR_TRUE_TURNING: {
            // True angular velocity - how fast the boid is actually turning
            // Use 2 color cycles like the Heading mode for visual variety
            let m = metrics[boidIndex];
            colorValue = fract(m.z * 2.0);
        }
        default: { 
            colorValue = 0.5; 
        }
    }
    
    // === SATURATION CALCULATION ===
    var saturation = 1.0;
    if (uniforms.saturationSource == COLOR_NONE) {
        saturation = 1.0;
    } else if (uniforms.saturationSource == COLOR_SPECIES) {
        saturation = getSpeciesSaturation(speciesId);
    } else {
        var satValue = 0.5;
        switch (uniforms.saturationSource) {
            case COLOR_SPEED: { satValue = clamp(speed / uniforms.maxSpeed, 0.0, 1.0); }
            case COLOR_ORIENTATION: { satValue = (angle + 3.14159265) / (2.0 * 3.14159265); }
            case COLOR_TURNING: {
                let angleNorm = (angle + 3.14159265) / (2.0 * 3.14159265);
                satValue = abs(sin(angleNorm * 6.28318530));
            }
            case COLOR_DENSITY: {
                let posX = positions[boidIndex].x / uniforms.canvasWidth - 0.5;
                let posY = positions[boidIndex].y / uniforms.canvasHeight - 0.5;
                satValue = clamp(sqrt(posX * posX + posY * posY) * 1.414, 0.0, 1.0);
            }
            case COLOR_LOCAL_DENSITY: {
                let m = metrics[boidIndex];
                satValue = clamp(m.x / 20.0, 0.0, 1.0);
            }
            case COLOR_ANISOTROPY: {
                let m = metrics[boidIndex];
                satValue = m.y;
            }
            case COLOR_INFLUENCE: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_SPECTRAL_RADIAL: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_SPECTRAL_ASYMMETRY: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_FLOW_ANGULAR: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_FLOW_RADIAL: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_FLOW_DIVERGENCE: {
                let m = metrics[boidIndex];
                satValue = fract(m.w);
            }
            case COLOR_TRUE_TURNING: {
                let m = metrics[boidIndex];
                satValue = m.z;
            }
            default: { satValue = 1.0; }
        }
        // Apply curve to transform saturation value
        saturation = lookupCurve(CURVE_SAT, satValue);
    }
    
    // === BRIGHTNESS CALCULATION ===
    var brightness = 0.5;
    if (uniforms.brightnessSource == COLOR_NONE) {
        brightness = 0.5;
    } else if (uniforms.brightnessSource == COLOR_SPECIES) {
        brightness = getSpeciesLightness(speciesId);
    } else {
        // Compute raw metric value (0-1 range)
        var brightValue = 0.5;
        switch (uniforms.brightnessSource) {
            case COLOR_SPEED: { brightValue = clamp(speed / uniforms.maxSpeed, 0.0, 1.0); }
            case COLOR_ORIENTATION: { brightValue = (angle + 3.14159265) / (2.0 * 3.14159265); }
            case COLOR_TURNING: {
                let angleNorm = (angle + 3.14159265) / (2.0 * 3.14159265);
                brightValue = abs(sin(angleNorm * 6.28318530));
            }
            case COLOR_DENSITY: {
                let posX = positions[boidIndex].x / uniforms.canvasWidth - 0.5;
                let posY = positions[boidIndex].y / uniforms.canvasHeight - 0.5;
                brightValue = clamp(sqrt(posX * posX + posY * posY) * 1.414, 0.0, 1.0);
            }
            case COLOR_LOCAL_DENSITY: {
                let m = metrics[boidIndex];
                brightValue = clamp(m.x / 20.0, 0.0, 1.0);
            }
            case COLOR_ANISOTROPY: {
                let m = metrics[boidIndex];
                brightValue = m.y;
            }
            case COLOR_INFLUENCE: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_SPECTRAL_RADIAL: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_SPECTRAL_ASYMMETRY: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_FLOW_ANGULAR: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_FLOW_RADIAL: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_FLOW_DIVERGENCE: {
                let m = metrics[boidIndex];
                brightValue = fract(m.w);
            }
            case COLOR_TRUE_TURNING: {
                let m = metrics[boidIndex];
                brightValue = m.z;
            }
            default: { brightValue = 0.5; }
        }
        // Apply curve to transform brightValue, then map to output range
        brightness = lookupCurve(CURVE_BRIGHT, brightValue);
    }
    
    // === COLOR CALCULATION (HSL with dynamic S and L) ===
    var baseColor: vec3<f32>;
    var hue = colorValue;
    if (uniforms.colorMode != COLOR_NONE && uniforms.colorMode != COLOR_SPECIES) {
        // Apply curve to transform color value to hue
        hue = lookupCurve(CURVE_HUE, colorValue);
    }
    
    if (uniforms.colorMode == COLOR_NONE) {
        baseColor = hslToRgb(0.0, 0.0, brightness);
    } else if (uniforms.colorMode == COLOR_SPECIES) {
        baseColor = hslToRgb(hue, saturation, brightness);
    } else {
        // Get color from spectrum
        let spectrumColor = getColorFromSpectrum(hue, uniforms.colorSpectrum);
        
        // Apply saturation and brightness directly to spectrum color
        // Calculate luminance of base color
        let lum = dot(spectrumColor, vec3<f32>(0.299, 0.587, 0.114));
        // Desaturate towards gray based on saturation
        let desaturated = mix(vec3<f32>(lum), spectrumColor, saturation);
        // Apply brightness (scale towards black or white)
        let brightnessAdjusted = desaturated * (brightness * 2.0);
        baseColor = clamp(brightnessAdjusted, vec3<f32>(0.0), vec3<f32>(1.0));
    }
    
    // Fade to dark as trail ages (no alpha blending for better performance)
    // Head: bright, Tail: darker
    let fadeFactor = 0.3 + alpha * 0.7;  // Range: 0.3 to 1.0 (not too dark at tail)
    output.color = baseColor * fadeFactor;
    // Fully opaque - no alpha blending
    output.alpha = 1.0;
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color, input.alpha);
}
