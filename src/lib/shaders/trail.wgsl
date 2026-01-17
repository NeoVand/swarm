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
    cursorForce: f32,
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
}

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_COOL: u32 = 1u;
const SPECTRUM_WARM: u32 = 2u;
const SPECTRUM_RAINBOW: u32 = 3u;
const SPECTRUM_MONO: u32 = 4u;

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
        case SPECTRUM_COOL: {
            return mix(
                mix(vec3<f32>(0.1, 0.1, 0.5), vec3<f32>(0.1, 0.4, 0.6), tt * 2.0),
                mix(vec3<f32>(0.1, 0.4, 0.6), vec3<f32>(0.4, 0.9, 0.9), (tt - 0.5) * 2.0),
                step(0.5, tt)
            );
        }
        case SPECTRUM_WARM: {
            if (tt < 0.5) {
                return mix(vec3<f32>(0.6, 0.1, 0.1), vec3<f32>(0.95, 0.4, 0.1), tt * 2.0);
            } else {
                return mix(vec3<f32>(0.95, 0.4, 0.1), vec3<f32>(1.0, 0.9, 0.3), (tt - 0.5) * 2.0);
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
    let trailBase = boidIndex * uniforms.trailLength;
    let head = uniforms.trailHead;
    
    // segmentIndex 0 is the oldest segment, trailLength-2 is the newest
    // We render from old to new
    let age = uniforms.trailLength - 2u - segmentIndex;
    
    // Get the two endpoints of this segment
    let idx1 = (head + uniforms.trailLength - age - 1u) % uniforms.trailLength;
    let idx2 = (head + uniforms.trailLength - age) % uniforms.trailLength;
    
    let p1 = trails[trailBase + idx1];
    let p2 = trails[trailBase + idx2];
    
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
    let perp = vec2<f32>(-normDir.y, normDir.x);
    
    // Width tapers from head (thick) to tail (thin)
    // Match boid width: boid uses size * 6.0 with 0.5 half-width = 3.0 * boidSize
    let ageRatio = f32(age) / f32(uniforms.trailLength - 1u);
    let baseWidth = uniforms.boidSize * 3.0;
    let width1 = baseWidth * (1.0 - ageRatio);
    let width2 = baseWidth * (1.0 - (ageRatio + 1.0 / f32(uniforms.trailLength - 1u)));
    
    // Build quad vertices
    var worldPos: vec2<f32>;
    var alpha: f32;
    
    switch (quadVertex) {
        case 0u: { worldPos = p1 + perp * width1; alpha = 1.0 - ageRatio; }
        case 1u: { worldPos = p1 - perp * width1; alpha = 1.0 - ageRatio; }
        case 2u: { worldPos = p2 + perp * width2; alpha = 1.0 - ageRatio - 1.0 / f32(uniforms.trailLength - 1u); }
        case 3u: { worldPos = p2 + perp * width2; alpha = 1.0 - ageRatio - 1.0 / f32(uniforms.trailLength - 1u); }
        case 4u: { worldPos = p1 - perp * width1; alpha = 1.0 - ageRatio; }
        case 5u: { worldPos = p2 - perp * width2; alpha = 1.0 - ageRatio - 1.0 / f32(uniforms.trailLength - 1u); }
        default: { worldPos = p1; alpha = 0.0; }
    }
    
    // Convert to clip space
    let clipX = (worldPos.x / uniforms.canvasWidth) * 2.0 - 1.0;
    let clipY = 1.0 - (worldPos.y / uniforms.canvasHeight) * 2.0;
    
    output.position = vec4<f32>(clipX, clipY, 0.0, 1.0);
    
    // Color based on current velocity of the boid
    let vel = velocities[boidIndex];
    let speed = length(vel);
    let angle = atan2(vel.y, vel.x);
    
    var colorValue: f32;
    switch (uniforms.colorMode) {
        case 0u: { colorValue = speed / uniforms.maxSpeed; }
        case 1u: { colorValue = (angle + 3.14159265) / (2.0 * 3.14159265); }
        default: { colorValue = 0.5; }
    }
    
    colorValue = pow(colorValue, 1.0 / uniforms.sensitivity);
    output.color = getColorFromSpectrum(colorValue, uniforms.colorSpectrum);
    output.alpha = alpha * 0.6; // Trails are semi-transparent
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color * input.alpha, input.alpha);
}
