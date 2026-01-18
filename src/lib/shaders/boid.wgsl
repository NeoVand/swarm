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

// Color modes
const COLOR_SPEED: u32 = 0u;
const COLOR_ORIENTATION: u32 = 1u;
const COLOR_NEIGHBORS: u32 = 2u;
const COLOR_ACCELERATION: u32 = 3u;
const COLOR_TURNING: u32 = 4u;

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_NEON: u32 = 1u;
const SPECTRUM_SUNSET: u32 = 2u;
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

// Triangle vertices for boid shape (pointing right)
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
    
    if (instanceIndex >= uniforms.boidCount) {
        output.position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        output.color = vec3<f32>(0.0);
        output.alpha = 0.0;
        return output;
    }
    
    let pos = positions[instanceIndex];
    let vel = velocities[instanceIndex];
    
    // Get local vertex
    let localVert = BOID_VERTICES[vertexIndex % 3u];
    
    // Scale by boid size
    let size = uniforms.boidSize * 6.0;
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
    
    // Translate to world position
    let worldPos = pos + rotatedVert;
    
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
            // This would need neighbor count passed in, approximate with position hash
            colorValue = fract(sin(dot(pos, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        }
        case COLOR_ACCELERATION: {
            // Approximate with velocity magnitude variation
            colorValue = fract(speed * 0.5);
        }
        case COLOR_TURNING: {
            // Use angular velocity approximation
            let angularChange = abs(sin(angle * 3.0 + uniforms.time));
            colorValue = angularChange;
        }
        default: {
            colorValue = 0.5;
        }
    }
    
    colorValue = pow(colorValue, 1.0 / uniforms.sensitivity);
    output.color = getColorFromSpectrum(colorValue, uniforms.colorSpectrum);
    output.alpha = 1.0;
    
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color, input.alpha);
}
