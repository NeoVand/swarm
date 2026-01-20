// Compute pipeline setup for boid simulation

import type { SimulationBuffers } from './types';
import { WORKGROUP_SIZE } from './types';

import clearShader from '$lib/shaders/clear.wgsl?raw';
import clearOffsetsShader from '$lib/shaders/clear_offsets.wgsl?raw';
import countShader from '$lib/shaders/count.wgsl?raw';
import prefixSumShader from '$lib/shaders/prefix_sum.wgsl?raw';
import scatterShader from '$lib/shaders/scatter.wgsl?raw';
import simulateShader from '$lib/shaders/simulate.wgsl?raw';

export interface ComputeBindGroups {
	clear: GPUBindGroup;
	clearOffsets: GPUBindGroup;
	count: GPUBindGroup[];
	prefixSum: GPUBindGroup;
	prefixSumAggregate: GPUBindGroup;
	scatter: GPUBindGroup;
	simulateA: GPUBindGroup; // Read from A, write to B
	simulateB: GPUBindGroup; // Read from B, write to A
}

export interface ComputeResources {
	pipelines: {
		clear: GPUComputePipeline;
		clearOffsets: GPUComputePipeline;
		count: GPUComputePipeline;
		prefixSum: GPUComputePipeline;
		prefixSumAggregate: GPUComputePipeline;
		scatter: GPUComputePipeline;
		simulate: GPUComputePipeline;
	};
	bindGroups: ComputeBindGroups;
	blockSumsBuffer: GPUBuffer;
}

export function createComputePipelines(
	device: GPUDevice,
	buffers: SimulationBuffers,
	blockSumsBuffer: GPUBuffer
): ComputeResources {
	// Create shader modules
	const clearModule = device.createShaderModule({ code: clearShader });
	const clearOffsetsModule = device.createShaderModule({ code: clearOffsetsShader });
	const countModule = device.createShaderModule({ code: countShader });
	const prefixSumModule = device.createShaderModule({ code: prefixSumShader });
	const scatterModule = device.createShaderModule({ code: scatterShader });
	const simulateModule = device.createShaderModule({ code: simulateShader });

	// === Clear Pipeline ===
	const clearBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const clearPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [clearBindGroupLayout] }),
		compute: { module: clearModule, entryPoint: 'main' }
	});

	const clearBindGroup = device.createBindGroup({
		layout: clearBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellCounts } }
		]
	});

	// === Clear Offsets Pipeline ===
	const clearOffsetsBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const clearOffsetsPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [clearOffsetsBindGroupLayout] }),
		compute: { module: clearOffsetsModule, entryPoint: 'main' }
	});

	const clearOffsetsBindGroup = device.createBindGroup({
		layout: clearOffsetsBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellOffsets } }
		]
	});

	// === Count Pipeline ===
	const countBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const countPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [countBindGroupLayout] }),
		compute: { module: countModule, entryPoint: 'main' }
	});

	// Two bind groups for ping-pong
	const countBindGroupA = device.createBindGroup({
		layout: countBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellCounts } },
			{ binding: 2, resource: { buffer: buffers.positionA } },
			{ binding: 3, resource: { buffer: buffers.boidCellIndices } }
		]
	});

	const countBindGroupB = device.createBindGroup({
		layout: countBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellCounts } },
			{ binding: 2, resource: { buffer: buffers.positionB } },
			{ binding: 3, resource: { buffer: buffers.boidCellIndices } }
		]
	});

	// === Prefix Sum Pipeline ===
	const prefixSumBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const prefixSumPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [prefixSumBindGroupLayout] }),
		compute: { module: prefixSumModule, entryPoint: 'main' }
	});

	const prefixSumAggregatePipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [prefixSumBindGroupLayout] }),
		compute: { module: prefixSumModule, entryPoint: 'addBlockSums' }
	});

	const prefixSumBindGroup = device.createBindGroup({
		layout: prefixSumBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellCounts } },
			{ binding: 2, resource: { buffer: buffers.prefixSums } },
			{ binding: 3, resource: { buffer: blockSumsBuffer } }
		]
	});

	const prefixSumAggregateBindGroup = device.createBindGroup({
		layout: prefixSumBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.cellCounts } },
			{ binding: 2, resource: { buffer: buffers.prefixSums } },
			{ binding: 3, resource: { buffer: blockSumsBuffer } }
		]
	});

	// === Scatter Pipeline ===
	const scatterBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const scatterPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [scatterBindGroupLayout] }),
		compute: { module: scatterModule, entryPoint: 'main' }
	});

	const scatterBindGroup = device.createBindGroup({
		layout: scatterBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.prefixSums } },
			{ binding: 2, resource: { buffer: buffers.cellOffsets } },
			{ binding: 3, resource: { buffer: buffers.boidCellIndices } },
			{ binding: 4, resource: { buffer: buffers.sortedIndices } }
		]
	});

	// === Simulate Pipeline ===
	const simulateBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 6, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 7, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 8, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
		]
	});

	const simulatePipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [simulateBindGroupLayout] }),
		compute: { module: simulateModule, entryPoint: 'main' }
	});

	// Bind group A: read from A, write to B
	const simulateBindGroupA = device.createBindGroup({
		layout: simulateBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionA } },
			{ binding: 2, resource: { buffer: buffers.positionB } },
			{ binding: 3, resource: { buffer: buffers.velocityA } },
			{ binding: 4, resource: { buffer: buffers.velocityB } },
			{ binding: 5, resource: { buffer: buffers.prefixSums } },
			{ binding: 6, resource: { buffer: buffers.cellCounts } },
			{ binding: 7, resource: { buffer: buffers.sortedIndices } },
			{ binding: 8, resource: { buffer: buffers.trails } }
		]
	});

	// Bind group B: read from B, write to A
	const simulateBindGroupB = device.createBindGroup({
		layout: simulateBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.positionA } },
			{ binding: 3, resource: { buffer: buffers.velocityB } },
			{ binding: 4, resource: { buffer: buffers.velocityA } },
			{ binding: 5, resource: { buffer: buffers.prefixSums } },
			{ binding: 6, resource: { buffer: buffers.cellCounts } },
			{ binding: 7, resource: { buffer: buffers.sortedIndices } },
			{ binding: 8, resource: { buffer: buffers.trails } }
		]
	});

	return {
		pipelines: {
			clear: clearPipeline,
			clearOffsets: clearOffsetsPipeline,
			count: countPipeline,
			prefixSum: prefixSumPipeline,
			prefixSumAggregate: prefixSumAggregatePipeline,
			scatter: scatterPipeline,
			simulate: simulatePipeline
		},
		bindGroups: {
			clear: clearBindGroup,
			clearOffsets: clearOffsetsBindGroup,
			count: [countBindGroupA, countBindGroupB],
			prefixSum: prefixSumBindGroup,
			prefixSumAggregate: prefixSumAggregateBindGroup,
			scatter: scatterBindGroup,
			simulateA: simulateBindGroupA,
			simulateB: simulateBindGroupB
		},
		blockSumsBuffer
	};
}

export function encodeComputePasses(
	encoder: GPUCommandEncoder,
	resources: ComputeResources,
	boidCount: number,
	totalCells: number,
	readFromA: boolean
): void {
	const boidWorkgroups = Math.ceil(boidCount / WORKGROUP_SIZE);
	const cellWorkgroups = Math.ceil(totalCells / WORKGROUP_SIZE);
	const prefixSumWorkgroups = Math.ceil(totalCells / (WORKGROUP_SIZE * 2));

	// Pass 1: Clear cell counts
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.clear);
		pass.setBindGroup(0, resources.bindGroups.clear);
		pass.dispatchWorkgroups(cellWorkgroups);
		pass.end();
	}

	// Pass 1b: Clear cell offsets
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.clearOffsets);
		pass.setBindGroup(0, resources.bindGroups.clearOffsets);
		pass.dispatchWorkgroups(cellWorkgroups);
		pass.end();
	}

	// Pass 2: Count boids per cell
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.count);
		pass.setBindGroup(0, resources.bindGroups.count[readFromA ? 0 : 1]);
		pass.dispatchWorkgroups(boidWorkgroups);
		pass.end();
	}

	// Pass 3: Prefix sum
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.prefixSum);
		pass.setBindGroup(0, resources.bindGroups.prefixSum);
		pass.dispatchWorkgroups(prefixSumWorkgroups);
		pass.end();
	}

	// Pass 3b: Aggregate block sums (for large grids)
	if (prefixSumWorkgroups > 1) {
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.prefixSumAggregate);
		pass.setBindGroup(0, resources.bindGroups.prefixSumAggregate);
		pass.dispatchWorkgroups(cellWorkgroups);
		pass.end();
	}

	// Pass 4: Scatter boids to sorted array
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.scatter);
		pass.setBindGroup(0, resources.bindGroups.scatter);
		pass.dispatchWorkgroups(boidWorkgroups);
		pass.end();
	}

	// Pass 5: Simulate flocking
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.simulate);
		pass.setBindGroup(
			0,
			readFromA ? resources.bindGroups.simulateA : resources.bindGroups.simulateB
		);
		pass.dispatchWorkgroups(boidWorkgroups);
		pass.end();
	}
}
