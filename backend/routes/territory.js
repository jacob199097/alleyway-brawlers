'use strict';

/**
 * THE TURF MAP (economy/territory.js)
 *   GET  /api/territory         {week, endsAt, clans, districts: [{id, name, image, locals: {name, strength},
 *                                clans: [{clan, points}], holder, boss, mine: {clan: points}, lastHolder}],
 *                                reward: {karat, weeks} | null, karat, points}
 *   POST /api/territory/claim   pays finished weeks' Karat → {karat, newKarat}
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const territory = require('../economy/territory');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await territory.overview(req.playerId));
    } catch (err) {
        console.error('[Territory]', err.message);
        res.status(500).json({ error: 'Could not load the turf map.' });
    }
});

router.post('/claim', requireAuth, async (req, res) => {
    try {
        res.json(await territory.claim(req.playerId));
    } catch (err) {
        console.error('[Territory] Claim failed:', err.message);
        res.status(500).json({ error: 'Could not claim your turf reward.' });
    }
});

module.exports = router;
