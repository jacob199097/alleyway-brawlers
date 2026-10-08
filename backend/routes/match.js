'use strict';

const express             = require('express');
const { requireAuth }     = require('./middleware');
const { resolveSoloMatch } = require('../economy/postMatch');

const router = express.Router();

/**
 * POST /api/match/complete
 * Called by the client after a solo (AI) duel ends.
 * Body: { result: 'win'|'loss'|'draw', playerMorale, opponentMorale, turns, durationSecs }
 */
router.post('/complete', requireAuth, async (req, res) => {
    const playerId = req.playerId;
    const { result, playerMorale, opponentMorale, turns, durationSecs } = req.body;

    if (!['win', 'loss', 'draw'].includes(result)) {
        return res.status(400).json({ error: 'Invalid result value.' });
    }

    try {
        const rewards = await resolveSoloMatch({
            playerId,
            outcome: result,
            matchMeta: { playerMorale, opponentMorale, turns, durationSecs },
        });
        res.json({ ok: true, rewards });
    } catch (err) {
        console.error('[match/complete]', err.message);
        res.status(500).json({ error: 'Failed to record match result.' });
    }
});

module.exports = router;
