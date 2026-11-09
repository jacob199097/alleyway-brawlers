'use strict';

/**
 * The auction house against a real Postgres (economy/auction.js): listing, bidding, outbids, the end of an
 * auction, cancelling, the limits and requirements, the abuse flags and deleting an account mid-auction.
 * Like progression.test.cjs it builds a scratch database (DB_NAME, default turf_war_test):
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/auction.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_test';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { Client } = require('pg');

const DB = path.join(__dirname, '../db');
const conn = (database) => new Client({
    host: process.env.DB_HOST || 'localhost', port: Number(process.env.DB_PORT || 5432),
    user: process.env.DB_USER || 'turf_admin', password: process.env.DB_PASS || undefined, database,
});

async function freshDatabase() {
    const admin = conn('postgres');
    await admin.connect();
    await admin.query(`DROP DATABASE IF EXISTS ${process.env.DB_NAME}`);
    await admin.query(`CREATE DATABASE ${process.env.DB_NAME}`);
    await admin.end();
    const c = conn(process.env.DB_NAME);
    await c.connect();
    await c.query(fs.readFileSync(path.join(DB, 'schema.sql'), 'utf8'));
    await c.end();
}

async function rejects(promise, pattern) {
    try {
        await promise;
    } catch (err) {
        assert.match(err.message, pattern);
        return;
    }
    assert.fail(`expected an error matching ${pattern}`);
}

(async () => {
    await freshDatabase();
    const { pool } = require('../db/pool');
    const { migrate } = require('../db/migrate');
    await migrate(pool);
    await migrate(pool);   // running it again changes nothing
    require('child_process').execFileSync(process.execPath, [path.join(__dirname, '../scripts/sync_cards.mjs')], { stdio: 'inherit' });
    const auction = require('./auction');
    const S = auction.SETTINGS;
    const { deleteAccount } = require('../routes/account');
    const { prizeCardIds } = await import('../../shared/turf.js');

    const q = (sql, params) => pool.query(sql, params);
    // A player who may trade: level 12, 40 days old, email confirmed (a "regular" one: not newer)
    const player = async (name, { level = 12, days = 40, verified = true, karat = 10000, ip = null } = {}) => (await q(
        `INSERT INTO players (username, email, password_hash, level, created_at, email_verified, karat, signup_ip)
         VALUES ($1, $7, 'x', $2, NOW() - make_interval(days => $3), $4, $5, $6) RETURNING id`,
        [name, level, days, verified, karat, ip, name + '@x'])).rows[0].id;
    const cardId = async (gameId) => (await q('SELECT id FROM cards WHERE art_url = $1', [gameId])).rows[0].id;
    const give = async (id, gameId, n) => q(
        `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, $3)
         ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = $3`, [id, await cardId(gameId), n]);
    const owned = async (id, gameId) => (await q(
        'SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2', [id, await cardId(gameId)])).rows[0]?.quantity || 0;
    const karat = async (id) => (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;
    const mails = async (id) => (await q('SELECT subject FROM player_mail WHERE player_id = $1 ORDER BY created_at', [id])).rows.map(r => r.subject);
    const expire = (auctionId) => q(`UPDATE auctions SET ends_at = NOW() - INTERVAL '1 second' WHERE id = $1`, [auctionId]);
    const prizes = prizeCardIds();
    const pick = async (rarity, n = 1) => (await q(
        `SELECT art_url FROM cards WHERE rarity = $1 AND card_type <> 'leader' ORDER BY art_url`, [rarity])).rows
        .map(r => r.art_url).filter(id => !prizes.has(id)).slice(0, n);
    const [legend] = await pick(5);
    const commons = await pick(1, 8);
    const legendPrice = S.PRICES[5];

    const seller = await player('seller', { ip: 'ip-seller' });
    const buyer = await player('buyer', { ip: 'ip-buyer' });
    const rival = await player('rival', { ip: 'ip-rival' });

    // ── Who can use it ──
    const fresh = await player('fresh', { level: 1, days: 0, verified: false });
    let e = await auction.eligibility(fresh);
    assert.equal(e.ok, false);
    assert.equal(e.reasons.length, 3, 'level, account age and email: ' + e.reasons.join(' | '));
    assert.equal(e.newer, true);
    await give(fresh, commons[0], 2);
    await rejects(auction.list(fresh, commons[0], S.PRICES[1].min), /can't use the auction house yet/);
    const steamOnly = await player('steamy', { verified: false });
    await q(`UPDATE players SET steam_id = '7656' WHERE id = $1`, [steamOnly]);
    assert.equal((await auction.eligibility(steamOnly)).ok, true, 'an account made with Steam needs no email');
    assert.equal((await auction.eligibility(seller)).ok, true);

    // ── Listing ──
    await give(seller, legend, 2);
    await rejects(auction.list(seller, legend, legendPrice.min - 1), /can start between/);
    await rejects(auction.list(seller, legend, legendPrice.max + 1), /can start between/);
    await rejects(auction.list(seller, commons[7], S.PRICES[1].min), /don't own/);
    const prize = [...prizes][0];
    if (prize) await rejects(auction.list(seller, prize, 100), /prize can't be sold/);
    // A deck using both copies protects them
    const { rows: [deck] } = await q(`INSERT INTO decks (player_id, name) VALUES ($1, 'd') RETURNING id`, [seller]);
    await q('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, 2)', [deck.id, await cardId(legend)]);
    await rejects(auction.list(seller, legend, legendPrice.min), /decks use all 2 copies/);
    await q('UPDATE deck_cards SET copies = 1 WHERE deck_id = $1', [deck.id]);
    const k0 = await karat(seller);
    let r = await auction.list(seller, legend, legendPrice.min, 'ip-seller-list');
    const fee = auction.listingFee(legendPrice.min);
    assert.equal(r.karat, k0 - fee, 'the listing fee is paid');
    assert.equal(await owned(seller, legend), 1, 'the card leaves the collection');
    assert.equal(r.auction.mine, true);
    assert.equal(r.auction.minBid, legendPrice.min);
    const big = r.auction.id;

    // ── Bidding ──
    await rejects(auction.bid(seller, big, legendPrice.min), /own auction/);
    await rejects(auction.bid(fresh, big, legendPrice.min), /can't use the auction house yet/);
    await rejects(auction.bid(buyer, big, legendPrice.min - 1), /at least/);
    await rejects(auction.bid(buyer, big, legendPrice.max + 1), /at most/);
    const poor = await player('poor', { karat: 10 });
    await rejects(auction.bid(poor, big, legendPrice.min), /need \d+ Karat/);
    const kb = await karat(buyer);
    r = await auction.bid(buyer, big, legendPrice.min);
    assert.equal(r.karat, kb - legendPrice.min, 'the bid is held from the balance');
    assert.equal(r.auction.leading, true);
    await rejects(auction.bid(buyer, big, legendPrice.min + 100), /already the top bidder/);
    const raise = auction.minBid({ rarity: 5, high_bid: legendPrice.min, start_price: legendPrice.min });
    assert.equal(raise, legendPrice.min + Math.max(S.MIN_RAISE, Math.ceil(legendPrice.min * S.MIN_RAISE_PCT / 100)));
    await rejects(auction.bid(rival, big, raise - 1), new RegExp(`at least ${raise}`));
    // A late bid pushes the end back
    await q(`UPDATE auctions SET ends_at = NOW() + INTERVAL '10 seconds' WHERE id = $1`, [big]);
    r = await auction.bid(rival, big, raise);
    assert.ok(new Date(r.auction.endsAt) - Date.now() > (S.SNIPE_SECONDS - 10) * 1000, 'a bid in the last minutes extends the auction');
    assert.equal(await karat(buyer), kb, 'the outbid Karat comes back');
    assert.ok((await mails(buyer)).some(s => /^Outbid/.test(s)));
    const browse = await auction.browse(buyer);
    const seen = browse.find(a => a.id === big);
    assert.equal(seen.highBid, raise);
    assert.equal(seen.leading, false);
    assert.equal(seen.seller, 'seller');
    assert.ok(!('highBidder' in seen) && !('high_bidder' in seen), "the top bidder's name isn't shown");
    assert.equal(seen.minBid, auction.minBid({ rarity: 5, high_bid: raise, start_price: legendPrice.min }));

    // ── The end: the card to the top bidder, the price less the fee to the seller ──
    const ks = await karat(seller);
    const kr = await karat(rival);
    await expire(big);
    assert.equal(await auction.settleDue(), 1);
    assert.equal(await owned(rival, legend), 1, 'the winner gets the card');
    assert.equal(await karat(seller), ks + raise - auction.saleFee(raise), 'the seller gets the price less the fee');
    assert.equal(await karat(rival), kr, 'the winning bid was already held');
    assert.ok((await mails(rival)).some(s => /^You won/.test(s)));
    assert.ok((await mails(seller)).some(s => /^Sold/.test(s)));
    await rejects(auction.bid(buyer, big, legendPrice.max), /has ended/);
    let mine = await auction.mine(rival);
    assert.ok(mine.bidding.find(a => a.id === big).won);

    // ── No bids: the card goes back. Cancelling only before the first bid ──
    await give(seller, commons[0], 3);
    r = await auction.list(seller, commons[0], S.PRICES[1].min);
    await expire(r.auction.id);
    await auction.settleDue();
    assert.equal(await owned(seller, commons[0]), 3, 'an unsold card comes back');
    assert.ok((await mails(seller)).some(s => /^No bids/.test(s)));
    r = await auction.list(seller, commons[0], S.PRICES[1].min);
    await auction.cancel(seller, r.auction.id);
    assert.equal(await owned(seller, commons[0]), 3, 'a cancelled card comes back');
    await rejects(auction.cancel(buyer, r.auction.id), /isn't yours/);

    // ── Limits: auctions per day, and running at once (newer accounts get fewer) ──
    const reg = S.LIMITS.regular;
    const today = (await auction.overview(seller)).limits.todayUsed;
    assert.equal(today, 3, 'every listing today counts, ended or not');
    await q(`UPDATE auctions SET created_at = NOW() - INTERVAL '2 days' WHERE seller_id = $1`, [seller]);
    for (let i = 0; i < reg.active; i++) {
        await give(seller, commons[1 + i], 1);
        await auction.list(seller, commons[1 + i], S.PRICES[1].min);
    }
    await give(seller, commons[6], 1);
    await rejects(auction.list(seller, commons[6], S.PRICES[1].min), new RegExp(`${reg.active} auctions running at once`));
    const newer = await player('newer', { level: 6, days: 10 });
    assert.equal((await auction.eligibility(newer)).limits.active, S.LIMITS.newer.active);
    for (let i = 0; i < S.LIMITS.newer.perDay; i++) {
        await give(newer, commons[i], 1);
        await auction.list(newer, commons[i], S.PRICES[1].min);
    }
    await give(newer, commons[5], 1);
    await rejects(auction.list(newer, commons[5], S.PRICES[1].min), /auctions (running at once|a day)/);

    // ── Leading on too many auctions at once ──
    const { rows: running } = await q(`SELECT id FROM auctions WHERE status = 'active' ORDER BY id`);
    assert.ok(running.length >= 2);
    const greedy = await player('greedy');
    await q('UPDATE auctions SET high_bidder = $1, high_bid = start_price WHERE id = $2', [greedy, running[0].id]);
    const leadCap = S.MAX_LEADING_BIDS;
    S.MAX_LEADING_BIDS = 1;   // (leading on one: the cap)
    await rejects(auction.bid(greedy, running[1].id, S.PRICES[1].min), /top bidder on 1 auctions/);
    S.MAX_LEADING_BIDS = leadCap;
    await q(`UPDATE auctions SET high_bidder = NULL, high_bid = NULL WHERE high_bidder = $1`, [greedy]);

    // ── Flags: the same IP address, the same two players again and again ──
    const twin = await player('twin', { ip: 'ip-seller' });   // made from the seller's connection
    await give(seller, commons[7], 3);
    await q(`UPDATE auctions SET status = 'cancelled', settled_at = NOW() WHERE seller_id = $1 AND status = 'active'`, [seller]);
    await q(`UPDATE auctions SET created_at = NOW() - INTERVAL '2 days' WHERE seller_id = $1`, [seller]);
    r = await auction.list(seller, commons[7], S.PRICES[1].min);
    await auction.bid(twin, r.auction.id, S.PRICES[1].min);
    await expire(r.auction.id);
    await auction.settleDue();
    let { rows: [sale] } = await q('SELECT flags FROM auctions WHERE id = $1', [r.auction.id]);
    assert.deepEqual(sale.flags, ['same_ip']);
    for (let i = 0; i < S.REPEAT_PAIR_SALES; i++) {   // (the first earlier sale was seller → rival; these are seller → buyer)
        r = await auction.list(seller, commons[7], S.PRICES[1].min);
        await auction.bid(buyer, r.auction.id, S.PRICES[1].min);
        await expire(r.auction.id);
        await auction.settleDue();
        await give(seller, commons[7], 3);
    }
    ({ rows: [sale] } = await q('SELECT flags FROM auctions WHERE id = $1', [r.auction.id]));
    assert.deepEqual(sale.flags, ['repeat_pair']);
    const rep = await auction.report(30);
    assert.ok(rep.flagged.length >= 2);
    assert.ok(rep.pairs.some(p => [p.a, p.b].includes('buyer') && p.sales === S.REPEAT_PAIR_SALES));
    assert.ok(rep.sharedSignups.some(g => g.includes('seller') && g.includes('twin')));

    // ── Deleting an account mid-auction ──
    r = await auction.list(seller, commons[7], S.PRICES[1].min);
    const kbuyer = await karat(buyer);
    await auction.bid(buyer, r.auction.id, S.PRICES[1].min + 20);
    await deleteAccount(seller);
    assert.equal(await karat(buyer), kbuyer, "the seller left: the bid comes back");
    assert.ok((await mails(buyer)).some(s => /^Auction cancelled/.test(s)));
    ({ rows: [sale] } = await q('SELECT status FROM auctions WHERE id = $1', [r.auction.id]));
    assert.equal(sale.status, 'cancelled');
    await give(rival, commons[2], 2);
    r = await auction.list(rival, commons[2], S.PRICES[1].min);
    await auction.bid(buyer, r.auction.id, S.PRICES[1].min);
    await deleteAccount(buyer);
    ({ rows: [sale] } = await q('SELECT status, high_bidder, high_bid FROM auctions WHERE id = $1', [r.auction.id]));
    assert.equal(sale.status, 'active');
    assert.equal(sale.high_bidder, null, "the deleted top bidder's bid is gone");
    await expire(r.auction.id);
    await auction.settleDue();
    assert.equal(await owned(rival, commons[2]), 2, 'with no bid left it goes back to the seller');

    // ── Old auctions are forgotten ──
    await q(`UPDATE auctions SET settled_at = NOW() - make_interval(days => $1) WHERE status <> 'active'`, [S.KEEP_DAYS + 1]);
    assert.ok(await auction.cleanup() > 0);
    assert.equal((await q(`SELECT COUNT(*)::int AS n FROM auctions WHERE status <> 'active'`)).rows[0].n, 0);

    const ov = await auction.overview(rival);
    assert.equal(ov.eligible, true);
    assert.equal(ov.rules.saleFeePct, S.SALE_FEE_PCT);
    mine = await auction.mine(rival);
    assert.ok(Array.isArray(mine.selling) && Array.isArray(mine.bidding));

    await pool.end();
    console.log('Auction house: ok');
})().catch(err => {
    console.error(err);
    process.exit(1);
});
