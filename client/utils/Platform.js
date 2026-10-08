/**
 * PLATFORM
 * Single place for "where am I running" and "where is the server".
 *
 *  - isDesktop: true inside the Electron shell (desktop/preload.js exposes window.desktop).
 *  - API_BASE:  server origin from VITE_SERVER_URL. '' on web, so '/api/...' stays same-origin
 *               (Vite proxy in dev, same host in production).
 *  - apiFetch:  fetch() against API_BASE with the player's auth token attached.
 */

export const isDesktop = typeof window !== 'undefined' && !!window.desktop;

export const API_BASE = (import.meta.env?.VITE_SERVER_URL || '').replace(/\/+$/, '');

let _registry = null;

/** Called once from main.js so apiFetch can read the token the scenes keep in the registry. */
export function bindRegistry(registry) {
    _registry = registry;
}

function _authToken() {
    const fromRegistry = _registry?.get('token');
    if (fromRegistry) return fromRegistry;
    try { return localStorage.getItem('twt_token'); } catch { return null; }
}

/**
 * fetch() for the game server. `path` is '/api/...'.
 * Adds `Authorization: Bearer <token>` when a token exists and the caller didn't set one.
 */
export function apiFetch(path, opts = {}) {
    const headers = new Headers(opts.headers || {});
    const token   = _authToken();
    if (token && !headers.has('Authorization')) headers.set('Authorization', `Bearer ${token}`);
    return fetch(API_BASE + path, { ...opts, headers });
}
