import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

// Exercise the production packers without requiring a browser or creating a
// GPU device. Transpilation only erases TypeScript; assertions inspect uploads.
function loadModule(name, dependencies = {}) {
	const source = readFileSync(new URL(`../src/lib/webgpu/${name}.ts`, import.meta.url), 'utf8');
	const { outputText } = ts.transpileModule(source, {
		compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
	});
	const exports = {};
	new Function('exports', 'require', outputText)(exports, (id) => {
		assert.ok(id in dependencies, `Unexpected dependency: ${id}`);
		return dependencies[id];
	});
	return exports;
}
const types = loadModule('types');
const { updateUniforms, updateInteractionMatrix, updateMetricRules } = loadModule('buffers', {
	'./types': types
});

function captureUploads() {
	const uploads = [];
	return {
		uploads,
		device: {
			queue: {
				writeBuffer: (buffer, offset, data) => {
					const bytes =
						data instanceof ArrayBuffer
							? data
							: data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
					uploads.push({ buffer, offset, bytes });
				}
			}
		}
	};
}

test('rank smoothing count uses padding without shifting camera or topology uniforms', () => {
	for (const [requested, expected] of [
		[0, 0],
		[1, 2],
		[4, 4],
		[5, 6],
		[6, 6],
		[8, 8]
	]) {
		const { device, uploads } = captureUploads();
		updateUniforms(
			device,
			{},
			{
				canvasWidth: 512,
				canvasHeight: 384,
				cellSize: 40,
				gridWidth: 13,
				gridHeight: 10,
				boidCount: 24,
				trailLength: 10,
				trailHead: 3,
				params: { ...types.DEFAULT_PARAMS, influenceIterations: requested },
				cursor: { x: 0, y: 0, isActive: false, isPressed: false },
				deltaTime: 1 / 60,
				time: 0,
				frameCount: 0,
				reducedWidth: 5,
				totalSlots: 180,
				embedBlend: 1,
				embedTopology: 5,
				viewProj: Float32Array.from({ length: 16 }, (_, i) => i + 1),
				cameraEye: [2, 3, 4],
				planeHalfWidth: 2,
				planeHalfHeight: 1,
				shellFade: 1,
				gridOpacity: 0.5,
				topologyBlend: 0.75,
				embedTopologyPrev: 3
			}
		);
		const { bytes } = uploads[0];
		const f = new Float32Array(bytes),
			u = new Uint32Array(bytes);
		assert.equal(bytes.byteLength, 512);
		assert.deepEqual(
			[...f.slice(48, 64)],
			Array.from({ length: 16 }, (_, i) => i + 1)
		);
		assert.deepEqual([...f.slice(64, 68)], [2, 3, 4, 0]);
		assert.deepEqual([...f.slice(68, 72)], [2, 1, 1, 0.5]);
		assert.equal(f[72], 0.75);
		assert.equal(u[73], 3);
		assert.equal(u[74], expected);
		assert.equal(u[75], 0);
	}
});

test('species matrix ignores metric rules and missing targets but retains wildcard rules', () => {
	const { device, uploads } = captureUploads();
	updateInteractionMatrix(device, {}, [
		{
			id: 0,
			interactions: [
				{ targetSpecies: -1, behavior: 1, strength: 0.5, range: 80 },
				{ type: 'metric', targetSpecies: 1, behavior: 2, strength: 1, range: 150 },
				{ behavior: 2, strength: 1, range: 150 },
				{ targetSpecies: 2, behavior: 3, strength: 0.75, range: 120 }
			]
		}
	]);
	const values = new Float32Array(uploads[0].bytes);
	assert.deepEqual([...values.slice(0, 4)], [0, 0, 0, 0]);
	assert.deepEqual([...values.slice(4, 8)], [1, 0.5, 80, 0]);
	assert.deepEqual([...values.slice(8, 12)], [3, 0.75, 120, 0]);
});

test('metric rules with omitted source upload local density', () => {
	const { device, uploads } = captureUploads();
	updateMetricRules(
		device,
		{},
		{},
		[{ id: 0, interactions: [{ type: 'metric', behavior: 1, strength: 0.5, range: 80 }] }],
		() => new Float32Array(64)
	);
	const values = new Float32Array(uploads[0].bytes);
	assert.equal(values[0], types.MetricSource.LocalDensity);
	assert.equal(values[5], 1);
	assert.ok([...values].every(Number.isFinite));
});
