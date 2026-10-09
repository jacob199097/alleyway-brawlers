import { defineConfig, loadEnv } from 'vite';
import { cpSync } from 'node:fs';
import { resolve } from 'node:path';

// Scenes load images/audio/video by path ('assets/...') at runtime, so Vite never sees them.
// Copy the folder into the build so dist/ is a complete, self-contained game (desktop + web).
const copyRuntimeAssets = {
    name: 'copy-runtime-assets',
    apply: 'build',
    closeBundle() {
        cpSync(resolve(__dirname, 'assets'), resolve(__dirname, '../dist/assets'), { recursive: true });
    },
};

export default defineConfig(({ mode }) => {
    // VITE_SERVER_URL (shell env or .env file) is exposed to the client as
    // import.meta.env.VITE_SERVER_URL and read by utils/Platform.js. Unset = same-origin '/api'.
    const env    = { ...loadEnv(mode, process.cwd(), 'VITE_'), ...process.env };
    const target = env.VITE_SERVER_URL || 'http://localhost:3000';

    return {
        base: './',
        plugins: [copyRuntimeAssets],
        server: {
            host:  '0.0.0.0',
            port:  5173,
            // Card rules live in ../shared (also loaded by the backend)
            fs:    { allow: ['..'] },
            proxy: {
                '/api':       target,
                '/socket.io': { target, ws: true },
            },
        },
        build: {
            outDir:     '../dist',
            emptyOutDir: true,
        },
    };
});
