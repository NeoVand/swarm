// Wall rendering shader - renders user-drawn obstacles as semi-transparent overlay

struct Uniforms {
    canvasWidth: f32,
    canvasHeight: f32,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var wallTexture: texture_2d<f32>;
@group(0) @binding(2) var wallSampler: sampler;

// Full-screen quad vertices (two triangles)
const QUAD_POSITIONS = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0),  // Bottom-left
    vec2<f32>(1.0, -1.0),   // Bottom-right
    vec2<f32>(-1.0, 1.0),   // Top-left
    vec2<f32>(-1.0, 1.0),   // Top-left
    vec2<f32>(1.0, -1.0),   // Bottom-right
    vec2<f32>(1.0, 1.0)     // Top-right
);

const QUAD_UVS = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 1.0),    // Bottom-left
    vec2<f32>(1.0, 1.0),    // Bottom-right
    vec2<f32>(0.0, 0.0),    // Top-left
    vec2<f32>(0.0, 0.0),    // Top-left
    vec2<f32>(1.0, 1.0),    // Bottom-right
    vec2<f32>(1.0, 0.0)     // Top-right
);

@vertex
fn vs_main(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    var output: VertexOutput;
    output.position = vec4<f32>(QUAD_POSITIONS[vertexIndex], 0.0, 1.0);
    output.uv = QUAD_UVS[vertexIndex];
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Sample wall texture
    let wallValue = textureSample(wallTexture, wallSampler, input.uv).r;
    
    // No wall - fully transparent
    if (wallValue < 0.01) {
        discard;
    }
    
    // Calculate pixel size in UV space for edge detection
    let texSize = vec2<f32>(textureDimensions(wallTexture, 0));
    let pixelSize = 1.0 / texSize;
    
    // Sample neighbors to detect inner edge
    // We sample in 8 directions to get a good edge estimate
    let sampleDist = pixelSize * 1.5; // Slightly larger for smoother edge
    
    let n  = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(0.0, -sampleDist.y)).r;
    let s  = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(0.0, sampleDist.y)).r;
    let e  = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(sampleDist.x, 0.0)).r;
    let w  = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(-sampleDist.x, 0.0)).r;
    let ne = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(sampleDist.x, -sampleDist.y)).r;
    let nw = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(-sampleDist.x, -sampleDist.y)).r;
    let se = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(sampleDist.x, sampleDist.y)).r;
    let sw = textureSample(wallTexture, wallSampler, input.uv + vec2<f32>(-sampleDist.x, sampleDist.y)).r;
    
    // Calculate how much this pixel is on the edge (inner edge detection)
    // If any neighbor has less wall than us, we're near an edge
    let minNeighbor = min(min(min(n, s), min(e, w)), min(min(ne, nw), min(se, sw)));
    let edgeFactor = clamp((wallValue - minNeighbor) * 3.0, 0.0, 1.0);
    
    // Wall colors
    // Base fill color: #282d37 (40, 45, 55) - dark gray
    let baseColor = vec3<f32>(0.157, 0.176, 0.216);
    // Inner stroke color: #4a5568 (74, 85, 104) - lighter gray-blue
    let strokeColor = vec3<f32>(0.29, 0.333, 0.408);
    
    // Add subtle noise for texture
    let noiseX = fract(sin(input.uv.x * 100.0 + input.uv.y * 50.0) * 43758.5453);
    let noiseY = fract(sin(input.uv.y * 100.0 + input.uv.x * 50.0) * 43758.5453);
    let noise = (noiseX + noiseY) * 0.5;
    
    // Mix base color with stroke color based on edge factor
    var color = mix(baseColor, strokeColor, edgeFactor * 0.8);
    
    // Add slight noise variation
    color = color + vec3<f32>(noise * 0.015 - 0.0075);
    
    // Alpha based on wall density with smooth edges
    // Edge areas are slightly more opaque for visibility
    let baseAlpha = smoothstep(0.0, 0.3, wallValue) * 0.7;
    let alpha = baseAlpha + edgeFactor * 0.15;
    
    return vec4<f32>(color, alpha);
}
