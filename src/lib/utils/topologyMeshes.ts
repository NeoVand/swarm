/**
 * Parametric surface generators for topology visualization
 * Each function returns a Three.js BufferGeometry
 */

import * as THREE from 'three';
import { ParametricGeometry } from 'three/addons/geometries/ParametricGeometry.js';

// Higher resolution for smooth parametric surfaces
const SLICES = 80;
const STACKS = 40;
const GRID_SLICES = 18;
const GRID_STACKS = 10;
const GRID_LINES_U = 10;
const GRID_LINES_V = 8;
const GRID_LINES_CURVE = 12;
const GRID_LINES_AXIS = 8;
const GRID_LINES_TORUS_MAJOR = 8;
const GRID_LINES_TORUS_MINOR = 6;
const GRID_LINES_MOBIUS_U = 20;
const GRID_LINES_MOBIUS_V = 4;
const GRID_LINES_KLEIN_U = 20;
const GRID_LINES_KLEIN_V = 8;
const GRID_SAMPLES = 48;

// Base color (used as fallback); per-vertex gradient is applied later
export const TOPOLOGY_COLOR = 0x7c9aff;

// Apply a circular hue gradient based on angular position to reveal folds
function colorizeGeometry(geometry: THREE.BufferGeometry): THREE.BufferGeometry {
	const position = geometry.getAttribute('position') as THREE.BufferAttribute;
	if (!position) return geometry;

	const colors = new Float32Array(position.count * 3);

	for (let i = 0; i < position.count; i++) {
		const x = position.getX(i);
		const y = position.getY(i);
		const z = position.getZ(i);

		// Hue from angle around Y axis, loop red→red
		const hue = (Math.atan2(z, x) / (2 * Math.PI) + 1) % 1;
		const sat = 0.75;
		const val = 1.0 - Math.min(0.12, Math.abs(y) * 0.02);
		const [r, g, b] = hsvToRgb(hue, sat, val);

		colors[i * 3] = r;
		colors[i * 3 + 1] = g;
		colors[i * 3 + 2] = b;
	}

	geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
	return geometry;
}

function hsvToRgb(h: number, s: number, v: number): [number, number, number] {
	const i = Math.floor(h * 6);
	const f = h * 6 - i;
	const p = v * (1 - s);
	const q = v * (1 - f * s);
	const t = v * (1 - (1 - f) * s);
	let r = 0,
		g = 0,
		b = 0;
	switch (i % 6) {
		case 0:
			r = v;
			g = t;
			b = p;
			break;
		case 1:
			r = q;
			g = v;
			b = p;
			break;
		case 2:
			r = p;
			g = v;
			b = t;
			break;
		case 3:
			r = p;
			g = q;
			b = v;
			break;
		case 4:
			r = t;
			g = p;
			b = v;
			break;
		case 5:
			r = v;
			g = p;
			b = q;
			break;
	}
	return [r, g, b];
}

function createParametricGeometry(
	func: (u: number, v: number, target: THREE.Vector3) => void,
	slices: number,
	stacks: number,
	shouldColorize: boolean
): THREE.BufferGeometry {
	const geometry = new ParametricGeometry(func, slices, stacks);
	return shouldColorize ? colorizeGeometry(geometry) : geometry;
}

function createParametricGridGeometry(
	func: (u: number, v: number, target: THREE.Vector3) => void,
	linesU: number,
	linesV: number,
	samples: number
): THREE.BufferGeometry {
	const positions: number[] = [];
	const point = new THREE.Vector3();
	const previous = new THREE.Vector3();

	const addLine = (getUV: (t: number) => { u: number; v: number }) => {
		for (let i = 0; i <= samples; i += 1) {
			const t = i / samples;
			const { u, v } = getUV(t);
			func(u, v, point);
			if (i > 0) {
				positions.push(previous.x, previous.y, previous.z, point.x, point.y, point.z);
			}
			previous.copy(point);
		}
	};

	for (let i = 0; i <= linesU; i += 1) {
		const u = i / linesU;
		addLine((t) => ({ u, v: t }));
	}

	for (let i = 0; i <= linesV; i += 1) {
		const v = i / linesV;
		addLine((t) => ({ u: t, v }));
	}

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
	return geometry;
}

function createParametricEdgeGeometry(
	func: (u: number, v: number, target: THREE.Vector3) => void,
	edges: { u?: number[]; v?: number[] },
	samples: number
): THREE.BufferGeometry {
	const positions: number[] = [];
	const point = new THREE.Vector3();
	const previous = new THREE.Vector3();

	const addEdge = (getUV: (t: number) => { u: number; v: number }) => {
		for (let i = 0; i <= samples; i += 1) {
			const t = i / samples;
			const { u, v } = getUV(t);
			func(u, v, point);
			if (i > 0) {
				positions.push(previous.x, previous.y, previous.z, point.x, point.y, point.z);
			}
			previous.copy(point);
		}
	};

	if (edges.u) {
		for (const u of edges.u) {
			addEdge((t) => ({ u, v: t }));
		}
	}
	if (edges.v) {
		for (const v of edges.v) {
			addEdge((t) => ({ u: t, v }));
		}
	}

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
	return geometry;
}

function createRoundedPlaneGeometry(
	width: number,
	height: number,
	radius: number,
	segments: number,
	shouldColorize: boolean
): THREE.BufferGeometry {
	const w = width / 2;
	const h = height / 2;
	const r = Math.min(radius, w, h);

	const shape = new THREE.Shape();
	shape.moveTo(-w + r, -h);
	shape.lineTo(w - r, -h);
	shape.quadraticCurveTo(w, -h, w, -h + r);
	shape.lineTo(w, h - r);
	shape.quadraticCurveTo(w, h, w - r, h);
	shape.lineTo(-w + r, h);
	shape.quadraticCurveTo(-w, h, -w, h - r);
	shape.lineTo(-w, -h + r);
	shape.quadraticCurveTo(-w, -h, -w + r, -h);

	const geometry = new THREE.ShapeGeometry(shape, segments);
	geometry.rotateX(-Math.PI * 0.15);
	return shouldColorize ? colorizeGeometry(geometry) : geometry;
}

function createRoundedPlaneGridGeometry(
	width: number,
	height: number,
	radius: number,
	linesX: number,
	linesY: number,
	samples: number
): THREE.BufferGeometry {
	const w = width / 2;
	const h = height / 2;
	const r = Math.min(radius, w, h);
	const innerW = w - r;
	const innerH = h - r;
	const positions: number[] = [];

	const addLine = (getPoint: (t: number) => THREE.Vector3) => {
		let prev: THREE.Vector3 | null = null;
		for (let i = 0; i <= samples; i += 1) {
			const t = i / samples;
			const p = getPoint(t);
			if (prev) {
				positions.push(prev.x, prev.y, prev.z, p.x, p.y, p.z);
			}
			prev = p;
		}
	};

	const getYExtent = (x: number) => {
		const ax = Math.abs(x);
		if (ax <= innerW) return h;
		const dx = Math.min(r, Math.max(0, ax - innerW));
		return innerH + Math.sqrt(Math.max(0, r * r - dx * dx));
	};

	const getXExtent = (y: number) => {
		const ay = Math.abs(y);
		if (ay <= innerH) return w;
		const dy = Math.min(r, Math.max(0, ay - innerH));
		return innerW + Math.sqrt(Math.max(0, r * r - dy * dy));
	};

	for (let i = 0; i <= linesX; i += 1) {
		const x = -w + (i / linesX) * (w * 2);
		const yMax = getYExtent(x);
		addLine((t) => new THREE.Vector3(x, -yMax + t * (yMax * 2), 0));
	}

	for (let i = 0; i <= linesY; i += 1) {
		const y = -h + (i / linesY) * (h * 2);
		const xMax = getXExtent(y);
		addLine((t) => new THREE.Vector3(-xMax + t * (xMax * 2), y, 0));
	}

	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
	geometry.rotateX(-Math.PI * 0.15);
	return geometry;
}

function createRoundedPlaneEdgeGeometry(
	width: number,
	height: number,
	radius: number,
	segments: number
): THREE.BufferGeometry {
	const w = width / 2;
	const h = height / 2;
	const r = Math.min(radius, w, h);
	const shape = new THREE.Shape();
	shape.moveTo(-w + r, -h);
	shape.lineTo(w - r, -h);
	shape.quadraticCurveTo(w, -h, w, -h + r);
	shape.lineTo(w, h - r);
	shape.quadraticCurveTo(w, h, w - r, h);
	shape.lineTo(-w + r, h);
	shape.quadraticCurveTo(-w, h, -w, h - r);
	shape.lineTo(-w, -h + r);
	shape.quadraticCurveTo(-w, -h, -w + r, -h);

	const points = shape.getPoints(segments);
	const positions: number[] = [];
	for (let i = 1; i < points.length; i += 1) {
		const a = points[i - 1];
		const b = points[i];
		positions.push(a.x, a.y, 0, b.x, b.y, 0);
	}
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
	geometry.rotateX(-Math.PI * 0.15);
	return geometry;
}

/**
 * Plane - flat rectangular surface with slight 3D tilt
 * Represents a bounded box with bouncy edges
 */
export function createPlaneGeometry(): THREE.BufferGeometry {
	return createRoundedPlaneGeometry(1.4, 1.05, 0.16, 24, true);
}

/**
 * Cylinder X - tube that wraps horizontally
 * Open ends to show it's not a closed surface on Y axis
 */
export function createCylinderXGeometry(): THREE.BufferGeometry {
	const R = 0.5; // Radius
	const height = 1.2; // Height

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const V = (v - 0.5) * height;

		target.set(Math.cos(U) * R, V, Math.sin(U) * R);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Cylinder Y - tube that wraps vertically
 * Rotated 90 degrees from Cylinder X
 */
export function createCylinderYGeometry(): THREE.BufferGeometry {
	const R = 0.5;
	const height = 1.2;

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const V = (v - 0.5) * height;

		// Rotated to wrap vertically
		target.set(V, Math.cos(U) * R, Math.sin(U) * R);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Torus - classic donut shape
 * R/r ratio tuned for nice visible hole
 */
export function createTorusGeometry(): THREE.BufferGeometry {
	const R = 0.6; // Major radius (center to tube center)
	const r = 0.22; // Minor radius (tube thickness) - R/r ~2.7 for nice hole

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const V = v * Math.PI * 2;

		const x = (R + r * Math.cos(V)) * Math.cos(U);
		const y = (R + r * Math.cos(V)) * Math.sin(U);
		const z = r * Math.sin(V);

		target.set(x, z, y); // Reorder for nice viewing angle
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Mobius Strip X - half-twisted strip (wraps horizontally with Y flip)
 * The U/2 term creates the characteristic half-twist
 */
export function createMobiusXGeometry(): THREE.BufferGeometry {
	const R = 0.55; // Center circle radius
	const w = 0.25; // Half-width of strip

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const S = (v - 0.5) * 2 * w; // S in [-w, w]

		const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
		const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
		const z = S * Math.sin(U / 2);

		target.set(x, z, y);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Mobius Strip Y - rotated version (wraps vertically with X flip)
 */
export function createMobiusYGeometry(): THREE.BufferGeometry {
	const R = 0.55;
	const w = 0.25;

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const S = (v - 0.5) * 2 * w;

		const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
		const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
		const z = S * Math.sin(U / 2);

		// Rotated 90 degrees for Y variant
		target.set(z, x, y);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Klein Bottle X - Classic "bottle" immersion (Wikipedia/Dickson piecewise)
 * The recognizable Klein bottle shape with neck passing through the side
 */
export function createKleinXGeometry(): THREE.BufferGeometry {
	const scale = 0.04; // Scale to fit viewport

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const V = v * Math.PI * 2;

		const cosU = Math.cos(U);
		const sinU = Math.sin(U);
		const cosV = Math.cos(V);
		const sinV = Math.sin(V);
		const c = 1 - 0.5 * cosU;

		let x: number, y: number, z: number;

		if (U <= Math.PI) {
			x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
			y = 16 * sinU + 4 * c * sinU * cosV;
		} else {
			x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
			y = 16 * sinU;
		}
		z = 4 * c * sinV;

		// Scale and center
		target.set(x * scale, z * scale, (y - 8) * scale);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Klein Bottle Y - rotated classic bottle immersion
 */
export function createKleinYGeometry(): THREE.BufferGeometry {
	const scale = 0.04;

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const U = u * Math.PI * 2;
		const V = v * Math.PI * 2;

		const cosU = Math.cos(U);
		const sinU = Math.sin(U);
		const cosV = Math.cos(V);
		const sinV = Math.sin(V);
		const c = 1 - 0.5 * cosU;

		let x: number, y: number, z: number;

		if (U <= Math.PI) {
			x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
			y = 16 * sinU + 4 * c * sinU * cosV;
		} else {
			x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
			y = 16 * sinU;
		}
		z = 4 * c * sinV;

		// Rotated for Y variant and scaled
		target.set(z * scale, x * scale, (y - 8) * scale);
	};

	return createParametricGeometry(func, SLICES, STACKS, true);
}

/**
 * Projective Plane - Roman (Steiner) Surface
 * Beautiful self-intersecting surface with tetrahedral symmetry
 * 4 lobes meeting at a triple point at origin
 */
export function createProjectivePlaneGeometry(): THREE.BufferGeometry {
	const scale = 0.9;

	const func = (u: number, v: number, target: THREE.Vector3) => {
		const theta = u * Math.PI; // Latitude [0, π]
		const phi = v * Math.PI * 2; // Longitude [0, 2π]

		const cosTheta = Math.cos(theta);
		const sinTheta = Math.sin(theta);
		const cosPhi = Math.cos(phi);
		const sinPhi = Math.sin(phi);

		// Roman surface parametric equations
		const x = cosTheta * sinTheta * sinPhi * scale;
		const y = cosTheta * sinTheta * cosPhi * scale;
		const z = cosTheta * cosTheta * cosPhi * sinPhi * scale;

		target.set(x, z, y);
	};

	return colorizeGeometry(new ParametricGeometry(func, SLICES, STACKS));
}

/**
 * Get geometry for a given boundary mode
 */
export function getTopologyGeometry(mode: number): THREE.BufferGeometry {
	switch (mode) {
		case 0:
			return createPlaneGeometry();
		case 1:
			return createCylinderXGeometry();
		case 2:
			return createCylinderYGeometry();
		case 3:
			return createTorusGeometry();
		case 4:
			return createMobiusXGeometry();
		case 5:
			return createMobiusYGeometry();
		case 6:
			return createKleinXGeometry();
		case 7:
			return createKleinYGeometry();
		case 8:
			return createProjectivePlaneGeometry();
		default:
			return createTorusGeometry();
	}
}

export function getTopologyGridGeometry(mode: number): THREE.BufferGeometry {
	switch (mode) {
		case 0: {
			return createRoundedPlaneGridGeometry(1.4, 1.05, 0.16, 10, 10, GRID_SAMPLES);
		}
		case 1: {
			const R = 0.5;
			const height = 1.2;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = (v - 0.5) * height;
				target.set(Math.cos(U) * R, V, Math.sin(U) * R);
			};
			return createParametricGridGeometry(func, GRID_LINES_CURVE, GRID_LINES_AXIS, GRID_SAMPLES);
		}
		case 2: {
			const R = 0.5;
			const height = 1.2;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = (v - 0.5) * height;
				target.set(V, Math.cos(U) * R, Math.sin(U) * R);
			};
			return createParametricGridGeometry(func, GRID_LINES_CURVE, GRID_LINES_AXIS, GRID_SAMPLES);
		}
		case 3: {
			const R = 0.6;
			const r = 0.22;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const x = (R + r * Math.cos(V)) * Math.cos(U);
				const y = (R + r * Math.cos(V)) * Math.sin(U);
				const z = r * Math.sin(V);
				target.set(x, z, y);
			};
			return createParametricGridGeometry(
				func,
				GRID_LINES_TORUS_MAJOR,
				GRID_LINES_TORUS_MINOR,
				GRID_SAMPLES
			);
		}
		case 4: {
			const R = 0.55;
			const w = 0.25;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const S = (v - 0.5) * 2 * w;
				const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
				const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
				const z = S * Math.sin(U / 2);
				target.set(x, z, y);
			};
			return createParametricGridGeometry(
				func,
				GRID_LINES_MOBIUS_U,
				GRID_LINES_MOBIUS_V,
				GRID_SAMPLES
			);
		}
		case 5: {
			const R = 0.55;
			const w = 0.25;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const S = (v - 0.5) * 2 * w;
				const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
				const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
				const z = S * Math.sin(U / 2);
				target.set(z, x, y);
			};
			return createParametricGridGeometry(
				func,
				GRID_LINES_MOBIUS_U,
				GRID_LINES_MOBIUS_V,
				GRID_SAMPLES
			);
		}
		case 6: {
			const scale = 0.04;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const cosU = Math.cos(U);
				const sinU = Math.sin(U);
				const cosV = Math.cos(V);
				const sinV = Math.sin(V);
				const c = 1 - 0.5 * cosU;
				let x: number, y: number, z: number;
				if (U <= Math.PI) {
					x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
					y = 16 * sinU + 4 * c * sinU * cosV;
				} else {
					x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
					y = 16 * sinU;
				}
				z = 4 * c * sinV;
				target.set(x * scale, z * scale, (y - 8) * scale);
			};
			return createParametricGridGeometry(
				func,
				GRID_LINES_KLEIN_U,
				GRID_LINES_KLEIN_V,
				GRID_SAMPLES
			);
		}
		case 7: {
			const scale = 0.04;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const cosU = Math.cos(U);
				const sinU = Math.sin(U);
				const cosV = Math.cos(V);
				const sinV = Math.sin(V);
				const c = 1 - 0.5 * cosU;
				let x: number, y: number, z: number;
				if (U <= Math.PI) {
					x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
					y = 16 * sinU + 4 * c * sinU * cosV;
				} else {
					x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
					y = 16 * sinU;
				}
				z = 4 * c * sinV;
				target.set(z * scale, x * scale, (y - 8) * scale);
			};
			return createParametricGridGeometry(
				func,
				GRID_LINES_KLEIN_U,
				GRID_LINES_KLEIN_V,
				GRID_SAMPLES
			);
		}
		case 8: {
			const scale = 0.9;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const theta = u * Math.PI;
				const phi = v * Math.PI * 2;
				const cosTheta = Math.cos(theta);
				const sinTheta = Math.sin(theta);
				const cosPhi = Math.cos(phi);
				const sinPhi = Math.sin(phi);
				const x = cosTheta * sinTheta * sinPhi * scale;
				const y = cosTheta * sinTheta * cosPhi * scale;
				const z = cosTheta * cosTheta * cosPhi * sinPhi * scale;
				target.set(x, z, y);
			};
			return createParametricGridGeometry(func, 10, 10, GRID_SAMPLES);
		}
		default:
			return createRoundedPlaneGeometry(1.4, 1.05, 0.16, 8, false);
	}
}

export function getTopologyEdgeGeometries(mode: number): {
	free: THREE.BufferGeometry | null;
	stitch: THREE.BufferGeometry | null;
} {
	switch (mode) {
		case 0:
			return { free: createRoundedPlaneEdgeGeometry(1.4, 1.05, 0.16, 48), stitch: null };
		case 1: {
			const R = 0.5;
			const height = 1.2;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = (v - 0.5) * height;
				target.set(Math.cos(U) * R, V, Math.sin(U) * R);
			};
			return {
				free: createParametricEdgeGeometry(func, { v: [0, 1] }, GRID_SAMPLES),
				stitch: createParametricEdgeGeometry(func, { u: [0] }, GRID_SAMPLES)
			};
		}
		case 2: {
			const R = 0.5;
			const height = 1.2;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = (v - 0.5) * height;
				target.set(V, Math.cos(U) * R, Math.sin(U) * R);
			};
			return {
				free: createParametricEdgeGeometry(func, { v: [0, 1] }, GRID_SAMPLES),
				stitch: createParametricEdgeGeometry(func, { u: [0] }, GRID_SAMPLES)
			};
		}
		case 3: {
			const R = 0.6;
			const r = 0.22;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const x = (R + r * Math.cos(V)) * Math.cos(U);
				const y = (R + r * Math.cos(V)) * Math.sin(U);
				const z = r * Math.sin(V);
				target.set(x, z, y);
			};
			return {
				free: null,
				stitch: createParametricEdgeGeometry(func, { u: [0], v: [0] }, GRID_SAMPLES)
			};
		}
		case 4: {
			const R = 0.55;
			const w = 0.25;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const S = (v - 0.5) * 2 * w;
				const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
				const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
				const z = S * Math.sin(U / 2);
				target.set(x, z, y);
			};
			return {
				free: createParametricEdgeGeometry(func, { v: [0, 1] }, GRID_SAMPLES),
				stitch: createParametricEdgeGeometry(func, { u: [0] }, GRID_SAMPLES)
			};
		}
		case 5: {
			const R = 0.55;
			const w = 0.25;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const S = (v - 0.5) * 2 * w;
				const x = (R + S * Math.cos(U / 2)) * Math.cos(U);
				const y = (R + S * Math.cos(U / 2)) * Math.sin(U);
				const z = S * Math.sin(U / 2);
				target.set(z, x, y);
			};
			return {
				free: createParametricEdgeGeometry(func, { v: [0, 1] }, GRID_SAMPLES),
				stitch: createParametricEdgeGeometry(func, { u: [0] }, GRID_SAMPLES)
			};
		}
		case 6: {
			const scale = 0.04;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const cosU = Math.cos(U);
				const sinU = Math.sin(U);
				const cosV = Math.cos(V);
				const sinV = Math.sin(V);
				const c = 1 - 0.5 * cosU;
				let x: number, y: number, z: number;
				if (U <= Math.PI) {
					x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
					y = 16 * sinU + 4 * c * sinU * cosV;
				} else {
					x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
					y = 16 * sinU;
				}
				z = 4 * c * sinV;
				target.set(x * scale, z * scale, (y - 8) * scale);
			};
			return {
				free: null,
				stitch: createParametricEdgeGeometry(func, { u: [0], v: [0] }, GRID_SAMPLES)
			};
		}
		case 7: {
			const scale = 0.04;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const U = u * Math.PI * 2;
				const V = v * Math.PI * 2;
				const cosU = Math.cos(U);
				const sinU = Math.sin(U);
				const cosV = Math.cos(V);
				const sinV = Math.sin(V);
				const c = 1 - 0.5 * cosU;
				let x: number, y: number, z: number;
				if (U <= Math.PI) {
					x = 6 * cosU * (1 + sinU) + 4 * c * cosU * cosV;
					y = 16 * sinU + 4 * c * sinU * cosV;
				} else {
					x = 6 * cosU * (1 + sinU) + 4 * c * Math.cos(V + Math.PI);
					y = 16 * sinU;
				}
				z = 4 * c * sinV;
				target.set(z * scale, x * scale, (y - 8) * scale);
			};
			return {
				free: null,
				stitch: createParametricEdgeGeometry(func, { u: [0], v: [0] }, GRID_SAMPLES)
			};
		}
		case 8: {
			const scale = 0.9;
			const func = (u: number, v: number, target: THREE.Vector3) => {
				const theta = u * Math.PI;
				const phi = v * Math.PI * 2;
				const cosTheta = Math.cos(theta);
				const sinTheta = Math.sin(theta);
				const cosPhi = Math.cos(phi);
				const sinPhi = Math.sin(phi);
				const x = cosTheta * sinTheta * sinPhi * scale;
				const y = cosTheta * sinTheta * cosPhi * scale;
				const z = cosTheta * cosTheta * cosPhi * sinPhi * scale;
				target.set(x, z, y);
			};
			return {
				free: null,
				stitch: createParametricEdgeGeometry(func, { u: [0], v: [0] }, GRID_SAMPLES)
			};
		}
		default:
			return { free: null, stitch: null };
	}
}

/**
 * Get color for topology - unified elegant color
 */
export function getTopologyColor(_mode: number): number {
	return TOPOLOGY_COLOR;
}

/**
 * Topology names for display
 */
export const TOPOLOGY_NAMES = [
	'Plane',
	'Cylinder X',
	'Cylinder Y',
	'Torus',
	'Möbius X',
	'Möbius Y',
	'Klein X',
	'Klein Y',
	'Projective Plane'
];
