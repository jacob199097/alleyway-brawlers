'use strict';

// Achievements and the cosmetics they unlock (economy/achievements.js).
//   GET  /api/achievements        → { achievements: [{id, name, desc, reward, clan, target, progress, unlocked, unlockedAt}],
//                                      cosmetics: {avatars, portraits, titles: [{id, text}], backs}, equipped: {avatar, title, back} }
//   POST /api/achievements/equip  { avatar?, title?, back? }   null title/back = back to the default

const router = require('express').Router();
const { requireAuth } = require('./middleware');
const achievements = require('../economy/achievements');

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await achievements.overview(req.playerId));
    } catch (err) {
        console.error('[Achievements]', err.message);
        res.status(500).json({ error: 'Achievements are unavailable right now.' });
    }
});

router.post('/equip', requireAuth, async (req, res) => {
    try {
        const r = await achievements.equip(req.playerId, req.body || {});
        if (r.error) return res.status(400).json(r);
        res.json(r);
    } catch (err) {
        console.error('[Achievements] equip:', err.message);
        res.status(500).json({ error: 'Something went wrong. Try again.' });
    }
});

module.exports = router;
