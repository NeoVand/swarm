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
		await new Promise((resolve) => setTimeout(resolve, waitTime));
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
			await new Promise((resolve) => setTimeout(resolve, 300));
		}

		// Detect if we're on a mobile device
		const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
			navigator.userAgent
		);

		// Request adapter with retry logic and exponential backoff
		// On mobile, try without power preference first (more compatible), then with preferences
		let adapter: GPUAdapter | null = null;
		const maxRetries = 5;

		// Different adapter options to try - mobile devices often work better without power preference
		const adapterOptions: GPURequestAdapterOptions[] = isMobile
			? [
					{}, // No preference - most compatible on mobile
					{ powerPreference: 'low-power' },
					{ powerPreference: 'high-performance' }
				]
			: [
					{ powerPreference: 'high-performance' },
					{ powerPreference: 'low-power' },
					{} // No preference as fallback
				];

		for (let attempt = 0; attempt < maxRetries; attempt++) {
			// Cycle through different adapter options
			const options = adapterOptions[attempt % adapterOptions.length];
			try {
				adapter = await navigator.gpu.requestAdapter(options);
				if (adapter) {
					console.log(`WebGPU adapter obtained with options:`, options);
					break;
				}
			} catch (e) {
				console.warn(
					`Adapter request attempt ${attempt + 1} failed with options ${JSON.stringify(options)}:`,
					e
				);
			}
			// Exponential backoff: 200ms, 400ms, 800ms, 1600ms, 3200ms
			const delay = 200 * Math.pow(2, attempt);
			console.log(
				`Retrying adapter request in ${delay}ms (attempt ${attempt + 2}/${maxRetries})...`
			);
			await new Promise((resolve) => setTimeout(resolve, delay));
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
			// We need at least 9 storage buffers per stage (8 core + 1 CA state)
			const requiredStorageBuffers = 10;
			const adapterStorageLimit = adapter.limits.maxStorageBuffersPerShaderStage;
			
			console.log(`Adapter storage buffer limit: ${adapterStorageLimit}, requesting: ${requiredStorageBuffers}`);
			
			if (adapterStorageLimit < requiredStorageBuffers) {
				console.warn(
					`Adapter supports only ${adapterStorageLimit} storage buffers per stage, ` +
					`but we need ${requiredStorageBuffers}. CA features may be limited.`
				);
			}
			
			device = await adapter.requestDevice({
				requiredFeatures: [],
				requiredLimits: {
					maxStorageBufferBindingSize: adapter.limits.maxStorageBufferBindingSize,
					maxBufferSize: adapter.limits.maxBufferSize,
					maxComputeWorkgroupsPerDimension: adapter.limits.maxComputeWorkgroupsPerDimension,
					maxStorageBuffersPerShaderStage: Math.min(requiredStorageBuffers, adapterStorageLimit)
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
			alphaMode: 'opaque'
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
			alphaMode: 'opaque'
		});
	} catch (e) {
		console.warn('Failed to reconfigure canvas context:', e);
	}
}
