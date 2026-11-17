'use strict';

/**
 * The profile showcase against a real Postgres (economy/showcase.js): up to three different cards the player
 * owns, kept in order, and a card no longer owned dropping out when it's read. Builds a scratch database like
 * animated.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/showcase.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_showcase_test';
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
    const showcase = require('./showcase');

    const clan = (await q('SELECT unnest(enum_range(NULL::pack_type))::text AS c LIMIT 1')).rows[0].c;
    const ids = ['card_t_001', 'card_t_002', 'card_t_003', 'card_t_004'];
    const uuid = {};
    for (const id of ids) {
        uuid[id] = (await q(`INSERT INTO cards (name, clan, card_type, rarity, art_url, authority, attack, defense)
            VALUES ($1, $2, 'gang_member', 1, $1, 1, 0, 0) RETURNING id`, [id, clan])).rows[0].id;
    }
    const p = (await q(`INSERT INTO players (username, email, password_hash) VALUES ('sam', 'sam@test.local', 'x') RETURNING id`)).rows[0].id;
    for (const id of ids.slice(0, 3)) await q('INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)', [p, uuid[id]]);

    assert.deepEqual(await showcase.get(p), [], 'nothing picked yet');
    assert.deepEqual(await showcase.set(p, [ids[2], ids[0]]), [ids[2], ids[0]]);
    assert.deepEqual(await showcase.get(p), [ids[2], ids[0]], 'kept in the order picked');
    await assert.rejects(showcase.set(p, [ids[3]]), /only show cards you own/, 'a card they do not own');
    await assert.rejects(showcase.set(p, [ids[0], ids[0]]), /once/, 'the same card twice');
    await assert.rejects(showcase.set(p, ids), /up to 3/, 'four cards');
    await assert.rejects(showcase.set(p, ['DROP TABLE']), /Unknown card/);
    await assert.rejects(showcase.set(p, 'card_t_001'), /up to 3/, 'not a list');
    assert.deepEqual(await showcase.set(p, []), [], 'emptied');
    await showcase.set(p, [ids[0], ids[1], ids[2]]);
    await q('DELETE FROM player_inventory WHERE player_id = $1 AND card_id = $2', [p, uuid[ids[1]]]);   // (sold or scrapped)
    assert.deepEqual(await showcase.get(p), [ids[0], ids[2]], 'a card no longer owned drops out');

    await pool.end();
    console.log('Showcase: OK');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
