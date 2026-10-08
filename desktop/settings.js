/**
 * settings.json in app.getPath('userData').
 * One flat object shared by the main process (display, v-sync) and the game client
 * (audio, graphics — see client/utils/SettingsManager.js). The main process only interprets
 * the keys in DISPLAY_DEFAULTS; everything else is stored as the client sends it.
 */

const { app } = require('electron');
const fs   = require('node:fs');
const path = require('node:path');

const FILE = path.join(app.getPath('userData'), 'settings.json');

const DISPLAY_DEFAULTS = {
    displayMode:  'windowed',   // 'windowed' | 'borderless' | 'fullscreen'
    windowWidth:  null,         // physical pixels; null = pick a size that fits the monitor
    windowHeight: null,
    displayId:    null,         // Electron display id; null = primary
    vsync:        true,         // applied at launch only
};

let data = { ...DISPLAY_DEFAULTS };
let writeTimer = null;

function load() {
    try {
        const parsed = JSON.parse(fs.readFileSync(FILE, 'utf8'));
        if (parsed && typeof parsed === 'object') data = { ...DISPLAY_DEFAULTS, ...parsed };
    } catch { /* first launch or corrupt file — defaults */ }
    if (!['windowed', 'borderless', 'fullscreen'].includes(data.displayMode)) data.displayMode = 'windowed';
    return data;
}

function get() { return data; }

/** Merge and write (debounced, so volume-slider drags don't hammer the disk). */
function set(patch) {
    if (!patch || typeof patch !== 'object') return data;
    data = { ...data, ...patch };
    clearTimeout(writeTimer);
    writeTimer = setTimeout(flush, 250);
    return data;
}

function flush() {
    clearTimeout(writeTimer);
    try {
        fs.mkdirSync(path.dirname(FILE), { recursive: true });
        fs.writeFileSync(FILE, JSON.stringify(data, null, 2));
    } catch (err) {
        console.error('[settings] write failed:', err);
    }
}

module.exports = { load, get, set, flush };
