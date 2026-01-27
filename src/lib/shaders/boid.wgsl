// Boid rendering shader - instanced triangles
// Note: This shader requires common.wgsl and color.wgsl to be prepended at load time

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
    @location(1) alpha: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> velocities: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> birthColors: array<f32>;
@group(0) @binding(4) var<storage, read> speciesIds: array<u32>;
@group(0) @binding(5) var<uniform> speciesParams: array<vec4<f32>, 35>;  // 7 species * 5 vec4s per species
@group(0) @binding(6) var<storage, read> metrics: array<vec4<f32>>;  // per-boid metrics [density, anisotropy, 0, 0]
@group(0) @binding(7) var<storage, read> curveSamples: array<f32>;  // 3 curves × 64 samples

// Linear interpolation lookup into curve samples buffer (shader-specific, uses curveSamples binding)
fn lookupCurve(curveId: u32, t: f32) -> f32 {
    let base = curveId * 64u;
    let pos = clamp(t, 0.0, 1.0) * 63.0;
    let idx0 = u32(floor(pos));
    let idx1 = min(idx0 + 1u, 63u);
    let frac = pos - f32(idx0);
    return mix(curveSamples[base + idx0], curveSamples[base + idx1], frac);
}

// Head shapes enum (proper polygons rendered as triangle fans)
const SHAPE_TRIANGLE: u32 = 0u;
const SHAPE_SQUARE: u32 = 1u;
const SHAPE_PENTAGON: u32 = 2u;
const SHAPE_HEXAGON: u32 = 3u;
const SHAPE_ARROW: u32 = 4u;

// Max triangles per shape (hexagon needs 6)
const MAX_SHAPE_TRIANGLES: u32 = 6u;

// Get species parameter by index (0-15)
// vec4[0]: [alignment, cohesion, separation, perception]
// vec4[1]: [maxSpeed, maxForce, hue, headShape]
// vec4[2]: [saturation, lightness, size, trailLength]
// vec4[3]: [rebels, cursorForce, cursorResponse, cursorVortexDir] (-1=CCW, 0=off, 1=CW)
// vec4[4]: [unused, unused, unused, unused]
fn getSpeciesParam(speciesId: u32, paramIdx: u32) -> f32 {
    let vec4Idx = speciesId * 5u + paramIdx / 4u;
    let componentIdx = paramIdx % 4u;
    let v = speciesParams[vec4Idx];
    switch (componentIdx) {
        case 0u: { return v.x; }
        case 1u: { return v.y; }
        case 2u: { return v.z; }
        default: { return v.w; }
    }
}

// Convenience functions for common species params
fn getSpeciesHue(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 1u].z;  // vec4[1].z = hue
}

fn getSpeciesHeadShape(speciesId: u32) -> u32 {
    return u32(speciesParams[speciesId * 5u + 1u].w);  // vec4[1].w = headShape
}

fn getSpeciesSaturation(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].x;  // vec4[2].x = saturation
}

fn getSpeciesLightness(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].y;  // vec4[2].y = lightness
}

fn getSpeciesSize(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].z;  // vec4[2].z = size
}

fn getSpeciesTrailLength(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 2u].w;  // vec4[2].w = trailLength
}

fn getSpeciesRebels(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 3u].x;  // vec4[3].x = rebels
}

fn getSpeciesCursorForce(speciesId: u32) -> f32 {
    return speciesParams[speciesId * 5u + 3u].y;  // vec4[3].y = cursorForce
}

fn getSpeciesCursorResponse(speciesId: u32) -> u32 {
    return u32(speciesParams[speciesId * 5u + 3u].z);  // vec4[3].z = cursorResponse
}

// Generate vertex position for different shapes
// Uses 18 vertices (6 triangles from center for complex shapes)
fn getShapeVertex(shape: u32, vertexIndex: u32) -> vec2<f32> {
    let triIdx = vertexIndex / 3u;  // Which triangle (0-5)
    let vertIdx = vertexIndex % 3u; // Which vertex in triangle (0-2)
    
    switch (shape) {
        case SHAPE_TRIANGLE: {
            // Original triangle pointing right - KEEP THIS EXACT SHAPE
            // Only uses first 3 vertices, rest are degenerate
            if (triIdx > 0u) {
                return vec2<f32>(0.0, 0.0);
            }
            switch (vertIdx) {
                case 0u: { return vec2<f32>(1.0, 0.0); }      // Nose (front)
                case 1u: { return vec2<f32>(-0.7, -0.5); }    // Right wing (back)
                default: { return vec2<f32>(-0.7, 0.5); }     // Left wing (back)
            }
        }
        case SHAPE_SQUARE: {
            // Square using triangle fan from center - 4 triangles
            if (triIdx >= 4u) {
                return vec2<f32>(0.0, 0.0);
            }
            if (vertIdx == 0u) {
                return vec2<f32>(0.0, 0.0); // Center
            }
            // Square vertices rotated 45° so a corner points right
            let s = 0.7;
            let corners = array<vec2<f32>, 4>(
                vec2<f32>(s, 0.0),    // Right corner (front)
                vec2<f32>(0.0, -s),   // Bottom corner
                vec2<f32>(-s, 0.0),   // Left corner (back)
                vec2<f32>(0.0, s)     // Top corner
            );
            if (vertIdx == 1u) {
                return corners[triIdx];
            } else {
                return corners[(triIdx + 1u) % 4u];
            }
        }
        case SHAPE_PENTAGON: {
            // Pentagon using triangle fan from center - 5 triangles
            if (triIdx >= 5u) {
                return vec2<f32>(0.0, 0.0);
            }
            if (vertIdx == 0u) {
                return vec2<f32>(0.0, 0.0); // Center
            }
            let s = 0.7;
            let pi = 3.14159265;
            // Vertex 0 points right
            let baseAngle = f32(triIdx) * 2.0 * pi / 5.0;
            let nextAngle = f32((triIdx + 1u) % 5u) * 2.0 * pi / 5.0;
            if (vertIdx == 1u) {
                return vec2<f32>(cos(baseAngle), sin(baseAngle)) * s;
            } else {
                return vec2<f32>(cos(nextAngle), sin(nextAngle)) * s;
            }
        }
        case SHAPE_HEXAGON: {
            // Hexagon using triangle fan from center - 6 triangles
            if (triIdx >= 6u) {
                return vec2<f32>(0.0, 0.0);
            }
            if (vertIdx == 0u) {
                return vec2<f32>(0.0, 0.0); // Center
            }
            let s = 0.7;
            let pi = 3.14159265;
            // Vertex 0 points right
            let baseAngle = f32(triIdx) * 2.0 * pi / 6.0;
            let nextAngle = f32((triIdx + 1u) % 6u) * 2.0 * pi / 6.0;
            if (vertIdx == 1u) {
                return vec2<f32>(cos(baseAngle), sin(baseAngle)) * s;
            } else {
                return vec2<f32>(cos(nextAngle), sin(nextAngle)) * s;
            }
        }
        case SHAPE_ARROW: {
            // Arrow/chevron shape - 4 triangles from center
            if (triIdx >= 4u) {
                return vec2<f32>(0.0, 0.0);
            }
            if (vertIdx == 0u) {
                return vec2<f32>(0.0, 0.0); // Center
            }
            let corners = array<vec2<f32>, 4>(
                vec2<f32>(1.0, 0.0),       // Front tip
                vec2<f32>(-0.5, -0.6),     // Bottom-right
                vec2<f32>(-0.2, 0.0),      // Back notch
                vec2<f32>(-0.5, 0.6)       // Top-right
            );
            if (vertIdx == 1u) {
                return corners[triIdx];
            } else {
                return corners[(triIdx + 1u) % 4u];
            }
        }
        default: {
            // Default to triangle
            if (triIdx > 0u) {
                return vec2<f32>(0.0, 0.0);
            }
            switch (vertIdx) {
                case 0u: { return vec2<f32>(1.0, 0.0); }
                case 1u: { return vec2<f32>(-0.7, -0.5); }
                default: { return vec2<f32>(-0.7, 0.5); }
            }
        }
    }
}

// Triangle vertices for boid shape (pointing right) - kept for reference
const BOID_VERTICES = array<vec2<f32>, 3>(
    vec2<f32>(1.0, 0.0),      // Nose
    vec2<f32>(-0.7, 0.5),     // Left wing
    vec2<f32>(-0.7, -0.5)     // Right wing
);

@vertex
fn vs_main(
    @builtin(vertex_index) vertexIndex: u32,
    @builtin(instance_index) instanceIndex: u32
) -> VertexOutput {
    var output: VertexOutput;
    
    // Decode instance index: we render up to 4 copies of each boid for edge wrapping
    // ghostType: 0 = original, 1 = X-ghost, 2 = Y-ghost, 3 = XY-ghost (corner)
    let boidIndex = instanceIndex / 4u;
    let ghostType = instanceIndex % 4u;
    
    if (boidIndex >= uniforms.boidCount) {
        // Place off-screen (outside clip space)
        output.position = vec4<f32>(3.0, 3.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    let pos = positions[boidIndex];
    let vel = velocities[boidIndex];
    
    // Get species info
    let speciesId = speciesIds[boidIndex];
    let headShape = getSpeciesHeadShape(speciesId);
    
    // Get local vertex based on head shape
    let localVert = getShapeVertex(headShape, vertexIndex);
    
    // Scale by per-species boid size
    let speciesSize = getSpeciesSize(speciesId);
    let size = speciesSize * 6.0;
    var scaledVert = localVert * size;
    
    // Rotate to face velocity direction
    let speed = length(vel);
    var angle = 0.0;
    if (speed > 0.001) {
        angle = atan2(vel.y, vel.x);
    }
    
    let cosA = cos(angle);
    let sinA = sin(angle);
    let rotatedVert = vec2<f32>(
        scaledVert.x * cosA - scaledVert.y * sinA,
        scaledVert.x * sinA + scaledVert.y * cosA
    );
    
    // Calculate ghost offset based on ghostType
    // Ghosts are rendered on the opposite side of the canvas for wrapped edges
    var ghostOffset = vec2<f32>(0.0, 0.0);
    let edgeThreshold = size * 1.5;  // How close to edge before we render a ghost
    
    // Determine if this ghost copy should be rendered
    var shouldRender = true;
    
    if (ghostType == 1u) {
        // X-ghost: rendered when boid is near left or right edge on wrapped X
        if (wrapsX()) {
            if (pos.x < edgeThreshold) {
                // Near left edge - render ghost on right side
                ghostOffset.x = uniforms.canvasWidth;
            } else if (pos.x > uniforms.canvasWidth - edgeThreshold) {
                // Near right edge - render ghost on left side
                ghostOffset.x = -uniforms.canvasWidth;
            } else {
                shouldRender = false;
            }
        } else {
            shouldRender = false;
        }
    } else if (ghostType == 2u) {
        // Y-ghost: rendered when boid is near top or bottom edge on wrapped Y
        if (wrapsY()) {
            if (pos.y < edgeThreshold) {
                // Near top edge - render ghost on bottom side
                ghostOffset.y = uniforms.canvasHeight;
            } else if (pos.y > uniforms.canvasHeight - edgeThreshold) {
                // Near bottom edge - render ghost on top side
                ghostOffset.y = -uniforms.canvasHeight;
            } else {
                shouldRender = false;
            }
        } else {
            shouldRender = false;
        }
    } else if (ghostType == 3u) {
        // XY-ghost (corner): rendered when boid is near both X and Y edges
        if (wrapsX() && wrapsY()) {
            var needsXGhost = false;
            var needsYGhost = false;
            
            if (pos.x < edgeThreshold) {
                ghostOffset.x = uniforms.canvasWidth;
                needsXGhost = true;
            } else if (pos.x > uniforms.canvasWidth - edgeThreshold) {
                ghostOffset.x = -uniforms.canvasWidth;
                needsXGhost = true;
            }
            
            if (pos.y < edgeThreshold) {
                ghostOffset.y = uniforms.canvasHeight;
                needsYGhost = true;
            } else if (pos.y > uniforms.canvasHeight - edgeThreshold) {
                ghostOffset.y = -uniforms.canvasHeight;
                needsYGhost = true;
            }
            
            // Only render corner ghost if near BOTH edges
            shouldRender = needsXGhost && needsYGhost;
        } else {
            shouldRender = false;
        }
    }
    // ghostType == 0u is the original, always rendered
    
    if (!shouldRender) {
        // Don't render this ghost - move it off-screen (outside clip space)
        output.position = vec4<f32>(3.0, 3.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    // Translate to world position with ghost offset
    let worldPos = pos + rotatedVert + ghostOffset;
    
    // Convert to clip space (orthographic projection)
    let clipX = (worldPos.x / uniforms.canvasWidth) * 2.0 - 1.0;
    let clipY = 1.0 - (worldPos.y / uniforms.canvasHeight) * 2.0;
    
    output.position = vec4<f32>(clipX, clipY, 0.0, 1.0);
    
    // Calculate color based on mode
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
            colorValue = speedRatio;
        }
        case COLOR_TURNING: {
            // Create distinct color bands based on heading angle
            // As boids turn, they smoothly transition between color bands
            let angleNorm = (angle + 3.14159265) / (2.0 * 3.14159265);
            colorValue = fract(angleNorm * 2.0); // 2 color cycles per full rotation
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
            // Use species hue directly
            colorValue = getSpeciesHue(speciesId);
        }
        case COLOR_LOCAL_DENSITY: {
            // Raw neighbor density (sum of kernel weights)
            // Linear normalization - curve handles all non-linear mapping
            let m = metrics[boidIndex];
            let density = m.x;
            // Linear: 20 neighbors at full weight = 1.0 input to curve
            colorValue = clamp(density / 20.0, 0.0, 1.0);
        }
        case COLOR_ANISOTROPY: {
            // Structure - direct value, no contrast stretch (was making it worse)
            let m = metrics[boidIndex];
            colorValue = m.y;
        }
        case COLOR_INFLUENCE: {
            // All spectral modes read from metrics.w (computed by rank.wgsl based on spectralMode)
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
            // Stored in metrics.z by simulate.wgsl
            // Use 2 color cycles like the Heading mode for visual variety
            let m = metrics[boidIndex];
            colorValue = fract(m.z * 2.0);
        }
        default: {
            colorValue = 0.5;
        }
    }
    
    // === SATURATION CALCULATION ===
    var saturation = 1.0;  // Default full saturation
    if (uniforms.saturationSource == COLOR_NONE) {
        saturation = 1.0;
    } else if (uniforms.saturationSource == COLOR_SPECIES) {
        saturation = getSpeciesSaturation(speciesId);
    } else {
        // Map metric to saturation (0.2 to 1.0 range)
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
    var brightness = 0.5;  // Default middle brightness
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
    var hue = colorValue;
    if (uniforms.colorMode != COLOR_NONE && uniforms.colorMode != COLOR_SPECIES) {
        // Apply curve to transform color value to hue
        hue = lookupCurve(CURVE_HUE, colorValue);
    }
    
    if (uniforms.colorMode == COLOR_NONE) {
        output.color = hslToRgb(0.0, 0.0, brightness);  // Grayscale based on brightness
    } else if (uniforms.colorMode == COLOR_SPECIES) {
        // For Species mode, use species hue but dynamic saturation and brightness
        output.color = hslToRgb(hue, saturation, brightness);
    } else {
        // Get color from spectrum
        let baseColor = getColorFromSpectrum(hue, uniforms.colorSpectrum);
        
        // Apply saturation and brightness directly to spectrum color
        // Calculate luminance of base color
        let lum = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
        // Desaturate towards gray based on saturation
        let desaturated = mix(vec3<f32>(lum), baseColor, saturation);
        // Apply brightness (scale towards black or white)
        let brightnessAdjusted = desaturated * (brightness * 2.0);
        output.color = clamp(brightnessAdjusted, vec3<f32>(0.0), vec3<f32>(1.0));
    }
    
    // No alpha blending - fully opaque for better performance
    output.alpha = 1.0;
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Solid fill - clean shapes without internal edge lines
    return vec4<f32>(input.color, input.alpha);
}
