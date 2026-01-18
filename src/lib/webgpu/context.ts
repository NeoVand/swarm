// WebGPU context initialization

import type { GPUContext } from './types';

// Track the current device for cleanup during HMR
let currentDevice: GPUDevice | null = null;
let currentContext: GPUCanvasContext | null = null;
let isInitializing = false;
let lastInitAttempt = 0;

// Track if we've had initialization failures (for recovery mode)
export let initializationFailed = false;
export let failureReason: 'no-webgpu' | 'no-adapter' | 'device-error' | null = null;

export async function initWebGPU(canvas: HTMLCanvasElement): Promise<GPUContext | null> {
	// Prevent concurrent initialization attempts
	if (isInitializing) {
		console.warn('WebGPU initialization already in progress');
		return null;
	}

	// Rate limit initialization attempts (minimum 500ms between attempts)
	const now = Date.now();
	const timeSinceLastAttempt = now - lastInitAttempt;
	if (timeSinceLastAttempt < 500 && lastInitAttempt > 0) {
		const waitTime = 500 - timeSinceLastAttempt;
		await new Promise(resolve => setTimeout(resolve, waitTime));
	}
	lastInitAttempt = Date.now();

	isInitializing = true;
	initializationFailed = false;
	failureReason = null;

	try {
		// Check for WebGPU support
		if (!navigator.gpu) {
			console.error('WebGPU not supported in this browser');
			initializationFailed = true;
			failureReason = 'no-webgpu';
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
			// Longer delay to let GPU fully release resources
			await new Promise(resolve => setTimeout(resolve, 300));
		}

		// Request adapter with retry logic and exponential backoff
		let adapter: GPUAdapter | null = null;
		const maxRetries = 5;
		for (let attempt = 0; attempt < maxRetries; attempt++) {
			try {
				adapter = await navigator.gpu.requestAdapter({
					powerPreference: 'high-performance'
				});
				if (adapter) break;
			} catch (e) {
				console.warn(`Adapter request attempt ${attempt + 1} failed:`, e);
			}
			// Exponential backoff: 200ms, 400ms, 800ms, 1600ms, 3200ms
			const delay = 200 * Math.pow(2, attempt);
			console.log(`Retrying adapter request in ${delay}ms (attempt ${attempt + 2}/${maxRetries})...`);
			await new Promise(resolve => setTimeout(resolve, delay));
		}

		if (!adapter) {
			console.error('Failed to get WebGPU adapter after retries');
			initializationFailed = true;
			failureReason = 'no-adapter';
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
			initializationFailed = true;
			failureReason = 'device-error';
			return null;
		}

		currentDevice = device;

		// Handle device loss
		device.lost.then((info) => {
			console.error('WebGPU device lost:', info.message);
			if (info.reason !== 'destroyed') {
				console.error('Device loss was unexpected - may need to reload page');
				initializationFailed = true;
				failureReason = 'device-error';
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
			initializationFailed = true;
			failureReason = 'device-error';
			return null;
		}

		currentContext = context;
		const format = navigator.gpu.getPreferredCanvasFormat();

		context.configure({
			device,
			format,
			alphaMode: 'premultiplied'
		});

		// Success - reset failure state
		initializationFailed = false;
		failureReason = null;

		return {
			device,
			context,
			format,
			canvas
		};
	} finally {
		isInitializing = false;
	}
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
