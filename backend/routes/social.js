'use strict';

const router          = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }        = require('../db/pool');

// ── GET /api/social/friends ───────────────────────────────────────────────────
router.get('/friends', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT
                f.id AS friendship_id,
                f.status,
                f.created_at,
                f.requester_id,
                CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END AS friend_id,
                CASE WHEN f.requester_id = $1 THEN a.username     ELSE r.username     END AS friend_username,
                CASE WHEN f.requester_id = $1 THEN a.avatar_url   ELSE r.avatar_url   END AS friend_avatar,
                CASE WHEN f.requester_id = $1 THEN a.is_online    ELSE r.is_online    END AS is_online,
                CASE WHEN f.requester_id = $1 THEN a.level        ELSE r.level        END AS level
             FROM friendships f
             JOIN players r ON r.id = f.requester_id
             JOIN players a ON a.id = f.addressee_id
             WHERE (f.requester_id = $1 OR f.addressee_id = $1)
               AND f.status <> 'blocked'
             ORDER BY f.status, friend_username`,
            [req.playerId]
        );
        // Who's in a match right now (set in server.js; the realtime service knows)
        const online = req.app.locals.online;
        for (const r of rows) {
            r.incoming = r.status === 'pending' && r.requester_id !== req.playerId;
            r.in_match = !!(r.is_online && online?.isInMatch(r.friend_id));
            delete r.requester_id;
        }
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/social/friends/request — send friend request ───────────────────
router.post('/friends/request', requireAuth, async (req, res) => {
    const { targetUsername } = req.body;
    try {
        const { rows: targets } = await pool.query(
            'SELECT id FROM players WHERE username = $1', [targetUsername]
        );
        if (!targets.length) return res.status(404).json({ error: 'Player not found.' });
        const targetId = targets[0].id;
        if (targetId === req.playerId) return res.status(400).json({ error: 'Cannot friend yourself.' });

        await pool.query(
            `INSERT INTO friendships (requester_id, addressee_id) VALUES ($1, $2)
             ON CONFLICT DO NOTHING`,
            [req.playerId, targetId]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── PATCH /api/social/friends/:id/accept ─────────────────────────────────────
router.patch('/friends/:id/accept', requireAuth, async (req, res) => {
    try {
        const { rowCount } = await pool.query(
            `UPDATE friendships SET status = 'accepted', updated_at = NOW()
             WHERE id = $1 AND addressee_id = $2 AND status = 'pending'`,
            [req.params.id, req.playerId]
        );
        if (!rowCount) return res.status(404).json({ error: 'Request not found.' });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── DELETE /api/social/friends/:id — remove friend ───────────────────────────
router.delete('/friends/:id', requireAuth, async (req, res) => {
    try {
        await pool.query(
            `DELETE FROM friendships
             WHERE id = $1 AND (requester_id = $2 OR addressee_id = $2)`,
            [req.params.id, req.playerId]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── GET /api/social/messages/:friendId — conversation history ────────────────
router.get('/messages/:friendId', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT id, sender_id, body, read, sent_at
             FROM   messages
             WHERE  (sender_id = $1 AND receiver_id = $2)
                OR  (sender_id = $2 AND receiver_id = $1)
             ORDER  BY sent_at DESC
             LIMIT  50`,
            [req.playerId, req.params.friendId]
        );
        // Mark incoming as read
        await pool.query(
            `UPDATE messages SET read = TRUE
             WHERE receiver_id = $1 AND sender_id = $2 AND read = FALSE`,
            [req.playerId, req.params.friendId]
        );
        res.json(rows.reverse());
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
