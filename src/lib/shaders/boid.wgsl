// Boid rendering shader - instanced triangles

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
const COLOR_LOCAL_DENSITY: u32 = 8u;
const COLOR_ANISOTROPY: u32 = 9u;

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_OCEAN: u32 = 1u;
const SPECTRUM_BANDS: u32 = 2u;
const SPECTRUM_RAINBOW: u32 = 3u;
const SPECTRUM_MONO: u32 = 4u;

// Boundary modes for wrapping detection
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

// Species constants
const MAX_SPECIES: u32 = 7u;

// Head shapes enum (proper polygons rendered as triangle fans)
const SHAPE_TRIANGLE: u32 = 0u;
const SHAPE_SQUARE: u32 = 1u;
const SHAPE_PENTAGON: u32 = 2u;
const SHAPE_HEXAGON: u32 = 3u;
const SHAPE_ARROW: u32 = 4u;

// Max triangles per shape (hexagon needs 6)
const MAX_SHAPE_TRIANGLES: u32 = 6u;

// Alpha modes for per-species transparency
const ALPHA_SOLID: u32 = 0u;
const ALPHA_DIRECTION: u32 = 1u;
const ALPHA_SPEED: u32 = 2u;
const ALPHA_TURNING: u32 = 3u;
const ALPHA_ACCELERATION: u32 = 4u;
const ALPHA_DENSITY: u32 = 5u;
const ALPHA_ANISOTROPY: u32 = 6u;

// Get species parameter by index (0-19)
// vec4[0]: [alignment, cohesion, separation, perception]
// vec4[1]: [maxSpeed, maxForce, hue, headShape]
// vec4[2]: [saturation, lightness, size, trailLength]
// vec4[3]: [rebels, cursorForce, cursorResponse, cursorVortexDir] (-1=CCW, 0=off, 1=CW)
// vec4[4]: [alphaMode, unused, unused, unused]
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

fn getSpeciesAlphaMode(speciesId: u32) -> u32 {
    return u32(speciesParams[speciesId * 5u + 4u].x);  // vec4[4].x = alphaMode
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
            // Blue to cyan to white to orange to red
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
            // Full rainbow
            return hsv2rgb(vec3<f32>(tt, 0.85, 0.9));
        }
        case SPECTRUM_MONO: {
            // White with varying brightness
            let brightness = 0.4 + tt * 0.6;
            return vec3<f32>(brightness, brightness * 0.95, brightness * 0.9);
        }
        default: {
            return vec3<f32>(1.0);
        }
    }
}

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
            // Use species hue directly
            colorValue = getSpeciesHue(speciesId);
        }
        case COLOR_LOCAL_DENSITY: {
            // Computed same-species neighbor density
            let m = metrics[boidIndex];
            // Log scale for better visual distribution
            colorValue = clamp(log(1.0 + m.x * 0.5) / 3.0, 0.0, 1.0);
        }
        case COLOR_ANISOTROPY: {
            // Computed local structure - edges/filaments vs blobs
            let m = metrics[boidIndex];
            colorValue = m.y;  // Already in [0,1]
        }
        default: {
            colorValue = 0.5;
        }
    }
    
    // For "None" mode, skip sensitivity adjustment to keep it uniform
    if (uniforms.colorMode == COLOR_NONE) {
        output.color = getColorFromSpectrum(0.5, uniforms.colorSpectrum);
        output.alpha = 1.0;
    } else if (uniforms.colorMode == COLOR_SPECIES) {
        // For Species mode, use full HSL with species hue, saturation, and lightness
        let hue = colorValue;  // Already normalized 0-1
        let sat = getSpeciesSaturation(speciesId);
        let light = getSpeciesLightness(speciesId);
        output.color = hslToRgb(hue, sat, light);
        
        // Calculate alpha based on per-species alpha mode
        let alphaMode = getSpeciesAlphaMode(speciesId);
        var alpha = 1.0;
        switch (alphaMode) {
            case ALPHA_SOLID: {
                alpha = 1.0;
            }
            case ALPHA_DIRECTION: {
                // Alpha based on direction - boids facing right are more visible
                let dirAlpha = (angle + 3.14159265) / (2.0 * 3.14159265);
                alpha = 0.3 + dirAlpha * 0.7;
            }
            case ALPHA_SPEED: {
                // Alpha based on speed - faster boids are more visible
                let speedAlpha = clamp(speed / uniforms.maxSpeed, 0.0, 1.0);
                alpha = 0.3 + speedAlpha * 0.7;
            }
            case ALPHA_TURNING: {
                // Alpha based on angle sectors - creates banding effect
                let angleNorm = (angle + 3.14159265) / (2.0 * 3.14159265);
                let turnAlpha = abs(sin(angleNorm * 6.28318530)); // Oscillating alpha
                alpha = 0.3 + turnAlpha * 0.7;
            }
            case ALPHA_ACCELERATION: {
                // Alpha based on speed ratio (proxy for acceleration state)
                let accAlpha = clamp(speed / uniforms.maxSpeed, 0.0, 1.0);
                // Invert so slower/accelerating boids are more visible
                alpha = 0.3 + (1.0 - accAlpha) * 0.7;
            }
            case ALPHA_DENSITY: {
                // Alpha based on local same-species density - higher density = more visible
                let m = metrics[boidIndex];
                let normalizedDensity = clamp(log(1.0 + m.x * 0.5) / 3.0, 0.0, 1.0);
                alpha = 0.3 + normalizedDensity * 0.7;
            }
            case ALPHA_ANISOTROPY: {
                // Alpha based on local structure - edges/filaments more visible than blobs
                let m = metrics[boidIndex];
                alpha = 0.3 + m.y * 0.7;  // aniso is already [0,1]
            }
            default: {
                alpha = 1.0;
            }
        }
        output.alpha = alpha;
    } else {
        colorValue = pow(colorValue, 1.0 / uniforms.sensitivity);
        output.color = getColorFromSpectrum(colorValue, uniforms.colorSpectrum);
        output.alpha = 1.0;
    }
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Solid fill - clean shapes without internal edge lines
    return vec4<f32>(input.color, input.alpha);
}
