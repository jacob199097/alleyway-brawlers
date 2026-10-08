'use strict';

/**
 * TURF WAR TACTICS — Main Server
 * Express + Socket.io on a single Node.js process.
 * Designed to run directly on the Linux server.
 *
 * Start: node server.js
 * Prod:  pm2 start server.js --name turf-war
 */

require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const express      = require('express');
const http         = require('http');
const { Server }   = require('socket.io');
const cors         = require('cors');
const jwt          = require('jsonwebtoken');

const { pool }                  = require('./db/pool');
const { registerMatchmaking }   = require('./socket/matchmaker');
const { registerDuelHandler }   = require('./socket/duelHandler');

// ── REST routes ───────────────────────────────────────────────────────────────
const authRoutes    = require('./routes/auth');
const shopRoutes    = require('./routes/shop');
const profileRoutes = require('./routes/profile');
const deckRoutes    = require('./routes/deck');
const socialRoutes  = require('./routes/social');
const matchRoutes   = require('./routes/match');
const { router: questRoutes } = require('./routes/quests');
const onboardingRoutes = require('./routes/onboarding');
const { router: mailRoutes } = require('./routes/mail');

// ── App setup ─────────────────────────────────────────────────────────────────
const app    = express();
const server = http.createServer(app);
const io     = new Server(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    pingTimeout:  60_000,
    pingInterval: 25_000,
});

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'change_me_in_production';

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// ── REST API routes ───────────────────────────────────────────────────────────
app.use('/api/auth',    authRoutes);
app.use('/api/shop',    shopRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/deck',    deckRoutes);
app.use('/api/social',  socialRoutes);
app.use('/api/match',   matchRoutes);
app.use('/api/quests',  questRoutes);
app.use('/api/onboarding', onboardingRoutes);
app.use('/api/mail',    mailRoutes);

app.get('/health', (_req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

// ── Socket.io JWT Middleware ──────────────────────────────────────────────────
io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Authentication token required.'));

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        socket.playerData = {
            playerId:  decoded.sub,
            username:  decoded.username,
            avatarUrl: decoded.avatarUrl || null,
            deckId:    decoded.deckId    || null,
        };
        next();
    } catch {
        next(new Error('Invalid or expired token.'));
    }
});

// ── Socket connections ────────────────────────────────────────────────────────
io.on('connection', (socket) => {
    const { playerData } = socket;
    console.log(`[Socket] Connected: ${playerData.username} (${socket.id})`);

    // Mark player online in DB (fire-and-forget)
    pool.query(
        'UPDATE players SET is_online = TRUE, socket_id = $1, last_login = NOW() WHERE id = $2',
        [socket.id, playerData.playerId]
    ).catch(err => console.error('[Socket] Online update failed:', err.message));

    // Register feature handlers
    registerMatchmaking(socket, io, playerData);
    registerDuelHandler(socket, io, playerData);

    // ── Direct challenge (friend invite) ────────────────────────────────────
    socket.on('challenge:send', ({ targetPlayerId }) => {
        // Look up target's socket ID and forward the challenge
        pool.query('SELECT socket_id, username FROM players WHERE id = $1', [targetPlayerId])
            .then(({ rows }) => {
                if (!rows.length || !rows[0].socket_id) return;
                io.to(rows[0].socket_id).emit('challenge:received', {
                    fromPlayerId: playerData.playerId,
                    fromUsername: playerData.username,
                });
            })
            .catch(err => console.error('[Challenge] Lookup failed:', err.message));
    });

    socket.on('challenge:accept', ({ fromPlayerId }) => {
        // Both players skip the queue and go straight to a match room
        pool.query('SELECT socket_id, username FROM players WHERE id = $1', [fromPlayerId])
            .then(({ rows }) => {
                if (!rows.length || !rows[0].socket_id) return;
                const challenger = {
                    socketId:  rows[0].socket_id,
                    playerId:  fromPlayerId,
                    username:  rows[0].username,
                };
                const accepter = {
                    socketId:  socket.id,
                    playerId:  playerData.playerId,
                    username:  playerData.username,
                };
                const { createMatch } = require('./socket/matchmaker');
                const match = createMatch(challenger, accepter);

                io.sockets.sockets.get(challenger.socketId)?.join(match.roomId);
                io.sockets.sockets.get(accepter.socketId)?.join(match.roomId);

                io.to(challenger.socketId).emit('match:found', {
                    matchId: match.matchId, roomId: match.roomId,
                    yourPlayerId: fromPlayerId, opponentName: playerData.username,
                    yourTurn: true,
                });
                io.to(accepter.socketId).emit('match:found', {
                    matchId: match.matchId, roomId: match.roomId,
                    yourPlayerId: playerData.playerId, opponentName: rows[0].username,
                    yourTurn: false,
                });
            })
            .catch(err => console.error('[Challenge] Accept failed:', err.message));
    });

    // ── Chat ─────────────────────────────────────────────────────────────────
    socket.on('chat:message', ({ toPlayerId, body }) => {
        if (!body || body.length > 500) return;

        pool.query(
            `INSERT INTO messages (sender_id, receiver_id, body) VALUES ($1,$2,$3) RETURNING id, sent_at`,
            [playerData.playerId, toPlayerId, body.trim()]
        ).then(({ rows }) => {
            pool.query('SELECT socket_id FROM players WHERE id = $1', [toPlayerId])
                .then(({ rows: targets }) => {
                    if (targets[0]?.socket_id) {
                        io.to(targets[0].socket_id).emit('chat:message', {
                            messageId:    rows[0].id,
                            fromPlayerId: playerData.playerId,
                            fromUsername: playerData.username,
                            body:         body.trim(),
                            sentAt:       rows[0].sent_at,
                        });
                    }
                });
        }).catch(err => console.error('[Chat] Failed:', err.message));
    });

    // ── Disconnect ───────────────────────────────────────────────────────────
    socket.on('disconnect', () => {
        console.log(`[Socket] Disconnected: ${playerData.username}`);
        pool.query(
            'UPDATE players SET is_online = FALSE, socket_id = NULL WHERE id = $1',
            [playerData.playerId]
        ).catch(err => console.error('[Socket] Offline update failed:', err.message));
    });
});

// ── Start ─────────────────────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
    console.log(`[Server] AlleyWay Brawlers running on port ${PORT}`);
});

module.exports = { app, io };
