// Embedded-mode surface math.
//
// The simulation always runs on the flat domain [0,W]x[0,H] with topological
// gluing rules. This file maps that domain onto the surface those rules
// actually describe, so the flock can be drawn on a real torus / Mobius strip /
// Klein bottle instead of on its unrolled 2D chart.
//
// Parametrizations are ported from $lib/utils/topologyMeshes.ts so the world
// and the topology picker thumbnails show the same shapes.
//
// Requires common.wgsl (Uniforms, boundary mode constants) prepended at load.

const TAU: f32 = 6.283185307179586;

// Domain position (pixels) -> parameter space.
// Parametric v is flipped relative to domain y because domain y grows downward
// while world Y grows upward; doing it here keeps every formula below verbatim.
fn domainToParam(pos: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(pos.x / uniforms.canvasWidth, 1.0 - pos.y / uniforms.canvasHeight);
}

// --- Individual surfaces ---
//
// Every surface derives its proportions from the domain rather than from
// hardcoded constants. Previously each carried fixed dimensions, so the 16:9
// domain was stretched onto whatever shape happened to be there: the Roman
// surface ended up carrying 13x the area it should and Mobius Y was squashed
// 12:1. Boids sample their size from the local metric, so that inflated them
// too - the "skin" looked stretched.
//
// Lu and Lv are the domain's width and height in world units.
//
// Plane, cylinders and torus are developable enough to match BOTH the domain's
// aspect and its area, so they are exactly isometric - no stretch at all.
//
// The Mobius strip, Klein bottle and Roman surface cannot be: an isometric
// Mobius from a 16:9 sheet needs a strip wider than its own loop radius
// (inner edge at -0.17, passing through its own axis), and the two immersions
// have intrinsically non-uniform metrics. Those match area only, which is what
// keeps boid size and density right, and keep their recognisable shape.

// Mobius width as a fraction of loop radius, and the area/radius of that strip
// at unit radius - used to solve for the radius that matches the domain area.
const MOBIUS_WIDTH_RATIO: f32 = 0.454545;
const MOBIUS_UNIT_AREA: f32 = 5.822360;
// Area of the unit-scale Dickson and Steiner immersions
const KLEIN_UNIT_AREA: f32 = 1888.940032;
const ROMAN_UNIT_AREA: f32 = 6.493252;

fn domainWidth() -> f32 { return 2.0 * uniforms.embedParams.x; }
fn domainHeight() -> f32 { return 2.0 * uniforms.embedParams.y; }

fn surfFlat(uv: vec2<f32>) -> vec3<f32> {
    return vec3<f32>((uv.x - 0.5) * domainWidth(), (uv.y - 0.5) * domainHeight(), 0.0);
}

// Rolled about u: the wrapped axis becomes the circumference, so the sheet maps
// onto the tube without stretching in either direction.
fn surfCylinderX(uv: vec2<f32>) -> vec3<f32> {
    let R = domainWidth() / TAU;
    let U = uv.x * TAU;
    return vec3<f32>(cos(U) * R, (uv.y - 0.5) * domainHeight(), sin(U) * R);
}

fn surfCylinderY(uv: vec2<f32>) -> vec3<f32> {
    let R = domainHeight() / TAU;
    let U = uv.y * TAU;
    return vec3<f32>((uv.x - 0.5) * domainWidth(), cos(U) * R, sin(U) * R);
}

// Both circumferences come straight from the domain, so a 16:9 sheet gives a
// noticeably fatter torus than the old fixed 0.6/0.22 - which is correct.
fn surfTorus(uv: vec2<f32>) -> vec3<f32> {
    let R = domainWidth() / TAU;
    let r = domainHeight() / TAU;
    let U = uv.x * TAU;
    let V = uv.y * TAU;
    let ring = R + r * cos(V);
    return vec3<f32>(ring * cos(U), r * sin(V), ring * sin(U));
}

fn mobiusRadius() -> f32 {
    return sqrt(domainWidth() * domainHeight() / MOBIUS_UNIT_AREA);
}

// The U/2 term is the half-twist: going once around u flips the strip over.
fn surfMobiusX(uv: vec2<f32>) -> vec3<f32> {
    let R = mobiusRadius();
    let w = MOBIUS_WIDTH_RATIO * R;
    let U = uv.x * TAU;
    let S = (uv.y - 0.5) * 2.0 * w;
    let radial = R + S * cos(U / 2.0);
    return vec3<f32>(radial * cos(U), S * sin(U / 2.0), radial * sin(U));
}

fn surfMobiusY(uv: vec2<f32>) -> vec3<f32> {
    let R = mobiusRadius();
    let w = MOBIUS_WIDTH_RATIO * R;
    let U = uv.y * TAU;
    let S = (uv.x - 0.5) * 2.0 * w;
    let radial = R + S * cos(U / 2.0);
    return vec3<f32>(S * sin(U / 2.0), radial * cos(U), radial * sin(U));
}

// Dickson's piecewise immersion - the recognizable "bottle" whose neck passes
// through its own side. Self-intersection is unavoidable: the Klein bottle does
// not embed in 3D. Scaled so its area matches the domain's, which is what keeps
// boids the same size here as anywhere else; its metric is intrinsically uneven
// so the aspect cannot also be matched.
fn kleinBase(u: f32, v: f32) -> vec3<f32> {
    let scale = sqrt(domainWidth() * domainHeight() / KLEIN_UNIT_AREA);

    // This immersion is NOT periodic in u: it satisfies F(u + 1, v) = F(u, -v),
    // the Klein bottle's orientation-reversing gluing. Treating u as periodic
    // tears the surface at the seam and makes the finite-difference frame blow
    // up. So reduce u by whole turns and flip v once per turn.
    let turns = floor(u);
    let uu = u - turns;
    var vv = v;
    if (fract(turns * 0.5) > 0.25) {
        vv = -vv;
    }

    // The raw parametrization glues as V -> pi - V. The quarter-turn phase shift
    // re-centers that to v -> -v, which is exactly the simulation's KleinX rule
    // (wrap in x, flip y) - without it, boids crossing the seam would reappear
    // half a tube-circumference away from where the surface says they should.
    let U = uu * TAU;
    let V = (vv + 0.25) * TAU;
    let cosU = cos(U);
    let sinU = sin(U);
    let cosV = cos(V);
    let sinV = sin(V);
    let c = 1.0 - 0.5 * cosU;

    var x: f32;
    var y: f32;
    if (U <= 3.141592653589793) {
        x = 6.0 * cosU * (1.0 + sinU) + 4.0 * c * cosU * cosV;
        y = 16.0 * sinU + 4.0 * c * sinU * cosV;
    } else {
        x = 6.0 * cosU * (1.0 + sinU) + 4.0 * c * cos(V + 3.141592653589793);
        y = 16.0 * sinU;
    }
    let z = 4.0 * c * sinV;
    return vec3<f32>(x * scale, z * scale, (y - 8.0) * scale);
}

fn surfKleinX(uv: vec2<f32>) -> vec3<f32> {
    return kleinBase(uv.x, uv.y);
}

fn surfKleinY(uv: vec2<f32>) -> vec3<f32> {
    // Parameters are swapped (not just the output axes) so the gluing matches
    // the simulation's Y-wrap-with-X-flip rule.
    let p = kleinBase(uv.y, uv.x);

    // Axis permutation from topologyMeshes.ts, then the quarter turn about X
    // that stands the bottle upright. Without it the long axis lies along Z and
    // the bottle reads as horizontal - the picker applies the same rotation and
    // labels it "Vertical" (getTopologyAdjustments in TopologySelector.svelte),
    // which is what makes the Y variant visually distinct from Klein X.
    let permuted = vec3<f32>(p.y, p.x, p.z);
    return vec3<f32>(permuted.x, -permuted.z, permuted.y);
}

// Roman (Steiner) surface - one immersion of the projective plane, with four
// lobes meeting at a triple point. Area-matched like the Klein bottle: at its
// old fixed scale it carried thirteen times the domain's area, which is what
// made the flock on it look blown up.
fn surfProjective(uv: vec2<f32>) -> vec3<f32> {
    let scale = sqrt(domainWidth() * domainHeight() / ROMAN_UNIT_AREA);
    let theta = uv.x * 3.141592653589793;
    let phi = uv.y * TAU;
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    let cosPhi = cos(phi);
    let sinPhi = sin(phi);
    return vec3<f32>(
        cosTheta * sinTheta * sinPhi * scale,
        cosTheta * cosTheta * cosPhi * sinPhi * scale,
        cosTheta * sinTheta * cosPhi * scale
    );
}

fn embeddedPointFor(uv: vec2<f32>, mode: u32) -> vec3<f32> {
    switch (mode) {
        case CYLINDER_X: { return surfCylinderX(uv); }
        case CYLINDER_Y: { return surfCylinderY(uv); }
        case TORUS: { return surfTorus(uv); }
        case MOBIUS_X: { return surfMobiusX(uv); }
        case MOBIUS_Y: { return surfMobiusY(uv); }
        case KLEIN_X: { return surfKleinX(uv); }
        case KLEIN_Y: { return surfKleinY(uv); }
        case PROJECTIVE_PLANE: { return surfProjective(uv); }
        default: { return surfFlat(uv); }
    }
}

/**
 * Fully embedded position, interpolating between the outgoing and incoming
 * topology while a switch is animating. The early-out keeps the steady state at
 * one parametrization evaluation - the double cost is only paid mid-transition.
 */
fn embeddedPoint(uv: vec2<f32>) -> vec3<f32> {
    let t = uniforms.topologyBlend;
    if (t >= 0.9999 || uniforms.embedTopologyPrev == uniforms.embedTopology) {
        return embeddedPointFor(uv, uniforms.embedTopology);
    }
    return mix(
        embeddedPointFor(uv, uniforms.embedTopologyPrev),
        embeddedPointFor(uv, uniforms.embedTopology),
        t
    );
}

/**
 * Surface point at the current morph blend. At blend 0 this is the flat
 * rectangle (matching the 2D view), at blend 1 the full embedding.
 */
fn surfacePoint(uv: vec2<f32>) -> vec3<f32> {
    let flat = surfFlat(uv);
    if (uniforms.embedBlend <= 0.0) {
        return flat;
    }
    return mix(flat, embeddedPoint(uv), uniforms.embedBlend);
}

struct SurfaceFrame {
    pos: vec3<f32>,
    du: vec3<f32>,     // dP/du, magnitude = world units per unit u
    dv: vec3<f32>,     // dP/dv
    normal: vec3<f32>, // unit surface normal
}

// Central differences rather than analytic derivatives: the Klein immersion is
// piecewise and the Roman surface has singular points, so a numeric frame is
// both shorter and more robust. One ring of slightly-off tangents at the Klein
// seam is not visible at these scales.
fn surfaceFrameAt(uv: vec2<f32>) -> SurfaceFrame {
    let eps = 0.0015;
    var frame: SurfaceFrame;
    frame.pos = surfacePoint(uv);
    frame.du = (surfacePoint(uv + vec2<f32>(eps, 0.0)) - surfacePoint(uv - vec2<f32>(eps, 0.0))) / (2.0 * eps);
    frame.dv = (surfacePoint(uv + vec2<f32>(0.0, eps)) - surfacePoint(uv - vec2<f32>(0.0, eps))) / (2.0 * eps);

    let n = cross(frame.du, frame.dv);
    let nLen = length(n);
    if (nLen < 1e-6) {
        // Degenerate point (e.g. Roman surface pinch) - any consistent normal
        // will do, the boid is vanishingly small there anyway.
        frame.normal = vec3<f32>(0.0, 0.0, 1.0);
    } else {
        frame.normal = n / nLen;
    }
    return frame;
}

/**
 * Local world scale at a point: world units per domain pixel, averaged over the
 * two parameter directions. Using the true local metric means boids naturally
 * shrink where the surface compresses (the inner rim of a torus) and grow where
 * it stretches, instead of all being one flat size.
 */
/**
 * World size of one domain pixel, constant across the whole surface.
 *
 * This deliberately ignores the local metric. Sizing each boid by the stretch
 * under it makes them swell on the body of a Klein bottle and shrink in the
 * neck, which reads as a texture stretched over the shape rather than a flock
 * on it. A boid is an agent, not a piece of skin: it keeps its own size
 * wherever it swims, exactly as it does in the flat view.
 *
 * Being constant also removes the need for the old blow-up guard - there is no
 * longer any derivative in the size at all.
 */
fn surfaceScale() -> f32 {
    return domainWidth() / uniforms.canvasWidth;
}

/**
 * Project a point that sits at `domainPos` on the surface, offset by
 * `localOffset` pixels in the surface tangent plane. `forward` is the domain-
 * space direction the offset's +x axis should point along (typically velocity).
 */
fn projectOnSurface(domainPos: vec2<f32>, localOffset: vec2<f32>, forward: vec2<f32>) -> vec4<f32> {
    let uv = domainToParam(domainPos);
    let frame = surfaceFrameAt(uv);
    let scale = surfaceScale();

    // Push the domain-space heading through the surface differential. Domain y
    // grows downward while parametric v grows upward, hence the negated y.
    let pushed = forward.x / uniforms.canvasWidth * frame.du
               - forward.y / uniforms.canvasHeight * frame.dv;
    var right = pushed;
    if (length(right) < 1e-8) {
        right = frame.du;
    }
    right = normalize(right);
    let up = cross(frame.normal, right);

    let world = frame.pos + (right * localOffset.x - up * localOffset.y) * scale;
    return uniforms.viewProj * vec4<f32>(world, 1.0);
}

/**
 * Project one edge of a ribbon whose centreline lies on the surface.
 *
 * Trails need a constant world-space width, same as boids, but the full tangent
 * frame costs five surface evaluations per vertex and trails are by far the
 * heaviest draw - doing it that way cost about 13% of the frame rate. Stepping
 * once along the perpendicular gives the same edge direction for two
 * evaluations instead of five, and the ribbon is far too thin for the
 * difference between a first- and second-order derivative to show.
 */
fn projectRibbonEdge(domainPos: vec2<f32>, perpDomain: vec2<f32>, halfWidth: f32) -> vec4<f32> {
    let uv = domainToParam(domainPos);
    let p0 = surfacePoint(uv);

    // Perpendicular in parameter space. Domain y is flipped relative to
    // parametric v, matching domainToParam.
    let step = vec2<f32>(perpDomain.x / uniforms.canvasWidth, -perpDomain.y / uniforms.canvasHeight);
    let stepLen = length(step);
    if (stepLen < 1e-9) {
        return uniforms.viewProj * vec4<f32>(p0, 1.0);
    }

    let eps = 0.0015;
    let p1 = surfacePoint(uv + step / stepLen * eps);
    var edge = p1 - p0;
    let edgeLen = length(edge);
    if (edgeLen < 1e-9) {
        return uniforms.viewProj * vec4<f32>(p0, 1.0);
    }

    let world = p0 + edge / edgeLen * halfWidth * surfaceScale();
    return uniforms.viewProj * vec4<f32>(world, 1.0);
}

/** World-space position for a domain point, for lighting/shell use. */
fn surfaceWorld(domainPos: vec2<f32>) -> vec3<f32> {
    return surfacePoint(domainToParam(domainPos));
}

/**
 * Project a domain point that already lies on the surface (no tangent-plane
 * offset). Used for trail ribbons, whose width is baked into the domain
 * coordinates already - this glues the ribbon exactly to the surface.
 */
fn projectDomainPoint(domainPos: vec2<f32>) -> vec4<f32> {
    return uniforms.viewProj * vec4<f32>(surfaceWorld(domainPos), 1.0);
}

struct SeamUnwrap {
    pos: vec2<f32>,
    valid: bool,
}

/**
 * Undo the boundary transform the simulation applied when a boid crossed a
 * seam, expressing p2 in coordinates continuous with p1.
 *
 * On the embedded surface the two endpoints of a wrapped segment are genuinely
 * adjacent - it is only their domain coordinates that jump a whole width apart
 * (and flip, on the non-orientable topologies). Continuing p2 past the edge
 * instead of cutting the ribbon is what makes trails flow across the seam, and
 * it works because every parametrization here satisfies the same gluing rule
 * the simulation uses: F(u+1, v) = F(u, 1-v) where the topology flips, and
 * F(u+1, v) = F(u, v) where it merely wraps.
 */
fn unwrapAcrossSeam(p1: vec2<f32>, p2in: vec2<f32>) -> SeamUnwrap {
    var out: SeamUnwrap;
    out.pos = p2in;
    out.valid = true;

    // The projective plane is the one mode where continuing past the edge lands
    // somewhere else entirely. Its boundary rule flips BOTH axes, and those two
    // deck transformations do not commute - so it is not a consistent quotient
    // of the plane, and in fact cannot be: RP^2's universal cover is the sphere,
    // not R^2. Every flat surface the plane does cover (cylinder, torus,
    // Mobius, Klein) is already handled below. Cut the segment instead of
    // drawing a streak to the wrong place.
    if (uniforms.embedTopology == PROJECTIVE_PLANE) {
        out.valid = false;
        return out;
    }

    let cfg = getBoundaryConfig();
    if (!cfg.wrapX && !cfg.wrapY) {
        out.valid = false;
        return out;
    }

    let w = uniforms.canvasWidth;
    let h = uniforms.canvasHeight;

    // Enumerate every boundary transform the simulation could have applied and
    // keep whichever lands closest to p1.
    //
    // Undoing the axes in sequence does not work, because a flip on one axis is
    // *induced* by a wrap on the other: crossing the Y seam of a Mobius Y flips
    // x, which looks exactly like an X wrap even though x does not wrap there.
    // A real frame step is a handful of pixels, so the correct candidate wins by
    // orders of magnitude and no ordering assumption is needed.
    var best = out.pos;
    var bestDist = distance(out.pos, p1);

    for (var i = 0u; i < 2u; i = i + 1u) {
        let s = select(-1.0, 1.0, i == 0u);

        if (cfg.wrapX) {
            var c = out.pos;
            c.x = c.x + s * w;
            if (cfg.flipOnWrapX) { c.y = h - c.y; }
            let d = distance(c, p1);
            if (d < bestDist) { bestDist = d; best = c; }
        }

        if (cfg.wrapY) {
            var c = out.pos;
            c.y = c.y + s * h;
            if (cfg.flipOnWrapY) { c.x = w - c.x; }
            let d = distance(c, p1);
            if (d < bestDist) { bestDist = d; best = c; }
        }
    }

    // Corner crossings hit both seams in one step. Both application orders are
    // tried because the transforms do not commute when either axis flips.
    if (cfg.wrapX && cfg.wrapY) {
        for (var i = 0u; i < 4u; i = i + 1u) {
            let sx = select(-1.0, 1.0, (i & 1u) == 0u);
            let sy = select(-1.0, 1.0, (i & 2u) == 0u);

            var a = out.pos;
            a.x = a.x + sx * w;
            if (cfg.flipOnWrapX) { a.y = h - a.y; }
            a.y = a.y + sy * h;
            if (cfg.flipOnWrapY) { a.x = w - a.x; }
            let da = distance(a, p1);
            if (da < bestDist) { bestDist = da; best = a; }

            var b = out.pos;
            b.y = b.y + sy * h;
            if (cfg.flipOnWrapY) { b.x = w - b.x; }
            b.x = b.x + sx * w;
            if (cfg.flipOnWrapX) { b.y = h - b.y; }
            let db = distance(b, p1);
            if (db < bestDist) { bestDist = db; best = b; }
        }
    }

    out.pos = best;
    // Nothing plausible found - this is a teleport (reset, respawn) rather than
    // a seam crossing, so drop it instead of drawing a streak across the shape.
    if (bestDist > 0.25 * min(w, h)) {
        out.valid = false;
    }
    return out;
}
