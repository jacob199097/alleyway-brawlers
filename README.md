Alleyway brawlers:

Start game server side:
cd client
$env:VITE_SERVER_URL="http://192.168.0.200:3000"; npm run dev
Game can be reached on: http://localhost:5173/

Desktop (Electron) app:
cd desktop
npm install
$env:VITE_SERVER_URL="http://192.168.0.200:3000"; npm run dev     # Electron window on the Vite dev server (F12 = DevTools)
$env:VITE_SERVER_URL="http://192.168.0.200:3000"; npm run build   # desktop/release: installer .exe + win-unpacked/

Desktop controls: right-click a card = details (right-click/Esc closes) · hover = name tooltip ·
Space/Enter = next phase · 1-9 = pick a hand card · hold Tab = zone counts · Esc = settings · F11 = fullscreen
