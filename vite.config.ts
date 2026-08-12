import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// Honor a PORT env var so the dev/preview server can be assigned a free port
const port = process.env.PORT ? Number(process.env.PORT) : undefined;

export default defineConfig({
	plugins: [tailwindcss(), sveltekit()],
	server: { port },
	preview: { port }
});
