'use strict';

/**
 * CONTRACTS in the shop (economy/contracts.js)
 *   GET  /api/contracts        today's offers, the active contract, Karat, seconds until new ones
 *   POST /api/contracts/buy    { index } → the same, after paying; 409 one is active (or taken today), 402 Karat
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const contracts = require('../economy/contracts');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        const s = await contracts.status(req.playerId);
        if (!s) return res.status(404).json({ error: 'Player not found.' });
        res.json(s);
    } catch (err) {
        console.error('[Contracts]', err.message);
        res.status(500).json({ error: 'Could not load the contracts.' });
    }
});

router.post('/buy', requireAuth, async (req, res) => {
    try {
        const r = await contracts.buy(req.playerId, req.body?.index);
        if (r.error) return res.status(r.code || 400).json({ error: r.error });
        res.json(r.status);
    } catch (err) {
        console.error('[Contracts]', err.message);
        res.status(500).json({ error: 'Could not buy the contract.' });
    }
});

module.exports = router;
