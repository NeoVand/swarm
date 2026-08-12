// Render pipeline setup for boids, trails, and walls

import type { SimulationBuffers } from './types';

import commonShader from '$lib/shaders/common.wgsl?raw';
import colorShader from '$lib/shaders/color.wgsl?raw';
import boidShader from '$lib/shaders/boid.wgsl?raw';
import trailShader from '$lib/shaders/trail.wgsl?raw';
import wallShader from '$lib/shaders/wall.wgsl?raw';
import embedShader from '$lib/shaders/embed.wgsl?raw';
import surfaceShader from '$lib/shaders/surface.wgsl?raw';

export const DEPTH_FORMAT: GPUTextureFormat = 'depth24plus';

// Shell/grid tessellation - must match the constants in surface.wgsl
const SHELL_U = 160;
const SHELL_V = 80;
const GRID_LINES_U = 24;
const GRID_LINES_V = 12;
const GRID_SEGMENTS = 160;

const SHELL_VERTEX_COUNT = SHELL_U * SHELL_V * 6;
// One extra line per axis so open boundaries get drawn (see vs_grid)
const GRID_VERTEX_COUNT = (GRID_LINES_U + 1 + GRID_LINES_V + 1) * GRID_SEGMENTS * 2;

export interface RenderBindGroups {
	boidA: GPUBindGroup;
	boidB: GPUBindGroup;
	trailA: GPUBindGroup;
	trailB: GPUBindGroup;
	wall: GPUBindGroup;
}

export interface RenderResources {
	pipelines: {
		boid: GPURenderPipeline;
		trail: GPURenderPipeline;
		wall: GPURenderPipeline;
		shell: GPURenderPipeline;
		grid: GPURenderPipeline;
	};
	bindGroups: RenderBindGroups;
	wallBindGroupLayout: GPUBindGroupLayout;
}

// The shell and grid premultiply alpha in the fragment shader so that a mostly
// transparent surface doesn't wash out the flock behind it.
const PREMULTIPLIED_BLEND: GPUBlendState = {
	color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha', operation: 'add' },
	alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha', operation: 'add' }
};

/**
 * Depth state shared by the 2D and 3D paths.
 *
 * 'less-equal' rather than 'less' is what lets one pipeline serve both: all 2D
 * geometry sits at depth 0, so a strict 'less' test would make everything after
 * the first draw fail.
 */
function depthState(write: boolean, bias = 0): GPUDepthStencilState {
	return {
		format: DEPTH_FORMAT,
		depthWriteEnabled: write,
		depthCompare: 'less-equal',
		depthBias: bias,
		// Deliberately no slope scaling. Boids and trails sit exactly on the
		// surface rather than at a slant to it, so a constant offset is the right
		// tool; slope scaling explodes wherever the surface turns edge-on to the
		// camera, which is most of the fold on a Mobius strip or Klein bottle,
		// and would push the shell far enough back to occlude the wrong sheet.
		depthBiasSlopeScale: 0,
		depthBiasClamp: 0
	};
}

// Depth texture is recreated lazily whenever the canvas size changes.
let depthTexture: GPUTexture | null = null;
let depthWidth = 0;
let depthHeight = 0;

function ensureDepthTexture(device: GPUDevice, width: number, height: number): GPUTextureView {
	if (!depthTexture || depthWidth !== width || depthHeight !== height) {
		depthTexture?.destroy();
		depthTexture = device.createTexture({
			size: { width: Math.max(1, width), height: Math.max(1, height) },
			format: DEPTH_FORMAT,
			usage: GPUTextureUsage.RENDER_ATTACHMENT
		});
		depthWidth = width;
		depthHeight = height;
	}
	return depthTexture.createView();
}

export function createRenderPipelines(
	device: GPUDevice,
	format: GPUTextureFormat,
	buffers: SimulationBuffers
): RenderResources {
	// Create shader modules (concatenate shared shaders for boid and trail)
	const boidModule = device.createShaderModule({
		code: commonShader + embedShader + colorShader + boidShader
	});
	const trailModule = device.createShaderModule({
		code: commonShader + embedShader + colorShader + trailShader
	});
	const wallModule = device.createShaderModule({ code: wallShader });
	const surfaceModule = device.createShaderModule({
		code: commonShader + embedShader + surfaceShader
	});

	// === Boid Render Pipeline ===
	const boidBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{
				binding: 0,
				visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
				buffer: { type: 'uniform' }
			},
			{ binding: 1, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 3, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // birthColors
			{ binding: 4, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // speciesIds
			{ binding: 5, visibility: GPUShaderStage.VERTEX, buffer: { type: 'uniform' } }, // speciesParams (uniform)
			{ binding: 6, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // metrics (density, anisotropy)
			{ binding: 7, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } } // curveSamples
		]
	});

	const boidPipeline = device.createRenderPipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [boidBindGroupLayout] }),
		vertex: {
			module: boidModule,
			entryPoint: 'vs_main'
		},
		fragment: {
			module: boidModule,
			entryPoint: 'fs_main',
			targets: [
				{
					format,
					blend: {
						// Standard alpha blending - objects occlude, no extra brightness
						color: {
							srcFactor: 'src-alpha',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						},
						alpha: {
							srcFactor: 'one',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						}
					}
				}
			]
		},
		primitive: {
			topology: 'triangle-list',
			cullMode: 'none'
		},
		// Boids are the opaque occluders in embedded mode, so they own the depth
		// buffer; trails and the glass shell test against what they write.
		depthStencil: depthState(true)
	});

	// Bind groups for ping-pong
	const boidBindGroupA = device.createBindGroup({
		layout: boidBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionA } },
			{ binding: 2, resource: { buffer: buffers.velocityA } },
			{ binding: 3, resource: { buffer: buffers.birthColors } },
			{ binding: 4, resource: { buffer: buffers.speciesIds } },
			{ binding: 5, resource: { buffer: buffers.speciesParams } },
			{ binding: 6, resource: { buffer: buffers.metrics } },
			{ binding: 7, resource: { buffer: buffers.curveSamples } }
		]
	});

	const boidBindGroupB = device.createBindGroup({
		layout: boidBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.velocityB } },
			{ binding: 3, resource: { buffer: buffers.birthColors } },
			{ binding: 4, resource: { buffer: buffers.speciesIds } },
			{ binding: 5, resource: { buffer: buffers.speciesParams } },
			{ binding: 6, resource: { buffer: buffers.metrics } },
			{ binding: 7, resource: { buffer: buffers.curveSamples } }
		]
	});

	// === Trail Render Pipeline ===
	const trailBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{
				binding: 0,
				visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
				buffer: { type: 'uniform' }
			},
			{ binding: 1, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 3, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 4, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // birthColors
			{ binding: 5, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // speciesIds
			{ binding: 6, visibility: GPUShaderStage.VERTEX, buffer: { type: 'uniform' } }, // speciesParams (uniform)
			{ binding: 7, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }, // metrics (density, anisotropy)
			{ binding: 8, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } } // curveSamples
		]
	});

	const trailPipeline = device.createRenderPipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [trailBindGroupLayout] }),
		vertex: {
			module: trailModule,
			entryPoint: 'vs_main'
		},
		fragment: {
			module: trailModule,
			entryPoint: 'fs_main',
			targets: [
				{
					format,
					blend: {
						// Standard alpha blending - trails layer naturally, no extra brightness
						color: {
							srcFactor: 'src-alpha',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						},
						alpha: {
							srcFactor: 'one',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						}
					}
				}
			]
		},
		primitive: {
			topology: 'triangle-list',
			cullMode: 'none'
		},
		// Alpha-blended ribbons test against boids but must not write depth, or
		// a nearly-transparent tail tip would punch a hole in whatever is behind.
		depthStencil: depthState(false)
	});

	// Trail bind groups for ping-pong
	const trailBindGroupA = device.createBindGroup({
		layout: trailBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionA } },
			{ binding: 2, resource: { buffer: buffers.velocityA } },
			{ binding: 3, resource: { buffer: buffers.trails } },
			{ binding: 4, resource: { buffer: buffers.birthColors } },
			{ binding: 5, resource: { buffer: buffers.speciesIds } },
			{ binding: 6, resource: { buffer: buffers.speciesParams } },
			{ binding: 7, resource: { buffer: buffers.metrics } },
			{ binding: 8, resource: { buffer: buffers.curveSamples } }
		]
	});

	const trailBindGroupB = device.createBindGroup({
		layout: trailBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.velocityB } },
			{ binding: 3, resource: { buffer: buffers.trails } },
			{ binding: 4, resource: { buffer: buffers.birthColors } },
			{ binding: 5, resource: { buffer: buffers.speciesIds } },
			{ binding: 6, resource: { buffer: buffers.speciesParams } },
			{ binding: 7, resource: { buffer: buffers.metrics } },
			{ binding: 8, resource: { buffer: buffers.curveSamples } }
		]
	});

	// === Wall Render Pipeline ===
	const wallBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{
				binding: 0,
				visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
				buffer: { type: 'uniform' }
			},
			{
				binding: 1,
				visibility: GPUShaderStage.FRAGMENT,
				texture: { sampleType: 'float' }
			},
			{
				binding: 2,
				visibility: GPUShaderStage.FRAGMENT,
				sampler: { type: 'filtering' }
			}
		]
	});

	const wallPipeline = device.createRenderPipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [wallBindGroupLayout] }),
		vertex: {
			module: wallModule,
			entryPoint: 'vs_main'
		},
		fragment: {
			module: wallModule,
			entryPoint: 'fs_main',
			targets: [
				{
					format,
					blend: {
						color: {
							srcFactor: 'src-alpha',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						},
						alpha: {
							srcFactor: 'one',
							dstFactor: 'one-minus-src-alpha',
							operation: 'add'
						}
					}
				}
			]
		},
		primitive: {
			topology: 'triangle-list',
			cullMode: 'none'
		},
		depthStencil: depthState(false)
	});

	// === Surface Shell + Grid Pipelines (embedded mode only) ===
	// The shell reuses the wall bind group layout verbatim: it needs the same
	// uniforms plus the wall texture, which it samples to tint painted walls
	// onto the surface.
	const surfacePipelineLayout = device.createPipelineLayout({
		bindGroupLayouts: [wallBindGroupLayout]
	});

	// Opaque shell: a single pass drawn before the flock, writing depth, with no
	// face culling so open surfaces (plane, cylinder, Mobius) show both sides.
	// Being opaque it has to lead rather than follow - the near wall occludes
	// the far side of the flock through the depth test instead of tinting it.
	// The depth bias pushes it away from the camera so boids and trails lying
	// exactly on the surface always win.
	const shellPipeline = device.createRenderPipeline({
		layout: surfacePipelineLayout,
		vertex: { module: surfaceModule, entryPoint: 'vs_shell' },
		fragment: {
			module: surfaceModule,
			entryPoint: 'fs_shell',
			targets: [{ format }]
		},
		primitive: { topology: 'triangle-list', cullMode: 'none' },
		depthStencil: depthState(true, 300)
	});

	const gridPipeline = device.createRenderPipeline({
		layout: surfacePipelineLayout,
		vertex: { module: surfaceModule, entryPoint: 'vs_grid' },
		fragment: {
			module: surfaceModule,
			entryPoint: 'fs_grid',
			targets: [{ format, blend: PREMULTIPLIED_BLEND }]
		},
		primitive: { topology: 'line-list' },
		// Depth bias is not applied to line primitives, so the unbiased grid sits
		// naturally in front of the biased shell without z-fighting.
		depthStencil: depthState(false)
	});

	// Wall bind group
	const wallBindGroup = device.createBindGroup({
		layout: wallBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: buffers.wallTexture.createView() },
			{ binding: 2, resource: buffers.wallSampler }
		]
	});

	return {
		pipelines: {
			boid: boidPipeline,
			trail: trailPipeline,
			wall: wallPipeline,
			shell: shellPipeline,
			grid: gridPipeline
		},
		bindGroups: {
			boidA: boidBindGroupA,
			boidB: boidBindGroupB,
			trailA: trailBindGroupA,
			trailB: trailBindGroupB,
			wall: wallBindGroup
		},
		wallBindGroupLayout
	};
}

export interface RenderPassOptions {
	boidCount: number;
	trailLength: number;
	readFromA: boolean;
	canvasWidth: number;
	canvasHeight: number;
	/** 0 = flat 2D view, > 0 = projecting through the 3D embedding. */
	embedBlend: number;
	showShell: boolean;
	showGrid: boolean;
}

export function encodeRenderPass(
	device: GPUDevice,
	encoder: GPUCommandEncoder,
	textureView: GPUTextureView,
	resources: RenderResources,
	options: RenderPassOptions
): void {
	const { boidCount, trailLength, readFromA, embedBlend } = options;
	const embedded = embedBlend > 0.0001;

	const renderPass = encoder.beginRenderPass({
		colorAttachments: [
			{
				view: textureView,
				clearValue: { r: 0.039, g: 0.043, b: 0.051, a: 1.0 }, // #0a0b0d
				loadOp: 'clear',
				storeOp: 'store'
			}
		],
		depthStencilAttachment: {
			view: ensureDepthTexture(device, options.canvasWidth, options.canvasHeight),
			depthClearValue: 1.0,
			depthLoadOp: 'clear',
			depthStoreOp: 'store'
		}
	});

	if (embedded) {
		// The opaque shell leads, filling the depth buffer with the nearest
		// surface so everything after it is occluded correctly. Painted walls
		// are tinted onto the shell itself, so the flat wall overlay is skipped.
		if (options.showShell) {
			renderPass.setPipeline(resources.pipelines.shell);
			renderPass.setBindGroup(0, resources.bindGroups.wall);
			renderPass.draw(SHELL_VERTEX_COUNT);
		}
		// Grid tests against the shell without writing, so parameter lines on the
		// far side are hidden by the near wall.
		if (options.showGrid) {
			renderPass.setPipeline(resources.pipelines.grid);
			renderPass.setBindGroup(0, resources.bindGroups.wall);
			renderPass.draw(GRID_VERTEX_COUNT);
		}
	} else {
		// Render walls first (background layer)
		renderPass.setPipeline(resources.pipelines.wall);
		renderPass.setBindGroup(0, resources.bindGroups.wall);
		renderPass.draw(6); // Full-screen quad
	}

	// Render trails (underneath boids) - skip entirely if trailLength is 0 for max performance
	if (trailLength > 1) {
		const trailSegments = boidCount * (trailLength - 1);
		renderPass.setPipeline(resources.pipelines.trail);
		renderPass.setBindGroup(
			0,
			readFromA ? resources.bindGroups.trailB : resources.bindGroups.trailA
		);
		renderPass.draw(6, trailSegments); // 6 vertices per instance
	}

	// Render boids on top
	// We draw 4x instances to handle edge wrapping ghosts (original + X/Y/XY ghosts)
	// The shader will discard ghosts that aren't needed
	// Using 18 vertices per boid for triangle fan rendering (6 triangles max for hexagon)
	renderPass.setPipeline(resources.pipelines.boid);
	renderPass.setBindGroup(0, readFromA ? resources.bindGroups.boidB : resources.bindGroups.boidA);
	renderPass.draw(18, boidCount * 4); // 18 vertices per shape (6 triangles from center), 4 copies for edge wrapping

	renderPass.end();
}

export function destroyRenderResources(): void {
	depthTexture?.destroy();
	depthTexture = null;
	depthWidth = 0;
	depthHeight = 0;
}

// Recreate wall bind group when wall texture changes (e.g., on resize)
export function recreateWallBindGroup(
	device: GPUDevice,
	layout: GPUBindGroupLayout,
	uniforms: GPUBuffer,
	wallTexture: GPUTexture,
	wallSampler: GPUSampler
): GPUBindGroup {
	return device.createBindGroup({
		layout,
		entries: [
			{ binding: 0, resource: { buffer: uniforms } },
			{ binding: 1, resource: wallTexture.createView() },
			{ binding: 2, resource: wallSampler }
		]
	});
}
