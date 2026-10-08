/**
 * Preload — the only bridge between the game page and Electron.
 * Runs sandboxed; expose narrow, typed values/functions only (never ipcRenderer itself).
 * The client detects the desktop build via `!!window.desktop` (client/utils/Platform.js).
 */

const { contextBridge, ipcRenderer } = require('electron');

// Read synchronously so the game can build its Phaser config (antialias, fps cap) at startup
const init  = ipcRenderer.sendSync('settings:init');
const cache = { ...init.settings };

contextBridge.exposeInMainWorld('desktop', {
    platform: process.platform,

    /** Values the running process was launched with (changing them needs a relaunch). */
    launch: { ...init.launch },

    settings: {
        get: () => ({ ...cache }),
        set: (patch) => {
            Object.assign(cache, patch);
            return ipcRenderer.invoke('settings:set', patch);
        },
    },

    display: {
        /** { current: {displayMode, displayId, windowWidth, windowHeight}, displays: [...] } */
        info: () => ipcRenderer.invoke('display:info'),
        /** Applies, asks the player to confirm (reverts after 10 s), resolves { kept, current }. */
        apply: (next) => ipcRenderer.invoke('display:apply', next),
    },

    relaunch: () => ipcRenderer.invoke('app:relaunch'),
});
