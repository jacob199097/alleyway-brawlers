'use strict';

/**
 * MAILBOX
 *   GET  /api/mail              → list inbox (newest first)
 *   POST /api/mail/:id/read     → mark a single message read
 *   POST /api/mail/read-all     → mark every message read
 *   DELETE /api/mail/:id        → delete a message
 *
 * Helper: sendMail(playerId, { subject, body, sender })
 *   Insert a system-generated message for a player. Used by registration,
 *   onboarding, daily quest claims, etc.
 */

const router         = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }       = require('../db/pool');

router.get('/', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT id, sender, subject, body, read_at, created_at
             FROM player_mail
             WHERE player_id = $1
             ORDER BY created_at DESC
             LIMIT 100`,
            [req.playerId]
        );
        const unread = rows.filter(r => !r.read_at).length;
        res.json({ messages: rows, unread });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

router.post('/:id/read', requireAuth, async (req, res) => {
    try {
        await pool.query(
            `UPDATE player_mail SET read_at = COALESCE(read_at, NOW())
             WHERE id = $1 AND player_id = $2`,
            [req.params.id, req.playerId]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

router.post('/read-all', requireAuth, async (req, res) => {
    try {
        await pool.query(
            `UPDATE player_mail SET read_at = NOW()
             WHERE player_id = $1 AND read_at IS NULL`,
            [req.playerId]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

router.delete('/:id', requireAuth, async (req, res) => {
    try {
        await pool.query(
            `DELETE FROM player_mail WHERE id = $1 AND player_id = $2`,
            [req.params.id, req.playerId]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

async function sendMail(playerId, { subject, body, sender = 'AlleyWay Brawlers' }) {
    try {
        await pool.query(
            `INSERT INTO player_mail (player_id, sender, subject, body)
             VALUES ($1, $2, $3, $4)`,
            [playerId, sender, subject, body]
        );
    } catch (err) {
        console.error('[Mail] sendMail failed:', err.message);
    }
}

module.exports = { router, sendMail };
