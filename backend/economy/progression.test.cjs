'use strict';

/**
 * Crafting and achievements against a real Postgres. It builds a scratch database from
 * db/schema.sql + db/seed_cards.sql + db/migrate.js, so point it at a server where it may do that:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/progression.test.cjs
 *
 * The scratch database is DB_NAME (default turf_war_test); it is dropped and made again each run.
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
    await c.query(fs.readFileSync(path.join(DB, 'seed_cards.sql'), 'utf8'));
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
    const crafting = require('./crafting');
    const achievements = require('./achievements');

    const q = (sql, params) => pool.query(sql, params);
    const { rows: [me] } = await q(`INSERT INTO players (username, email, password_hash) VALUES ('tester', 't@x', 'x') RETURNING id`);
    const id = me.id;
    const cardId = async (gameId) => (await q('SELECT id FROM cards WHERE art_url = $1', [gameId])).rows[0].id;
    const give = async (gameId, n) => q(
        `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, $3)
         ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = $3`, [id, await cardId(gameId), n]);
    const owned = async (gameId) => (await q(
        'SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2', [id, await cardId(gameId)])).rows[0]?.quantity || 0;
    const { rows: [{ rarity: mayaRarity }] } = await q(`SELECT rarity FROM cards WHERE art_url = 'maya_lv1'`);
    const value = crafting.VALUES[mayaRarity];

    // ── Crafting ──
    await give('maya_lv1', 5);   // 2 extras
    await give('king_roan', 2);  // a leader: 1 extra
    let s = await crafting.summary(id);
    assert.equal(s.dust, 0);
    assert.equal(s.extras, 3);

    // A deck using 3 Mayas protects them
    const { rows: [deck] } = await q(`INSERT INTO decks (player_id, name) VALUES ($1, 'd') RETURNING id`, [id]);
    await q('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, 3)', [deck.id, await cardId('maya_lv1')]);
    await rejects(crafting.scrap(id, 'maya_lv1', 3), /decks use 3/);
    let r = await crafting.scrap(id, 'maya_lv1', 1);
    assert.equal(r.quantity, 4);
    assert.equal(r.gained, value.scrap);
    await rejects(crafting.scrap(id, 'hunter_lv1'), /don't own/);

    r = await crafting.scrapExtras(id);
    assert.equal(await owned('maya_lv1'), 3);
    assert.equal(await owned('king_roan'), 1);
    assert.equal(r.scrapped, 2);
    s = await crafting.summary(id);
    assert.equal(s.extras, 0);
    assert.equal(s.dust, r.dust);

    // Crafting costs Dust, stops at 3 copies and only makes cards that are in the game
    await rejects(crafting.craft(id, 'hunter_lv1'), /need \d+ Dust/);
    await q('UPDATE players SET dust = 10000 WHERE id = $1', [id]);
    r = await crafting.craft(id, 'hunter_lv1');
    assert.equal(r.quantity, 1);
    assert.equal(await owned('hunter_lv1'), 1);
    await rejects(crafting.craft(id, 'maya_lv1'), /all a deck can use/);
    await rejects(crafting.craft(id, 'king_roan'), /all a deck can use/);
    await rejects(crafting.craft(id, 'not_a_card'), /can't be crafted/);
    const dustBefore = (await crafting.summary(id)).dust;
    await rejects(crafting.craft(id, 'maya_lv1'), /all a deck can use/);
    assert.equal((await crafting.summary(id)).dust, dustBefore, 'a refused craft costs nothing');

    // ── Achievements ──
    let fresh = await achievements.check(id);
    assert.ok(fresh.some(a => a.id === 'craft_1'), 'Craftsman unlocks after crafting');
    assert.equal((await achievements.check(id)).length, 0, 'nothing unlocks twice');

    const karat0 = (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;
    await q('UPDATE players SET wins = 1 WHERE id = $1', [id]);   // resolveMatch counts the win
    fresh = await achievements.recordMatch({ playerId: id, outcome: 'win', mode: 'cpu', difficulty: 'hard',
        clan: 'lion_pride', kos: 5, promotes: 1, awakens: 1, morale: 6000 });
    const got = fresh.map(a => a.id).sort();
    assert.deepEqual(got, ['awaken', 'first_win', 'flawless', 'hard_cpu', 'rampage'].sort());
    const karat1 = (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;
    assert.equal(karat1 - karat0, 100 + 150 + 200, 'First Blood, Awakening and Machine Breaker pay Karat');

    // Cosmetics: only what's unlocked can be worn
    assert.deepEqual(await achievements.equip(id, { title: 'flawless' }), { ok: true });
    assert.ok((await achievements.equip(id, { title: 'wins_100' })).error);
    assert.ok((await achievements.equip(id, { back: 'lion_pride' })).error);
    assert.ok((await achievements.equip(id, { avatar: 'clan:lion_pride' })).error);
    assert.ok((await achievements.equip(id, { avatar: 'card:maya_lv1' })).error, 'portraits come with Collector');
    for (let i = 0; i < 9; i++) {
        await achievements.recordMatch({ playerId: id, outcome: 'win', mode: 'casual', clan: 'lion_pride', morale: 3000 });
    }
    const ov = await achievements.overview(id);
    const loyal = ov.achievements.find(a => a.id === 'clan_lion_pride_10');
    assert.ok(loyal && loyal.unlocked, 'Lion Pride Loyalist unlocks after 10 Lion Pride wins');
    assert.equal(ov.achievements.find(a => a.id === 'online_25').progress, 9);
    assert.ok(ov.cosmetics.backs.includes('lion_pride'));
    assert.deepEqual(await achievements.equip(id, { back: 'lion_pride', avatar: 'clan:lion_pride' }), { ok: true });
    assert.deepEqual(await achievements.equip(id, { title: null, back: null }), { ok: true });
    assert.equal(ov.equipped.title, 'flawless');
    assert.equal(await achievements.titleText('flawless'), 'Untouchable');

    // Collector unlocks portraits of owned cards
    await q(`INSERT INTO player_inventory (player_id, card_id, quantity)
             SELECT $1, id, 1 FROM cards ON CONFLICT DO NOTHING`, [id]);
    await achievements.check(id);
    const coll = (await achievements.overview(id)).achievements.find(a => a.id === 'collect_25');
    assert.equal(coll.unlocked, (await q('SELECT COUNT(*)::int AS n FROM cards')).rows[0].n >= 25);
    if (coll.unlocked) assert.deepEqual(await achievements.equip(id, { avatar: 'card:maya_lv1' }), { ok: true });

    // CPU seats never record anything
    assert.deepEqual(await achievements.recordMatch({ playerId: 'cpu:x', outcome: 'win' }), []);

    await pool.end();
    console.log('all good');
})().catch(async (err) => {
    console.error(err);
    process.exit(1);
});
