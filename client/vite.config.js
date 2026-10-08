import { defineConfig } from 'vite';

export default defineConfig({
    base: './',
    server: {
        host:  '0.0.0.0',
        port:  5173,
        proxy: {
            '/api':       'http://localhost:3000',
            '/socket.io': { target: 'http://localhost:3000', ws: true },
        },
    },
    build: {
        outDir:     '../dist',
        emptyOutDir: true,
    },
    define: {
        // Expose for SocketClient
        'import.meta.env.VITE_SERVER_URL': JSON.stringify(
            process.env.VITE_SERVER_URL || 'http://localhost:3000'
        ),
    },
});
