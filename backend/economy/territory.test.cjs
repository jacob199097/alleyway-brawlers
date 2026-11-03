'use strict';

/**
 * Veteran cards (economy/veterans.js) and the turf map (economy/territory.js) against a real
 * Postgres: wins and plays per card and the tiers they reach; influence by mode, a district taken
 * from its local gang, a tie keeping it nobody's, the boss of a district, the week's Karat claimed
 * once, and nothing for a week still running. Builds a scratch database like economy/turf.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/territory.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_territory_test';
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
    const veterans = require('./veterans');
    const territory = require('./territory');
    const q = (sql, params) => pool.query(sql, params);
    const newPlayer = async (name) => (await q(
        `INSERT INTO players (username, email, password_hash) VALUES ($1, $2, 'x') RETURNING id`, [name, `${name}@x`])).rows[0].id;
    const ann = await newPlayer('ann');
    const bob = await newPlayer('bob');
    const karat = async (id) => (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;

    // ── Veteran cards ──
    assert.deepEqual(await veterans.record(ann, ['nebu_001', 'nebu_002', 'nebu_001'], false), []);   // a loss: plays only
    for (let i = 0; i < 4; i++) assert.deepEqual(await veterans.record(ann, ['nebu_001'], true), []);
    let up = await veterans.record(ann, ['nebu_001', 'nebu_002'], true);   // nebu_001's 5th win
    assert.deepEqual(up, [{ id: 'nebu_001', tier: 1, name: 'Seasoned' }]);
    let all = await veterans.overview(ann);
    assert.deepEqual(all.cards.nebu_001, { wins: 5, plays: 6, tier: 1 });
    assert.deepEqual(all.cards.nebu_002, { wins: 1, plays: 2, tier: 0 });
    assert.deepEqual(await veterans.tiers(ann), { nebu_001: 1 });
    assert.deepEqual(await veterans.tiers(ann, ['nebu_002', 'mili_001']), {}, 'only the cards asked about');
    assert.deepEqual(await veterans.tiers(bob), {}, "someone else's cards aren't mine");
    for (let i = 0; i < 10; i++) up = await veterans.record(ann, ['nebu_001'], true);
    assert.deepEqual(up, [{ id: 'nebu_001', tier: 2, name: 'Battle-Scarred' }]);
    assert.equal(veterans.tierOf(39), 2);
    assert.equal(veterans.tierOf(40), 3);

    // ── The turf map ──
    const [d1, d2, d3] = territory.DISTRICTS.map(d => d.id);
    assert.ok(d3, 'districts come from the arenas');
    assert.equal(territory.pointsFor({ mode: 'ranked', outcome: 'win' }), 3);
    assert.equal(territory.pointsFor({ mode: 'casual', outcome: 'loss' }), 1);
    assert.equal(territory.pointsFor({ mode: 'cpu', outcome: 'win', difficulty: 'easy' }), 1);
    assert.equal(territory.pointsFor({ mode: 'cpu', outcome: 'win', difficulty: 'hard' }), 2);
    assert.equal(territory.pointsFor({ mode: 'cpu_ranked', outcome: 'loss' }), 0);
    assert.equal(territory.pointsFor({ mode: 'coop', outcome: 'win' }), 3);
    // A turf map fight: its gang's stars decide it (5 stars: +3), whatever the difficulty
    assert.equal(territory.pointsFor({ mode: 'cpu', outcome: 'win', difficulty: 'hard', stars: 5 }), 3);
    assert.equal(territory.pointsFor({ mode: 'cpu', outcome: 'win', difficulty: 'easy', stars: 1 }), 1);
    // Every rating from 1 to 5 is on the map each week, the strongest gang at 5
    const rated = territory.DISTRICTS.map(d => ({ stars: territory.starsOf(d.id), strength: territory.locals(d.id, territory.weekOf()).strength }));
    assert.deepEqual([...new Set(rated.map(r => r.stars))].sort(), [1, 2, 3, 4, 5]);
    assert.equal(rated.find(r => r.stars === 5).strength >= Math.max(...rated.filter(r => r.stars === 1).map(r => r.strength)), true);
    assert.equal(territory.gangOf(territory.DISTRICTS[0].id).ai, territory.GANG_STARS[territory.starsOf(territory.DISTRICTS[0].id)].ai);
    assert.equal(territory.weekOf(new Date('2026-11-01T12:00:00Z')), '2026-10-26', 'a Sunday is the end of the week');
    assert.equal(territory.weekOf(new Date('2026-11-02T00:00:00Z')), '2026-11-02');
    assert.equal(await territory.record({ playerId: ann, district: 'nowhere', clan: 'nebula', mode: 'ranked', outcome: 'win' }), null);
    assert.equal(await territory.record({ playerId: ann, district: d1, clan: 'nebula', mode: 'cpu', outcome: 'loss' }), null, 'no influence, no row');

    const lastWeek = new Date('2026-10-28T10:00:00Z');   // (week of 2026-10-26)
    const now = new Date('2026-11-03T10:00:00Z');        // the next week
    const week = territory.weekOf(lastWeek);
    const gang = territory.locals(d1, week);
    assert.ok(gang.strength >= 3 && gang.strength <= 8 && gang.name.startsWith('The '));
    // d1: ann (Nebula) wins it from the locals; bob helps Militia but less
    let won = 0;
    while (won <= gang.strength) {
        const r = await territory.record({ playerId: ann, district: d1, clan: 'nebula', mode: 'ranked', outcome: 'win', at: lastWeek });
        assert.deepEqual(r, { district: d1, name: territory.DISTRICTS[0].name, clan: 'nebula', points: 3 });
        won += 3;
    }
    await territory.record({ playerId: bob, district: d1, clan: 'militia', mode: 'casual', outcome: 'loss', at: lastWeek });
    // d2: two clans tied above the locals: nobody holds it
    for (let i = 0; i < 4; i++) {
        await territory.record({ playerId: ann, district: d2, clan: 'nebula', mode: 'ranked', outcome: 'win', at: lastWeek });
        await territory.record({ playerId: bob, district: d2, clan: 'militia', mode: 'ranked', outcome: 'win', at: lastWeek });
    }
    // d3: bob fights for Nebula too, and is its boss with more influence
    for (let i = 0; i < 4; i++) await territory.record({ playerId: bob, district: d3, clan: 'nebula', mode: 'ranked', outcome: 'win', at: lastWeek });
    await territory.record({ playerId: ann, district: d3, clan: 'nebula', mode: 'cpu', outcome: 'win', difficulty: 'normal', at: lastWeek });
    const map = await territory.weekMap(week);
    const at = (id) => map.districts.find(d => d.id === id);
    assert.equal(at(d1).holder, 'nebula');
    assert.equal(at(d1).boss.username, 'ann');
    assert.equal(at(d2).holder, '', 'a tie keeps it nobody\'s');
    assert.equal(at(d3).holder, 'nebula');
    assert.equal(at(d3).boss.username, 'bob');
    assert.deepEqual(territory.payFrom(map, ann).districts.map(d => [d.id, d.boss]), [[d1, true], [d3, false]]);
    assert.equal(territory.payFrom(map, ann).karat, 2 * territory.KARAT.district + territory.KARAT.boss);
    assert.equal(territory.payFrom(map, bob).karat, territory.KARAT.district + territory.KARAT.boss, 'bob: d3 only (his Militia lost d1)');

    // This week's screen: last week's holders, and its Karat waiting
    const o = await territory.overview(ann, now);
    assert.equal(o.week, territory.weekOf(now));
    assert.equal(o.districts.find(d => d.id === d1).lastHolder, 'nebula');
    assert.equal(o.districts.find(d => d.id === d1).holder, '', 'a new week starts afresh');
    assert.equal(o.reward.karat, 2 * territory.KARAT.district + territory.KARAT.boss);
    // Claimed once
    const before = await karat(ann);
    const paid = await territory.claim(ann, now);
    assert.equal(paid.karat, o.reward.karat);
    assert.equal(await karat(ann), before + paid.karat);
    assert.equal((await territory.claim(ann, now)).karat, 0, 'only once');
    assert.equal((await territory.overview(ann, now)).reward, null);
    // A week still running pays nothing yet
    await territory.record({ playerId: ann, district: d1, clan: 'nebula', mode: 'ranked', outcome: 'win', at: now });
    assert.equal((await territory.claim(ann, now)).karat, 0);
    assert.deepEqual((await territory.overview(ann, now)).districts.find(d => d.id === d1).mine, { nebula: 3 });

    await pool.end();
    console.log('veterans and turf map: ok');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
