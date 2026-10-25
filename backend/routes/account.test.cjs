'use strict';

/**
 * Account deletion (routes/account.js) against a real Postgres: everything of the player's goes,
 * the other player's things stay, and their shared match keeps the other side. Builds a scratch
 * database like economy/progression.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/routes/account.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_account_test';
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
    await c.end();

    const { pool } = require('../db/pool');
    const { migrate } = require('../db/migrate');
    await migrate(pool);
    await migrate(pool);   // running it again changes nothing
    const q = (sql, params) => pool.query(sql, params);
    const count = async (sql, params) => Number((await q(sql, params)).rows[0].n);

    const player = async (name) => (await q(
        `INSERT INTO players (username, email, password_hash) VALUES ($1, $2, 'x') RETURNING id`, [name, name + '@x'])).rows[0].id;
    const gone = await player('leaving');
    const stays = await player('staying');

    // Things of both players', and things they share
    for (const id of [gone, stays]) {
        await q(`INSERT INTO decks (player_id, name) VALUES ($1, 'Deck')`, [id]);
        await q(`INSERT INTO player_mail (player_id, subject, body) VALUES ($1, 'Hi', 'Hello')`, [id]);
    }
    await q(`INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1, $2, 'accepted')`, [gone, stays]);
    await q(`INSERT INTO messages (sender_id, receiver_id, body) VALUES ($1, $2, 'gg')`, [gone, stays]);
    await q(`INSERT INTO matches (player_one_id, player_two_id, winner_id, turns) VALUES ($1, $2, $1, 9)`, [gone, stays]);
    await q(`INSERT INTO payment_grants (payment_intent_id, player_id, bundle_id, contraband) VALUES ('pi_1', $1, 'b', 100)`, [gone]);
    await q(`CREATE TABLE IF NOT EXISTS match_replays (id UUID PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        mode TEXT NOT NULL, p1 TEXT NOT NULL, p2 TEXT NOT NULL, data JSONB NOT NULL)`);
    await q(`INSERT INTO match_replays (id, mode, p1, p2, data) VALUES (uuid_generate_v4(), 'online', $1, $2, '{}'),
        (uuid_generate_v4(), 'cpu', $2, 'cpu:x', '{}')`, [gone, stays]);
    await q(`CREATE TABLE IF NOT EXISTS client_errors (id BIGSERIAL PRIMARY KEY, player_id TEXT, message TEXT)`);
    await q(`INSERT INTO client_errors (player_id, message) VALUES ($1, 'oops'), ($2, 'oops')`, [gone, stays]);

    const { deleteAccount } = require('./account');
    assert.equal(await deleteAccount(gone), true);
    assert.equal(await deleteAccount(gone), false);   // (already gone)

    // Everything of theirs is gone
    assert.equal(await count('SELECT COUNT(*) AS n FROM players WHERE id = $1', [gone]), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM decks WHERE player_id = $1', [gone]), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM player_mail WHERE player_id = $1', [gone]), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM friendships'), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM messages'), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM match_replays WHERE p1 = $1 OR p2 = $1', [gone]), 0);
    assert.equal(await count('SELECT COUNT(*) AS n FROM client_errors WHERE player_id = $1', [gone]), 0);
    // The other player keeps theirs, and the shared match without the deleted side
    assert.equal(await count('SELECT COUNT(*) AS n FROM decks WHERE player_id = $1', [stays]), 1);
    assert.equal(await count('SELECT COUNT(*) AS n FROM player_mail WHERE player_id = $1', [stays]), 1);
    assert.equal(await count('SELECT COUNT(*) AS n FROM match_replays WHERE p1 = $1', [stays]), 1);
    assert.equal(await count('SELECT COUNT(*) AS n FROM client_errors WHERE player_id = $1', [stays]), 1);
    const { rows: [m] } = await q('SELECT player_one_id, player_two_id, winner_id, turns FROM matches');
    assert.deepEqual([m.player_one_id, m.player_two_id, m.winner_id, m.turns], [null, stays, null, 9]);
    // The payment stays marked as used, so it can't be claimed again
    const { rows: [pay] } = await q(`SELECT player_id FROM payment_grants WHERE payment_intent_id = 'pi_1'`);
    assert.equal(pay.player_id, null);

    await pool.end();
    console.log('Account deletion: ok');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
