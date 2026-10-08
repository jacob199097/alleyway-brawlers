/**
 * ALLEYWAY BRAWLERS — Electron main process
 *
 *  - Production: serves the Vite build (../dist, or resources/game when packaged) over app://game/
 *    so the page has a stable origin (localStorage survives) and media autoplay works.
 *  - Dev (`--dev`): loads the Vite dev server so hot reload keeps working.
 *  - Display mode / resolution / monitor come from settings.json (settings.js) and can be
 *    changed live over IPC; v-sync is a Chromium switch, so it only changes on relaunch.
 */

const { app, BrowserWindow, protocol, net, shell, screen, ipcMain, dialog } = require('electron');
const fs                = require('node:fs');
const path              = require('node:path');
const { pathToFileURL } = require('node:url');
const settings          = require('./settings');

const IS_DEV   = process.argv.includes('--dev');
const DEV_URL  = process.env.VITE_DEV_URL || 'http://localhost:5173';
const APP_URL  = 'app://game/index.html';
const GAME_DIR = app.isPackaged
    ? path.join(process.resourcesPath, 'game')
    : path.join(__dirname, '..', 'dist');

const DISPLAY_KEYS = ['displayMode', 'windowWidth', 'windowHeight', 'displayId'];
const MODES        = ['windowed', 'borderless', 'fullscreen'];
// Window sizes offered in windowed mode (physical pixels), filtered to what fits the monitor
const RESOLUTIONS  = [[1280, 720], [1366, 768], [1600, 900], [1920, 1080], [2560, 1440], [3200, 1800], [3840, 2160]];
const TITLE_BAR_DIP = 32;
const REVERT_MS     = 10000;

// ── Before ready: settings that only apply at launch ────────────────────────
const launchSettings = settings.load();
const LAUNCH_VSYNC   = launchSettings.vsync !== false;
if (!LAUNCH_VSYNC) {
    app.commandLine.appendSwitch('disable-gpu-vsync');
    app.commandLine.appendSwitch('disable-frame-rate-limit');
}

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
        if (!file.startsWith(GAME_DIR + path.sep) || !fs.existsSync(file)) {
            return new Response('Not found', { status: 404 });
        }
        return net.fetch(pathToFileURL(file).toString());
    });
}

// ── Displays & sizes ─────────────────────────────────────────────────────────

function findDisplay(id) {
    return screen.getAllDisplays().find(d => d.id === id) || screen.getPrimaryDisplay();
}

function nativeSize(d) {
    return [Math.round(d.bounds.width * d.scaleFactor), Math.round(d.bounds.height * d.scaleFactor)];
}

/** Windowed sizes (physical px) whose window, title bar included, fits the display's work area. */
function windowedResolutions(d) {
    const maxW = d.workArea.width * d.scaleFactor;
    const maxH = (d.workArea.height - TITLE_BAR_DIP) * d.scaleFactor;
    const fits = RESOLUTIONS.filter(([w, h]) => w <= maxW && h <= maxH);
    return fits.length ? fits : [[Math.floor(maxW), Math.floor(maxH)]];
}

/** The saved window size if it still fits this display, else the largest size ≤ 80% of it. */
function resolveWindowSize(s, d) {
    const options = windowedResolutions(d);
    const saved   = options.find(([w, h]) => w === s.windowWidth && h === s.windowHeight);
    if (saved) return saved;
    const maxW = d.workArea.width * d.scaleFactor * 0.8;
    const maxH = d.workArea.height * d.scaleFactor * 0.8;
    const roomy = options.filter(([w, h]) => w <= maxW && h <= maxH);
    return roomy.length ? roomy[roomy.length - 1] : options[0];
}

/** Content bounds (DIP) for a window of physical size [w, h] centred in the display's work area. */
function windowedContentBounds(d, [w, h]) {
    const width  = Math.round(w / d.scaleFactor);
    const height = Math.round(h / d.scaleFactor);
    return {
        x: Math.round(d.workArea.x + (d.workArea.width - width) / 2),
        y: Math.round(d.workArea.y + (d.workArea.height - height + TITLE_BAR_DIP) / 2),
        width, height,
    };
}

function sanitizeDisplay(s) {
    const d    = findDisplay(s.displayId);
    const size = resolveWindowSize(s, d);
    return {
        displayMode:  MODES.includes(s.displayMode) ? s.displayMode : 'windowed',
        displayId:    d.id,
        windowWidth:  size[0],
        windowHeight: size[1],
    };
}

const pickDisplay = (s) => Object.fromEntries(DISPLAY_KEYS.map(k => [k, s[k]]));
const sameDisplay = (a, b) => DISPLAY_KEYS.every(k => a[k] === b[k]);

// ── Window ───────────────────────────────────────────────────────────────────

function createWindow() {
    const s = sanitizeDisplay(settings.get());
    settings.set(s);
    const d = findDisplay(s.displayId);
    const borderless = s.displayMode === 'borderless';

    const w = new BrowserWindow({
        ...(borderless ? d.bounds : windowedContentBounds(d, [s.windowWidth, s.windowHeight])),
        useContentSize:  !borderless,
        frame:           !borderless,
        thickFrame:      !borderless,   // no resize border, or Windows treats a screen-sized window as maximized (work area)
        fullscreen:      s.displayMode === 'fullscreen',
        // Windowed size comes from the Resolution setting, like a native game. Fullscreen on
        // Windows only covers the monitor if the window is resizable, so it is while fullscreen.
        resizable:       s.displayMode === 'fullscreen',
        maximizable:     false,
        fullscreenable:  true,
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
    w.removeMenu();
    w.hasFrame = !borderless;
    if (borderless) w.setBounds(d.bounds);

    // Links that try to open a new window go to the system browser
    w.webContents.setWindowOpenHandler(({ url }) => {
        if (/^https?:\/\//.test(url)) shell.openExternal(url);
        return { action: 'deny' };
    });
    // Never navigate the game window away from the game
    const home = IS_DEV ? new URL(DEV_URL).origin : 'app://game';
    w.webContents.on('will-navigate', (e, url) => {
        if (!url.startsWith(home)) e.preventDefault();
    });

    if (IS_DEV) {
        w.webContents.on('before-input-event', (e, input) => {
            if (input.type === 'keyDown' && input.key === 'F12') w.webContents.toggleDevTools();
        });
    }

    w.loadURL(IS_DEV ? DEV_URL : APP_URL);
    w.on('closed', () => { if (win === w) win = null; });
    win = w;
    return new Promise(resolve => w.once('ready-to-show', () => { w.show(); resolve(w); }));
}

function leaveFullScreen(w) {
    if (!w.isFullScreen()) return Promise.resolve();
    return new Promise(resolve => {
        const done = () => { clearTimeout(t); resolve(); };
        const t = setTimeout(done, 1500);
        w.once('leave-full-screen', done);
        w.setFullScreen(false);
    });
}

/** Put the window into the given display state. Borderless needs a frameless window, which
 *  Electron can't toggle on an existing window, so switching in/out of it recreates the window
 *  (the game reloads and signs back in from its saved token). */
async function applyDisplay(s) {
    settings.set(s);
    const d = findDisplay(s.displayId);

    if (win.hasFrame !== (s.displayMode !== 'borderless')) {
        const old = win;
        await createWindow();
        old.destroy();
        return;
    }

    if (s.displayMode === 'borderless') {
        win.setBounds(d.bounds);
        return;
    }
    await leaveFullScreen(win);
    win.setResizable(s.displayMode === 'fullscreen');
    win.setContentBounds(windowedContentBounds(d, [s.windowWidth, s.windowHeight]));
    if (s.displayMode === 'fullscreen') win.setFullScreen(true);
}

async function confirmKeep() {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), REVERT_MS);
    try {
        const { response } = await dialog.showMessageBox(win, {
            type:     'question',
            title:    'Display settings',
            message:  'Keep these display settings?',
            detail:   `They will revert in ${REVERT_MS / 1000} seconds.`,
            buttons:  ['Keep changes', 'Revert'],
            defaultId: 0,
            cancelId:  1,
            noLink:    true,
            signal:    abort.signal,
        });
        return response === 0;
    } catch {
        return false;
    } finally {
        clearTimeout(timer);
    }
}

// ── IPC (exposed to the game through preload.js) ────────────────────────────

let applying = false;

function registerIpc() {
    ipcMain.on('settings:init', (e) => {
        e.returnValue = { settings: settings.get(), launch: { vsync: LAUNCH_VSYNC } };
    });

    ipcMain.handle('settings:set', (_e, patch) => {
        // Display keys only change through display:apply (it validates and confirms them)
        const clean = { ...patch };
        DISPLAY_KEYS.forEach(k => delete clean[k]);
        settings.set(clean);
    });

    ipcMain.handle('display:info', () => {
        const current = sanitizeDisplay(settings.get());
        const displays = screen.getAllDisplays().map((d, i) => {
            const [w, h] = nativeSize(d);
            return {
                id:          d.id,
                label:       `${i + 1}: ${w}×${h}${d.id === screen.getPrimaryDisplay().id ? ' (main)' : ''}`,
                native:      [w, h],
                resolutions: windowedResolutions(d),
            };
        });
        return { current, displays };
    });

    ipcMain.handle('display:apply', async (_e, requested) => {
        if (applying || !win) return { kept: false, current: sanitizeDisplay(settings.get()) };
        applying = true;
        try {
            const prev = sanitizeDisplay(settings.get());
            const next = sanitizeDisplay({ ...prev, ...pickDisplay(requested || {}) });
            if (sameDisplay(prev, next)) return { kept: true, current: next };

            await applyDisplay(next);
            const kept = await confirmKeep();
            if (!kept) await applyDisplay(prev);
            settings.flush();
            return { kept, current: sanitizeDisplay(settings.get()) };
        } finally {
            applying = false;
        }
    });

    ipcMain.handle('app:relaunch', () => {
        settings.flush();
        app.relaunch();
        app.exit(0);
    });
}

app.on('second-instance', () => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
});

app.whenReady().then(() => {
    serveGameFiles();
    registerIpc();
    createWindow();
});

app.on('before-quit', () => settings.flush());
app.on('window-all-closed', () => app.quit());
