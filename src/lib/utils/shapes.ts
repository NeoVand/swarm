// Shared shape path generation for SVG icons

import { HeadShape } from '$lib/webgpu/types';

/**
 * Generate an SVG path for a boid head shape
 * @param shape - The HeadShape enum value
 * @param cx - Center X coordinate
 * @param cy - Center Y coordinate
 * @param size - Size/radius of the shape
 * @returns SVG path string
 */
export function getShapePath(shape: HeadShape, cx: number, cy: number, size: number): string {
	const s = size;

	// Generate regular polygon with first vertex pointing right
	const polygon = (sides: number): string => {
		const points: string[] = [];
		for (let i = 0; i < sides; i++) {
			const angle = (2 * Math.PI * i) / sides;
			points.push(`${cx + Math.cos(angle) * s},${cy + Math.sin(angle) * s}`);
		}
		return `M ${points.join(' L ')} Z`;
	};

	switch (shape) {
		case HeadShape.Triangle:
			return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
		case HeadShape.Square:
			return `M ${cx + s} ${cy} L ${cx} ${cy + s} L ${cx - s} ${cy} L ${cx} ${cy - s} Z`;
		case HeadShape.Pentagon:
			return polygon(5);
		case HeadShape.Hexagon:
			return polygon(6);
		case HeadShape.Arrow:
			return `M ${cx + s} ${cy} L ${cx - s * 0.5} ${cy + s * 0.6} L ${cx - s * 0.2} ${cy} L ${cx - s * 0.5} ${cy - s * 0.6} Z`;
		default:
			return `M ${cx + s} ${cy} L ${cx - s * 0.7} ${cy + s * 0.5} L ${cx - s * 0.7} ${cy - s * 0.5} Z`;
	}
}
