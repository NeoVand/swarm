# Swarm

![Swarm Screenshot](static/swarmscreenshot.jpg)

**[▶ Live Demo](https://neovand.github.io/swarm/)**

A high-performance boids flocking simulation running entirely on the GPU using WebGPU. Watch thousands of autonomous agents exhibit emergent collective behavior—schooling, swarming, and flowing like starling murmurations.

## Features

- **Massive Scale**: Simulate 10,000+ boids at 60fps with smooth trails
- **GPU-Accelerated**: All simulation logic runs in WebGPU compute shaders
- **Interactive**: Attract, repel, or create vortices with cursor interactions
- **Topological Boundaries**: Torus, Klein bottle, Möbius strip, projective plane
- **Real-time Controls**: Adjust flocking behavior, colors, and dynamics on the fly

## How It Works

### The Boids Algorithm

Each boid follows three simple rules that create complex emergent behavior:

1. **Alignment** — Steer toward the average heading of nearby flockmates
2. **Cohesion** — Move toward the center of mass of nearby flockmates  
3. **Separation** — Avoid crowding neighbors (short-range repulsion)

These local interactions produce global patterns: schools of fish, flocks of birds, swarms of insects.

### Spatial Hashing

To efficiently find neighbors for thousands of boids, the simulation uses a **uniform spatial grid**:

1. **Count** — Count how many boids fall into each grid cell
2. **Prefix Sum** — Compute cumulative offsets for each cell
3. **Scatter** — Place boid indices into sorted order by cell

This transforms O(n²) neighbor searches into O(n) operations, enabling real-time simulation of massive swarms.

### GPU Pipeline

The entire simulation runs in WebGPU compute shaders:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Clear      │───▶│  Count      │───▶│ Prefix Sum  │───▶│  Scatter    │
│  Counts     │    │  Per Cell   │    │  (Parallel) │    │  Indices    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                │
                   ┌─────────────┐    ┌─────────────┐           ▼
                   │  Render     │◀───│  Simulate   │◀──────────┘
                   │  Boids      │    │  Physics    │
                   └─────────────┘    └─────────────┘
```

### Boundary Topologies

The simulation supports exotic topological spaces:

| Boundary | Description |
|----------|-------------|
| **Plane** | Hard walls, boids bounce back |
| **Torus** | Wraps horizontally and vertically (like Pac-Man) |
| **Cylinder** | Wraps on one axis only |
| **Möbius Strip** | Wraps with a twist—exit right, enter left upside-down |
| **Klein Bottle** | Double twist, non-orientable surface |
| **Projective Plane** | Both axes twisted, most exotic topology |

### Color Modes

Boids are colored based on various properties:

- **Direction** — Hue based on heading angle (rainbow compass)
- **Speed** — Slow=cool, fast=hot
- **Neighbors** — Density visualization
- **Acceleration** — Force magnitude
- **Turning** — Angular velocity

## Tech Stack

- **[SvelteKit](https://kit.svelte.dev/)** — Framework & static site generation
- **[WebGPU](https://www.w3.org/TR/webgpu/)** — GPU compute & rendering API
- **[WGSL](https://www.w3.org/TR/WGSL/)** — Shader language for WebGPU
- **[Tailwind CSS](https://tailwindcss.com/)** — Styling

## Development

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Browser Support

WebGPU is required. Currently supported in:
- Chrome 113+ / Edge 113+
- Firefox Nightly (with flag)
- Safari 18+ (macOS Sequoia / iOS 18)

## License

MIT

---

*Inspired by Craig Reynolds' [original boids paper](https://www.red3d.com/cwr/boids/) (1987)*
