// Translucent shell + parameter grid for embedded 3D mode.
//
// Both meshes are generated procedurally from vertex_index - no vertex buffers,
// matching how boids and trails are drawn. The shell is rendered twice per
// frame (back faces before the flock, front faces after) so boids on the far
// side of a torus stay visible through the near wall.
//
// Requires common.wgsl and embed.wgsl prepended at load time.

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var wallTexture: texture_2d<f32>;
@group(0) @binding(2) var wallSampler: sampler;

// Shell tessellation. Generous in u because that is the wrapping direction on
// most topologies and carries the visible silhouette.
const SHELL_U: u32 = 160u;
const SHELL_V: u32 = 80u;

// Parameter grid density
const GRID_LINES_U: u32 = 24u;
const GRID_LINES_V: u32 = 12u;
const GRID_SEGMENTS: u32 = 160u;

struct SurfaceOut {
    @builtin(position) position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) worldPos: vec3<f32>,
    @location(2) uv: vec2<f32>,
}

// Corner offsets for the two triangles of a quad
fn quadCorner(i: u32) -> vec2<f32> {
    switch (i) {
        case 0u: { return vec2<f32>(0.0, 0.0); }
        case 1u: { return vec2<f32>(1.0, 0.0); }
        case 2u: { return vec2<f32>(0.0, 1.0); }
        case 3u: { return vec2<f32>(0.0, 1.0); }
        case 4u: { return vec2<f32>(1.0, 0.0); }
        default: { return vec2<f32>(1.0, 1.0); }
    }
}

@vertex
fn vs_shell(@builtin(vertex_index) vertexIndex: u32) -> SurfaceOut {
    let quadIndex = vertexIndex / 6u;
    let corner = quadCorner(vertexIndex % 6u);

    let cellU = quadIndex % SHELL_U;
    let cellV = quadIndex / SHELL_U;

    let uv = vec2<f32>(
        (f32(cellU) + corner.x) / f32(SHELL_U),
        (f32(cellV) + corner.y) / f32(SHELL_V)
    );

    let frame = surfaceFrameAt(uv);

    var out: SurfaceOut;
    out.position = uniforms.viewProj * vec4<f32>(frame.pos, 1.0);
    out.normal = frame.normal;
    out.worldPos = frame.pos;
    out.uv = uv;
    return out;
}

@fragment
fn fs_shell(in: SurfaceOut) -> @location(0) vec4<f32> {
    // The shell is the same black as the page background: its job is purely to
    // occlude - it hides the far side of the flock through the depth buffer
    // without ever tinting the scene. Shape reads from the boids, their trails
    // and the parameter grid drawn over it, not from shading the surface.
    let background = vec3<f32>(0.039, 0.043, 0.051);
    var color = background;

    // Painted walls are the one thing that must still show on the surface.
    let wall = textureSampleLevel(wallTexture, wallSampler, vec2<f32>(in.uv.x, 1.0 - in.uv.y), 0.0).r;
    if (wall > 0.01) {
        color = mix(color, vec3<f32>(0.34, 0.36, 0.44), wall * 0.85);
    }

    // No fade needed on the way in - the shell already matches the background,
    // so it can write depth from the first frame of the morph without showing.
    return vec4<f32>(color, 1.0);
}

struct GridOut {
    @builtin(position) position: vec4<f32>,
    @location(0) fade: f32,
}

@vertex
fn vs_grid(@builtin(vertex_index) vertexIndex: u32) -> GridOut {
    // Two vertices per segment, GRID_SEGMENTS segments per line.
    let vertsPerLine = GRID_SEGMENTS * 2u;
    let lineIndex = vertexIndex / vertsPerLine;
    let withinLine = vertexIndex % vertsPerLine;
    let segment = withinLine / 2u;
    let endpoint = withinLine % 2u;

    let t = f32(segment + endpoint) / f32(GRID_SEGMENTS);

    // One extra line per axis so both boundaries are drawn. Lines used to stop
    // at (N-1)/N, which is invisible on a wrapping axis - the missing line sits
    // exactly on the one at 0 - but leaves an *open* edge with no line on it at
    // all, so the cylinder ends, the Mobius rim and the plane border all just
    // stopped mid-air. Where the axis does wrap, the duplicate is suppressed
    // instead so that seam is not drawn twice as bright.
    var uv: vec2<f32>;
    var visible = true;
    if (lineIndex <= GRID_LINES_U) {
        // Lines of constant u, running along v
        if (lineIndex == GRID_LINES_U && wrapsX()) {
            visible = false;
        }
        uv = vec2<f32>(f32(lineIndex) / f32(GRID_LINES_U), t);
    } else {
        // Lines of constant v, running along u
        let vIndex = lineIndex - GRID_LINES_U - 1u;
        if (vIndex == GRID_LINES_V && wrapsY()) {
            visible = false;
        }
        uv = vec2<f32>(t, f32(vIndex) / f32(GRID_LINES_V));
    }

    var out: GridOut;
    out.position = uniforms.viewProj * vec4<f32>(surfacePoint(uv), 1.0);
    out.fade = select(0.0, 1.0, visible);
    return out;
}

@fragment
fn fs_grid(in: GridOut) -> @location(0) vec4<f32> {
    let a = uniforms.embedParams.w * in.fade;
    // Bright and slightly cool so the parameter lines stay legible over a dense
    // flock - these are the main cue for how the domain is glued together.
    let color = vec3<f32>(0.72, 0.85, 1.0);
    return vec4<f32>(color * a, a);
}
