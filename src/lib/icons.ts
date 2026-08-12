/**
 * Every icon in the interface, in one place.
 *
 * The UI used to carry 235 hand-pasted inline `<svg>` blocks across eight
 * components - a mix of Lucide, Heroicons and one-off shapes, with the same
 * icon copied out up to ten times. Changing one meant finding all ten. They now
 * come from Hugeicons, and the choice of icon lives here rather than in the
 * markup, so this file is the whole tally: what each icon is, and what it
 * labels.
 *
 * Deliberately NOT here, because they are drawings rather than icons - they
 * carry meaning by their shape and swapping them for a stock glyph would lose
 * information:
 *
 *   - boid head shapes (`getShapePath`) - the actual silhouette a boid is drawn
 *     with, previewed in the species picker
 *   - cursor force fields (ring / disk) - diagrams of the force's shape, drawn
 *     to scale over the canvas in BoidsCanvas
 *   - topology thumbnails (TopologySelector, BoundaryIcon) - little pictures of
 *     the surface and of how its edges glue
 *   - palette swatches (PaletteIcon) - the gradient itself, not a symbol for it
 *   - the app mark, and the curve editor's plotting surface
 */

import {
	AccelerationIcon,
	Add01Icon,
	ArrowDataTransferHorizontalIcon,
	ArrowDown01Icon,
	ArrowMoveUpLeftIcon,
	ArrowRight01Icon,
	ArrowRightDoubleIcon,
	Atom01Icon,
	BirdIcon,
	Cancel01Icon,
	Camera01Icon,
	Compass01Icon,
	ContrastIcon,
	DashboardSpeed02Icon,
	Delete02Icon,
	DiceFaces05Icon,
	Dna01Icon,
	DropletIcon,
	EnergyIcon,
	EraserIcon,
	FootprintsIcon,
	Github01Icon,
	GitMergeIcon,
	GlobeIcon,
	Grid02Icon,
	HelpCircleIcon,
	KeyboardIcon,
	Layers01Icon,
	Location01Icon,
	Magnet02Icon,
	Maximize02Icon,
	MinusSignIcon,
	MirrorIcon,
	Navigation03Icon,
	Orbit01Icon,
	PaintBoardIcon,
	PauseIcon,
	PencilIcon,
	PlayIcon,
	PowerIcon,
	Radar01Icon,
	Refresh01Icon,
	Rotate01Icon,
	ScanIcon,
	Settings01Icon,
	Shield01Icon,
	StopIcon,
	Sun03Icon,
	Sword02Icon,
	Target02Icon,
	Target03Icon,
	TestTube01Icon,
	Tornado01Icon,
	Tornado02Icon,
	UnavailableIcon,
	UserGroupIcon,
	UserMultipleIcon,
	Video01Icon
} from '@hugeicons/core-free-icons';

import { ColorMode, InteractionBehavior, MetricSource } from '$lib/webgpu/types';

import type { IconSvgElement } from '@hugeicons/svelte';
export type { IconSvgElement };

/**
 * Render an icon to an SVG string.
 *
 * The guided tour hands driver.js raw HTML rather than Svelte markup, so its
 * icons cannot be components. This keeps them on the same registry as the rest
 * of the app instead of a second, drifting set pasted into template literals.
 */
export function iconMarkup(icon: IconSvgElement, size = 14, extraStyle = ''): string {
	const body = icon
		.map(
			([tag, attrs]) =>
				`<${tag} ${Object.entries(attrs)
					.map(([k, v]) => `${k}="${v}"`)
					.join(' ')} />`
		)
		.join('');
	return (
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" ` +
		`stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" ` +
		`style="width:${size}px;height:${size}px;flex-shrink:0;${extraStyle}">${body}</svg>`
	);
}

// --- Window chrome and media controls -------------------------------------

/** The collapsed panel's handle. The lab, in one glyph. */
export const IconLab = TestTube01Icon;
export const IconPlay = PlayIcon;
export const IconPause = PauseIcon;
/** Stops a recording in progress - a stop square, not a second record dot. */
export const IconStopRecording = StopIcon;
export const IconRecord = Video01Icon;
export const IconScreenshot = Camera01Icon;
/** Rolls new species and interaction rules, so: dice, not shuffle. */
export const IconRandomize = DiceFaces05Icon;
/** Puts the boids back to a fresh start - a full turn, not an undo arrow. */
export const IconReset = Refresh01Icon;
export const IconClose = Cancel01Icon;
export const IconHelp = HelpCircleIcon;
export const IconKeyboard = KeyboardIcon;
export const IconGithub = Github01Icon;

// --- Panel sections --------------------------------------------------------

/** Boids: the flock itself. */
export const IconBoids = BirdIcon;
export const IconColor = PaintBoardIcon;
/** Forces: the cursor pulling and pushing the flock around. */
export const IconForces = Magnet02Icon;
/** Interactions: species acting on each other, like bonded particles. */
export const IconInteractions = Atom01Icon;
/** Flocking: the three rules that make a group out of individuals. */
export const IconFlocking = UserGroupIcon;
/** World: the topology the flock lives on. */
export const IconWorld = GlobeIcon;
/** Dynamics: speed, noise, the energy in the system. */
export const IconDynamics = EnergyIcon;

// --- Controls and tools ----------------------------------------------------

export const IconChevronDown = ArrowDown01Icon;
export const IconChevronRight = ArrowRight01Icon;
export const IconAdd = Add01Icon;
export const IconDelete = Delete02Icon;
export const IconPower = PowerIcon;
export const IconPencil = PencilIcon;
export const IconEraser = EraserIcon;
/** The parameter grid drawn over an embedded surface. */
export const IconGrid = Grid02Icon;
/** Auto-rotate: the view turning slowly on its own. */
export const IconAutoRotate = Rotate01Icon;
/** Opens the extra options on an interaction rule. */
export const IconSettings = Settings01Icon;

// --- Colour modes ----------------------------------------------------------
//
// One map, used by the hue, saturation and brightness pickers alike. Each of
// those used to inline the whole set twice over - once for the closed button
// and once for the open menu - which is where six of every ten icons in the
// app came from.

const COLOR_MODE_ICONS: Record<number, typeof MinusSignIcon> = {
	/** Off. Reads as "nothing applied", not as a subtraction. */
	[ColorMode.None]: MinusSignIcon,
	/** Which species a boid belongs to - its lineage. */
	[ColorMode.Species]: Dna01Icon,
	/** "Position": the colour it was born with, fixed to where it started. */
	[ColorMode.Density]: Location01Icon,
	/** "Heading": which way it is pointing. */
	[ColorMode.Turning]: Compass01Icon,
	/** "Turn Rate": how fast that heading is changing. */
	[ColorMode.TrueTurning]: Rotate01Icon,
	[ColorMode.Speed]: DashboardSpeed02Icon,
	/** "Direction" of travel, as distinct from Heading's absolute angle. */
	[ColorMode.Orientation]: Navigation03Icon,
	/** A raw count of who is nearby. */
	[ColorMode.Neighbors]: UserMultipleIcon,
	/** How tightly those neighbours are packed - crowding, stacked up. */
	[ColorMode.LocalDensity]: Layers01Icon,
	/** "Structure": whether the neighbourhood is a blob or an edge. */
	[ColorMode.Anisotropy]: ScanIcon,
	/** Spectral Angular: bearing from the local centre, swept like a radar. */
	[ColorMode.Influence]: Radar01Icon,
	/** Spectral Radial: distance from that centre - core versus rim. */
	[ColorMode.SpectralRadial]: Target03Icon,
	/** Spectral Asymmetry: how lopsided the neighbourhood is. */
	[ColorMode.SpectralAsymmetry]: ContrastIcon,
	/** Flow Angular: motion across the local flow - the circling component. */
	[ColorMode.FlowAngular]: Tornado02Icon,
	/** Flow Radial: motion toward or away from the centre. */
	[ColorMode.FlowRadial]: Maximize02Icon,
	/** Flow Divergence: whether neighbours are moving with you or against. */
	[ColorMode.FlowDivergence]: ArrowDataTransferHorizontalIcon
};

export function colorModeIcon(mode: ColorMode) {
	return COLOR_MODE_ICONS[mode] ?? MinusSignIcon;
}

// --- Metric sources --------------------------------------------------------
//
// The quantities a metric rule can key off. They are the same measurements the
// colour modes expose, so they deliberately borrow the same icons - a rule
// keyed on speed should show the speedometer the Speed colour mode shows.

const METRIC_SOURCE_ICONS: Record<number, typeof MinusSignIcon> = {
	[MetricSource.LocalDensity]: Layers01Icon,
	[MetricSource.Anisotropy]: ScanIcon,
	[MetricSource.Spectral]: Radar01Icon,
	[MetricSource.TurnRate]: Rotate01Icon,
	[MetricSource.Speed]: DashboardSpeed02Icon,
	[MetricSource.Orientation]: Compass01Icon,
	[MetricSource.Neighbors]: UserMultipleIcon,
	[MetricSource.Acceleration]: AccelerationIcon
};

export function metricSourceIcon(source: MetricSource) {
	return METRIC_SOURCE_ICONS[source] ?? DashboardSpeed02Icon;
}

/** Whose metric a rule reads: the neighbour's, mine, or the gap between. */
export const IconRoleNeighbor = UserMultipleIcon;
export const IconRoleSelf = UserGroupIcon;
export const IconRoleDifference = ArrowDataTransferHorizontalIcon;

// --- Interaction behaviours ------------------------------------------------
//
// What one species does when it meets another. These are the plainest labels in
// the app and the icons should read at a glance, so each one is the gesture
// rather than the mechanism.

const BEHAVIOR_ICONS: Record<number, typeof MinusSignIcon> = {
	[InteractionBehavior.Ignore]: UnavailableIcon,
	/** Flee: break away, at speed, in the opposite direction. */
	[InteractionBehavior.Flee]: ArrowMoveUpLeftIcon,
	/** Chase: lock on and pursue. */
	[InteractionBehavior.Chase]: Target02Icon,
	/** Cohere: two streams becoming one. */
	[InteractionBehavior.Cohere]: GitMergeIcon,
	/** Align: fall into the same heading. */
	[InteractionBehavior.Align]: ArrowRightDoubleIcon,
	/** Orbit: circle without closing. */
	[InteractionBehavior.Orbit]: Orbit01Icon,
	/** Follow: hold station behind. */
	[InteractionBehavior.Follow]: FootprintsIcon,
	/** Guard: keep station around, protectively. */
	[InteractionBehavior.Guard]: Shield01Icon,
	/** Disperse: burst outward. */
	[InteractionBehavior.Disperse]: Maximize02Icon,
	/** Mob: gang up. */
	[InteractionBehavior.Mob]: Sword02Icon,
	/** Mirror: move as the reflection of the other. */
	[InteractionBehavior.Mirror]: MirrorIcon,
	/** Spiral: close in while circling - a vortex. */
	[InteractionBehavior.Spiral]: Tornado01Icon
};

export function behaviorIcon(behavior: InteractionBehavior) {
	return BEHAVIOR_ICONS[behavior] ?? UnavailableIcon;
}

// --- Colour channel headers ------------------------------------------------

/** Saturation - how much colour there is. */
export const IconSaturation = DropletIcon;
/** Brightness - how much light. */
export const IconBrightness = Sun03Icon;
