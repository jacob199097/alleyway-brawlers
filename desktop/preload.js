/**
 * Preload — the only bridge between the game page and Electron.
 * Runs sandboxed; expose narrow, typed values/functions only (never ipcRenderer itself).
 * The client detects the desktop build via `!!window.desktop` (client/utils/Platform.js).
 */

const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('desktop', {
    platform: process.platform,
});
