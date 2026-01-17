// Pass 5: Main boid simulation with flocking rules

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

// Boundary modes
const PLANE: u32 = 0u;
const CYLINDER_X: u32 = 1u;
const CYLINDER_Y: u32 = 2u;
const TORUS: u32 = 3u;
const MOBIUS_X: u32 = 4u;
const MOBIUS_Y: u32 = 5u;
const KLEIN_X: u32 = 6u;
const KLEIN_Y: u32 = 7u;
const PROJECTIVE_PLANE: u32 = 8u;

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> positionsIn: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read_write> positionsOut: array<vec2<f32>>;
@group(0) @binding(3) var<storage, read> velocitiesIn: array<vec2<f32>>;
@group(0) @binding(4) var<storage, read_write> velocitiesOut: array<vec2<f32>>;
@group(0) @binding(5) var<storage, read> prefixSums: array<u32>;
@group(0) @binding(6) var<storage, read> cellCounts: array<u32>;
@group(0) @binding(7) var<storage, read> sortedIndices: array<u32>;
@group(0) @binding(8) var<storage, read_write> trails: array<vec2<f32>>;

// Simple hash for pseudo-random numbers
fn hash(n: u32) -> f32 {
    var x = n;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return f32(x) / f32(0xffffffffu);
}

fn random2(seed: u32) -> vec2<f32> {
    return vec2<f32>(
        hash(seed) * 2.0 - 1.0,
        hash(seed + 1u) * 2.0 - 1.0
    );
}

fn limitMagnitude(v: vec2<f32>, maxMag: f32) -> vec2<f32> {
    let mag = length(v);
    if (mag > maxMag && mag > 0.0) {
        return v * (maxMag / mag);
    }
    return v;
}

fn getCellCoords(pos: vec2<f32>) -> vec2<i32> {
    return vec2<i32>(
        clamp(i32(pos.x / uniforms.cellSize), 0i, i32(uniforms.gridWidth) - 1i),
        clamp(i32(pos.y / uniforms.cellSize), 0i, i32(uniforms.gridHeight) - 1i)
    );
}

fn getCellIndex(cx: i32, cy: i32) -> u32 {
    return u32(cy) * uniforms.gridWidth + u32(cx);
}

// Handle wrapped distance for toroidal/cylindrical spaces
fn wrappedDelta(delta: f32, size: f32, wrap: bool) -> f32 {
    if (!wrap) {
        return delta;
    }
    let halfSize = size * 0.5;
    if (delta > halfSize) {
        return delta - size;
    } else if (delta < -halfSize) {
        return delta + size;
    }
    return delta;
}

fn getNeighborDelta(myPos: vec2<f32>, otherPos: vec2<f32>) -> vec2<f32> {
    var delta = otherPos - myPos;
    
    let wrapX = uniforms.boundaryMode == TORUS || 
                uniforms.boundaryMode == CYLINDER_X || 
                uniforms.boundaryMode == MOBIUS_X ||
                uniforms.boundaryMode == KLEIN_X ||
                uniforms.boundaryMode == PROJECTIVE_PLANE;
    let wrapY = uniforms.boundaryMode == TORUS || 
                uniforms.boundaryMode == CYLINDER_Y || 
                uniforms.boundaryMode == MOBIUS_Y ||
                uniforms.boundaryMode == KLEIN_Y ||
                uniforms.boundaryMode == PROJECTIVE_PLANE;
    
    delta.x = wrappedDelta(delta.x, uniforms.canvasWidth, wrapX);
    delta.y = wrappedDelta(delta.y, uniforms.canvasHeight, wrapY);
    
    return delta;
}

fn applyBoundary(pos: vec2<f32>, vel: vec2<f32>) -> vec2<f32> {
    var newPos = pos;
    var newVel = vel;
    
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    
    switch (uniforms.boundaryMode) {
        case PLANE: {
            // Bounce off edges
            if (newPos.x < 0.0) { newPos.x = -newPos.x; }
            if (newPos.x >= w) { newPos.x = 2.0 * w - newPos.x - 1.0; }
            if (newPos.y < 0.0) { newPos.y = -newPos.y; }
            if (newPos.y >= h) { newPos.y = 2.0 * h - newPos.y - 1.0; }
        }
        case CYLINDER_X: {
            // Wrap X, bounce Y
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            if (newPos.y < 0.0) { newPos.y = -newPos.y; }
            if (newPos.y >= h) { newPos.y = 2.0 * h - newPos.y - 1.0; }
        }
        case CYLINDER_Y: {
            // Bounce X, wrap Y
            if (newPos.x < 0.0) { newPos.x = -newPos.x; }
            if (newPos.x >= w) { newPos.x = 2.0 * w - newPos.x - 1.0; }
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case TORUS: {
            // Wrap both axes
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case MOBIUS_X: {
            // Wrap X with Y flip, bounce Y
            if (newPos.x < 0.0) {
                newPos.x = newPos.x + w;
                newPos.y = h - newPos.y;
            } else if (newPos.x >= w) {
                newPos.x = newPos.x - w;
                newPos.y = h - newPos.y;
            }
            if (newPos.y < 0.0) { newPos.y = -newPos.y; }
            if (newPos.y >= h) { newPos.y = 2.0 * h - newPos.y - 1.0; }
        }
        case MOBIUS_Y: {
            // Bounce X, wrap Y with X flip
            if (newPos.x < 0.0) { newPos.x = -newPos.x; }
            if (newPos.x >= w) { newPos.x = 2.0 * w - newPos.x - 1.0; }
            if (newPos.y < 0.0) {
                newPos.y = newPos.y + h;
                newPos.x = w - newPos.x;
            } else if (newPos.y >= h) {
                newPos.y = newPos.y - h;
                newPos.x = w - newPos.x;
            }
        }
        case KLEIN_X: {
            // Wrap X with Y flip, wrap Y normally
            if (newPos.x < 0.0) {
                newPos.x = newPos.x + w;
                newPos.y = h - newPos.y;
            } else if (newPos.x >= w) {
                newPos.x = newPos.x - w;
                newPos.y = h - newPos.y;
            }
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
        case KLEIN_Y: {
            // Wrap X normally, wrap Y with X flip
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            if (newPos.y < 0.0) {
                newPos.y = newPos.y + h;
                newPos.x = w - newPos.x;
            } else if (newPos.y >= h) {
                newPos.y = newPos.y - h;
                newPos.x = w - newPos.x;
            }
        }
        case PROJECTIVE_PLANE: {
            // Wrap both axes with flips
            if (newPos.x < 0.0) {
                newPos.x = newPos.x + w;
                newPos.y = h - newPos.y;
            } else if (newPos.x >= w) {
                newPos.x = newPos.x - w;
                newPos.y = h - newPos.y;
            }
            if (newPos.y < 0.0) {
                newPos.y = newPos.y + h;
                newPos.x = w - newPos.x;
            } else if (newPos.y >= h) {
                newPos.y = newPos.y - h;
                newPos.x = w - newPos.x;
            }
        }
        default: {
            // Default to torus
            newPos.x = newPos.x - floor(newPos.x / w) * w;
            newPos.y = newPos.y - floor(newPos.y / h) * h;
        }
    }
    
    return newPos;
}

fn applyBoundaryVelocity(pos: vec2<f32>, vel: vec2<f32>) -> vec2<f32> {
    var newVel = vel;
    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;
    let margin = 50.0;
    let turnForce = 0.5;
    
    // For bounce modes, reverse velocity at edges
    if (uniforms.boundaryMode == PLANE) {
        if (pos.x < margin) { newVel.x += turnForce; }
        if (pos.x > w - margin) { newVel.x -= turnForce; }
        if (pos.y < margin) { newVel.y += turnForce; }
        if (pos.y > h - margin) { newVel.y -= turnForce; }
    } else if (uniforms.boundaryMode == CYLINDER_X) {
        if (pos.y < margin) { newVel.y += turnForce; }
        if (pos.y > h - margin) { newVel.y -= turnForce; }
    } else if (uniforms.boundaryMode == CYLINDER_Y) {
        if (pos.x < margin) { newVel.x += turnForce; }
        if (pos.x > w - margin) { newVel.x -= turnForce; }
    } else if (uniforms.boundaryMode == MOBIUS_X) {
        if (pos.y < margin) { newVel.y += turnForce; }
        if (pos.y > h - margin) { newVel.y -= turnForce; }
    } else if (uniforms.boundaryMode == MOBIUS_Y) {
        if (pos.x < margin) { newVel.x += turnForce; }
        if (pos.x > w - margin) { newVel.x -= turnForce; }
    }
    
    return newVel;
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let boidIndex = global_id.x;
    
    if (boidIndex >= uniforms.boidCount) {
        return;
    }
    
    let myPos = positionsIn[boidIndex];
    let myVel = velocitiesIn[boidIndex];
    let myCellCoords = getCellCoords(myPos);
    
    // Check if this boid is a rebel
    // Rebels have consistent rebellious periods based on time
    // Each boid has a unique phase offset, and rebels for ~60 frames when their phase aligns
    let rebelPeriod = 180u; // ~3 seconds at 60fps between potential rebel phases
    let rebelDuration = 60u; // ~1 second of rebellion
    let boidPhase = u32(hash(boidIndex * 12345u) * f32(rebelPeriod));
    let timeInCycle = (uniforms.frameCount + boidPhase) % rebelPeriod;
    let inRebelWindow = timeInCycle < rebelDuration;
    // Only some boids are prone to rebellion (determined by rebels parameter)
    let isRebelProne = hash(boidIndex * 7919u) < uniforms.rebels * 5.0; // Scale up since it's now persistent
    let isRebel = isRebelProne && inRebelWindow;
    let rebelFactor = select(1.0, 0.2, isRebel);
    
    // Accumulate forces from neighbors
    var alignmentSum = vec2<f32>(0.0);
    var cohesionSum = vec2<f32>(0.0);
    var separationSum = vec2<f32>(0.0);
    var neighborCount = 0u;
    var closeCount = 0u;
    
    let perceptionSq = uniforms.perception * uniforms.perception;
    let separationDist = uniforms.perception * 0.5;
    let separationDistSq = separationDist * separationDist;
    
    // Max neighbors to process for performance (prevents slowdown in dense clusters)
    let maxNeighbors = 64u;
    
    // Iterate over 3x3 neighboring cells
    for (var dy = -1i; dy <= 1i; dy++) {
        for (var dx = -1i; dx <= 1i; dx++) {
            var cx = myCellCoords.x + dx;
            var cy = myCellCoords.y + dy;
            
            // Handle wrapping for toroidal topologies
            let wrapX = uniforms.boundaryMode == TORUS || 
                        uniforms.boundaryMode == CYLINDER_X || 
                        uniforms.boundaryMode == MOBIUS_X ||
                        uniforms.boundaryMode == KLEIN_X ||
                        uniforms.boundaryMode == PROJECTIVE_PLANE;
            let wrapY = uniforms.boundaryMode == TORUS || 
                        uniforms.boundaryMode == CYLINDER_Y || 
                        uniforms.boundaryMode == MOBIUS_Y ||
                        uniforms.boundaryMode == KLEIN_Y ||
                        uniforms.boundaryMode == PROJECTIVE_PLANE;
            
            if (wrapX) {
                cx = (cx + i32(uniforms.gridWidth)) % i32(uniforms.gridWidth);
            } else if (cx < 0i || cx >= i32(uniforms.gridWidth)) {
                continue;
            }
            
            if (wrapY) {
                cy = (cy + i32(uniforms.gridHeight)) % i32(uniforms.gridHeight);
            } else if (cy < 0i || cy >= i32(uniforms.gridHeight)) {
                continue;
            }
            
            let cellIdx = getCellIndex(cx, cy);
            let cellStart = prefixSums[cellIdx];
            let cellCount = cellCounts[cellIdx];
            
            // Iterate over boids in this cell
            for (var i = 0u; i < cellCount && neighborCount < maxNeighbors; i++) {
                let otherBoidIndex = sortedIndices[cellStart + i];
                
                if (otherBoidIndex == boidIndex) {
                    continue;
                }
                
                let otherPos = positionsIn[otherBoidIndex];
                let otherVel = velocitiesIn[otherBoidIndex];
                
                let delta = getNeighborDelta(myPos, otherPos);
                let distSq = dot(delta, delta);
                
                // Handle boids that are extremely close (nearly overlapping)
                // These need strong separation but can't use delta (it's near zero)
                if (distSq < 0.01) {
                    // Apply strong random separation force based on boid indices
                    let seed = boidIndex * 31u + otherBoidIndex * 17u + uniforms.frameCount;
                    let randomDir = normalize(random2(seed));
                    separationSum += randomDir * 5.0; // Strong push in random direction
                    closeCount++;
                    continue;
                }
                
                if (distSq < perceptionSq) {
                    let dist = sqrt(distSq);
                    
                    // Alignment: average velocity of neighbors
                    alignmentSum += otherVel;
                    
                    // Cohesion: average position of neighbors
                    cohesionSum += delta;
                    
                    neighborCount++;
                    
                    // Separation: avoid close neighbors
                    if (distSq < separationDistSq) {
                        // Stronger weight for closer boids (inverse square falloff)
                        let normalizedDist = dist / separationDist;
                        let weight = (1.0 - normalizedDist) * (1.0 - normalizedDist);
                        separationSum -= delta * (weight / dist);
                        closeCount++;
                    }
                }
            }
            
            // Early exit if we've hit max neighbors
            if (neighborCount >= maxNeighbors) {
                break;
            }
        }
        if (neighborCount >= maxNeighbors) {
            break;
        }
    }
    
    var acceleration = vec2<f32>(0.0);
    
    if (neighborCount > 0u) {
        let nf = f32(neighborCount);
        
        // Alignment force
        if (uniforms.alignment > 0.0) {
            let avgVel = alignmentSum / nf;
            let alignForce = limitMagnitude(avgVel - myVel, uniforms.maxForce);
            acceleration += alignForce * uniforms.alignment * rebelFactor;
        }
        
        // Cohesion force
        if (uniforms.cohesion > 0.0) {
            let avgDelta = cohesionSum / nf;
            let cohesionForce = limitMagnitude(avgDelta, uniforms.maxForce);
            acceleration += cohesionForce * uniforms.cohesion * rebelFactor;
        }
    }
    
    // Separation force (higher force limit than other rules for collision avoidance)
    if (closeCount > 0u && uniforms.separation > 0.0) {
        let sepForce = limitMagnitude(separationSum, uniforms.maxForce * 3.0);
        acceleration += sepForce * uniforms.separation;
    }
    
    // Cursor interaction
    if (uniforms.cursorMode != 0u && uniforms.cursorActive != 0u) {
        let cursorPos = vec2<f32>(uniforms.cursorX, uniforms.cursorY);
        let toCursor = getNeighborDelta(myPos, cursorPos);
        let cursorDist = length(toCursor);
        
        if (cursorDist > 1.0) {
            let cursorInfluence = 200.0; // Influence radius
            let strength = select(0.3, 1.0, uniforms.cursorPressed != 0u);
            
            if (cursorDist < cursorInfluence) {
                let cursorWeight = (1.0 - cursorDist / cursorInfluence) * strength;
                var cursorForce = normalize(toCursor) * uniforms.cursorForce * cursorWeight;
                
                if (uniforms.cursorMode == 2u) {
                    cursorForce = -cursorForce; // Repel
                }
                
                acceleration += cursorForce;
            }
        }
    }
    
    // Add noise
    if (uniforms.noise > 0.0) {
        let noiseSeed = boidIndex * 31u + uniforms.frameCount * 17u;
        let noiseVec = random2(noiseSeed) * uniforms.noise * uniforms.maxForce;
        acceleration += noiseVec;
    }
    
    // Apply boundary steering
    var newVel = applyBoundaryVelocity(myPos, myVel + acceleration);
    
    // Limit speed
    newVel = limitMagnitude(newVel, uniforms.maxSpeed);
    
    // Ensure minimum speed
    let speed = length(newVel);
    if (speed < uniforms.maxSpeed * 0.3) {
        if (speed > 0.001) {
            newVel = normalize(newVel) * uniforms.maxSpeed * 0.3;
        } else {
            // Give stationary boid a random direction
            let rndSeed = boidIndex * 13u + uniforms.frameCount * 23u;
            newVel = normalize(random2(rndSeed)) * uniforms.maxSpeed * 0.3;
        }
    }
    
    // Update position
    var newPos = myPos + newVel * uniforms.deltaTime * 60.0;
    
    // Apply boundary conditions
    newPos = applyBoundary(newPos, newVel);
    
    // Write output
    positionsOut[boidIndex] = newPos;
    velocitiesOut[boidIndex] = newVel;
    
    // Update trail
    let trailIdx = boidIndex * uniforms.trailLength + uniforms.trailHead;
    trails[trailIdx] = newPos;
}
