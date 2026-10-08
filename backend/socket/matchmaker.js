'use strict';

/**
 * MATCHMAKING MODULE
 * Manages the queue and pairs players into rooms.
 * Imported by server.js and wired to the Socket.io instance.
 *
 * Flow:
 *   1. Player emits  'queue:join'   → added to waiting queue
 *   2. Two players in queue         → paired into a match room
 *   3. Server emits  'match:found'  → both clients load MultiplayerDuelScene
 *   4. Player emits  'queue:leave'  → removed from queue
 */

const { v4: uuidv4 } = require('uuid');

// In-memory queue: [{ socketId, playerId, username, deckId, joinedAt }]
const queue = [];

// Active rooms: matchId → { p1, p2, state }
const activeMatches = new Map();

// ── Queue Helpers ─────────────────────────────────────────────────────────────

function addToQueue(entry) {
    // Prevent duplicate entries for the same player
    if (queue.some(e => e.playerId === entry.playerId)) return false;
    queue.push({ ...entry, joinedAt: Date.now() });
    return true;
}

function removeFromQueue(socketId) {
    const idx = queue.findIndex(e => e.socketId === socketId);
    if (idx !== -1) queue.splice(idx, 1);
}

function tryPair() {
    if (queue.length < 2) return null;
    const p1 = queue.shift();
    const p2 = queue.shift();
    return { p1, p2 };
}

// ── Match Room ────────────────────────────────────────────────────────────────

function createMatch(p1, p2) {
    const matchId = uuidv4();
    const roomId  = `match:${matchId}`;

    const match = {
        matchId,
        roomId,
        p1: { ...p1, morale: 6000, field: Array(10).fill(null) },
        p2: { ...p2, morale: 6000, field: Array(10).fill(null) },
        turn: 1,
        activePlayerId: p1.playerId,   // p1 always goes first
        phase: 'upkeep',
        startedAt: Date.now(),
    };

    activeMatches.set(matchId, match);
    return match;
}

function getMatch(matchId) {
    return activeMatches.get(matchId) || null;
}

function removeMatch(matchId) {
    activeMatches.delete(matchId);
}

// ── Socket Event Wiring ───────────────────────────────────────────────────────

/**
 * Registers matchmaking socket events on a single connected socket.
 * Call this inside io.on('connection', socket => { ... }).
 *
 * @param {import('socket.io').Socket} socket
 * @param {import('socket.io').Server} io
 * @param {object} playerData  - { playerId, username, deckId } from JWT/session
 */
function registerMatchmaking(socket, io, playerData) {

    // ── Join Queue ───────────────────────────────────────────────────────────
    socket.on('queue:join', () => {
        const entry = { socketId: socket.id, ...playerData };
        const added  = addToQueue(entry);

        if (!added) {
            socket.emit('queue:error', { message: 'Already in queue.' });
            return;
        }

        socket.emit('queue:joined', { position: queue.length });
        console.log(`[Queue] ${playerData.username} joined. Queue size: ${queue.length}`);

        // Attempt to pair
        const pair = tryPair();
        if (!pair) return;

        const match = createMatch(pair.p1, pair.p2);
        const { matchId, roomId, p1, p2 } = match;

        // Both sockets join the shared room
        io.sockets.sockets.get(p1.socketId)?.join(roomId);
        io.sockets.sockets.get(p2.socketId)?.join(roomId);

        // Payload each client needs to initialise MultiplayerDuelScene
        const basePayload = {
            matchId,
            roomId,
            opponentName: '',
            opponentAvatar: '',
            yourTurn: false,
            activePhase: match.phase,
        };

        io.to(p1.socketId).emit('match:found', {
            ...basePayload,
            yourPlayerId:   p1.playerId,
            yourRole:       'p1',
            opponentName:   p2.username,
            opponentAvatar: p2.avatarUrl || null,
            yourTurn:       true,   // p1 moves first
        });

        io.to(p2.socketId).emit('match:found', {
            ...basePayload,
            yourPlayerId:   p2.playerId,
            yourRole:       'p2',
            opponentName:   p1.username,
            opponentAvatar: p1.avatarUrl || null,
            yourTurn:       false,
        });

        console.log(`[Match] ${p1.username} vs ${p2.username} — room ${roomId}`);
    });

    // ── Leave Queue ──────────────────────────────────────────────────────────
    socket.on('queue:leave', () => {
        removeFromQueue(socket.id);
        socket.emit('queue:left');
        console.log(`[Queue] ${playerData.username} left queue.`);
    });

    // ── Handle disconnect: clean up queue and forfeit active match ───────────
    socket.on('disconnect', () => {
        removeFromQueue(socket.id);

        // Find any active match this socket was part of
        for (const [matchId, match] of activeMatches) {
            const isP1 = match.p1.socketId === socket.id;
            const isP2 = match.p2.socketId === socket.id;
            if (!isP1 && !isP2) continue;

            const opponentSocketId = isP1 ? match.p2.socketId : match.p1.socketId;
            io.to(opponentSocketId).emit('match:opponentDisconnected', {
                matchId,
                message: 'Your opponent disconnected. You win by forfeit.',
            });

            removeMatch(matchId);
            break;
        }
    });
}

module.exports = { registerMatchmaking, getMatch, removeMatch, activeMatches };
