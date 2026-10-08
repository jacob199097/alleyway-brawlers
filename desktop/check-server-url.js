// The packaged game runs from app://game, which has no /api, so the build must know the server.
if (!process.env.VITE_SERVER_URL) {
    console.error('VITE_SERVER_URL is not set. Example (PowerShell):');
    console.error('  $env:VITE_SERVER_URL="http://192.168.0.200:3000"; npm run build');
    process.exit(1);
}
console.log(`Building desktop client against ${process.env.VITE_SERVER_URL}`);
