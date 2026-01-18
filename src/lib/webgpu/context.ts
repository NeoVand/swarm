// WebGPU context initialization

import type { GPUContext } from './types';

// Track the current device for cleanup during HMR
let currentDevice: GPUDevice | null = null;
let currentContext: GPUCanvasContext | null = null;

export async function initWebGPU(canvas: HTMLCanvasElement): Promise<GPUContext | null> {
	// Check for WebGPU support
	if (!navigator.gpu) {
		console.error('WebGPU not supported in this browser');
		return null;
	}

	// Clean up any existing context from previous HMR cycle
	if (currentContext) {
		try {
			currentContext.unconfigure();
		} catch {
			// Context may already be invalid
		}
		currentContext = null;
	}

	if (currentDevice) {
		try {
			currentDevice.destroy();
		} catch {
			// Device may already be destroyed
		}
		currentDevice = null;
		// Small delay to let GPU release resources
		await new Promise(resolve => setTimeout(resolve, 100));
	}

	// Request adapter with retry logic
	let adapter: GPUAdapter | null = null;
	for (let attempt = 0; attempt < 3; attempt++) {
		adapter = await navigator.gpu.requestAdapter({
			powerPreference: 'high-performance'
		});
		if (adapter) break;
		// Wait before retry
		await new Promise(resolve => setTimeout(resolve, 200 * (attempt + 1)));
	}

	if (!adapter) {
		console.error('Failed to get WebGPU adapter after retries');
		return null;
	}

	// Request device with required features
	let device: GPUDevice;
	try {
		device = await adapter.requestDevice({
			requiredFeatures: [],
			requiredLimits: {
				maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
				maxBufferSize: adapter.limits.maxBufferSize,
				maxComputeWorkgroupsPerDimension: adapter.limits.maxComputeWorkgroupsPerDimension
			}
		});
	} catch (e) {
		console.error('Failed to request WebGPU device:', e);
		return null;
	}

	currentDevice = device;

	// Handle device loss
	device.lost.then((info) => {
		console.error('WebGPU device lost:', info.message);
		if (info.reason !== 'destroyed') {
			console.error('Device loss was unexpected - may need to reload page');
		}
		if (currentDevice === device) {
			currentDevice = null;
		}
	});

	// Configure canvas context
	const context = canvas.getContext('webgpu');
	if (!context) {
		console.error('Failed to get WebGPU context from canvas');
		device.destroy();
		currentDevice = null;
		return null;
	}

	currentContext = context;
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

export function destroyWebGPU(gpuContext: GPUContext | null): void {
	if (!gpuContext) return;

	try {
		gpuContext.context.unconfigure();
	} catch {
		// May already be unconfigured
	}

	try {
		gpuContext.device.destroy();
	} catch {
		// May already be destroyed
	}

	if (currentDevice === gpuContext.device) {
		currentDevice = null;
	}
	if (currentContext === gpuContext.context) {
		currentContext = null;
	}
}

export function resizeCanvas(gpuContext: GPUContext, width: number, height: number): void {
	const { canvas, device, context, format } = gpuContext;

	// Update canvas dimensions
	canvas.width = width;
	canvas.height = height;

	// Reconfigure context (may fail if device is lost)
	try {
		context.configure({
			device,
			format,
			alphaMode: 'premultiplied'
		});
	} catch (e) {
		console.warn('Failed to reconfigure canvas context:', e);
	}
}
