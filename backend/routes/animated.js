'use strict';

// Animated cards (economy/animated.js): a card's animated version, crafted for Dust or bought for Contraband.
//   GET  /api/animated                       → { craftFactor, cards: [{id, rarity, dust, contraband, owned}] }
//   POST /api/animated/craft  {card}         → { id, dust, contraband, spent, currency, gaveCard }   (Dust; needs the card)
//   POST /api/animated/buy    {card}         → the same                                            (Contraband; gives the card if none)

const router = require('express').Router();
const { requireAuth } = require('./middleware');
const animated = require('../economy/animated');
const { checkAndAnnounce } = require('../economy/achievements');

function fail(res, err) {
    if (err instanceof animated.AnimatedError) return res.status(400).json({ error: err.message });
    console.error('[Animated]', err.message);
    res.status(500).json({ error: 'Something went wrong. Try again.' });
}

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await animated.overview(req.playerId));
    } catch (err) {
        fail(res, err);
    }
});

for (const [path, currency] of [['/craft', 'dust'], ['/buy', 'contraband']]) {
    router.post(path, requireAuth, async (req, res) => {
        const { card } = req.body || {};
        if (typeof card !== 'string') return res.status(400).json({ error: 'Which card?' });
        try {
            res.json(await animated.acquire(req.playerId, card, currency));
            checkAndAnnounce(req.playerId);
        } catch (err) {
            fail(res, err);
        }
    });
}

module.exports = router;
