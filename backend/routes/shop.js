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

// A pack for every clan with at least 3 collectable cards (new Card Forge clans appear here
// automatically after backend/scripts/sync_cards.mjs). Cached for a minute.
let _packs = { at: 0, list: ['lion_pride', 'viper_clan'] };
async function validPacks() {
    if (Date.now() - _packs.at < 60_000) return _packs.list;
    try {
        const { rows } = await pool.query(
            `SELECT clan::text AS clan FROM cards WHERE card_type <> 'leader'
             GROUP BY clan HAVING COUNT(*) >= 3 ORDER BY MIN(created_at), clan`);
        _packs = { at: Date.now(), list: rows.map(r => r.clan) };
    } catch (err) {
        console.error('[Shop] Could not list packs:', err.message);
    }
    return _packs.list;
}

// ── GET /api/shop/packs — list available packs and player karat ───────────────
router.get('/packs', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            'SELECT karat FROM players WHERE id = $1', [req.playerId]
        );
        res.json({
            karat: rows[0]?.karat ?? 0,
            packs: (await validPacks()).map(p => ({
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
    if (!(await validPacks()).includes(packType)) {
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
    if (!(await validPacks()).includes(packType)) {
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

// ── Contraband bundles — the server is the only source of price and amount ───
// The client only ever names a bundleId; never trust an amount or price it sends.
const CONTRABAND_BUNDLES = {
    cb_500:   { contraband: 500,   priceCents: 499  },
    cb_1200:  { contraband: 1200,  priceCents: 999  },
    cb_2500:  { contraband: 2500,  priceCents: 1999 },
    cb_7000:  { contraband: 7000,  priceCents: 4999 },
    cb_15000: { contraband: 15000, priceCents: 9999 },
};

// Free grants without a real payment are only possible when explicitly opted
// into on a non-production server (local testing of the shop UI).
function devFreePurchases() {
    return process.env.NODE_ENV !== 'production' && process.env.DEV_FREE_PURCHASES === 'true';
}

// ── POST /api/shop/contraband/create-intent — create Stripe PaymentIntent ────
router.post('/contraband/create-intent', requireAuth, async (req, res) => {
    const { bundleId } = req.body;
    const bundle = CONTRABAND_BUNDLES[bundleId];
    if (!bundle) return res.status(400).json({ error: 'Invalid bundle.' });
    try {
        const intent = await getStripe().paymentIntents.create({
            amount:   bundle.priceCents,
            currency: 'usd',
            metadata: { playerId: req.playerId, bundleId },
        });
        res.json({ clientSecret: intent.client_secret });
    } catch (err) {
        console.error('[shop/create-intent]', err.message);
        res.status(500).json({ error: 'Could not start payment.' });
    }
});

// ── POST /api/shop/contraband/purchase — verify payment, then grant once ─────
router.post('/contraband/purchase', requireAuth, async (req, res) => {
    const { paymentIntentId, bundleId } = req.body;

    let grantKey, grantBundleId;
    try {
        if (devFreePurchases()) {
            if (!CONTRABAND_BUNDLES[bundleId]) return res.status(400).json({ error: 'Invalid bundle.' });
            grantKey      = `dev_${req.playerId}_${Date.now()}_${Math.random().toString(36).slice(2)}`;
            grantBundleId = bundleId;
        } else {
            if (!process.env.STRIPE_SECRET_KEY) {
                return res.status(503).json({ error: 'Purchases are not available yet.' });
            }
            if (typeof paymentIntentId !== 'string' || !paymentIntentId) {
                return res.status(400).json({ error: 'Missing paymentIntentId.' });
            }
            const intent = await getStripe().paymentIntents.retrieve(paymentIntentId);
            const bundle = CONTRABAND_BUNDLES[intent.metadata?.bundleId];
            if (intent.status !== 'succeeded') {
                return res.status(402).json({ error: 'Payment not completed.' });
            }
            if (String(intent.metadata?.playerId) !== String(req.playerId)) {
                return res.status(403).json({ error: 'Payment does not belong to this account.' });
            }
            // Bundle comes from the intent the server created, and the amount
            // actually charged must match its price.
            if (!bundle || intent.amount_received !== bundle.priceCents || intent.currency !== 'usd') {
                return res.status(400).json({ error: 'Payment does not match a valid bundle.' });
            }
            grantKey      = intent.id;
            grantBundleId = intent.metadata.bundleId;
        }
    } catch (err) {
        console.error('[shop/purchase] verify', err.message);
        return res.status(500).json({ error: 'Could not verify payment.' });
    }

    const bundle = CONTRABAND_BUNDLES[grantBundleId];
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        // One grant per PaymentIntent — a replayed id inserts nothing.
        const { rowCount } = await client.query(
            `INSERT INTO payment_grants (payment_intent_id, player_id, bundle_id, contraband)
             VALUES ($1, $2, $3, $4) ON CONFLICT (payment_intent_id) DO NOTHING`,
            [grantKey, req.playerId, grantBundleId, bundle.contraband]
        );
        if (!rowCount) {
            await client.query('ROLLBACK');
            return res.status(409).json({ error: 'This payment has already been redeemed.' });
        }
        const { rows } = await client.query(
            'UPDATE players SET contraband = contraband + $1 WHERE id = $2 RETURNING contraband',
            [bundle.contraband, req.playerId]
        );
        await client.query('COMMIT');
        res.json({
            success: true,
            contrabandGranted: bundle.contraband,
            newContraband: rows[0].contraband,
            devMode: grantKey.startsWith('dev_'),
        });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('[shop/purchase] grant', err.message);
        res.status(500).json({ error: 'Purchase failed.' });
    } finally {
        client.release();
    }
});

module.exports = router;
