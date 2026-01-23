<script lang="ts">
	import { VortexDirection } from '$lib/webgpu/types';

	/**
	 * Animated particle visualization for force buttons.
	 * - Attract: 4 symmetric particles moving inward together
	 * - Repel: 4 symmetric particles moving outward together
	 * - Vortex: Layered particles spinning (direction based on vortexDirection)
	 */

	type ForceType = 'attract' | 'repel' | 'vortex';

	interface Props {
		type: ForceType;
		active?: boolean;
		size?: number;
		vortexDirection?: VortexDirection;
	}

	let { type, active = false, size = 20, vortexDirection = VortexDirection.Off }: Props = $props();

	let canvas: HTMLCanvasElement | undefined = $state();

	// Colors matching the UI design
	const COLORS: Record<ForceType, { active: string; inactive: string; activeCCW?: string }> = {
		attract: { active: '#22d3ee', inactive: '#71717a' }, // cyan
		repel: { active: '#fb7185', inactive: '#71717a' }, // rose
		vortex: { active: '#f97316', inactive: '#71717a', activeCCW: '#a855f7' } // orange (CW), purple (CCW)
	};

	// Animation loop
	$effect(() => {
		if (!canvas) return;

		const ctx = canvas.getContext('2d');
		if (!ctx) return;

		let animationId: number;

		const centerX = size / 2;
		const centerY = size / 2;
		const maxRadius = size / 2 - 2;

		// Symmetric animation progress (0 to 1, loops)
		// Random initial offset so different button instances don't sync
		let progress = Math.random();

		// Vortex layer angles - also randomized
		let outerAngle = Math.random() * Math.PI * 2;

		let lastTime = performance.now();

		const animate = (currentTime: number) => {
			const deltaTime = (currentTime - lastTime) / 1000;
			lastTime = currentTime;

			// Clear canvas
			ctx.clearRect(0, 0, size, size);

			// Apply circular clip
			ctx.save();
			ctx.beginPath();
			ctx.arc(centerX, centerY, size / 2, 0, Math.PI * 2);
			ctx.clip();

			// Get color based on active state and vortex direction
			let color: string;
			if (!active) {
				color = COLORS[type].inactive;
			} else if (type === 'vortex' && vortexDirection === VortexDirection.CounterClockwise) {
				color = COLORS[type].activeCCW ?? COLORS[type].active;
			} else {
				color = COLORS[type].active;
			}

			// Helper function to draw a triangle pointing in a direction
		const drawTriangle = (x: number, y: number, triSize: number, rotation: number) => {
			ctx.save();
			ctx.translate(x, y);
			ctx.rotate(rotation);
			ctx.beginPath();
			// Triangle centered at origin, pointing right (rotation 0)
			// Centroid at (0,0): tip at (2s, 0), back at (-s, ±s)
			const s = triSize * 0.5;
			ctx.moveTo(2 * s, 0); // tip
			ctx.lineTo(-s, -s); // back left
			ctx.lineTo(-s, s); // back right
			ctx.closePath();
			ctx.fill();
			ctx.restore();
		};

		// Number of triangles arranged in a circle
		const numTriangles = 8;
		const triangleSize = 3.5;

		// Helper to draw all triangles at a given radius (perfectly synchronized)
		const drawSyncedTriangles = (t: number, isAttract: boolean, alpha: number) => {
			// Radius range - from edge to center
			const outerRadius = maxRadius * 1.1;
			const innerRadius = maxRadius * 0.08;
			
			// All triangles at the same radius
			const radius = isAttract
				? outerRadius - (outerRadius - innerRadius) * t
				: innerRadius + (outerRadius - innerRadius) * t;

			for (let i = 0; i < numTriangles; i++) {
				const angle = (i * Math.PI * 2) / numTriangles;
				const rotation = isAttract ? angle + Math.PI : angle;

				const x = centerX + Math.cos(angle) * radius;
				const y = centerY + Math.sin(angle) * radius;

				ctx.fillStyle = color;
				ctx.globalAlpha = alpha;
				drawTriangle(x, y, triangleSize, rotation);
			}
		};

		if (type === 'attract' || type === 'repel') {
			const isAttract = type === 'attract';
			
			// Update progress
			progress += deltaTime * 0.5;
			if (progress >= 1) {
				progress -= 1;
			}

			// Draw 2 waves with good spacing so direction is visible
			for (let wave = 0; wave < 2; wave++) {
				const waveT = (progress + wave / 2) % 1;
				
				// Smooth fade in/out using sine curve
				// Peaks at t=0.5, fades to 0 at t=0 and t=1
				const fadeAlpha = Math.sin(waveT * Math.PI);
				
				// Position boost - brighter when further from center
				const posBoost = isAttract
					? 1 - waveT * 0.2
					: 0.8 + waveT * 0.2;
				
				const finalAlpha = fadeAlpha * posBoost * 0.95;
				
				if (finalAlpha > 0.02) {
					drawSyncedTriangles(waveT, isAttract, finalAlpha);
				}
			}
		} else if (type === 'vortex') {
			// Wind turbine / pinwheel style - 3 curved arms rotating with trail
			// Direction: clockwise = positive rotation, counter-clockwise = negative
			const directionMultiplier =
				vortexDirection === VortexDirection.CounterClockwise ? -1 : 1;
			const rotationSpeed = 2.5 * directionMultiplier;
			outerAngle += deltaTime * rotationSpeed;

			// Helper to draw a spiral arm at a given base angle
			const drawArm = (baseAngle: number, alpha: number, lineWidth: number) => {
				ctx.beginPath();
				ctx.strokeStyle = color;
				ctx.lineWidth = lineWidth;
				ctx.lineCap = 'round';
				ctx.globalAlpha = alpha;

				// Draw curved arm from center outward
				// Curve direction matches rotation direction
				const steps = 10;
				for (let i = 0; i <= steps; i++) {
					const t = i / steps;
					const r = t * maxRadius * 0.9;
					const spiralTwist = t * 1.0 * directionMultiplier; // Curve matches rotation
					const angle = baseAngle + spiralTwist;

					const x = centerX + Math.cos(angle) * r;
					const y = centerY + Math.sin(angle) * r;

					if (i === 0) {
						ctx.moveTo(x, y);
					} else {
						ctx.lineTo(x, y);
					}
				}
				ctx.stroke();
			};

			// Trail settings - draw arms at previous positions (behind current rotation)
			// Using fewer segments with wider spacing for a longer, sparser trail
			const trailCount = 8;
			const trailSpacing = 0.12; // Radians between each trail segment (every other frame)

			// Draw trails first (behind the main arms - opposite direction of rotation)
			for (let trailIdx = trailCount - 1; trailIdx >= 0; trailIdx--) {
				const trailOffset = (trailIdx + 1) * trailSpacing * directionMultiplier;
				// Slower fade - stays visible longer
				const trailAlpha = 0.55 * (1 - (trailIdx + 1) / (trailCount + 2));
				const trailWidth = 1.8 * (1 - trailIdx * 0.07);

				for (let armIndex = 0; armIndex < 3; armIndex++) {
					const armBaseAngle = outerAngle - trailOffset + (armIndex * Math.PI * 2) / 3;
					drawArm(armBaseAngle, trailAlpha, trailWidth);
				}
			}

			// Draw main arms (brightest, on top)
			for (let armIndex = 0; armIndex < 3; armIndex++) {
				const armBaseAngle = outerAngle + (armIndex * Math.PI * 2) / 3;
				drawArm(armBaseAngle, 0.9, 2);
			}

			// Center dot
			ctx.beginPath();
			ctx.arc(centerX, centerY, 2, 0, Math.PI * 2);
			ctx.fillStyle = color;
			ctx.globalAlpha = 0.9;
			ctx.fill();
		}

			ctx.globalAlpha = 1;
			ctx.restore(); // Remove circular clip
			animationId = requestAnimationFrame(animate);
		};

		animationId = requestAnimationFrame(animate);

		return () => {
			cancelAnimationFrame(animationId);
		};
	});
</script>

<canvas
	bind:this={canvas}
	width={size}
	height={size}
	class="force-animation"
	style="width: {size}px; height: {size}px;"
></canvas>

<style>
	.force-animation {
		display: block;
		pointer-events: none;
		border-radius: 50%;
		overflow: hidden;
	}
</style>
