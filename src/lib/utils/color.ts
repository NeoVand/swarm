// Shared color utility functions

/**
 * Create an HSL color string
 * @param hue - Hue value (0-360)
 * @param saturation - Saturation percentage (0-100)
 * @param lightness - Lightness percentage (0-100)
 * @returns CSS HSL color string
 */
export function hslColor(hue: number, saturation: number, lightness: number): string {
	return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
}
