// Shared color utilities - constants, conversions, and spectrum functions
// This file is concatenated with other shader files at load time

// Color modes
const COLOR_SPEED: u32 = 0u;
const COLOR_ORIENTATION: u32 = 1u;
const COLOR_NEIGHBORS: u32 = 2u;
const COLOR_ACCELERATION: u32 = 3u;
const COLOR_TURNING: u32 = 4u;
const COLOR_NONE: u32 = 5u;
const COLOR_DENSITY: u32 = 6u;
const COLOR_SPECIES: u32 = 7u;
const COLOR_LOCAL_DENSITY: u32 = 8u;
const COLOR_ANISOTROPY: u32 = 9u;
// 10u was COLOR_DIFFUSION - removed
const COLOR_INFLUENCE: u32 = 11u;
const COLOR_SPECTRAL_RADIAL: u32 = 12u;
const COLOR_SPECTRAL_ASYMMETRY: u32 = 13u;
const COLOR_FLOW_ANGULAR: u32 = 14u;
const COLOR_FLOW_RADIAL: u32 = 15u;
const COLOR_FLOW_DIVERGENCE: u32 = 16u;
const COLOR_TRUE_TURNING: u32 = 17u;

// Color spectrums
const SPECTRUM_CHROME: u32 = 0u;
const SPECTRUM_OCEAN: u32 = 1u;
const SPECTRUM_BANDS: u32 = 2u;
const SPECTRUM_RAINBOW: u32 = 3u;
const SPECTRUM_MONO: u32 = 4u;

// Curve indices for lookupCurve
const CURVE_HUE: u32 = 0u;
const CURVE_SAT: u32 = 1u;
const CURVE_BRIGHT: u32 = 2u;

// HSV to RGB conversion
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x;
    let s = hsv.y;
    let v = hsv.z;
    
    let c = v * s;
    let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = v - c;
    
    var rgb: vec3<f32>;
    let hi = i32(h * 6.0) % 6;
    
    switch (hi) {
        case 0: { rgb = vec3<f32>(c, x, 0.0); }
        case 1: { rgb = vec3<f32>(x, c, 0.0); }
        case 2: { rgb = vec3<f32>(0.0, c, x); }
        case 3: { rgb = vec3<f32>(0.0, x, c); }
        case 4: { rgb = vec3<f32>(x, 0.0, c); }
        default: { rgb = vec3<f32>(c, 0.0, x); }
    }
    
    return rgb + m;
}

// HSL to RGB conversion
fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var rgb: vec3<f32>;
    let hi = i32(h * 6.0) % 6;
    
    switch (hi) {
        case 0: { rgb = vec3<f32>(c, x, 0.0); }
        case 1: { rgb = vec3<f32>(x, c, 0.0); }
        case 2: { rgb = vec3<f32>(0.0, c, x); }
        case 3: { rgb = vec3<f32>(0.0, x, c); }
        case 4: { rgb = vec3<f32>(x, 0.0, c); }
        default: { rgb = vec3<f32>(c, 0.0, x); }
    }
    
    return rgb + m;
}

// RGB to Hue extraction (returns hue in 0-1 range)
fn rgbToHue(rgb: vec3<f32>) -> f32 {
    let maxC = max(max(rgb.r, rgb.g), rgb.b);
    let minC = min(min(rgb.r, rgb.g), rgb.b);
    let delta = maxC - minC;
    
    if (delta < 0.001) {
        return 0.0;  // Gray, no hue
    }
    
    var h: f32;
    if (maxC == rgb.r) {
        h = (rgb.g - rgb.b) / delta;
        if (rgb.g < rgb.b) { h += 6.0; }
    } else if (maxC == rgb.g) {
        h = 2.0 + (rgb.b - rgb.r) / delta;
    } else {
        h = 4.0 + (rgb.r - rgb.g) / delta;
    }
    
    return h / 6.0;  // Normalize to 0-1
}

// Get color from spectrum palette
fn getColorFromSpectrum(t: f32, spectrum: u32) -> vec3<f32> {
    let tt = clamp(t, 0.0, 1.0);
    
    switch (spectrum) {
        case SPECTRUM_CHROME: {
            // Blue to cyan to white to orange to red
            if (tt < 0.25) {
                return mix(vec3<f32>(0.2, 0.4, 0.9), vec3<f32>(0.3, 0.8, 0.9), tt * 4.0);
            } else if (tt < 0.5) {
                return mix(vec3<f32>(0.3, 0.8, 0.9), vec3<f32>(0.95, 0.95, 0.9), (tt - 0.25) * 4.0);
            } else if (tt < 0.75) {
                return mix(vec3<f32>(0.95, 0.95, 0.9), vec3<f32>(0.95, 0.6, 0.2), (tt - 0.5) * 4.0);
            } else {
                return mix(vec3<f32>(0.95, 0.6, 0.2), vec3<f32>(0.9, 0.2, 0.2), (tt - 0.75) * 4.0);
            }
        }
        case SPECTRUM_OCEAN: {
            // Sophisticated circular palette - loops back to start
            if (tt < 0.167) {
                return mix(vec3<f32>(0.3, 0.42, 0.78), vec3<f32>(0.25, 0.65, 0.7), tt * 6.0);
            } else if (tt < 0.333) {
                return mix(vec3<f32>(0.25, 0.65, 0.7), vec3<f32>(0.35, 0.75, 0.55), (tt - 0.167) * 6.0);
            } else if (tt < 0.5) {
                return mix(vec3<f32>(0.35, 0.75, 0.55), vec3<f32>(0.92, 0.78, 0.35), (tt - 0.333) * 6.0);
            } else if (tt < 0.667) {
                return mix(vec3<f32>(0.92, 0.78, 0.35), vec3<f32>(0.88, 0.5, 0.45), (tt - 0.5) * 6.0);
            } else if (tt < 0.833) {
                return mix(vec3<f32>(0.88, 0.5, 0.45), vec3<f32>(0.65, 0.42, 0.65), (tt - 0.667) * 6.0);
            } else {
                return mix(vec3<f32>(0.65, 0.42, 0.65), vec3<f32>(0.3, 0.42, 0.78), (tt - 0.833) * 6.0);
            }
        }
        case SPECTRUM_BANDS: {
            // Distinct color bands - sharp transitions
            let band = u32(tt * 6.0);
            let bandT = fract(tt * 6.0);
            let blend = smoothstep(0.85, 1.0, bandT);
            
            var c1: vec3<f32>;
            var c2: vec3<f32>;
            switch (band) {
                case 0u: { c1 = vec3<f32>(0.9, 0.2, 0.3); c2 = vec3<f32>(0.95, 0.6, 0.1); }
                case 1u: { c1 = vec3<f32>(0.95, 0.6, 0.1); c2 = vec3<f32>(0.95, 0.9, 0.2); }
                case 2u: { c1 = vec3<f32>(0.95, 0.9, 0.2); c2 = vec3<f32>(0.2, 0.8, 0.4); }
                case 3u: { c1 = vec3<f32>(0.2, 0.8, 0.4); c2 = vec3<f32>(0.2, 0.6, 0.9); }
                case 4u: { c1 = vec3<f32>(0.2, 0.6, 0.9); c2 = vec3<f32>(0.6, 0.3, 0.8); }
                default: { c1 = vec3<f32>(0.6, 0.3, 0.8); c2 = vec3<f32>(0.9, 0.2, 0.3); }
            }
            return mix(c1, c2, blend);
        }
        case SPECTRUM_RAINBOW: {
            return hsv2rgb(vec3<f32>(tt, 0.85, 0.9));
        }
        case SPECTRUM_MONO: {
            let brightness = 0.4 + tt * 0.6;
            return vec3<f32>(brightness, brightness * 0.95, brightness * 0.9);
        }
        default: {
            return vec3<f32>(1.0);
        }
    }
}
