'use strict';

/**
 * Contracts against a real Postgres (economy/contracts.js): the day's offers, buying one (Karat paid, one
 * at a time, each offer once a day, not without the Karat), done → paid once, three matches without it →
 * failed; which matches count; and each goal judged from a match's events. Builds a scratch database like
 * seasons.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/contracts.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_contracts_test';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { Client } = require('pg');

const conn = (database) => new Client({
    host: process.env.DB_HOST || 'localhost', port: Number(process.env.DB_PORT || 5432),
    user: process.env.DB_USER || 'turf_admin', password: process.env.DB_PASS || undefined, database,
});

(async () => {
    const admin = conn('postgres');
    await admin.connect();
    await admin.query(`DROP DATABASE IF EXISTS ${process.env.DB_NAME}`);
    await admin.query(`CREATE DATABASE ${process.env.DB_NAME}`);
    await admin.end();
    const c = conn(process.env.DB_NAME);
    await c.connect();
    await c.query(fs.readFileSync(path.join(__dirname, '../db/schema.sql'), 'utf8'));
    await c.end();

    const { pool } = require('../db/pool');
    const { migrate } = require('../db/migrate');
    await migrate(pool);
    await migrate(pool);   // running it again changes nothing
    const q = (sql, params) => pool.query(sql, params);
    const contracts = require('./contracts');
    const { GOALS, MATCHES, OFFERS } = require('./contract_settings');
    const player = async (name, karat) => (await q(
        `INSERT INTO players (username, email, password_hash, karat) VALUES ($1, $2, 'x', $3) RETURNING id`,
        [name, `${name}@test.local`, karat])).rows[0].id;
    const karatOf = async (id) => Number((await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat);

    // The day's offers: the same for everyone, different goals, a new set another day
    const day = contracts.offers('2026-11-15');
    assert.deepEqual(day, contracts.offers('2026-11-15'));
    assert.equal(day.length, OFFERS);
    assert.equal(new Set(day.map(o => o.goal)).size, OFFERS, 'no goal twice in a day');
    const week = new Set();
    for (let d = 10; d < 24; d++) week.add(contracts.offers(`2026-11-${d}`).map(o => o.goal).join());
    assert.ok(week.size > 5, 'the offers change from day to day');
    for (const o of day) assert.ok(o.payout > o.price, 'a contract pays more than it costs');

    // Buying: paid in Karat, one at a time, each offer once a day
    const ana = await player('ana', 1000);
    let s = await contracts.status(ana);
    assert.equal(s.active, null);
    assert.ok(s.resetsIn > 0 && s.resetsIn <= 86400);
    const o0 = s.offers[0], o1 = s.offers[1];
    let r = await contracts.buy(ana, 0);
    assert.ok(r.status, r.error);
    assert.equal(await karatOf(ana), 1000 - o0.price, 'paid');
    assert.equal(r.status.active.goal, o0.goal);
    assert.equal(r.status.active.matches_left, MATCHES);
    assert.equal(r.status.offers[0].bought, 'active');
    r = await contracts.buy(ana, 1);
    assert.equal(r.code, 409, 'one contract at a time');
    assert.equal(await karatOf(ana), 1000 - o0.price, 'and nothing paid for it');
    assert.equal((await contracts.buy(ana, 9)).code, 400, 'not an offer');

    // Done: paid once
    const active = await contracts.activeFor(ana);
    let paid = await contracts.complete(ana, active.id);
    assert.equal(paid.payout, o0.payout);
    assert.equal(await karatOf(ana), 1000 - o0.price + o0.payout);
    assert.equal(await contracts.complete(ana, active.id), null, 'never paid twice');
    assert.equal(await contracts.activeFor(ana), null);
    assert.equal((await contracts.buy(ana, 0)).code, 409, 'the same offer only once a day');

    // Three matches without it: it has failed (and the Karat is gone)
    r = await contracts.buy(ana, 1);
    assert.ok(r.status, r.error);
    const second = await contracts.activeFor(ana);
    const before = await karatOf(ana);
    assert.deepEqual(await contracts.matchPlayed(ana, second.id), { status: 'active', matches_left: 2 });
    assert.deepEqual(await contracts.matchPlayed(ana, second.id), { status: 'active', matches_left: 1 });
    assert.deepEqual(await contracts.matchPlayed(ana, second.id), { status: 'failed', matches_left: 0 });
    assert.equal(await contracts.matchPlayed(ana, second.id), null, 'over');
    assert.equal(await contracts.complete(ana, second.id), null, 'a failed contract pays nothing');
    assert.equal(await karatOf(ana), before);
    s = await contracts.status(ana);
    assert.equal(s.offers[1].bought, 'failed');
    assert.equal(s.active, null);

    // Not without the Karat
    const bo = await player('bo', 50);
    assert.equal((await contracts.buy(bo, 0)).code, 402);
    assert.equal(await karatOf(bo), 50);
    void o1;

    // Which matches count
    assert.ok(contracts.eligible('casual') && contracts.eligible('ranked') && contracts.eligible('cpu_ranked', 'hard'));
    assert.ok(contracts.eligible('cpu', 'normal') && contracts.eligible('cpu', 'hard'));
    assert.ok(!contracts.eligible('cpu', 'easy'), 'not the easy CPU');
    assert.ok(!contracts.eligible('friendly'), 'not a friendly challenge');
    assert.ok(!contracts.eligible('cpu', 'hard', { week: 1 }), 'not a weekly challenge');

    // Each goal, judged from a match's events (seat "player" is the contract holder)
    const judge = (goal, events, end = null) => {
        const t = contracts.tracker({ id: 1, goal, ...GOALS[goal] });
        let mid = false;
        for (const ev of events) {
            contracts.track(t, ev, 'player');
            if (contracts.doneNow(t)) { mid = true; t.done = true; }
        }
        if (mid) return 'now';
        return end && contracts.doneAtEnd(t, end) ? 'end' : 'no';
    };
    const ko = (side, extra = {}) => ({ type: 'ko', side, card: { id: 'x' }, ...extra });
    assert.equal(judge('ko_3', [ko('opponent'), ko('opponent'), ko('player'), ko('opponent')]), 'now');
    assert.equal(judge('ko_3', [ko('opponent'), ko('opponent'), ko('opponent', { exiled: true })]), 'no', 'EXILE is not a KO');
    assert.equal(judge('ko_5', [ko('opponent'), ko('opponent'), ko('opponent'), ko('opponent')], { won: true, morale: 6000, turns: 9 }), 'no');
    assert.equal(judge('down_5', Array(5).fill({ type: 'downed', side: 'opponent' })), 'now');
    assert.equal(judge('direct_2000', [{ type: 'clash', side: 'player', vs: 'DIRECT', att: 1500 }, { type: 'clash', side: 'opponent', vs: 'DIRECT', att: 900 },
        { type: 'clash', side: 'player', vs: 'DIRECT', att: 500 }]), 'now');
    assert.equal(judge('promote_1', [{ type: 'promote', side: 'player' }]), 'now');
    assert.equal(judge('awaken', [{ type: 'awaken', side: 'opponent' }]), 'no', 'their leader, not yours');
    assert.equal(judge('hustles_3', [{ type: 'hustle', side: 'player' }, { type: 'lasting', side: 'player', card: { cardType: 'hustle' } },
        { type: 'hustle', side: 'player' }]), 'now');
    assert.equal(judge('win_morale_3000', [], { won: true, morale: 3200, turns: 20 }), 'end');
    assert.equal(judge('win_morale_3000', [], { won: false, morale: 6000, turns: 20 }), 'no', 'only in a match you win');
    assert.equal(judge('win_morale_3000', [], { won: true, morale: 2900, turns: 20 }), 'no');
    assert.equal(judge('win_leader_safe', [{ type: 'leader_hit', side: 'opponent' }], { won: true, morale: 10, turns: 20 }), 'end', 'their leader can be hit');
    assert.equal(judge('win_leader_safe', [{ type: 'leader_hit', side: 'player' }], { won: true, morale: 6000, turns: 9 }), 'no');
    assert.equal(judge('win_fast', [], { won: true, morale: 10, turns: 12 }), 'end');
    assert.equal(judge('win_fast', [], { won: true, morale: 10, turns: 13 }), 'no');
    assert.equal(judge('win_no_losses', [ko('player', { card: { token: true } })], { won: true, morale: 10, turns: 30 }), 'end', 'a token lost is no character');
    assert.equal(judge('win_no_losses', [ko('player')], { won: true, morale: 10, turns: 30 }), 'no');
    for (const goal of Object.keys(GOALS)) assert.ok(GOALS[goal].text && GOALS[goal].payout > GOALS[goal].price, goal);

    await pool.end();
    console.log('contracts: all passed');
})().catch(async (err) => {
    console.error(err);
    process.exit(1);
});
