import {
	DEFAULT_PARAMS,
	createDefaultSpecies,
	BoundaryMode,
	ColorMode,
	ColorSpectrum,
	InteractionBehavior as Behavior,
	CursorResponse,
	VortexDirection,
	type Species,
	type SimulationParams
} from '../webgpu/types';
import type { Scene } from './format';

function species(id: number, population: number, changes: Partial<Species>): Species {
	return {
		...createDefaultSpecies(id, population),
		cursorResponse: CursorResponse.Repel,
		cursorVortex: VortexDirection.Off,
		interactions: [],
		...changes
	};
}

function preset(
	id: string,
	name: string,
	description: string,
	flock: Species[],
	changes: Partial<SimulationParams>
): Scene {
	return {
		version: 1,
		id: `builtin-${id}`,
		name,
		description,
		createdAt: '2026-01-01T00:00:00.000Z',
		params: {
			...structuredClone(DEFAULT_PARAMS),
			brightnessSource: ColorMode.None,
			enableInfluence: true,
			species: flock,
			population: flock.reduce((sum, s) => sum + s.population, 0),
			activeSpeciesId: flock[0].id,
			...changes
		}
	};
}

/** Small, contrasting starting points. Loading restarts particles with these rules. */
export const BUILTIN_SCENES: Scene[] = [
	preset(
		'murmuration',
		'Murmuration',
		'One silver flock. Strong alignment turns local decisions into sweeping waves.',
		[
			species(0, 3600, {
				name: 'Starlings',
				hue: 210,
				saturation: 25,
				lightness: 80,
				alignment: 2.4,
				cohesion: 0.35,
				separation: 1.6,
				perception: 95,
				trailLength: 12,
				size: 1.1,
				rebels: 0.005
			})
		],
		{
			boundaryMode: BoundaryMode.Torus,
			colorMode: ColorMode.Orientation,
			colorSpectrum: ColorSpectrum.Chrome,
			noise: 0.015
		}
	),
	preset(
		'open-water',
		'Open Water',
		'A large school evades a few hunters. Chase and flee create a restless two-species dance.',
		[
			species(0, 3200, {
				name: 'School',
				hue: 188,
				saturation: 85,
				lightness: 60,
				alignment: 1.8,
				cohesion: 0.8,
				trailLength: 18,
				interactions: [{ targetSpecies: 1, behavior: Behavior.Flee, strength: 0.9, range: 140 }]
			}),
			species(1, 80, {
				name: 'Hunters',
				hue: 22,
				saturation: 95,
				lightness: 62,
				headShape: 4,
				size: 2.2,
				alignment: 0.2,
				cohesion: 0.1,
				separation: 2.4,
				trailLength: 30,
				rebels: 0,
				interactions: [{ targetSpecies: 0, behavior: Behavior.Chase, strength: 0.85, range: 160 }]
			})
		],
		{
			boundaryMode: BoundaryMode.Plane,
			colorMode: ColorMode.Species,
			maxSpeed: 5,
			globalCollision: 0.25
		}
	),
	preset(
		'satellites',
		'Satellites',
		'Golden escorts orbit a violet colony, balancing attraction with room to move.',
		[
			species(0, 1800, {
				name: 'Colony',
				hue: 267,
				saturation: 70,
				lightness: 70,
				alignment: 1.5,
				cohesion: 1.3,
				separation: 1.8,
				trailLength: 15
			}),
			species(1, 1100, {
				name: 'Escorts',
				hue: 46,
				saturation: 95,
				lightness: 63,
				alignment: 0.5,
				cohesion: 0.3,
				separation: 1.4,
				trailLength: 35,
				cursorResponse: CursorResponse.Attract,
				cursorVortex: VortexDirection.Clockwise,
				interactions: [{ targetSpecies: 0, behavior: Behavior.Orbit, strength: 0.8, range: 180 }]
			})
		],
		{
			boundaryMode: BoundaryMode.Torus,
			colorMode: ColorMode.Species,
			maxSpeed: 3.5,
			globalCollision: 0.15
		}
	),
	preset(
		'cross-currents',
		'Cross Currents',
		'Three colonies mirror and follow one another, weaving bright intersecting streams.',
		[
			species(0, 1200, {
				name: 'Coral',
				hue: 350,
				saturation: 88,
				lightness: 65,
				alignment: 1.9,
				cohesion: 0.25,
				trailLength: 30,
				interactions: [{ targetSpecies: 1, behavior: Behavior.Mirror, strength: 0.7, range: 130 }]
			}),
			species(1, 1200, {
				name: 'Azure',
				hue: 198,
				saturation: 92,
				lightness: 62,
				alignment: 1.9,
				cohesion: 0.25,
				trailLength: 30,
				interactions: [{ targetSpecies: 2, behavior: Behavior.Follow, strength: 0.65, range: 120 }]
			}),
			species(2, 1200, {
				name: 'Amber',
				hue: 40,
				saturation: 94,
				lightness: 62,
				alignment: 1.9,
				cohesion: 0.25,
				trailLength: 30,
				interactions: [{ targetSpecies: 0, behavior: Behavior.Mirror, strength: 0.7, range: 130 }]
			})
		],
		{
			boundaryMode: BoundaryMode.CylinderX,
			colorMode: ColorMode.Species,
			maxSpeed: 5,
			globalCollision: 0.1,
			noise: 0.025
		}
	),
	preset(
		'one-sided',
		'One-Sided World',
		'Follow a turquoise flock around a Möbius strip and watch its route return with a twist.',
		[
			species(0, 2600, {
				name: 'Wanderers',
				hue: 174,
				saturation: 80,
				lightness: 63,
				alignment: 2,
				cohesion: 0.35,
				separation: 1.7,
				perception: 70,
				trailLength: 25,
				rebels: 0.01
			})
		],
		{
			boundaryMode: BoundaryMode.MobiusX,
			embedded3D: true,
			embedShowGrid: true,
			embedAutoRotate: true,
			colorMode: ColorMode.Orientation,
			colorSpectrum: ColorSpectrum.Ocean,
			maxSpeed: 3,
			noise: 0.01
		}
	),
	preset(
		'klein-currents',
		'Klein Currents',
		'Rose spirals and jade guardians follow a looping current through a Klein bottle.',
		[
			species(0, 1800, {
				name: 'Spirals',
				hue: 332,
				saturation: 85,
				lightness: 66,
				alignment: 0.8,
				cohesion: 0.45,
				separation: 1.8,
				trailLength: 32,
				interactions: [{ targetSpecies: 1, behavior: Behavior.Spiral, strength: 0.55, range: 130 }]
			}),
			species(1, 1200, {
				name: 'Guardians',
				hue: 150,
				saturation: 72,
				lightness: 63,
				alignment: 1.7,
				cohesion: 0.75,
				separation: 1.5,
				trailLength: 18,
				interactions: [{ targetSpecies: 0, behavior: Behavior.Guard, strength: 0.45, range: 110 }]
			})
		],
		{
			boundaryMode: BoundaryMode.KleinX,
			embedded3D: true,
			embedShowGrid: true,
			colorMode: ColorMode.Species,
			maxSpeed: 3.5,
			globalCollision: 0.2,
			noise: 0.02
		}
	)
];
