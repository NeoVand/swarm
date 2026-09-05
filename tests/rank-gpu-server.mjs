// Run: node tests/rank-gpu-server.mjs <git-ref-before-rank-optimization>
// Open the printed localhost URL in a browser with WebGPU. No packages needed.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const baseline = process.argv[2] ?? 'HEAD';
const shaders = new URL('../src/lib/shaders/', import.meta.url);
const read = (name) => readFileSync(new URL(name, shaders), 'utf8');
const sources = {
	baseline,
	common: read('common.wgsl'),
	embed: read('embed.wgsl'),
	current: read('rank.wgsl'),
	legacy: execFileSync('git', ['show', `${baseline}:src/lib/shaders/rank.wgsl`], {
		encoding: 'utf8'
	})
};
if (!sources.legacy.includes('ranksIn')) {
	throw new Error('Choose a baseline git revision containing the original ping-pong rank shader.');
}
const server = createServer((request, response) => {
	if (request.url === '/sources') {
		response.setHeader('Content-Type', 'application/json');
		response.end(
			JSON.stringify({ ...sources, common: read('common.wgsl'), current: read('rank.wgsl') })
		);
	} else if (request.url === '/run.js') {
		response.setHeader('Content-Type', 'text/javascript; charset=utf-8');
		response.end(readFileSync(new URL('./rank-gpu-regression.js', import.meta.url)));
	} else {
		response.setHeader('Content-Type', 'text/html; charset=utf-8');
		response.end(
			'<!doctype html><meta charset="utf-8"><title>Rank GPU regression</title><h1>Rank GPU regression</h1><pre id="result">Running…</pre><script type="module" src="/run.js"></script>'
		);
	}
});
server.listen(8794, '127.0.0.1', () =>
	console.log('Open http://127.0.0.1:8794 — compares current shader with ' + baseline)
);
