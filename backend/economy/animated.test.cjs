'use strict';

/**
 * Animated cards against a real Postgres (economy/animated.js): which cards have an animated version and
 * at what price, crafting one for Dust (needs a copy of the card), buying one for Contraband (gives a copy
 * if none), never twice, never without the price, and a match's deck only reporting the ones owned.
 * Builds a scratch database like contracts.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/animated.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_animated_test';
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
    const animated = require('./animated');
    const { VALUES } = require('./crafting');
    const { CARD_CATALOG } = await import('../../shared/cards.js');

    // Two animatable cards and one that isn't, as rows the server knows
    const able = await animated.animatable();
    const ids = Object.keys(able);
    assert.ok(ids.length >= 2, 'some cards have an animated version (their artFx)');
    // (every card has one but tokens, which are never owned)
    const plain = Object.keys(CARD_CATALOG).find(id => !CARD_CATALOG[id].artFx || CARD_CATALOG[id].token);
    // (any clan the fresh schema knows: sync_cards.mjs adds the rest, and the clan doesn't matter here)
    const clan = (await q('SELECT unnest(enum_range(NULL::pack_type))::text AS c LIMIT 1')).rows[0].c;
    for (const id of [ids[0], ids[1], plain]) {
        const k = CARD_CATALOG[id];
        await q(`INSERT INTO cards (name, clan, card_type, rarity, art_url, authority, attack, defense) VALUES ($1, $2, $3, $4, $5, 1, 0, 0)`,
            [k.name, clan, k.cardType, k.rarity, id]);
    }
    const cardUuid = async (id) => (await q('SELECT id FROM cards WHERE art_url = $1', [id])).rows[0].id;
    const player = async (name, dust, cb) => (await q(
        `INSERT INTO players (username, email, password_hash, dust, contraband) VALUES ($1, $2, 'x', $3, $4) RETURNING id`,
        [name, `${name}@test.local`, dust, cb])).rows[0].id;
    const wallet = async (id) => (await q('SELECT dust, contraband FROM players WHERE id = $1', [id])).rows[0];

    // Prices: four times the card's craft cost in Dust; Contraband by rarity
    const r0 = able[ids[0]];
    assert.deepEqual(animated.pricesOf(r0), { dust: VALUES[r0].craft * animated.CRAFT_FACTOR, contraband: animated.CONTRABAND[r0] });

    // Crafting needs the card, and the Dust
    const a = await player('anna', 100000, 0);
    await assert.rejects(animated.acquire(a, ids[0], 'dust'), /Craft or find/, 'crafting needs a copy of the card');
    await q('INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 2)', [a, await cardUuid(ids[0])]);
    const made = await animated.acquire(a, ids[0], 'dust');
    assert.equal(made.spent, animated.pricesOf(r0).dust);
    assert.equal(made.gaveCard, false);
    assert.equal(Number((await wallet(a)).dust), 100000 - made.spent, 'the Dust is paid');
    await assert.rejects(animated.acquire(a, ids[0], 'dust'), /already have/, 'never twice');
    await assert.rejects(animated.acquire(a, ids[0], 'contraband'), /already have/, 'nor bought after crafting');
    await assert.rejects(animated.acquire(a, plain, 'dust'), /no animated version/, 'a token (or a card without artFx)');
    await assert.rejects(animated.acquire(a, 'nope', 'dust'), /no animated version/);

    // The shop's rotation: FEATURED a day, the same all day, different another day
    const today = animated.featured(ids);
    assert.equal(today.length, Math.min(animated.FEATURED, ids.length));
    assert.deepEqual(animated.featured(ids), today, 'the same all day');
    assert.notDeepEqual(animated.featured(ids, 1000), animated.featured(ids, 1001), 'another day, other cards');
    // Buying needs the Contraband, and gives the card if the player has none; only today's featured ones
    const offShop = ids.find(id => !today.includes(id) && id !== ids[0]);
    const onShop = today.find(id => id !== ids[0]);
    for (const id of [offShop, onShop]) {
        if (!(await q('SELECT 1 FROM cards WHERE art_url = $1', [id])).rows.length) {
            const k = CARD_CATALOG[id];
            await q(`INSERT INTO cards (name, clan, card_type, rarity, art_url, authority, attack, defense) VALUES ($1, $2, $3, $4, $5, 1, 0, 0)`,
                [k.name, clan, k.cardType, k.rarity, id]);
        }
    }
    const b = await player('ben', 0, 10);
    await assert.rejects(animated.acquire(b, onShop, 'contraband'), /You need/, 'not without the Contraband');
    await q('UPDATE players SET contraband = 5000 WHERE id = $1', [b]);
    await assert.rejects(animated.acquire(b, offShop, 'contraband'), /isn't in the shop today/, "not one that isn't in today's shop");
    const bought = await animated.acquire(b, onShop, 'contraband');
    assert.equal(bought.gaveCard, true, 'a copy of the card comes with it');
    assert.equal(Number((await q('SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2', [b, await cardUuid(onShop)])).rows[0].quantity), 1);
    assert.equal(Number((await wallet(b)).contraband), 5000 - bought.spent);

    // What a match's deck reports, and the overview
    assert.deepEqual(await animated.owned(a, [ids[0], ids[1], plain]), [ids[0]], 'only the deck cards they own animated');
    const ov = await animated.overview(b);
    assert.equal(ov.cards.find(x => x.id === onShop).owned, true);
    assert.equal(ov.cards.filter(x => x.featured).length, today.length, "today's featured ones are marked");
    assert.equal(ov.cards.find(x => x.id === ids[0]).owned, false);
    assert.ok(!ov.cards.some(x => x.id === plain));

    // Deleting the account takes them too
    await q('DELETE FROM players WHERE id = $1', [b]);
    assert.equal(Number((await q('SELECT COUNT(*) AS n FROM animated_cards WHERE player_id = $1', [b])).rows[0].n), 0);

    await pool.end();
    console.log('animated cards: ok');
})().catch((err) => { console.error(err); process.exit(1); });
