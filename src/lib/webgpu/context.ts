// WebGPU context initialization

import type { GPUContext } from './types';

export async function initWebGPU(canvas: HTMLCanvasElement): Promise<GPUContext | null> {
	// Check for WebGPU support
	if (!navigator.gpu) {
		console.error('WebGPU not supported in this browser');
		return null;
	}

	// Request adapter
	const adapter = await navigator.gpu.requestAdapter({
		powerPreference: 'high-performance'
	});

	if (!adapter) {
		console.error('Failed to get WebGPU adapter');
		return null;
	}

	// Request device with required features
	const device = await adapter.requestDevice({
		requiredFeatures: [],
		requiredLimits: {
			maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
			maxBufferSize: adapter.limits.maxBufferSize,
			maxComputeWorkgroupsPerDimension: adapter.limits.maxComputeWorkgroupsPerDimension
		}
	});

	// Handle device loss
	device.lost.then((info) => {
		console.error('WebGPU device lost:', info.message);
		if (info.reason !== 'destroyed') {
			// Could attempt recovery here
			console.error('Device loss was unexpected');
		}
	});

	// Configure canvas context
	const context = canvas.getContext('webgpu');
	if (!context) {
		console.error('Failed to get WebGPU context from canvas');
		return null;
	}

	const format = navigator.gpu.getPreferredCanvasFormat();

	context.configure({
		device,
		format,
		alphaMode: 'premultiplied'
	});

	return {
		device,
		context,
		format,
		canvas
	};
}

export function resizeCanvas(gpuContext: GPUContext, width: number, height: number): void {
	const { canvas, device, context, format } = gpuContext;

	// Update canvas dimensions
	canvas.width = width;
	canvas.height = height;

	// Reconfigure context
	context.configure({
		device,
		format,
		alphaMode: 'premultiplied'
	});
}
