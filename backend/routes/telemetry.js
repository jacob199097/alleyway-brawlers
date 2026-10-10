'use strict';

/**
 * ERROR REPORTS FROM THE GAME
 *
 * The Godot client sends script errors and "the game didn't close properly last time" reports
 * here (godot/scripts/error_report.gd), so bugs show up without players having to describe them.
 *
 *   POST /api/telemetry/errors   { version, os, errors: [{kind, message, location, count, detail}] }
 *
 * Signing in is optional (reports from the login screen count too). Stored in client_errors,
 * kept 30 days. Read them with:  node backend/scripts/client_errors.js [days]
 */

const express = require('express');
const jwt     = require('jsonwebtoken');
const { pool } = require('../db/pool');

const router = express.Router();
const MAX_PER_POST = 20;
const WINDOW_MS = 10 * 60 * 1000;
const POSTS_PER_WINDOW = 20;        // per IP address
const recent = new Map();           // ip -> {start, count}

let ready = null;
const ensureTable = () => (ready ||= pool.query(`
    CREATE TABLE IF NOT EXISTS client_errors (
        id         BIGSERIAL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        player_id  TEXT,
        version    TEXT,
        os         TEXT,
        kind       TEXT,
        message    TEXT,
        location   TEXT,
        count      INT NOT NULL DEFAULT 1,
        detail     TEXT
    );
    CREATE INDEX IF NOT EXISTS client_errors_created ON client_errors (created_at);
`).catch((err) => { ready = null; throw err; }));

const text = (v, max) => String(v ?? '').slice(0, max);

function clientIp(req) {
    return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

router.post('/errors', async (req, res) => {
    const ip = clientIp(req);
    const now = Date.now();
    let r = recent.get(ip);
    if (!r || now - r.start > WINDOW_MS) recent.set(ip, r = { start: now, count: 0 });
    if (++r.count > POSTS_PER_WINDOW) return res.status(429).json({ error: 'Too many reports.' });

    const errors = Array.isArray(req.body?.errors) ? req.body.errors.slice(0, MAX_PER_POST) : [];
    if (!errors.length) return res.json({ stored: 0 });
    let playerId = null;
    const header = req.headers.authorization;
    if (header?.startsWith('Bearer ')) {
        try { playerId = jwt.verify(header.slice(7), process.env.JWT_SECRET).sub; } catch { /* report anyway */ }
    }
    try {
        await ensureTable();
        for (const e of errors) {
            await pool.query(
                `INSERT INTO client_errors (player_id, version, os, kind, message, location, count, detail)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
                [playerId, text(req.body.version, 20), text(req.body.os, 40), text(e.kind, 20), text(e.message, 500),
                    text(e.location, 200), Math.min(1000, Math.max(1, Math.trunc(Number(e.count) || 1))), text(e.detail, 4000)]
            );
        }
        if (Math.random() < 0.02) pool.query(`DELETE FROM client_errors WHERE created_at < NOW() - INTERVAL '30 days'`).catch(() => {});
        res.json({ stored: errors.length });
    } catch (err) {
        console.error('[Telemetry] Store failed:', err.message);
        res.status(500).json({ error: 'Could not store the report.' });
    }
});

// Stale rate-limit entries
setInterval(() => {
    const now = Date.now();
    for (const [ip, r] of recent) if (now - r.start > WINDOW_MS) recent.delete(ip);
}, WINDOW_MS).unref();

module.exports = router;
