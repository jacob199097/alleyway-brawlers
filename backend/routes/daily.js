'use strict';

/**
 * THE DAILY REWARD (economy/daily.js)
 *   GET  /api/daily         {day 1-7, claimed, streak, rewards: [{karat?, dust?, free_packs?} x7]}
 *   POST /api/daily/claim   today's reward → {day, reward, karat, dust, free_packs}; 409 once taken
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const daily = require('../economy/daily');
const { checkAndAnnounce } = require('../economy/achievements');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        const s = await daily.status(req.playerId);
        if (!s) return res.status(404).json({ error: 'Player not found.' });
        res.json(s);
    } catch (err) {
        console.error('[Daily]', err.message);
        res.status(500).json({ error: 'Could not load the daily reward.' });
    }
});

router.post('/claim', requireAuth, async (req, res) => {
    try {
        const r = await daily.claim(req.playerId);
        if (!r) return res.status(409).json({ error: "You've already taken today's reward. Come back tomorrow!" });
        res.json(r);
        checkAndAnnounce(req.playerId);   // (a week of them is an achievement)
    } catch (err) {
        console.error('[Daily]', err.message);
        res.status(500).json({ error: 'Could not claim the daily reward.' });
    }
});

module.exports = router;
