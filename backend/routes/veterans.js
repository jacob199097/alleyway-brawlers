'use strict';

/**
 * VETERAN CARDS (economy/veterans.js)
 *   GET /api/veterans   {tiers: [{tier, wins, name}], cards: {cardId: {wins, plays, tier}}}
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const veterans = require('../economy/veterans');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await veterans.overview(req.playerId));
    } catch (err) {
        console.error('[Veterans]', err.message);
        res.status(500).json({ error: 'Could not load your veteran cards.' });
    }
});

module.exports = router;
