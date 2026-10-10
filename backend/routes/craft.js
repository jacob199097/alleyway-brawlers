'use strict';

// Crafting (economy/crafting.js). Cards are named by game ID, e.g. { card: "maya_lv1" }.
//   GET  /api/craft                → { dust, values: {rarity: {scrap, craft}}, maxCopies, extras, extrasDust }
//   POST /api/craft/scrap  {card, copies?}  → { dust, quantity, gained }
//   POST /api/craft/extras                  → { dust, gained, scrapped }   every copy beyond 3 (leaders: 1)
//   POST /api/craft/make   {card}           → { dust, quantity, spent }

const router = require('express').Router();
const { requireAuth } = require('./middleware');
const crafting = require('../economy/crafting');
const { checkAndAnnounce } = require('../economy/achievements');

function fail(res, err) {
    if (err instanceof crafting.CraftError) return res.status(400).json({ error: err.message });
    console.error('[Craft]', err.message);
    res.status(500).json({ error: 'Something went wrong. Try again.' });
}

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await crafting.summary(req.playerId));
    } catch (err) {
        fail(res, err);
    }
});

router.post('/scrap', requireAuth, async (req, res) => {
    const { card, copies = 1 } = req.body || {};
    if (typeof card !== 'string') return res.status(400).json({ error: 'Which card?' });
    try {
        res.json(await crafting.scrap(req.playerId, card, copies));
        checkAndAnnounce(req.playerId);
    } catch (err) {
        fail(res, err);
    }
});

router.post('/extras', requireAuth, async (req, res) => {
    try {
        res.json(await crafting.scrapExtras(req.playerId));
        checkAndAnnounce(req.playerId);
    } catch (err) {
        fail(res, err);
    }
});

router.post('/make', requireAuth, async (req, res) => {
    const { card } = req.body || {};
    if (typeof card !== 'string') return res.status(400).json({ error: 'Which card?' });
    try {
        res.json(await crafting.craft(req.playerId, card));
        checkAndAnnounce(req.playerId);
    } catch (err) {
        fail(res, err);
    }
});

module.exports = router;
