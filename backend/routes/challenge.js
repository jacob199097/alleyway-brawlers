'use strict';

/**
 * THE WEEKLY CHALLENGE
 *   GET /api/challenge   this week's twist and whether you've won it:
 *                        {week, id, name, text, ends_at, reward: {karat, free_packs}, won}
 * Playing it: the socket's mp:cpu {challenge: true} (socket/onlineMatch.js).
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const challenge = require('../economy/challenge');

const router = express.Router();

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await challenge.status(req.playerId));
    } catch (err) {
        console.error('[Challenge]', err.message);
        res.status(500).json({ error: 'Could not load this week\'s challenge.' });
    }
});

module.exports = router;
