// Compute pipeline setup for boid simulation

import type { SimulationBuffers } from './types';
import { WORKGROUP_SIZE } from './types';

import clearShader from '$lib/shaders/clear.wgsl?raw';
import countShader from '$lib/shaders/count.wgsl?raw';
import prefixSumShader from '$lib/shaders/prefix_sum.wgsl?raw';
import scatterShader from '$lib/shaders/scatter.wgsl?raw';
import simulateShader from '$lib/shaders/simulate.wgsl?raw';
import commonShader from '$lib/shaders/common.wgsl?raw';
import rankShader from '$lib/shaders/rank.wgsl?raw';
import writeMetricsShader from '$lib/shaders/write_metrics.wgsl?raw';

export interface ComputeBindGroups {
	clear: GPUBindGroup;
	count: GPUBindGroup[];
	prefixSum: GPUBindGroup;
	prefixSumAggregate: GPUBindGroup;
	scatter: GPUBindGroup;
	simulate0A: GPUBindGroup; // Bind group 0: Read from A, write to B
	simulate0B: GPUBindGroup; // Bind group 0: Read from B, write to A
	simulate1: GPUBindGroup; // Bind group 1: Species data (shared)
	// Iterative metrics bind groups
	rank0A: GPUBindGroup; // Spatial hash data (read from posA)
	rank0B: GPUBindGroup; // Spatial hash data (read from posB)
	rank1: GPUBindGroup; // Species + metrics
	rank2A: GPUBindGroup; // Ranks: read A, write B
	rank2B: GPUBindGroup; // Ranks: read B, write A
	writeMetrics: GPUBindGroup; // Final copy to metrics.zw
}

export interface ComputeResources {
	pipelines: {
		clear: GPUComputePipeline;
		count: GPUComputePipeline;
		prefixSum: GPUComputePipeline;
		prefixSumCumulative: GPUComputePipeline; // New: compute cumulative block sums
		prefixSumAggregate: GPUComputePipeline;
		scatter: GPUComputePipeline;
		simulate: GPUComputePipeline;
		// Iterative metrics pipelines
		rankInit: GPUComputePipeline;
		rankIter: GPUComputePipeline;
		writeMetrics: GPUComputePipeline;
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
	const countModule = device.createShaderModule({ code: countShader });
	const prefixSumModule = device.createShaderModule({ code: prefixSumShader });
	const scatterModule = device.createShaderModule({ code: scatterShader });
	// Concatenate common.wgsl (Uniforms, boundary config) with simulate shader
	const simulateModule = device.createShaderModule({ code: commonShader + simulateShader });

	// === Clear Pipeline (clears both cellCounts and cellOffsets in one pass) ===
	const clearBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }
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
			{ binding: 1, resource: { buffer: buffers.cellCounts } },
			{ binding: 2, resource: { buffer: buffers.cellOffsets } }
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

	// New: compute cumulative block sums (runs with 1 thread)
	const prefixSumCumulativePipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [prefixSumBindGroupLayout] }),
		compute: { module: prefixSumModule, entryPoint: 'computeCumulativeBlockSums' }
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
	// Use two bind groups to stay under the 8 storage buffer limit per group
	const simulateBindGroupLayout0 = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 6, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 7, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
			{ binding: 8, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
			{ binding: 9, visibility: GPUShaderStage.COMPUTE, texture: { sampleType: 'float' } },
			{ binding: 10, visibility: GPUShaderStage.COMPUTE, sampler: { type: 'filtering' } }
		]
	});

	// Second bind group for species data and metrics
	const simulateBindGroupLayout1 = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // speciesIds
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } }, // speciesParams (uniform for small data)
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } }, // interactionMatrix (uniform for small data)
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } }, // metrics output (density, anisotropy)
			{ binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } }, // metricRules
			{ binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } } // metricRuleCurves (packed as vec4)
		]
	});

	const simulatePipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({
			bindGroupLayouts: [simulateBindGroupLayout0, simulateBindGroupLayout1]
		}),
		compute: { module: simulateModule, entryPoint: 'main' }
	});

	// Bind group 0 A: read from A, write to B
	const simulateBindGroup0A = device.createBindGroup({
		layout: simulateBindGroupLayout0,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionA } },
			{ binding: 2, resource: { buffer: buffers.positionB } },
			{ binding: 3, resource: { buffer: buffers.velocityA } },
			{ binding: 4, resource: { buffer: buffers.velocityB } },
			{ binding: 5, resource: { buffer: buffers.prefixSums } },
			{ binding: 6, resource: { buffer: buffers.cellCounts } },
			{ binding: 7, resource: { buffer: buffers.sortedIndices } },
			{ binding: 8, resource: { buffer: buffers.trails } },
			{ binding: 9, resource: buffers.wallTexture.createView() },
			{ binding: 10, resource: buffers.wallSampler }
		]
	});

	// Bind group 0 B: read from B, write to A
	const simulateBindGroup0B = device.createBindGroup({
		layout: simulateBindGroupLayout0,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.positionA } },
			{ binding: 3, resource: { buffer: buffers.velocityB } },
			{ binding: 4, resource: { buffer: buffers.velocityA } },
			{ binding: 5, resource: { buffer: buffers.prefixSums } },
			{ binding: 6, resource: { buffer: buffers.cellCounts } },
			{ binding: 7, resource: { buffer: buffers.sortedIndices } },
			{ binding: 8, resource: { buffer: buffers.trails } },
			{ binding: 9, resource: buffers.wallTexture.createView() },
			{ binding: 10, resource: buffers.wallSampler }
		]
	});

	// Bind group 1: Species data and metrics (shared between A and B)
	const simulateBindGroup1 = device.createBindGroup({
		layout: simulateBindGroupLayout1,
		entries: [
			{ binding: 0, resource: { buffer: buffers.speciesIds } },
			{ binding: 1, resource: { buffer: buffers.speciesParams } },
			{ binding: 2, resource: { buffer: buffers.interactionMatrix } },
			{ binding: 3, resource: { buffer: buffers.metrics } },
			{ binding: 4, resource: { buffer: buffers.metricRules } },
			{ binding: 5, resource: { buffer: buffers.metricRuleCurves } }
		]
	});

	// === Rank (Spectral) Pipeline ===
	// Concatenate common.wgsl (Uniforms, boundary config) with rank shader
	const rankModule = device.createShaderModule({ code: commonShader + rankShader });

	// Bind group 0 for rank: includes velocities for dynamic spectral modes
	const rankBindGroupLayout0 = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } }, // uniforms
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // positions
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // velocities
			{ binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // prefixSums
			{ binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // cellCounts
			{ binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } } // sortedIndices
		]
	});

	// Bind group 1: Species + metrics (read-only)
	const rankBindGroupLayout1 = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // speciesIds
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } } // metrics
		]
	});

	// Bind group 2: Rank ping-pong
	const rankBindGroupLayout2 = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // ranksIn
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } } // ranksOut
		]
	});

	const rankInitPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({
			bindGroupLayouts: [rankBindGroupLayout0, rankBindGroupLayout1, rankBindGroupLayout2]
		}),
		compute: { module: rankModule, entryPoint: 'init_main' }
	});

	const rankIterPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({
			bindGroupLayouts: [rankBindGroupLayout0, rankBindGroupLayout1, rankBindGroupLayout2]
		}),
		compute: { module: rankModule, entryPoint: 'iter_main' }
	});

	// Rank bind group 0: with velocities
	const rankBindGroup0A = device.createBindGroup({
		layout: rankBindGroupLayout0,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionA } },
			{ binding: 2, resource: { buffer: buffers.velocityA } },
			{ binding: 3, resource: { buffer: buffers.prefixSums } },
			{ binding: 4, resource: { buffer: buffers.cellCounts } },
			{ binding: 5, resource: { buffer: buffers.sortedIndices } }
		]
	});

	const rankBindGroup0B = device.createBindGroup({
		layout: rankBindGroupLayout0,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.positionB } },
			{ binding: 2, resource: { buffer: buffers.velocityB } },
			{ binding: 3, resource: { buffer: buffers.prefixSums } },
			{ binding: 4, resource: { buffer: buffers.cellCounts } },
			{ binding: 5, resource: { buffer: buffers.sortedIndices } }
		]
	});

	// Rank bind group 1: species + metrics
	const rankBindGroup1 = device.createBindGroup({
		layout: rankBindGroupLayout1,
		entries: [
			{ binding: 0, resource: { buffer: buffers.speciesIds } },
			{ binding: 1, resource: { buffer: buffers.metrics } }
		]
	});

	// Rank bind group 2: ping-pong buffers
	const rankBindGroup2A = device.createBindGroup({
		layout: rankBindGroupLayout2,
		entries: [
			{ binding: 0, resource: { buffer: buffers.rankA } },
			{ binding: 1, resource: { buffer: buffers.rankB } }
		]
	});

	const rankBindGroup2B = device.createBindGroup({
		layout: rankBindGroupLayout2,
		entries: [
			{ binding: 0, resource: { buffer: buffers.rankB } },
			{ binding: 1, resource: { buffer: buffers.rankA } }
		]
	});

	// === Write Metrics Pipeline ===
	const writeMetricsModule = device.createShaderModule({ code: writeMetricsShader });

	const writeMetricsBindGroupLayout = device.createBindGroupLayout({
		entries: [
			{ binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } }, // uniforms
			{ binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } }, // rankValues
			{ binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } } // metrics
		]
	});

	const writeMetricsPipeline = device.createComputePipeline({
		layout: device.createPipelineLayout({ bindGroupLayouts: [writeMetricsBindGroupLayout] }),
		compute: { module: writeMetricsModule, entryPoint: 'main' }
	});

	const writeMetricsBindGroup = device.createBindGroup({
		layout: writeMetricsBindGroupLayout,
		entries: [
			{ binding: 0, resource: { buffer: buffers.uniforms } },
			{ binding: 1, resource: { buffer: buffers.rankA } },
			{ binding: 2, resource: { buffer: buffers.metrics } }
		]
	});

	return {
		pipelines: {
			clear: clearPipeline,
			count: countPipeline,
			prefixSum: prefixSumPipeline,
			prefixSumCumulative: prefixSumCumulativePipeline,
			prefixSumAggregate: prefixSumAggregatePipeline,
			scatter: scatterPipeline,
			simulate: simulatePipeline,
			rankInit: rankInitPipeline,
			rankIter: rankIterPipeline,
			writeMetrics: writeMetricsPipeline
		},
		bindGroups: {
			clear: clearBindGroup,
			count: [countBindGroupA, countBindGroupB],
			prefixSum: prefixSumBindGroup,
			prefixSumAggregate: prefixSumAggregateBindGroup,
			scatter: scatterBindGroup,
			simulate0A: simulateBindGroup0A,
			simulate0B: simulateBindGroup0B,
			simulate1: simulateBindGroup1,
			rank0A: rankBindGroup0A,
			rank0B: rankBindGroup0B,
			rank1: rankBindGroup1,
			rank2A: rankBindGroup2A,
			rank2B: rankBindGroup2B,
			writeMetrics: writeMetricsBindGroup
		},
		blockSumsBuffer
	};
}

export interface IterativeMetricsConfig {
	enableInfluence: boolean;
	influenceIterations: number;
	needsRankInit: boolean;
}

export function encodeComputePasses(
	encoder: GPUCommandEncoder,
	resources: ComputeResources,
	boidCount: number,
	totalSlots: number, // Use totalSlots for locally perfect hashing
	readFromA: boolean,
	iterativeConfig?: IterativeMetricsConfig
): void {
	const boidWorkgroups = Math.ceil(boidCount / WORKGROUP_SIZE);
	const cellWorkgroups = Math.ceil(totalSlots / WORKGROUP_SIZE);
	const prefixSumWorkgroups = Math.ceil(totalSlots / (WORKGROUP_SIZE * 2));

	// Pass 1: Clear cell counts and cell offsets (merged into single pass)
	{
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.clear);
		pass.setBindGroup(0, resources.bindGroups.clear);
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

	// Pass 3b: Compute cumulative block sums (for large grids)
	// This converts blockSums from per-block totals to exclusive prefix sums
	if (prefixSumWorkgroups > 1) {
		const pass = encoder.beginComputePass();
		pass.setPipeline(resources.pipelines.prefixSumCumulative);
		pass.setBindGroup(0, resources.bindGroups.prefixSum);
		pass.dispatchWorkgroups(1); // Single workgroup, single thread
		pass.end();
	}

	// Pass 3c: Add cumulative block sums to get final prefix sums - O(1) per element
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
			readFromA ? resources.bindGroups.simulate0A : resources.bindGroups.simulate0B
		);
		pass.setBindGroup(1, resources.bindGroups.simulate1);
		pass.dispatchWorkgroups(boidWorkgroups);
		pass.end();
	}

	// Iterative metrics passes (after simulate, so density is available)
	if (iterativeConfig) {
		// For rank: use rank bind groups (with velocities)
		const rankBindGroup0 = readFromA ? resources.bindGroups.rank0B : resources.bindGroups.rank0A;

		// Pass 6: Spectral/Flow influence (uses velocities for flow modes)
		if (iterativeConfig.enableInfluence) {
			// Initialize if needed - use rank2B so it writes to buffer A
			if (iterativeConfig.needsRankInit) {
				const pass = encoder.beginComputePass();
				pass.setPipeline(resources.pipelines.rankInit);
				pass.setBindGroup(0, rankBindGroup0);
				pass.setBindGroup(1, resources.bindGroups.rank1);
				pass.setBindGroup(2, resources.bindGroups.rank2B); // Write to A
				pass.dispatchWorkgroups(boidWorkgroups);
				pass.end();
			}

			// Ensure even iteration count so final result ends up in buffer A
			const rankIters =
				iterativeConfig.influenceIterations % 2 === 0
					? iterativeConfig.influenceIterations
					: iterativeConfig.influenceIterations + 1;

			// Run iterations with ping-pong
			for (let i = 0; i < rankIters; i++) {
				const pass = encoder.beginComputePass();
				pass.setPipeline(resources.pipelines.rankIter);
				pass.setBindGroup(0, rankBindGroup0);
				pass.setBindGroup(1, resources.bindGroups.rank1);
				pass.setBindGroup(
					2,
					i % 2 === 0 ? resources.bindGroups.rank2A : resources.bindGroups.rank2B
				);
				pass.dispatchWorkgroups(boidWorkgroups);
				pass.end();
			}
		}

		// Pass 7: Write final values to metrics.w
		if (iterativeConfig.enableInfluence) {
			const pass = encoder.beginComputePass();
			pass.setPipeline(resources.pipelines.writeMetrics);
			pass.setBindGroup(0, resources.bindGroups.writeMetrics);
			pass.dispatchWorkgroups(boidWorkgroups);
			pass.end();
		}
	}
}
