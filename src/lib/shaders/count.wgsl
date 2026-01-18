// Pass 2: Count boids per cell and assign cell indices to boids

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
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read_write> cellCounts: array<atomic<u32>>;
@group(0) @binding(2) var<storage, read> positions: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read_write> boidCellIndices: array<u32>;

fn getCellIndex(pos: vec2<f32>) -> u32 {
    let cellX = clamp(u32(pos.x / uniforms.cellSize), 0u, uniforms.gridWidth - 1u);
    let cellY = clamp(u32(pos.y / uniforms.cellSize), 0u, uniforms.gridHeight - 1u);
    return cellY * uniforms.gridWidth + cellX;
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let boidIndex = global_id.x;
    
    if (boidIndex >= uniforms.boidCount) {
        return;
    }
    
    let pos = positions[boidIndex];
    let cellIndex = getCellIndex(pos);
    
    // Store which cell this boid belongs to
    boidCellIndices[boidIndex] = cellIndex;
    
    // Atomically increment the count for this cell
    atomicAdd(&cellCounts[cellIndex], 1u);
}
