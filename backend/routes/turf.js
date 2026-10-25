'use strict';

/**
 * TURF DEFENSE (economy/turf.js; matches: socket/coopMatch.js)
 *   GET /api/turf   {loss, bosses: [{id, name, title, clan, color, portrait, prize, prize_won, lines,
 *                    levels: [{level, name, morale, draw, authority, phases, first_clear, clear,
 *                    unlocked, clears, attempts, best_turns}]}], waiting: {"bossId:level": n}}
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const turf = require('../economy/turf');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        const s = await turf.status(req.playerId);
        res.json({ ...s, waiting: req.app.locals.coop?.waiting() || {} });
    } catch (err) {
        console.error('[Turf]', err.message);
        res.status(500).json({ error: 'Could not load Turf Defense.' });
    }
});

module.exports = router;
