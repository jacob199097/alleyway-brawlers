/**
 * SOCKET CLIENT
 * Singleton wrapper around Socket.io-client.
 * Scenes import this module and call SocketClient.emit / SocketClient.on
 * without managing the socket lifecycle themselves.
 */

import { io } from 'socket.io-client';

const SERVER_URL = import.meta.env?.VITE_SERVER_URL || 'http://localhost:3000';

class _SocketClient {
    constructor() {
        this._socket   = null;
        this._handlers = new Map();   // event → [handler, ...]
    }

    /**
     * Connect (or re-use existing connection) with a JWT token.
     * @param {string} token
     */
    connect(token) {
        if (this._socket?.connected) return;

        this._socket = io(SERVER_URL, {
            auth:        { token },
            reconnection: true,
            reconnectionDelay: 1000,
            reconnectionAttempts: 10,
        });

        this._socket.on('connect', () => {
            console.log('[Socket] Connected:', this._socket.id);
        });

        this._socket.on('connect_error', (err) => {
            console.error('[Socket] Connection error:', err.message);
        });

        this._socket.on('disconnect', (reason) => {
            console.warn('[Socket] Disconnected:', reason);
        });

        // Re-attach any handlers registered before connection
        for (const [event, handlers] of this._handlers) {
            handlers.forEach(h => this._socket.on(event, h));
        }
    }

    disconnect() {
        this._socket?.disconnect();
        this._socket = null;
    }

    /**
     * Emit an event to the server.
     */
    emit(event, data) {
        if (!this._socket?.connected) {
            console.warn('[Socket] Cannot emit — not connected.');
            return;
        }
        this._socket.emit(event, data);
    }

    /**
     * Listen for a server event.
     * Handlers survive reconnects because they're stored in _handlers.
     */
    on(event, handler) {
        if (!this._handlers.has(event)) this._handlers.set(event, []);
        this._handlers.get(event).push(handler);
        this._socket?.on(event, handler);
    }

    /**
     * Remove a specific listener (or all if handler is omitted).
     */
    off(event, handler) {
        if (handler) {
            const list = this._handlers.get(event) || [];
            this._handlers.set(event, list.filter(h => h !== handler));
            this._socket?.off(event, handler);
        } else {
            this._handlers.delete(event);
            this._socket?.removeAllListeners(event);
        }
    }

    get isConnected() { return this._socket?.connected ?? false; }
    get id()          { return this._socket?.id ?? null; }
}

export const SocketClient = new _SocketClient();
