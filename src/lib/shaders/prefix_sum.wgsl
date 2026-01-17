// Pass 3: Parallel prefix sum (exclusive scan) for cell start indices
// Uses Blelloch scan algorithm with workgroup shared memory

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

const WORKGROUP_SIZE: u32 = 256u;

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(2) var<storage, read_write> prefixSums: array<u32>;
@group(0) @binding(3) var<storage, read_write> blockSums: array<u32>;

var<workgroup> sharedData: array<u32, 512>;

@compute @workgroup_size(256)
fn main(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(local_invocation_id) local_id: vec3<u32>,
    @builtin(workgroup_id) workgroup_id: vec3<u32>
) {
    let totalCells = uniforms.gridWidth * uniforms.gridHeight;
    let tid = local_id.x;
    let blockOffset = workgroup_id.x * WORKGROUP_SIZE * 2u;
    
    // Load data into shared memory (two elements per thread)
    let idx1 = blockOffset + tid;
    let idx2 = blockOffset + tid + WORKGROUP_SIZE;
    
    if (idx1 < totalCells) {
        sharedData[tid] = cellCounts[idx1];
    } else {
        sharedData[tid] = 0u;
    }
    
    if (idx2 < totalCells) {
        sharedData[tid + WORKGROUP_SIZE] = cellCounts[idx2];
    } else {
        sharedData[tid + WORKGROUP_SIZE] = 0u;
    }
    
    // Up-sweep (reduce) phase
    var offset = 1u;
    for (var d = WORKGROUP_SIZE; d > 0u; d = d >> 1u) {
        workgroupBarrier();
        if (tid < d) {
            let ai = offset * (2u * tid + 1u) - 1u;
            let bi = offset * (2u * tid + 2u) - 1u;
            sharedData[bi] += sharedData[ai];
        }
        offset = offset << 1u;
    }
    
    // Store block sum and clear last element
    if (tid == 0u) {
        blockSums[workgroup_id.x] = sharedData[WORKGROUP_SIZE * 2u - 1u];
        sharedData[WORKGROUP_SIZE * 2u - 1u] = 0u;
    }
    
    // Down-sweep phase
    for (var d = 1u; d < WORKGROUP_SIZE * 2u; d = d << 1u) {
        offset = offset >> 1u;
        workgroupBarrier();
        if (tid < d) {
            let ai = offset * (2u * tid + 1u) - 1u;
            let bi = offset * (2u * tid + 2u) - 1u;
            let temp = sharedData[ai];
            sharedData[ai] = sharedData[bi];
            sharedData[bi] += temp;
        }
    }
    
    workgroupBarrier();
    
    // Write results back
    if (idx1 < totalCells) {
        prefixSums[idx1] = sharedData[tid];
    }
    if (idx2 < totalCells) {
        prefixSums[idx2] = sharedData[tid + WORKGROUP_SIZE];
    }
}

// Second pass: add block sums to get final prefix sums
@compute @workgroup_size(256)
fn addBlockSums(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(workgroup_id) workgroup_id: vec3<u32>
) {
    let totalCells = uniforms.gridWidth * uniforms.gridHeight;
    let idx = global_id.x;
    
    if (idx >= totalCells) {
        return;
    }
    
    // Calculate which ORIGINAL block this element belongs to
    // Each original block processed 512 elements (WORKGROUP_SIZE * 2)
    let originalBlock = idx / (WORKGROUP_SIZE * 2u);
    
    // Skip elements in the first block - they don't need adjustment
    if (originalBlock == 0u) {
        return;
    }
    
    // Add the sum of all previous blocks
    var blockSum = 0u;
    for (var i = 0u; i < originalBlock; i++) {
        blockSum += blockSums[i];
    }
    
    prefixSums[idx] += blockSum;
}
