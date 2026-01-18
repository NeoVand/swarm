// Render pipeline setup for boids and trails

import type { SimulationBuffers } from './types';

import boidShader from '$lib/shaders/boid.wgsl?raw';
import trailShader from '$lib/shaders/trail.wgsl?raw';

export interface RenderBindGroups {
	boidA: GPUBindGroup;
	boidB: GPUBindGroup;
	trailA: GPUBindGroup;
	trailB: GPUBindGroup;
}

export interface RenderResources {
	pipelines: {
		boid: GPURenderPipeline;
		trail: GPURenderPipeline;
	};
	bindGroups: RenderBindGroups;
}

export function createRenderPipelines(
	device: GPUDevice,
	format: GPUTextureFormat,
	buffers: SimulationBuffers
): RenderResources {
	// Create shader modules
	const boidModule = device.createShaderModule({ code: boidShader });
	const trailModule = device.createShaderModule({ code: trailShader });

	// === Boid Render Pipeline ===
	const boidBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }
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
						// Max blending - takes brighter color, no draw-order fighting
						color: {
							srcFactor: 'one',
							dstFactor: 'one',
							operation: 'max'
						},
						alpha: {
							srcFactor: 'one',
							dstFactor: 'one',
							operation: 'max'
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
			{ binding: 2, resource: { buffer: buffers.velocityA } }
		]
	});

	const boidBindGroupB = device.createBindGroup({
		layout: boidBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.velocityB } }
		]
	});

	// === Trail Render Pipeline ===
	const trailBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
			{ binding: 3, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } }
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
						// Max blending - takes brighter color, no draw-order fighting
						// Same as boids for consistency
						color: {
							srcFactor: 'one',
							dstFactor: 'one',
							operation: 'max'
						},
						alpha: {
							srcFactor: 'one',
							dstFactor: 'one',
							operation: 'max'
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
			{ binding: 3, resource: { buffer: buffers.trails } }
		]
	});

	const trailBindGroupB = device.createBindGroup({
		layout: trailBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.velocityB } },
			{ binding: 3, resource: { buffer: buffers.trails } }
		]
	});

	return {
		pipelines: {
			boid: boidPipeline,
			trail: trailPipeline
		},
		bindGroups: {
			boidA: boidBindGroupA,
			boidB: boidBindGroupB,
			trailA: trailBindGroupA,
			trailB: trailBindGroupB
		}
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

	// Render trails first (additive blending underneath boids)
	const trailSegments = boidCount * (trailLength - 1);
	const trailVertices = trailSegments * 6; // 6 vertices per segment (2 triangles)
	
	renderPass.setPipeline(resources.pipelines.trail);
	renderPass.setBindGroup(0, readFromA ? resources.bindGroups.trailB : resources.bindGroups.trailA);
	renderPass.draw(6, trailSegments); // 6 vertices per instance

	// Render boids on top
	renderPass.setPipeline(resources.pipelines.boid);
	renderPass.setBindGroup(0, readFromA ? resources.bindGroups.boidB : resources.bindGroups.boidA);
	renderPass.draw(3, boidCount); // 3 vertices per triangle

	renderPass.end();
}
