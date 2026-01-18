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

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_NEON: u32 = 1u;
const SPECTRUM_SUNSET: u32 = 2u;
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
        case SPECTRUM_NEON: {
            // Electric cyan to hot pink to purple (synthwave)
            if (tt < 0.5) {
                return mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 0.78), tt * 2.0);
            } else {
                return mix(vec3<f32>(1.0, 0.0, 0.78), vec3<f32>(0.47, 0.0, 1.0), (tt - 0.5) * 2.0);
            }
        }
        case SPECTRUM_SUNSET: {
            // Magenta to orange to gold (dramatic sunset)
            if (tt < 0.5) {
                return mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(1.0, 0.4, 0.0), tt * 2.0);
            } else {
                return mix(vec3<f32>(1.0, 0.4, 0.0), vec3<f32>(1.0, 0.86, 0.0), (tt - 0.5) * 2.0);
            }
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

// Check if two positions are too far apart (boundary wrap detection)
fn isWrapped(p1: vec2<f32>, p2: vec2<f32>) -> bool {
    let dx = abs(p1.x - p2.x);
    let dy = abs(p1.y - p2.y);
    return dx > uniforms.canvasWidth * 0.5 || dy > uniforms.canvasHeight * 0.5;
}

@vertex
fn vs_main(
    @builtin(vertex_index) vertexIndex: u32,
    @builtin(instance_index) instanceIndex: u32
) -> VertexOutput {
    var output: VertexOutput;
    
    // Each instance is one trail segment (line between two consecutive trail points)
    // instanceIndex = boidIndex * (trailLength - 1) + segmentIndex
    let boidIndex = instanceIndex / (uniforms.trailLength - 1u);
    let segmentIndex = instanceIndex % (uniforms.trailLength - 1u);
    
    if (boidIndex >= uniforms.boidCount) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    // Calculate trail indices (ring buffer)
    // Use MAX_TRAIL_LENGTH for buffer stride so changing trailLength doesn't shift data
    let trailBase = boidIndex * MAX_TRAIL_LENGTH;
    let head = uniforms.trailHead;
    
    // segmentIndex 0 is the oldest segment, trailLength-2 is the newest
    // We render from old to new
    let age = uniforms.trailLength - 2u - segmentIndex;
    
    // Get the two endpoints of this segment
    let idx1 = (head + uniforms.trailLength - age - 1u) % uniforms.trailLength;
    let idx2 = (head + uniforms.trailLength - age) % uniforms.trailLength;
    
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
            let baseOffset = 0.7 * uniforms.boidSize * 6.0;
            p2 = currentPos - dir * baseOffset;
        } else {
            p2 = currentPos;
        }
    }
    
    // Skip if points are at origin (uninitialized) or wrapped across boundary
    if ((p1.x == 0.0 && p1.y == 0.0) || (p2.x == 0.0 && p2.y == 0.0) || isWrapped(p1, p2)) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
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
    // Match boid triangle base: vertices at (-0.7, ±0.5), scaled by boidSize * 6.0
    // Half-width at base = 0.5 * boidSize * 6.0 = 3.0 * boidSize
    let ageRatio = f32(age) / f32(uniforms.trailLength - 1u);
    let baseWidth = uniforms.boidSize * 3.0; // Exact match with triangle base half-width
    let width1 = baseWidth * (1.0 - ageRatio * 0.95); // Don't fully taper to zero
    
    // For newest segment, width2 should be slightly smaller than triangle base
    var width2: f32;
    if (age == 0u) {
        width2 = baseWidth;
    } else {
        width2 = baseWidth * (1.0 - (ageRatio + 1.0 / f32(uniforms.trailLength - 1u)) * 0.95);
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
        alpha2 = 1.0 - ageRatio - 1.0 / f32(uniforms.trailLength - 1u);
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
            // Local density estimation using spatial hash cell occupancy
            let cellSize = uniforms.perception;
            let cellX = floor(pos.x / cellSize);
            let cellY = floor(pos.y / cellSize);
            
            // Hash function to estimate local density pattern
            var densitySum = 0.0;
            for (var dy = -1; dy <= 1; dy++) {
                for (var dx = -1; dx <= 1; dx++) {
                    let cx = cellX + f32(dx);
                    let cy = cellY + f32(dy);
                    let h = fract(sin(cx * 127.1 + cy * 311.7) * 43758.5453);
                    densitySum += h;
                }
            }
            let baseDensity = densitySum / 9.0;
            let posMod = fract(pos.x * 0.01 + pos.y * 0.01);
            colorValue = baseDensity * 0.7 + posMod * 0.3;
        }
        default: { 
            colorValue = 0.5; 
        }
    }
    
    // Get the base color from spectrum
    var baseColor: vec3<f32>;
    if (uniforms.colorMode == COLOR_NONE) {
        baseColor = getColorFromSpectrum(0.5, uniforms.colorSpectrum);
    } else {
        colorValue = pow(colorValue, 1.0 / uniforms.sensitivity);
        baseColor = getColorFromSpectrum(colorValue, uniforms.colorSpectrum);
    }
    
    // Aggressive fade to dark - squared for faster dropoff
    // Head (alpha=1): full brightness, Tail (alpha→0): much darker
    let fadeFactor = alpha * alpha;  // Squared for aggressive fade
    output.color = baseColor * fadeFactor;
    output.alpha = 1.0;
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Non-premultiplied output for additive blending
    // Trails glow brighter where they overlap
    return vec4<f32>(input.color, input.alpha);
}
