'use strict';

/**
 * MATCH REPLAYS
 *
 * Every online and CPU match is recorded on the server (socket/onlineMatch.js: decks, shuffle
 * seed, who went first and every action). A replay is rebuilt by playing the match again on the
 * server's rules and sending the requesting player exactly what they saw live.
 *
 *   GET /api/replays          your last matches: [{id, created_at, mode, opponent, result, turns}]
 *   GET /api/replays/:id      {start, updates, over, complete} for the duel screen to play back
 *
 * The last KEEP replays per player are kept.
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const { pool } = require('../db/pool');

const KEEP = 30;
let ready = null;
const ensureTable = () => (ready ||= pool.query(`
    CREATE TABLE IF NOT EXISTS match_replays (
        id         UUID PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        mode       TEXT NOT NULL,
        p1         TEXT NOT NULL,
        p2         TEXT NOT NULL,
        data       JSONB NOT NULL
    );
    CREATE INDEX IF NOT EXISTS match_replays_p1 ON match_replays (p1, created_at);
    CREATE INDEX IF NOT EXISTS match_replays_p2 ON match_replays (p2, created_at);
`).catch((err) => { ready = null; throw err; }));

/** Store a finished match's record (called by the online service). */
async function saveReplay(rec) {
    await ensureTable();
    await pool.query(
        `INSERT INTO match_replays (id, mode, p1, p2, data) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (id) DO NOTHING`,
        [rec.id, rec.mode, rec.playerIds.player, rec.playerIds.opponent, JSON.stringify(rec)]
    );
    for (const id of Object.values(rec.playerIds)) {
        if (id.startsWith('cpu:')) continue;
        await pool.query(
            `DELETE FROM match_replays WHERE id IN (
                 SELECT id FROM match_replays WHERE p1 = $1 OR p2 = $1 ORDER BY created_at DESC OFFSET $2)`,
            [id, KEEP]
        );
    }
}

function createReplayRoutes(replaySteps) {
    const router = express.Router();

    router.get('/', requireAuth, async (req, res) => {
        try {
            await ensureTable();
            const { rows } = await pool.query(
                `SELECT id, created_at, mode, p1, data->'profiles' AS profiles, data->'end' AS ending
                 FROM   match_replays WHERE p1 = $1 OR p2 = $1
                 ORDER  BY created_at DESC LIMIT 20`, [req.playerId]);
            res.json(rows.map((r) => {
                const seat = r.p1 === req.playerId ? 'player' : 'opponent';
                const foe = seat === 'player' ? 'opponent' : 'player';
                const end = r.ending || {};
                return {
                    id: r.id, created_at: r.created_at, mode: r.mode,
                    opponent: r.profiles?.[foe] || { username: '?' },
                    result: !end.winner ? 'draw' : end.winner === seat ? 'win' : 'loss',
                    reason: end.reason || '', turns: end.turns || 0,
                };
            }));
        } catch (err) {
            console.error('[Replays] List failed:', err.message);
            res.status(500).json({ error: 'Could not load your replays.' });
        }
    });

    router.get('/:id', requireAuth, async (req, res) => {
        if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) return res.status(404).json({ error: 'Replay not found.' });
        try {
            await ensureTable();
            const { rows } = await pool.query('SELECT p1, p2, data FROM match_replays WHERE id = $1', [req.params.id]);
            const r = rows[0];
            if (!r || (r.p1 !== req.playerId && r.p2 !== req.playerId)) return res.status(404).json({ error: 'Replay not found.' });
            res.json(await replaySteps(r.data, r.p1 === req.playerId ? 'player' : 'opponent'));
        } catch (err) {
            console.error('[Replays] Load failed:', err.message);
            res.status(500).json({ error: 'Could not load that replay.' });
        }
    });
    return router;
}

module.exports = { saveReplay, createReplayRoutes };
