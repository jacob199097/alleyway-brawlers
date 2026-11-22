'use strict';

/**
 * Card mastery quests against a real Postgres (economy/veterans.js): a match's events counted for the card
 * whose attack they came in, the quests done in order earning each tier, and a tier earned by card XP before
 * the quests kept. Builds a scratch database like showcase.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/veterans.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_veterans_test';
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
    const q = (sql, params) => pool.query(sql, params);
    const vet = require('./veterans');
    const { CARD_CATALOG } = await import('../../shared/cards.js');

    // Every card has three quests, by what it is
    for (const card of Object.values(CARD_CATALOG)) {
        const quests = vet.KINDS[vet.questKind(card)];
        assert.ok(Array.isArray(quests) && quests.length === 3, `${card.id}: three quests`);
    }
    const brawler = Object.values(CARD_CATALOG).find(x => vet.questKind(x) === 'character');
    const striver = Object.values(CARD_CATALOG).find(x => vet.questKind(x) === 'striver');
    assert.ok(brawler && striver, 'cards of both kinds');

    // The tracker: a KO or Down counts for the attacking card, until the phase changes; effects for the card itself
    const t = vet.tracker();
    const evs = [
        { type: 'attack', side: 'player', card: { id: brawler.id } },
        { type: 'downed', side: 'opponent', card: { id: 'x' } },
        { type: 'ko', side: 'opponent', card: { id: 'x' } },
        { type: 'ko', side: 'player', card: { id: brawler.id } },   // (its own: not counted)
        { type: 'phase', phase: 'regroup', side: 'player' },
        { type: 'ko', side: 'opponent', card: { id: 'y' } },        // (after the attack: nobody's)
        { type: 'attack', side: 'opponent', card: { id: 'z' } },
        { type: 'ko', side: 'opponent', card: { id: 'y' } },        // (in their attack)
        { type: 'effect', side: 'player', card: { id: striver.id }, text: 'x: does a thing' },
        { type: 'effect', side: 'player', card: { id: striver.id }, text: `${striver.name}: not now` },
        { type: 'promote', side: 'player', from: { id: striver.id }, card: { id: 'next' } },
    ];
    for (const ev of evs) vet.track(t, ev, 'player');
    assert.deepEqual(t.cards[brawler.id], { downs: 1, kos: 1 });
    assert.deepEqual(t.cards[striver.id], { effects: 1, promotes: 1 });

    const p = (await q(`INSERT INTO players (username, email, password_hash) VALUES ('sam', 'sam@test.local', 'x') RETURNING id`)).rows[0].id;
    // A brawler's first quest: Down or KO 5 enemy characters with it (one match: 2, then 3 more)
    assert.deepEqual(await vet.record(p, [brawler.id, striver.id], true, t), []);
    const t2 = { cards: { [brawler.id]: { kos: 3 } } };
    const up = await vet.record(p, [brawler.id], false, t2);
    assert.deepEqual(up, [{ id: brawler.id, tier: 1, name: 'Seasoned' }], 'the first quest done: Seasoned');
    let all = await vet.tiers(p);
    assert.equal(all[brawler.id], 1);
    assert.equal(all[striver.id], undefined, 'one PROMOTE of 3: no tier yet');
    // The second quest (Win 8 matches with it played) comes before the third, however many KOs
    await vet.record(p, [brawler.id], false, { cards: { [brawler.id]: { kos: 30 } } });
    assert.equal((await vet.tiers(p))[brawler.id], 1, 'in order: the wins first');
    for (let i = 0; i < 7; i++) await vet.record(p, [brawler.id], true);
    assert.equal((await vet.tiers(p))[brawler.id], 3, '8 wins, and its KOs already there: Street Legend');
    const o = await vet.overview(p);
    assert.equal(o.cards[brawler.id].kos, 34);
    assert.equal(o.cards[brawler.id].wins, 8);
    assert.equal(o.cards[brawler.id].tier, 3);

    // A tier earned by card XP before the quests stays
    await q('UPDATE card_veterans SET legacy_tier = 2 WHERE player_id = $1 AND card_id = $2', [p, striver.id]);
    assert.equal((await vet.tiers(p, [striver.id]))[striver.id], 2);

    await pool.end();
    console.log('Veteran quests: OK');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
