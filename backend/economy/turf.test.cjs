'use strict';

/**
 * Turf Defense rewards (economy/turf.js) against a real Postgres: level 1 open and the rest locked,
 * the first clear's rewards and prize card, repeat clears paying less, a defeat, the next level
 * opening, best turns, and the achievement counters. Builds a scratch database like
 * economy/progression.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/turf.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_turf_test';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { Client } = require('pg');

const DB = path.join(__dirname, '../db');
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
    await c.query(fs.readFileSync(path.join(DB, 'schema.sql'), 'utf8'));
    await c.query(`ALTER TYPE pack_type ADD VALUE IF NOT EXISTS 'nebula'`);
    await c.end();

    const { pool } = require('../db/pool');
    const { migrate } = require('../db/migrate');
    await migrate(pool);
    await migrate(pool);   // running it again changes nothing
    const turf = require('./turf');
    const { BOSSES, BOSS_DATA } = await import('../../shared/turf.js');
    const archon = BOSSES.find(b => b.id === 'archon');
    const q = (sql, params) => pool.query(sql, params);
    await q(`INSERT INTO cards (name, clan, card_type, rarity, art_url) VALUES ('DS-001', 'nebula', 'gang_member', 5, $1)`, [archon.prize]);
    const { rows: [{ id: me }] } = await q(`INSERT INTO players (username, email, password_hash) VALUES ('ann', 'ann@x', 'x') RETURNING id`);
    const player = async () => (await q('SELECT karat, xp, free_packs, wins, losses FROM players WHERE id = $1', [me])).rows[0];
    const counter = async (key) => Number((await q('SELECT value FROM player_counters WHERE player_id = $1 AND key = $2', [me, key])).rows[0]?.value || 0);
    const owned = async () => Number((await q(
        'SELECT quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id WHERE pi.player_id = $1 AND c.art_url = $2', [me, archon.prize])).rows[0]?.quantity || 0);

    // Nothing played: level 1 of every boss is open, the rest locked
    let s = await turf.status(me);
    assert.equal(s.bosses.length, BOSSES.length);
    const lv = (st, n) => st.bosses.find(b => b.id === 'archon').levels[n - 1];
    assert.ok(lv(s, 1).unlocked && !lv(s, 2).unlocked && !lv(s, 3).unlocked);
    assert.equal(s.bosses.find(b => b.id === 'archon').prize_won, false);

    // A defeat: the loss pay, nothing opens
    const start = await player();
    let r = await turf.resolve({ playerId: me, bossId: 'archon', level: 1, won: false, turns: 20 });
    assert.equal(r.won, false);
    assert.equal(r.karatEarned, BOSS_DATA.loss.karat);
    assert.equal((await player()).karat, start.karat + BOSS_DATA.loss.karat);
    assert.equal((await player()).losses, start.losses + 1);
    s = await turf.status(me);
    assert.ok(!lv(s, 2).unlocked && lv(s, 1).attempts === 1 && lv(s, 1).clears === 0);

    // The first clear: its rewards, the prize card, level 2 opens
    const before = await player();
    r = await turf.resolve({ playerId: me, bossId: 'archon', level: 1, won: true, turns: 24 });
    const first = archon.levels[0].first_clear;
    assert.ok(r.first && r.won);
    assert.equal(r.prize, archon.prize);
    assert.equal(r.karatEarned, first.karat);
    assert.equal(r.xpEarned, first.xp);
    assert.ok(r.unlockedNext);
    const after = await player();
    assert.equal(after.karat, before.karat + first.karat);
    assert.equal(after.xp, before.xp + first.xp);
    assert.equal(after.wins, before.wins + 1);
    assert.equal(await owned(), 1, 'the prize card is in the collection');
    s = await turf.status(me);
    assert.ok(lv(s, 2).unlocked && lv(s, 1).clears === 1 && lv(s, 1).best_turns === 24);
    assert.equal(s.bosses.find(b => b.id === 'archon').prize_won, true);
    assert.equal(await counter('turf_clears'), 1);
    assert.equal(await counter('turf_bosses'), 1);

    // Clearing it again: the smaller pay, no second prize, the best turns kept
    r = await turf.resolve({ playerId: me, bossId: 'archon', level: 1, won: true, turns: 30 });
    assert.ok(!r.first && r.prize === null);
    assert.equal(r.karatEarned, archon.levels[0].clear.karat);
    assert.equal(await owned(), 1);
    r = await turf.resolve({ playerId: me, bossId: 'archon', level: 1, won: true, turns: 18 });
    s = await turf.status(me);
    assert.equal(lv(s, 1).clears, 3);
    assert.equal(lv(s, 1).best_turns, 18);
    assert.equal(await counter('turf_bosses'), 1, 'still one boss beaten');

    // Level 2's first clear: its packs; level 3 opens; then a Nightmare clear counts
    const p2 = await player();
    r = await turf.resolve({ playerId: me, bossId: 'archon', level: 2, won: true, turns: 26 });
    assert.ok(r.first && r.packs === archon.levels[1].first_clear.packs);
    assert.ok((await player()).free_packs >= p2.free_packs + r.packs);
    assert.ok(lv(await turf.status(me), 3).unlocked);
    await turf.resolve({ playerId: me, bossId: 'archon', level: 3, won: true, turns: 30 });
    assert.equal(await counter('turf_nightmare'), 1);
    assert.deepEqual(Object.keys((await turf.clearsOf(pool, me)).archon).sort(), ['1', '2', '3']);
    assert.ok(turf.unlocked({}, 'veyr', 1) && !turf.unlocked({}, 'veyr', 2));

    await pool.end();
    console.log('turf rewards: ok');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
