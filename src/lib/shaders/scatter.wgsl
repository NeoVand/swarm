// Pass 4: Scatter boids into sorted array by cell

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

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(2) var<storage, read_write> cellOffsets: array<atomic<u32>>;
@group(0) @binding(3) var<storage, read> boidCellIndices: array<u32>;
@group(0) @binding(4) var<storage, read_write> sortedIndices: array<u32>;

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let boidIndex = global_id.x;
    
    if (boidIndex >= uniforms.boidCount) {
        return;
    }
    
    let cellIndex = boidCellIndices[boidIndex];
    let cellStart = prefixSums[cellIndex];
    let localOffset = atomicAdd(&cellOffsets[cellIndex], 1u);
    
    sortedIndices[cellStart + localOffset] = boidIndex;
}
