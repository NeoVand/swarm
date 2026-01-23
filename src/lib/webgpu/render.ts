// Render pipeline setup for boids, trails, and walls

import type { SimulationBuffers } from './types';

import boidShader from '$lib/shaders/boid.wgsl?raw';
import trailShader from '$lib/shaders/trail.wgsl?raw';
import wallShader from '$lib/shaders/wall.wgsl?raw';

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
	};
	bindGroups: RenderBindGroups;
	wallBindGroupLayout: GPUBindGroupLayout;
}

export function createRenderPipelines(
	device: GPUDevice,
	format: GPUTextureFormat,
	buffers: SimulationBuffers
): RenderResources {
	// Create shader modules
	const boidModule = device.createShaderModule({ code: boidShader });
	const trailModule = device.createShaderModule({ code: trailShader });
	const wallModule = device.createShaderModule({ code: wallShader });

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
			{ binding: 5, visibility: GPUShaderStage.VERTEX, buffer: { type: 'uniform' } } // speciesParams (uniform)
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
		}
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
			{ binding: 5, resource: { buffer: buffers.speciesParams } }
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
			{ binding: 5, resource: { buffer: buffers.speciesParams } }
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
			{ binding: 6, visibility: GPUShaderStage.VERTEX, buffer: { type: 'uniform' } } // speciesParams (uniform)
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
		}
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
			{ binding: 6, resource: { buffer: buffers.speciesParams } }
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
			{ binding: 6, resource: { buffer: buffers.speciesParams } }
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
		}
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
			wall: wallPipeline
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

export function encodeRenderPass(
	encoder: GPUCommandEncoder,
	textureView: GPUTextureView,
	resources: RenderResources,
	boidCount: number,
	trailLength: number,
	readFromA: boolean
): void {
	const renderPass = encoder.beginRenderPass({
		colorAttachments: [
			{
				view: textureView,
				clearValue: { r: 0.039, g: 0.043, b: 0.051, a: 1.0 }, // #0a0b0d
				loadOp: 'clear',
				storeOp: 'store'
			}
		]
	});

	// Render walls first (background layer)
	renderPass.setPipeline(resources.pipelines.wall);
	renderPass.setBindGroup(0, resources.bindGroups.wall);
	renderPass.draw(6); // Full-screen quad

	// Render trails (underneath boids)
	const trailSegments = boidCount * (trailLength - 1);

	renderPass.setPipeline(resources.pipelines.trail);
	renderPass.setBindGroup(0, readFromA ? resources.bindGroups.trailB : resources.bindGroups.trailA);
	renderPass.draw(6, trailSegments); // 6 vertices per instance

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
	// No resources to clean up without depth buffer
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
