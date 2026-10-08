'use strict';

const router          = require('express').Router();
const { requireAuth } = require('./middleware');
const { openPack, buyPack } = require('../economy/packOpener');
const { pool }        = require('../db/pool');
const Stripe          = require('stripe');
// Initialised lazily so the server starts even without a Stripe key configured yet
let _stripe = null;
function getStripe() {
    if (!_stripe) {
        if (!process.env.STRIPE_SECRET_KEY) {
            throw new Error('STRIPE_SECRET_KEY is not set in .env');
        }
        _stripe = Stripe(process.env.STRIPE_SECRET_KEY);
    }
    return _stripe;
}

const VALID_PACKS = ['lion_pride', 'viper_clan'];

// ── GET /api/shop/packs — list available packs and player karat ───────────────
router.get('/packs', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            'SELECT karat FROM players WHERE id = $1', [req.playerId]
        );
        res.json({
            karat: rows[0]?.karat ?? 0,
            packs: VALID_PACKS.map(p => ({
                id:    p,
                name:  p.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
                cost:  200,
                cards: 3,
            })),
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/shop/buy — purchase without opening ────────────────────────────
router.post('/buy', requireAuth, async (req, res) => {
    const { packType } = req.body;
    if (!VALID_PACKS.includes(packType)) {
        return res.status(400).json({ error: 'Invalid pack type.' });
    }
    try {
        const result = await buyPack(req.playerId, packType);
        res.json(result);
    } catch (err) {
        const status = err.message.includes('Insufficient') ? 402 : 500;
        res.status(status).json({ error: err.message });
    }
});

// ── POST /api/shop/open — spend karat and open a pack immediately ─────────────
router.post('/open', requireAuth, async (req, res) => {
    const { packType, currency = 'karat' } = req.body;
    if (!VALID_PACKS.includes(packType)) {
        return res.status(400).json({ error: 'Invalid pack type.' });
    }
    if (!['karat', 'contraband'].includes(currency)) {
        return res.status(400).json({ error: 'Invalid currency.' });
    }
    try {
        const result = await openPack(req.playerId, packType, currency);
        res.json(result);
    } catch (err) {
        const status = err.message.includes('Insufficient') ? 402 : 500;
        res.status(status).json({ error: err.message });
    }
});

// ── POST /api/shop/contraband/create-intent — create Stripe PaymentIntent ────
router.post('/contraband/create-intent', requireAuth, async (req, res) => {
    const { amount = 100 } = req.body;
    if (!Number.isInteger(amount) || amount <= 0) {
        return res.status(400).json({ error: 'Invalid amount.' });
    }
    try {
        const intent = await getStripe().paymentIntents.create({
            amount:   499,   // $4.99 in cents
            currency: 'usd',
            metadata: { playerId: req.playerId, contrabandAmount: String(amount) },
        });
        res.json({ clientSecret: intent.client_secret });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/shop/contraband/purchase — verify payment, then grant ───────────
router.post('/contraband/purchase', requireAuth, async (req, res) => {
    const { paymentIntentId, amount = 100 } = req.body;
    if (!Number.isInteger(amount) || amount <= 0) {
        return res.status(400).json({ error: 'Invalid amount.' });
    }
    try {
        // Dev mode: skip Stripe verification when NODE_ENV is not 'production'
        // OR when Stripe isn't configured. Production must have STRIPE_SECRET_KEY
        // set and the client must complete a PaymentIntent through Stripe
        // Elements first.
        const devMode = process.env.NODE_ENV !== 'production'
            || !process.env.STRIPE_SECRET_KEY;
        if (!devMode) {
            if (!paymentIntentId) {
                return res.status(400).json({ error: 'Missing paymentIntentId.' });
            }
            const intent = await getStripe().paymentIntents.retrieve(paymentIntentId);
            if (intent.status !== 'succeeded') {
                return res.status(402).json({ error: 'Payment not completed.' });
            }
            if (String(intent.metadata.playerId) !== String(req.playerId)) {
                return res.status(403).json({ error: 'Payment does not belong to this account.' });
            }
        }
        const { rows } = await pool.query(
            'UPDATE players SET contraband = contraband + $1 WHERE id = $2 RETURNING contraband',
            [amount, req.playerId]
        );
        res.json({ success: true, newContraband: rows[0].contraband, devMode });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
