'use strict';

/**
 * CONTRACTS: a goal bought in the shop for Karat (economy/contract_settings.js has every number). It covers
 * the player's next MATCHES eligible matches (Casual, Ranked, CPU on Normal or harder): done in one of them,
 * it pays its payout, the moment it's done (a "win" goal at the end of a match the player won); not done in
 * time, the Karat it cost is gone. One at a time, and each of the day's OFFERS once a day.
 * The server judges it from the match it runs (socket/onlineMatch.js), so nothing a game reports counts.
 *
 *   offers(day)                  the day's contracts (the same for everyone)
 *   status(playerId)             → { day, offers, active, resetsIn, karat }
 *   buy(playerId, index)         → { status } | { error, code }
 *   activeFor(playerId)          the active contract, as a match tracks it (or null)
 *   complete(playerId, id)       pays a done contract → { payout, karat } (null if it wasn't active)
 *   matchPlayed(playerId, id)    an eligible match ended without it → { status, matches_left }
 *   eligible(mode, level, challenge)   whether a match counts
 *   tracker / track / doneNow / doneAtEnd   following a goal through a match's events
 */

const { pool } = require('../db/pool');
const { MATCHES, OFFERS, CPU_LEVELS, MODES, GOALS } = require('./contract_settings');

const today = () => new Date().toISOString().slice(0, 10);

/** A small seeded generator (the day's offers are the same for everyone). */
function seeded(text) {
    let h = 2166136261;
    for (const ch of text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
    return () => {
        h = (h + 0x6D2B79F5) >>> 0;
        let t = h;
        t = Math.imul(t ^ (t >>> 15), 1 | t);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

/** The day's contracts: OFFERS different goals, picked by the date. */
function offers(day = today()) {
    const keys = Object.keys(GOALS);
    const rand = seeded(`contracts:${day}`);
    for (let i = keys.length - 1; i > 0; i--) {
        const j = Math.floor(rand() * (i + 1));
        [keys[i], keys[j]] = [keys[j], keys[i]];
    }
    return keys.slice(0, OFFERS).map((goal, index) => card(goal, index));
}

function card(goal, index = null) {
    const g = GOALS[goal];
    const out = { goal, text: g.text, price: g.price, payout: g.payout, matches: MATCHES, win: !!g.win };
    if (index != null) out.index = index;
    return out;
}

const secsToMidnight = () => {
    const now = new Date();
    return Math.max(1, Math.round((Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1) - now) / 1000));
};

const rowOut = (r) => r && GOALS[r.goal] ? { id: r.id, ...card(r.goal), price: r.price, payout: r.payout, matches_left: r.matches_left, status: r.status } : null;

async function status(playerId, client = pool) {
    const day = today();
    const { rows: [p] } = await client.query('SELECT karat FROM players WHERE id = $1', [playerId]);
    if (!p) return null;
    const { rows } = await client.query(
        `SELECT id, goal, price, payout, matches_left, status, day::text AS day FROM player_contracts
          WHERE player_id = $1 AND (status = 'active' OR day = $2::date) ORDER BY id`, [playerId, day]);
    const active = rowOut(rows.find(r => r.status === 'active'));
    const bought = {};
    for (const r of rows) if (r.day === day) bought[r.goal] = r.status;
    return {
        day, active, resetsIn: secsToMidnight(), karat: Number(p.karat) || 0,
        offers: offers(day).map(o => ({ ...o, bought: bought[o.goal] || null })),
    };
}

/** Buys one of today's offers → { status } or { error, code } (409: one is active / bought today; 402: Karat). */
async function buy(playerId, index) {
    const offer = offers(today())[Number(index)];
    if (!offer) return { error: 'That contract is not on offer.', code: 400 };
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [busy] } = await client.query(
            `SELECT 1 FROM player_contracts WHERE player_id = $1 AND status = 'active' FOR UPDATE`, [playerId]);
        if (busy) {
            await client.query('ROLLBACK');
            return { error: 'You already have a contract. Finish it (or run out of matches) first.', code: 409 };
        }
        const { rows: [again] } = await client.query(
            'SELECT 1 FROM player_contracts WHERE player_id = $1 AND day = $2::date AND goal = $3', [playerId, today(), offer.goal]);
        if (again) {
            await client.query('ROLLBACK');
            return { error: "You've taken that contract today. New ones arrive tomorrow.", code: 409 };
        }
        const { rows: [paid] } = await client.query(
            'UPDATE players SET karat = karat - $1 WHERE id = $2 AND karat >= $1 RETURNING karat', [offer.price, playerId]);
        if (!paid) {
            await client.query('ROLLBACK');
            return { error: `Not enough Karat: this contract costs ${offer.price}.`, code: 402 };
        }
        await client.query(
            `INSERT INTO player_contracts (player_id, day, goal, price, payout, matches_left) VALUES ($1, $2::date, $3, $4, $5, $6)`,
            [playerId, today(), offer.goal, offer.price, offer.payout, MATCHES]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        if (err.code === '23505') return { error: 'You already have a contract.', code: 409 };   // (two buys at once)
        throw err;
    } finally {
        client.release();
    }
    return { status: await status(playerId) };
}

async function activeFor(playerId) {
    const { rows: [r] } = await pool.query(
        `SELECT id, goal, price, payout, matches_left, status FROM player_contracts WHERE player_id = $1 AND status = 'active'`, [playerId]);
    return rowOut(r);
}

/** It's done: marked done and paid, once → { payout, karat } (null if it wasn't active any more). */
async function complete(playerId, id) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [c] } = await client.query(
            `UPDATE player_contracts SET status = 'done', ended_at = NOW() WHERE id = $1 AND player_id = $2 AND status = 'active' RETURNING payout`,
            [id, playerId]);
        if (!c) {
            await client.query('ROLLBACK');
            return null;
        }
        const { rows: [p] } = await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2 RETURNING karat', [c.payout, playerId]);
        await client.query('COMMIT');
        return { payout: c.payout, karat: Number(p.karat) || 0 };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

/** An eligible match ended and the contract wasn't done: one match fewer; none left and it has failed. */
async function matchPlayed(playerId, id) {
    const { rows: [c] } = await pool.query(
        `UPDATE player_contracts SET matches_left = matches_left - 1,
                status = CASE WHEN matches_left <= 1 THEN 'failed' ELSE status END,
                ended_at = CASE WHEN matches_left <= 1 THEN NOW() ELSE ended_at END
          WHERE id = $1 AND player_id = $2 AND status = 'active' RETURNING status, matches_left`, [id, playerId]);
    return c || null;
}

/** Whether a match counts toward a contract: Casual, Ranked, or a CPU on Normal or harder; not a weekly challenge. */
function eligible(mode, level = null, challenge = null) {
    if (challenge || !MODES.includes(mode)) return false;
    return mode !== 'cpu' || CPU_LEVELS.includes(level || 'normal');
}

// ── Following a goal through a match ──
function tracker(contract) {
    return { ...contract, n: 0, spoiled: false, done: false };
}

/** One of the match's events (seat names the server's: me is the player's seat). */
function track(t, ev, me) {
    const g = GOALS[t.goal];
    if (!g || t.done) return;
    if (g.spoil && g.spoil(ev, me)) t.spoiled = true;
    if (g.count && g.count(ev, me)) t.n += 1;
    if (g.sum) t.n += g.sum(ev, me);
}

/** Done during the match (goals that don't need a win). */
function doneNow(t) {
    const g = GOALS[t.goal];
    return !!g && !t.done && !g.win && g.need != null && t.n >= g.need;
}

/** Done at the end of the match: m = { won, morale, turns }. */
function doneAtEnd(t, m) {
    const g = GOALS[t.goal];
    if (!g || t.done) return false;
    if (!g.win) return doneNow(t);
    return m.won && !t.spoiled && (!g.end || g.end(m)) && (g.need == null || t.n >= g.need);
}

/** What a player is told of their progress: "2 / 3", or "" for goals judged at the end. */
function progressText(t) {
    const g = GOALS[t.goal];
    return g && g.need != null && !g.win ? `${Math.min(t.n, g.need)} / ${g.need}` : '';
}

module.exports = { offers, status, buy, activeFor, complete, matchPlayed, eligible, tracker, track, doneNow, doneAtEnd, progressText, today };
