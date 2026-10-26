'use strict';

/**
 * STEAM (utils/steam.js talks to Steam; the game's side is godot/scripts/steam.gd)
 *
 *   GET  /api/steam/status            {login, purchases, appId}: what the server has set up
 *   POST /api/steam/login             {ticket, create?}  → {token, player, created} like /api/auth/login;
 *                                      a Steam account with no player yet: 404 {code: 'no_account'} unless
 *                                      create is true (then a new player, named after the Steam name)
 *   POST /api/steam/link              {ticket} signed in: this player signs in with that Steam account from now on
 *   POST /api/steam/purchase/init     {bundleId, language?} signed in, Steam linked → {orderId}: Steam shows the
 *                                      order in its overlay; the game hears whether the player approved it
 *   POST /api/steam/purchase/finalize {orderId} → {contrabandGranted, newContraband}: charged once, granted once
 */

const router = require('express').Router();
const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool');
const { requireAuth } = require('./middleware');
const steam = require('../utils/steam');
const { CONTRABAND_BUNDLES, grantContraband } = require('./shop');

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES = process.env.JWT_EXPIRES || '7d';
const PLAYER_FIELDS = `id, username, email, karat, contraband, level, xp, rank, avatar_url, wins, losses, chosen_clan`;

let deps = { verifyTicket: steam.verifyTicket, personaName: steam.personaName, initTxn: steam.initTxn, finalizeTxn: steam.finalizeTxn };
/** Tests: stand-ins for the Steam calls. */
router.useSteam = (d) => { deps = { ...deps, ...d }; };

function sign(player) {
    return jwt.sign({ sub: player.id, username: player.username, avatarUrl: player.avatar_url || null }, JWT_SECRET, { expiresIn: JWT_EXPIRES });
}

function fail(res, err, what) {
    if (err instanceof steam.SteamError) return res.status(err.status).json({ error: err.message });
    console.error(`[Steam] ${what}:`, err.message);
    res.status(500).json({ error: `Could not ${what}.` });
}

/** A username from a Steam name: printable, 3-20 characters, and free (a number added if it's taken). */
async function freeName(name) {
    let base = String(name || '').replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, 16);
    if (base.length < 3) base = 'Brawler';
    for (let i = 0; i < 20; i++) {
        const tryName = i === 0 ? base : `${base}${Math.floor(1000 + Math.random() * 9000)}`;
        const { rowCount } = await pool.query('SELECT 1 FROM players WHERE username = $1', [tryName]);
        if (!rowCount) return tryName;
    }
    return `Brawler${Date.now() % 1000000}`;
}

router.get('/status', (req, res) => {
    const cfg = steam.config();
    res.json({ appId: cfg.appId, login: !!cfg.key, purchases: !!cfg.publisher, sandbox: cfg.sandbox });
});

router.post('/login', async (req, res) => {
    const { ticket, create } = req.body || {};
    try {
        const steamId = await deps.verifyTicket(ticket);
        const { rows } = await pool.query(`SELECT ${PLAYER_FIELDS} FROM players WHERE steam_id = $1`, [steamId]);
        if (rows.length) {
            await pool.query('UPDATE players SET last_login = NOW() WHERE id = $1', [rows[0].id]);
            return res.json({ token: sign(rows[0]), player: rows[0], created: false });
        }
        if (!create) return res.status(404).json({ error: 'No player for this Steam account yet.', code: 'no_account' });
        const username = await freeName(await deps.personaName(steamId));
        const { rows: [player] } = await pool.query(
            `INSERT INTO players (username, steam_id, email_verified, karat, contraband)
             VALUES ($1, $2, true, 500, 0) RETURNING ${PLAYER_FIELDS}`, [username, steamId]);
        console.log(`[Steam] New player ${username} (Steam ${steamId})`);
        res.status(201).json({ token: sign(player), player, created: true });
    } catch (err) {
        if (err.code === '23505') return res.status(409).json({ error: 'This Steam account already has a player. Try again.' });
        fail(res, err, 'sign in with Steam');
    }
});

router.post('/link', requireAuth, async (req, res) => {
    try {
        const steamId = await deps.verifyTicket((req.body || {}).ticket);
        const { rows: [other] } = await pool.query('SELECT id, username FROM players WHERE steam_id = $1', [steamId]);
        if (other && other.id !== req.playerId) {
            return res.status(409).json({ error: `That Steam account already plays as ${other.username}.`, code: 'steam_taken' });
        }
        await pool.query('UPDATE players SET steam_id = $1 WHERE id = $2', [steamId, req.playerId]);
        res.json({ linked: true });
    } catch (err) {
        fail(res, err, 'link the Steam account');
    }
});

router.post('/purchase/init', requireAuth, async (req, res) => {
    const { bundleId, language } = req.body || {};
    const bundle = CONTRABAND_BUNDLES[bundleId];
    if (!bundle) return res.status(400).json({ error: 'Invalid bundle.' });
    try {
        const { rows: [p] } = await pool.query('SELECT steam_id FROM players WHERE id = $1', [req.playerId]);
        if (!p?.steam_id) return res.status(400).json({ error: 'Link your Steam account first (Settings).', code: 'not_linked' });
        const { rows: [order] } = await pool.query(
            `INSERT INTO steam_orders (player_id, steam_id, bundle_id, amount_cents, currency)
             VALUES ($1, $2, $3, $4, 'USD') RETURNING order_id`, [req.playerId, p.steam_id, bundleId, bundle.priceCents]);
        const { transId } = await deps.initTxn({
            orderId: order.order_id, steamId: p.steam_id, itemId: bundleId.replace(/\D/g, '') || '1',
            description: `${bundle.contraband.toLocaleString('en')} Contraband`, amountCents: bundle.priceCents,
            language: /^[a-z]{2}$/.test(String(language || '')) ? language : 'en',
        });
        await pool.query('UPDATE steam_orders SET trans_id = $1 WHERE order_id = $2', [transId, order.order_id]);
        res.json({ orderId: String(order.order_id) });
    } catch (err) {
        fail(res, err, 'start the purchase');
    }
});

router.post('/purchase/finalize', requireAuth, async (req, res) => {
    const orderId = String((req.body || {}).orderId || '');
    if (!/^\d{1,19}$/.test(orderId)) return res.status(400).json({ error: 'Missing orderId.' });
    try {
        const { rows: [order] } = await pool.query('SELECT * FROM steam_orders WHERE order_id = $1', [orderId]);
        if (!order || order.player_id !== req.playerId) return res.status(404).json({ error: 'No such order.' });
        if (order.status === 'done') return res.status(409).json({ error: 'This purchase has already been added.' });
        await deps.finalizeTxn(orderId);   // (Steam charges the wallet here; it refuses a second time)
        await pool.query(`UPDATE steam_orders SET status = 'done', finalized_at = NOW() WHERE order_id = $1`, [orderId]);
        const r = await grantContraband(`steam:${orderId}`, req.playerId, order.bundle_id);
        if (!r) return res.status(409).json({ error: 'This purchase has already been added.' });
        res.json({ success: true, contrabandGranted: r.contrabandGranted, newContraband: r.newContraband });
    } catch (err) {
        if (err instanceof steam.SteamError) {
            await pool.query(`UPDATE steam_orders SET status = 'failed' WHERE order_id = $1 AND status = 'init'`, [orderId]).catch(() => {});
        }
        fail(res, err, 'finish the purchase');
    }
});

module.exports = router;
