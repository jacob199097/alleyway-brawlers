'use strict';

/**
 * PHONE NOTIFICATIONS (utils/push.js)
 *   POST   /api/push/token   { token, platform: 'android', tz_minutes }   this phone gets notifications for this account
 *   DELETE /api/push/token   { token }                                     it doesn't any more (signed out, or turned off)
 */

const express = require('express');
const { requireAuth } = require('./middleware');
const push = require('../utils/push');

const router = express.Router();
const TOKEN = /^[A-Za-z0-9_:\-.]{20,4096}$/;

router.post('/token', requireAuth, async (req, res) => {
    const { token, platform, tz_minutes } = req.body || {};
    if (typeof token !== 'string' || !TOKEN.test(token)) return res.status(400).json({ error: 'No token.' });
    const tz = Math.max(-14 * 60, Math.min(14 * 60, Math.round(Number(tz_minutes) || 0)));
    try {
        await push.register(req.playerId, token, platform === 'ios' ? 'ios' : 'android', tz);
        res.json({ success: true });
    } catch (err) {
        console.error('[Push]', err.message);
        res.status(500).json({ error: 'Could not turn notifications on.' });
    }
});

router.delete('/token', requireAuth, async (req, res) => {
    const { token } = req.body || {};
    if (typeof token !== 'string') return res.status(400).json({ error: 'No token.' });
    try {
        await push.unregister(req.playerId, token);
        res.json({ success: true });
    } catch (err) {
        console.error('[Push]', err.message);
        res.status(500).json({ error: 'Could not turn notifications off.' });
    }
});

module.exports = router;
