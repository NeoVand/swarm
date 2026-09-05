// Executes both complete shaders on the same GPU. This compares actual f32
// outputs, including circular smoothing and retained state across two frames.
const output = document.querySelector('#result');
if (!output) throw new Error('Missing regression result element');

async function run() {
	/** @type {{ baseline: string, common: string, embed: string, current: string, legacy: string }} */
	const sources = await fetch('/sources').then((r) => r.json());
	const adapter = await navigator.gpu?.requestAdapter();
	if (!adapter) throw new Error('WebGPU adapter unavailable');
	const device = await adapter.requestDevice({
		requiredLimits: { maxStorageBuffersPerShaderStage: 10 }
	});
	/** @type {string[]} */
	const errors = [];
	device.addEventListener('uncapturederror', (event) => errors.push(event.error.message));
	/** @type {GPUBuffer[]} */
	const allocated = [];
	/**
	 * @param {GPUAllowSharedBufferSource} data
	 * @param {GPUBufferUsageFlags} [usage]
	 */
	const buffer = (data, usage = GPUBufferUsage.STORAGE) => {
		const b = device.createBuffer({
			size: data.byteLength,
			usage: usage | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC
		});
		device.queue.writeBuffer(b, 0, data);
		allocated.push(b);
		return b;
	};
	/** @param {GPUBufferBindingType[]} types */
	const layout = (types) =>
		device.createBindGroupLayout({
			entries: types.map((type, binding) => ({
				binding,
				visibility: GPUShaderStage.COMPUTE,
				buffer: { type }
			}))
		});
	const group0Layout = layout(['uniform', ...Array(5).fill('read-only-storage')]);
	const group1Layout = layout(['read-only-storage', 'read-only-storage']);
	const oldLayout = layout(['read-only-storage', 'storage']);
	const newLayout = layout(['storage']);
	/**
	 * @param {string} rank
	 * @param {GPUBindGroupLayout} rankLayout
	 */
	const pipelines = async (rank, rankLayout) => {
		const module = device.createShaderModule({ code: sources.common + sources.embed + rank });
		const messages = (await module.getCompilationInfo()).messages.filter((m) => m.type === 'error');
		if (messages.length) throw new Error(messages.map((m) => m.message).join('\n'));
		const pipelineLayout = device.createPipelineLayout({
			bindGroupLayouts: [group0Layout, group1Layout, rankLayout]
		});
		const [init_main, iter_main] = await Promise.all(
			['init_main', 'iter_main'].map((entryPoint) =>
				device.createComputePipelineAsync({
					layout: pipelineLayout,
					compute: { module, entryPoint }
				})
			)
		);
		return { init_main, iter_main };
	};
	const oldPipelines = await pipelines(sources.legacy, oldLayout);
	const newPipelines = await pipelines(sources.current, newLayout);
	/**
	 * @param {GPUBindGroupLayout} bindLayout
	 * @param {GPUBuffer[]} buffers
	 */
	const bind = (bindLayout, buffers) =>
		device.createBindGroup({
			layout: bindLayout,
			entries: buffers.map((b, binding) => ({ binding, resource: { buffer: b } }))
		});

	// Dense asymmetric cluster, seam-adjacent pairs, and isolated boids exercise
	// local and sparse branches. Non-multiple-of-256 count checks the bounds guard.
	const points = [
		[160, 130],
		[162, 133],
		[171, 128],
		[180, 137],
		[155, 149],
		[149, 135],
		[162, 130],
		[171, 145],
		[184, 147],
		[158, 118],
		[165, 138],
		[176, 140],
		[3, 90],
		[509, 90],
		[5, 294],
		[507, 294],
		[100, 2],
		[100, 382],
		[400, 2],
		[400, 382],
		[280, 250],
		[450, 200],
		[295, 70],
		[90, 300]
	];
	const count = points.length;
	const positions = buffer(new Float32Array(points.flat()));
	const velocities = buffer(new Float32Array(count * 2));
	/** @type {number[][]} */
	const cells = Array.from({ length: 180 }, () => []);
	points.forEach(([x, y], index) => {
		const cx = Math.floor(x / 40),
			cy = Math.floor(y / 40);
		cells[9 * (Math.floor(cy / 3) * 5 + Math.floor(cx / 3)) + 3 * (cx % 3) + (cy % 3)].push(index);
	});
	let offset = 0;
	const starts = cells.map((cell) => {
		const start = offset;
		offset += cell.length;
		return start;
	});
	const prefix = buffer(new Uint32Array(starts));
	const counts = buffer(new Uint32Array(cells.map((cell) => cell.length)));
	const indices = buffer(new Uint32Array(cells.flat()));
	const species = buffer(new Uint32Array(count));
	const metrics = buffer(new Float32Array(count * 4));
	const uniformData = new ArrayBuffer(512);
	const floats = new Float32Array(uniformData),
		ints = new Uint32Array(uniformData);
	floats[0] = 512;
	floats[1] = 384;
	floats[2] = 40;
	ints[3] = 13;
	ints[4] = 10;
	ints[5] = count;
	floats[11] = 80;
	floats[12] = 4;
	ints[37] = 5;
	ints[38] = cells.length;
	floats[68] = 4 / 3;
	floats[69] = 1;
	floats[72] = 1;
	const uniforms = buffer(uniformData, GPUBufferUsage.UNIFORM);
	const group0 = bind(group0Layout, [uniforms, positions, velocities, prefix, counts, indices]);
	const group1 = bind(group1Layout, [species, metrics]);
	const initial = new Float32Array(points.map((_, i) => [0.001, 0.999, 0.25, 0.5, 0.75][i % 5]));
	const oldA = buffer(initial),
		oldB = buffer(initial),
		current = buffer(initial);
	const oldAB = bind(oldLayout, [oldA, oldB]),
		oldBA = bind(oldLayout, [oldB, oldA]);
	const currentGroup = bind(newLayout, [current]);
	const readback = device.createBuffer({
		size: count * 8,
		usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
	});
	allocated.push(readback);
	/**
	 * @param {GPUCommandEncoder} encoder
	 * @param {GPUComputePipeline} pipeline
	 * @param {GPUBindGroup} ranks
	 */
	const dispatch = (encoder, pipeline, ranks) => {
		const pass = encoder.beginComputePass();
		pass.setPipeline(pipeline);
		pass.setBindGroup(0, group0);
		pass.setBindGroup(1, group1);
		pass.setBindGroup(2, ranks);
		pass.dispatchWorkgroups(Math.ceil(count / 256));
		pass.end();
	};
	let cases = 0,
		compared = 0,
		maxDifference = 0;
	try {
		for (const topology of [0, 3, 5, 8])
			for (const speedMode of [0, 1, 2])
				for (let mode = 0; mode < 6; mode++)
					for (const requestedSteps of [0, 1, 4, 6, 8]) {
						const steps = Math.ceil(requestedSteps / 2) * 2;
						ints[16] = topology;
						ints[36] = mode;
						ints[47] = topology;
						ints[73] = topology;
						ints[74] = steps;
						floats[46] = topology === 0 ? 0 : 1;
						device.queue.writeBuffer(uniforms, 0, uniformData);
						device.queue.writeBuffer(
							velocities,
							0,
							new Float32Array(
								points.flatMap((_, i) =>
									speedMode === 0
										? [0, 0]
										: speedMode === 1
											? [2, 1]
											: [Math.cos(i * 0.7) * (0.1 + (i % 5)), Math.sin(i * 0.7) * (0.1 + (i % 5))]
								)
							)
						);
						device.queue.writeBuffer(oldA, 0, initial);
						device.queue.writeBuffer(current, 0, initial);
						const encoder = device.createCommandEncoder();
						if (cases % 2 === 0) {
							dispatch(encoder, oldPipelines.init_main, oldBA);
							dispatch(encoder, newPipelines.init_main, currentGroup);
						}
						for (let frame = 0; frame < 2; frame++) {
							for (let step = 0; step < steps; step++)
								dispatch(encoder, oldPipelines.iter_main, step % 2 === 0 ? oldAB : oldBA);
							if (steps > 0) dispatch(encoder, newPipelines.iter_main, currentGroup);
						}
						encoder.copyBufferToBuffer(oldA, 0, readback, 0, count * 4);
						encoder.copyBufferToBuffer(current, 0, readback, count * 4, count * 4);
						device.queue.submit([encoder.finish()]);
						await readback.mapAsync(GPUMapMode.READ);
						const actual = new Float32Array(readback.getMappedRange());
						for (let i = 0; i < count; i++) {
							const difference = Math.abs(actual[i] - actual[count + i]);
							if (!Number.isFinite(difference) || difference > 0.00001)
								throw new Error(
									JSON.stringify({
										topology,
										speedMode,
										mode,
										requestedSteps,
										boid: i,
										old: actual[i],
										current: actual[count + i],
										difference
									})
								);
							maxDifference = Math.max(maxDifference, difference);
							compared++;
						}
						readback.unmap();
						cases++;
					}
		if (errors.length) throw new Error(errors.join('\n'));
		return {
			status: 'PASS',
			cases,
			compared,
			framesPerCase: 2,
			maxDifference,
			baseline: sources.baseline,
			adapter: adapter.info?.description ?? 'available',
			coverage:
				'6 modes × 5 iteration counts × 4 topologies × 3 velocity fixtures; dense/sparse/seam neighbors; alternating initialization'
		};
	} finally {
		for (const b of allocated) b.destroy();
		device.destroy();
	}
}

run()
	.then((result) => {
		output.textContent = JSON.stringify(result, null, 2);
	})
	.catch((error) => {
		output.textContent = 'FAIL\n' + error.stack;
	});
