// Orbit camera for the embedded 3D topology view.
//
// The simulation domain is always the flat rectangle; embedded mode re-projects
// it onto the surface it topologically represents. This camera orbits that
// surface. Matrix helpers are hand-rolled to keep the WebGPU layer free of
// dependencies - three.js is only used for the topology picker thumbnails.

export type Vec3 = [number, number, number];

export interface OrbitCamera {
	azimuth: number; // Horizontal angle in radians
	elevation: number; // Vertical angle in radians, clamped away from the poles
	distance: number; // Distance from the target
	target: [number, number, number];
	fov: number; // Vertical field of view in radians
	/**
	 * Pan as a shift of the projected image rather than of the orbit pivot,
	 * expressed in NDC (2 units spans the viewport height).
	 *
	 * Moving the pivot is the usual CAD behaviour, but here there is a single
	 * object at the origin: sliding the pivot off it makes orbiting swing the
	 * shape around an empty point in space instead of spinning it in place,
	 * which is very visible with auto-rotate on. Offsetting the projection
	 * keeps the pivot on the shape and just slides the picture.
	 */
	panX: number;
	panY: number;
}

// Half-extent of the flat domain in world units. Chosen to sit in the same size
// range as the parametric shapes in topologyMeshes.ts (~1.2-1.5 across) so the
// morph between flat and embedded doesn't jump in scale.
export const PLANE_HALF_WIDTH = 0.7;

// Elevation is clamped just short of vertical to avoid a degenerate up vector.
const MAX_ELEVATION = Math.PI / 2 - 0.02;

export const MIN_DISTANCE = 0.6;
export const MAX_DISTANCE = 12;

/** Half-extents of the flat domain, preserving the canvas aspect ratio. */
export function planeHalfExtents(
	canvasWidth: number,
	canvasHeight: number
): { halfWidth: number; halfHeight: number } {
	const aspect = canvasWidth / Math.max(canvasHeight, 1);
	return { halfWidth: PLANE_HALF_WIDTH, halfHeight: PLANE_HALF_WIDTH / Math.max(aspect, 0.0001) };
}

/**
 * Distance at which the flat plane exactly fills the viewport.
 *
 * At blend 0 the embedded view shows the flat rectangle, so starting the camera
 * here makes entering embedded mode continuous with the 2D view - the morph
 * appears to unfold from exactly what was already on screen.
 */
export function fitDistance(canvasWidth: number, canvasHeight: number, fov: number): number {
	const { halfWidth, halfHeight } = planeHalfExtents(canvasWidth, canvasHeight);
	const aspect = canvasWidth / Math.max(canvasHeight, 1);
	// Fit vertically, then check the horizontal constraint for narrow viewports.
	const distV = halfHeight / Math.tan(fov / 2);
	const distH = halfWidth / (Math.tan(fov / 2) * aspect);
	return Math.max(distV, distH);
}

// Largest bounding radius across the parametric shapes in topologyMeshes.ts
// (torus R+r = 0.82 is the widest), plus margin so nothing clips at the edges.
export const SHAPE_BOUNDING_RADIUS = 0.95;

/**
 * Distance at which a sphere of the given radius fits the viewport. Uses the
 * narrower of the vertical and horizontal fields of view so the shape fits in
 * both directions, including on tall/narrow phone viewports.
 */
export function fitDistanceForRadius(
	radius: number,
	canvasWidth: number,
	canvasHeight: number,
	fov: number
): number {
	const aspect = canvasWidth / Math.max(canvasHeight, 1);
	const halfV = fov / 2;
	const halfH = Math.atan(Math.tan(halfV) * aspect);
	return radius / Math.sin(Math.min(halfV, halfH));
}

export function createOrbitCamera(canvasWidth: number, canvasHeight: number): OrbitCamera {
	const fov = (50 * Math.PI) / 180;
	return {
		azimuth: 0,
		elevation: 0,
		distance: fitDistance(canvasWidth, canvasHeight, fov),
		target: [0, 0, 0],
		fov,
		panX: 0,
		panY: 0
	};
}

/** Camera eye position in world space, derived from the orbit angles. */
export function cameraEye(camera: OrbitCamera): [number, number, number] {
	const cosE = Math.cos(camera.elevation);
	return [
		camera.target[0] + camera.distance * cosE * Math.sin(camera.azimuth),
		camera.target[1] + camera.distance * Math.sin(camera.elevation),
		camera.target[2] + camera.distance * cosE * Math.cos(camera.azimuth)
	];
}

export function orbit(camera: OrbitCamera, deltaX: number, deltaY: number): void {
	camera.azimuth -= deltaX;
	camera.elevation = Math.max(-MAX_ELEVATION, Math.min(MAX_ELEVATION, camera.elevation + deltaY));
}

export function zoom(camera: OrbitCamera, factor: number): void {
	camera.distance = Math.max(MIN_DISTANCE, Math.min(MAX_DISTANCE, camera.distance * factor));
}

/**
 * Slide the orbit target across the view plane.
 *
 * Deltas are fractions of the viewport height, scaled by distance so a drag
 * moves the surface the same amount under the pointer at any zoom level.
 */
export function pan(camera: OrbitCamera, deltaX: number, deltaY: number): void {
	// Deltas arrive as fractions of the viewport height; NDC spans 2 over that
	// height. Screen y runs downward, so a downward drag lowers the image.
	camera.panX += deltaX * 2;
	camera.panY -= deltaY * 2;
}

/** Clear the pan offset without disturbing the orbit angles or zoom. */
export function resetPan(camera: OrbitCamera): void {
	camera.panX = 0;
	camera.panY = 0;
}

/** Orthonormal camera basis: forward (toward target), right, up. */
export function cameraBasis(camera: OrbitCamera): {
	forward: Vec3;
	right: Vec3;
	up: Vec3;
} {
	const eye = cameraEye(camera);
	let fx = camera.target[0] - eye[0];
	let fy = camera.target[1] - eye[1];
	let fz = camera.target[2] - eye[2];
	const fLen = Math.hypot(fx, fy, fz) || 1;
	fx /= fLen;
	fy /= fLen;
	fz /= fLen;

	let rx = fy * 0 - fz * 1;
	let ry = fz * 0 - fx * 0;
	let rz = fx * 1 - fy * 0;
	const rLen = Math.hypot(rx, ry, rz) || 1;
	rx /= rLen;
	ry /= rLen;
	rz /= rLen;

	return {
		forward: [fx, fy, fz],
		right: [rx, ry, rz],
		up: [ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx]
	};
}

/**
 * World-space ray through a normalised device coordinate, for picking.
 * `tanHalfFov` is returned too so callers can size a screen-space pick radius
 * that stays constant in pixels regardless of distance.
 */
export function rayThrough(
	camera: OrbitCamera,
	ndcX: number,
	ndcY: number,
	aspect: number
): { origin: Vec3; dir: Vec3; tanHalfFov: number } {
	const { forward, right, up } = cameraBasis(camera);
	const origin = cameraEye(camera);
	const t = Math.tan(camera.fov / 2);

	// Back out the pan, which shifts the image after projection: a cursor at
	// screen ndcX corresponds to unshifted ndcX - panX. Skipping this would make
	// picking drift away from the pointer by exactly the pan amount.
	const sx = (ndcX - camera.panX / aspect) * t * aspect;
	const sy = (ndcY - camera.panY) * t;

	let dx = forward[0] + right[0] * sx + up[0] * sy;
	let dy = forward[1] + right[1] * sx + up[1] * sy;
	let dz = forward[2] + right[2] * sx + up[2] * sy;
	const len = Math.hypot(dx, dy, dz) || 1;
	dx /= len;
	dy /= len;
	dz /= len;

	return { origin, dir: [dx, dy, dz], tanHalfFov: t };
}

/**
 * Build the view-projection matrix in column-major order, ready to upload as a
 * WGSL mat4x4<f32>. Uses WebGPU's [0,1] depth range (not OpenGL's [-1,1]).
 */
export function viewProjectionMatrix(
	camera: OrbitCamera,
	canvasWidth: number,
	canvasHeight: number
): Float32Array {
	const eye = cameraEye(camera);
	const aspect = canvasWidth / Math.max(canvasHeight, 1);

	// --- View matrix (look-at) ---
	let fx = camera.target[0] - eye[0];
	let fy = camera.target[1] - eye[1];
	let fz = camera.target[2] - eye[2];
	const fLen = Math.hypot(fx, fy, fz) || 1;
	fx /= fLen;
	fy /= fLen;
	fz /= fLen;

	// right = normalize(cross(forward, worldUp))
	const worldUp: [number, number, number] = [0, 1, 0];
	let rx = fy * worldUp[2] - fz * worldUp[1];
	let ry = fz * worldUp[0] - fx * worldUp[2];
	let rz = fx * worldUp[1] - fy * worldUp[0];
	const rLen = Math.hypot(rx, ry, rz) || 1;
	rx /= rLen;
	ry /= rLen;
	rz /= rLen;

	// up = cross(right, forward)
	const ux = ry * fz - rz * fy;
	const uy = rz * fx - rx * fz;
	const uz = rx * fy - ry * fx;

	// --- Perspective projection (depth in [0,1]) ---
	// Tight near/far around the ~1-3 unit shapes keeps depth precision high.
	const near = 0.05;
	const far = 50;
	const f = 1 / Math.tan(camera.fov / 2);
	const nf = 1 / (near - far);

	// p = proj * view, computed directly to avoid an intermediate allocation.
	// view rows are (right, up, -forward) with translations -dot(axis, eye).
	const tx = -(rx * eye[0] + ry * eye[1] + rz * eye[2]);
	const ty = -(ux * eye[0] + uy * eye[1] + uz * eye[2]);
	const tz = fx * eye[0] + fy * eye[1] + fz * eye[2];

	const sx = f / aspect;
	const sy = f;
	const a = far * nf; // depth scale
	const b = far * near * nf; // depth bias

	// Column-major: element [col * 4 + row].
	// Row 3 is -(view row 2), so w_clip is the positive distance in front of the
	// camera; getting this sign wrong makes every vertex fail the clip test.
	const m = new Float32Array([
		// column 0
		sx * rx,
		sy * ux,
		a * -fx,
		fx,
		// column 1
		sx * ry,
		sy * uy,
		a * -fy,
		fy,
		// column 2
		sx * rz,
		sy * uz,
		a * -fz,
		fz,
		// column 3
		sx * tx,
		sy * ty,
		a * tz + b,
		-tz
	]);

	// Pan as an off-axis projection shift: clip.xy += pan * clip.w, i.e. add a
	// multiple of the w row into the x and y rows. This slides the image without
	// touching the eye or the pivot, so orbiting still spins the shape about
	// itself no matter how far the view has been panned.
	const ox = camera.panX / aspect;
	const oy = camera.panY;
	if (ox !== 0 || oy !== 0) {
		m[0] += ox * m[3];
		m[4] += ox * m[7];
		m[8] += ox * m[11];
		m[12] += ox * m[15];
		m[1] += oy * m[3];
		m[5] += oy * m[7];
		m[9] += oy * m[11];
		m[13] += oy * m[15];
	}

	return m;
}
