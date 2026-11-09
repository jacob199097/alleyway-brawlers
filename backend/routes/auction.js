'use strict';

// The auction house (economy/auction.js; its numbers: economy/auction_settings.js). Cards are named by game ID.
//   GET  /api/auction                      → { eligible, reasons, karat, limits, rules }
//   GET  /api/auction/browse?rarity=&clan=&search=   → { auctions: [...] }   running auctions, soonest to end first
//   GET  /api/auction/mine                 → { selling: [...], bidding: [...] }   yours, running and the last 7 days'
//   POST /api/auction/list   {card, startPrice, buyNow?}  → { auction, karat }   startPrice = the reserve (lowest bid)
//   POST /api/auction/:id/bid  {amount}          → { auction, karat }
//   POST /api/auction/:id/buy                    → { auction, karat }   Buy Now, only before the first bid
//   POST /api/auction/:id/cancel                 → { ok }   only before the first bid

const router = require('express').Router();
const { requireAuth } = require('./middleware');
const auction = require('../economy/auction');
const { ipHash } = require('../utils/ipHash');

function fail(res, err) {
    if (err instanceof auction.AuctionError) return res.status(400).json({ error: err.message });
    console.error('[Auction]', err.message);
    res.status(500).json({ error: 'Something went wrong. Try again.' });
}

router.get('/', requireAuth, async (req, res) => {
    try {
        res.json(await auction.overview(req.playerId));
    } catch (err) {
        fail(res, err);
    }
});

router.get('/browse', requireAuth, async (req, res) => {
    try {
        const { rarity, clan, search } = req.query;
        res.json({ auctions: await auction.browse(req.playerId, { rarity, clan, search }) });
    } catch (err) {
        fail(res, err);
    }
});

router.get('/mine', requireAuth, async (req, res) => {
    try {
        res.json(await auction.mine(req.playerId));
    } catch (err) {
        fail(res, err);
    }
});

router.post('/list', requireAuth, async (req, res) => {
    const { card, startPrice, buyNow } = req.body || {};
    if (typeof card !== 'string') return res.status(400).json({ error: 'Which card?' });
    try {
        res.json(await auction.list(req.playerId, card, Number(startPrice), ipHash(req), buyNow == null || buyNow === 0 ? null : Number(buyNow)));
    } catch (err) {
        fail(res, err);
    }
});

router.post('/:id/bid', requireAuth, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Which auction?' });
    try {
        res.json(await auction.bid(req.playerId, id, Number((req.body || {}).amount), ipHash(req)));
    } catch (err) {
        fail(res, err);
    }
});

router.post('/:id/buy', requireAuth, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Which auction?' });
    try {
        res.json(await auction.buyNow(req.playerId, id, ipHash(req)));
    } catch (err) {
        fail(res, err);
    }
});

router.post('/:id/cancel', requireAuth, async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'Which auction?' });
    try {
        res.json(await auction.cancel(req.playerId, id));
    } catch (err) {
        fail(res, err);
    }
});

module.exports = router;
