/**
 * ALLEYWAY BRAWLERS — Electron main process
 *
 *  - Production: serves the Vite build (../dist, or resources/game when packaged) over app://game/
 *    so the page has a stable origin (localStorage survives) and media autoplay works.
 *  - Dev (`--dev`): loads the Vite dev server so hot reload keeps working.
 */

const { app, BrowserWindow, protocol, net, shell } = require('electron');
const path              = require('node:path');
const { pathToFileURL } = require('node:url');

const IS_DEV   = process.argv.includes('--dev');
const DEV_URL  = process.env.VITE_DEV_URL || 'http://localhost:5173';
const APP_URL  = 'app://game/index.html';
const GAME_DIR = app.isPackaged
    ? path.join(process.resourcesPath, 'game')
    : path.join(__dirname, '..', 'dist');

// Must run before app is ready
protocol.registerSchemesAsPrivileged([{
    scheme: 'app',
    privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true },
}]);
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

// One running copy only — a second launch focuses the existing window
if (!app.requestSingleInstanceLock()) app.quit();

let win = null;

function serveGameFiles() {
    protocol.handle('app', (req) => {
        const rel  = decodeURIComponent(new URL(req.url).pathname);
        const file = path.normalize(path.join(GAME_DIR, rel === '/' ? 'index.html' : rel));
        if (!file.startsWith(GAME_DIR + path.sep)) {
            return new Response('Not found', { status: 404 });
        }
        return net.fetch(pathToFileURL(file).toString());
    });
}

function createWindow() {
    win = new BrowserWindow({
        width:           1280,
        height:          720,
        minWidth:        844,
        minHeight:       390,
        useContentSize:  true,
        backgroundColor: '#0d0d1a',
        title:           'AlleyWay Brawlers',
        autoHideMenuBar: true,
        show:            false,
        webPreferences: {
            preload:          path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration:  false,
            sandbox:          true,
        },
    });
    win.removeMenu();
    win.once('ready-to-show', () => win.show());

    // Links that try to open a new window go to the system browser
    win.webContents.setWindowOpenHandler(({ url }) => {
        if (/^https?:\/\//.test(url)) shell.openExternal(url);
        return { action: 'deny' };
    });
    // Never navigate the game window away from the game
    const home = IS_DEV ? new URL(DEV_URL).origin : 'app://game';
    win.webContents.on('will-navigate', (e, url) => {
        if (!url.startsWith(home)) e.preventDefault();
    });

    if (IS_DEV) {
        win.webContents.on('before-input-event', (e, input) => {
            if (input.type === 'keyDown' && input.key === 'F12') win.webContents.toggleDevTools();
        });
    }

    win.loadURL(IS_DEV ? DEV_URL : APP_URL);
    win.on('closed', () => { win = null; });
}

app.on('second-instance', () => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
});

app.whenReady().then(() => {
    serveGameFiles();
    createWindow();
});

app.on('window-all-closed', () => app.quit());
