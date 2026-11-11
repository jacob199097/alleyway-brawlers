'use strict';

/**
 * RANKED SEASONS (economy/seasons.js)
 *   GET  /api/seasons          {season: {id, name, subtitle, started_at, ends_at}, tiers: [{tier, name, min, reward}],
 *                               me: {points, tier, ranked, peak_points, peak_tier}, unclaimed: [...], soft_reset_tiers}
 *   POST /api/seasons/claim    {season} → that season's reward → {season, name, peak_tier, reward, karat, free_packs}; 409 once taken
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const seasons = require('../economy/seasons');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        const s = await seasons.status(req.playerId);
        if (!s) return res.status(404).json({ error: 'Player not found.' });
        res.json(s);
    } catch (err) {
        console.error('[Seasons]', err.message);
        res.status(500).json({ error: 'Could not load the season.' });
    }
});

router.post('/claim', requireAuth, async (req, res) => {
    const season = Number(req.body && req.body.season);
    if (!Number.isInteger(season) || season < 0) return res.status(400).json({ error: 'Which season?' });
    try {
        const r = await seasons.claim(req.playerId, season);
        if (!r) return res.status(409).json({ error: "There's no reward to take for that season (or it's been taken)." });
        res.json(r);
    } catch (err) {
        console.error('[Seasons]', err.message);
        res.status(500).json({ error: 'Could not take the season reward.' });
    }
});

module.exports = router;
