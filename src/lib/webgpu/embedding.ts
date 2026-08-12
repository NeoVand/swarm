// CPU mirror of the surface math in $lib/shaders/embed.wgsl.
//
// The GPU owns the drawing, but the cursor needs to know *which point of the
// domain* is under the mouse in embedded mode, and that answer has to come back
// to the CPU to drive the cursor force. Reading it back from the GPU would cost
// a stall every frame, so the parametrizations are duplicated here instead.
//
// These must stay in step with embed.wgsl. Any change to a surface there needs
// the same change here.

import { BoundaryMode } from './types';

const TAU = Math.PI * 2;
const PI = Math.PI;

const fract = (x: number) => x - Math.floor(x);

export type Vec3 = [number, number, number];

export interface EmbedView {
	topology: BoundaryMode;
	prevTopology: BoundaryMode;
	/** 0..1 cross-fade between prevTopology and topology. */
	topologyBlend: number;
	/** 0 = flat rectangle, 1 = full embedding. */
	embedBlend: number;
	planeHalfWidth: number;
	planeHalfHeight: number;
}

function surfFlat(u: number, v: number, view: EmbedView): Vec3 {
	return [(u - 0.5) * 2 * view.planeHalfWidth, (v - 0.5) * 2 * view.planeHalfHeight, 0];
}

function surfCylinderX(u: number, v: number): Vec3 {
	const R = 0.5;
	const height = 1.2;
	const U = u * TAU;
	return [Math.cos(U) * R, (v - 0.5) * height, Math.sin(U) * R];
}

function surfCylinderY(u: number, v: number): Vec3 {
	const R = 0.5;
	const height = 1.2;
	const U = v * TAU;
	return [(u - 0.5) * height, Math.cos(U) * R, Math.sin(U) * R];
}

function surfTorus(u: number, v: number): Vec3 {
	const R = 0.6;
	const r = 0.22;
	const U = u * TAU;
	const V = v * TAU;
	const ring = R + r * Math.cos(V);
	return [ring * Math.cos(U), r * Math.sin(V), ring * Math.sin(U)];
}

function surfMobiusX(u: number, v: number): Vec3 {
	const R = 0.55;
	const w = 0.25;
	const U = u * TAU;
	const S = (v - 0.5) * 2 * w;
	const radial = R + S * Math.cos(U / 2);
	return [radial * Math.cos(U), S * Math.sin(U / 2), radial * Math.sin(U)];
}

function surfMobiusY(u: number, v: number): Vec3 {
	const R = 0.55;
	const w = 0.25;
	const U = v * TAU;
	const S = (u - 0.5) * 2 * w;
	const radial = R + S * Math.cos(U / 2);
	return [S * Math.sin(U / 2), radial * Math.cos(U), radial * Math.sin(U)];
}

function kleinBase(u: number, v: number): Vec3 {
	const scale = 0.04;

	// Not periodic in u: F(u + 1, v) = F(u, -v). See embed.wgsl.
	const turns = Math.floor(u);
	const uu = u - turns;
	let vv = v;
	if (fract(turns * 0.5) > 0.25) vv = -vv;

	const U = uu * TAU;
	const V = (vv + 0.25) * TAU;
	const cosU = Math.cos(U);
	const sinU = Math.sin(U);
	const cosV = Math.cos(V);
	const sinV = Math.sin(V);
	const c = 1 - 0.5 * cosU;

	let x: number;
	let y: number;
	if (U <= PI) {
		x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
		y = 16 * sinU + 4 * c * sinU * cosV;
	} else {
		x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + PI);
		y = 16 * sinU;
	}
	return [x * scale, 4 * c * sinV * scale, (y - 8) * scale];
}

function surfKleinX(u: number, v: number): Vec3 {
	return kleinBase(u, v);
}

function surfKleinY(u: number, v: number): Vec3 {
	const p = kleinBase(v, u);
	// Axis permutation plus the quarter turn about X that stands it upright.
	const permuted: Vec3 = [p[1], p[0], p[2]];
	return [permuted[0], -permuted[2], permuted[1]];
}

function surfProjective(u: number, v: number): Vec3 {
	const scale = 1.5;
	const theta = u * PI;
	const phi = v * TAU;
	const cosTheta = Math.cos(theta);
	const sinTheta = Math.sin(theta);
	const cosPhi = Math.cos(phi);
	const sinPhi = Math.sin(phi);
	return [
		cosTheta * sinTheta * sinPhi * scale,
		cosTheta * cosTheta * cosPhi * sinPhi * scale,
		cosTheta * sinTheta * cosPhi * scale
	];
}

function embeddedPointFor(u: number, v: number, mode: BoundaryMode, view: EmbedView): Vec3 {
	switch (mode) {
		case BoundaryMode.CylinderX:
			return surfCylinderX(u, v);
		case BoundaryMode.CylinderY:
			return surfCylinderY(u, v);
		case BoundaryMode.Torus:
			return surfTorus(u, v);
		case BoundaryMode.MobiusX:
			return surfMobiusX(u, v);
		case BoundaryMode.MobiusY:
			return surfMobiusY(u, v);
		case BoundaryMode.KleinX:
			return surfKleinX(u, v);
		case BoundaryMode.KleinY:
			return surfKleinY(u, v);
		case BoundaryMode.ProjectivePlane:
			return surfProjective(u, v);
		default:
			return surfFlat(u, v, view);
	}
}

/** Surface point at the current morph blend and topology cross-fade. */
export function surfacePoint(u: number, v: number, view: EmbedView): Vec3 {
	const flat = surfFlat(u, v, view);
	if (view.embedBlend <= 0) return flat;

	let embedded: Vec3;
	if (view.topologyBlend >= 0.9999 || view.prevTopology === view.topology) {
		embedded = embeddedPointFor(u, v, view.topology, view);
	} else {
		const a = embeddedPointFor(u, v, view.prevTopology, view);
		const b = embeddedPointFor(u, v, view.topology, view);
		const t = view.topologyBlend;
		embedded = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
	}

	const e = view.embedBlend;
	return [
		flat[0] + (embedded[0] - flat[0]) * e,
		flat[1] + (embedded[1] - flat[1]) * e,
		flat[2] + (embedded[2] - flat[2]) * e
	];
}

// Sweep resolution for picking. Dense enough that every visible fold of the
// surface drops at least one sample inside the pick cone; the refinement then
// walks that sample down to the exact point. ~12k evaluations per mouse move is
// still nothing next to a frame.
const COARSE_U = 160;
const COARSE_V = 80;
const REFINE_STEPS = 6;

// Pick cone half-angle as a fraction of the vertical field of view. Roughly a
// 40px radius at a 1000px-tall viewport.
const PICK_CONE = 0.04;

/**
 * First-hit ray cast against the surface.
 *
 * Screen-space nearest-sample picking does not work here: on a torus the near
 * and far sheets project to the same pixels, so both are equally close to the
 * cursor and the winner is arbitrary - which is why the back face kept getting
 * picked. Casting a ray and keeping the smallest distance *along* it resolves
 * the sheets properly, and does so for the self-intersecting immersions too,
 * where no analytic intersection exists.
 *
 * @param origin  camera position in world space
 * @param dir     unit ray direction through the cursor
 * @returns       uv in [0,1), or null when the ray misses the surface
 */
export function pickSurfaceUV(
	origin: Vec3,
	dir: Vec3,
	tanHalfFov: number,
	view: EmbedView
): { u: number; v: number } | null {
	let bestU = -1;
	let bestV = -1;
	let bestT = Infinity;

	// Perpendicular distance from the ray, and distance along it.
	const measure = (p: Vec3): { t: number; d: number } => {
		const vx = p[0] - origin[0];
		const vy = p[1] - origin[1];
		const vz = p[2] - origin[2];
		const t = vx * dir[0] + vy * dir[1] + vz * dir[2];
		const px = vx - dir[0] * t;
		const py = vy - dir[1] * t;
		const pz = vz - dir[2] * t;
		return { t, d: Math.hypot(px, py, pz) };
	};

	// The cone widens with distance so the pick radius stays constant on screen.
	const coneRadius = (t: number) => Math.max(t, 0.05) * tanHalfFov * PICK_CONE;

	for (let i = 0; i <= COARSE_U; i++) {
		const u = i / COARSE_U;
		for (let j = 0; j <= COARSE_V; j++) {
			const v = j / COARSE_V;
			const { t, d } = measure(surfacePoint(u, v, view));
			if (t <= 0) continue; // behind the camera
			if (d > coneRadius(t)) continue; // outside the pick cone
			if (t < bestT) {
				bestT = t;
				bestU = u;
				bestV = v;
			}
		}
	}

	if (bestU < 0) return null;

	// Tighten onto the true intersection, staying on the sheet found above by
	// only accepting moves that get closer to the ray without jumping backwards.
	let radiusU = 1 / COARSE_U;
	let radiusV = 1 / COARSE_V;
	let bestD = measure(surfacePoint(bestU, bestV, view)).d;

	for (let step = 0; step < REFINE_STEPS; step++) {
		let localU = bestU;
		let localV = bestV;
		let localD = bestD;
		let localT = bestT;

		for (let i = -2; i <= 2; i++) {
			for (let j = -2; j <= 2; j++) {
				if (i === 0 && j === 0) continue;
				const u = bestU + (i * radiusU) / 2;
				const v = bestV + (j * radiusV) / 2;
				const { t, d } = measure(surfacePoint(u, v, view));
				if (t <= 0) continue;
				// Reject anything that has wandered onto a different sheet
				if (t > bestT + coneRadius(bestT)) continue;
				if (d < localD) {
					localD = d;
					localT = t;
					localU = u;
					localV = v;
				}
			}
		}

		bestU = localU;
		bestV = localV;
		bestD = localD;
		bestT = localT;
		radiusU *= 0.5;
		radiusV *= 0.5;
	}

	// Wrapping topologies can land the refinement just outside [0,1].
	return { u: bestU - Math.floor(bestU), v: bestV - Math.floor(bestV) };
}
