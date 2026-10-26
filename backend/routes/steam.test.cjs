'use strict';

/**
 * Steam sign-in, linking and purchases (routes/steam.js) against a real Postgres, with Steam's own
 * Web API stood in for (no network): a Steam account with no player is told so, then gets one named
 * after its Steam name; signing in again finds it; an email player links Steam; one Steam account
 * can't be linked twice; a Steam wallet purchase is granted once; a Steam-only account can be
 * deleted with "DELETE". Builds a scratch database like economy/progression.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/routes/steam.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_steam_test';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-steam';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const http = require('http');
const express = require('express');
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

    // Steam stand-ins: a ticket "aa..." is Steam account 7656119800000000N
    const steam = require('./steam');
    const charged = [];
    steam.useSteam({
        verifyTicket: async (t) => {
            if (!/^a{16}\d$/.test(String(t))) throw new (require('../utils/steam').SteamError)("Steam didn't accept the ticket.", 401);
            return `7656119800000000${String(t).slice(-1)}`;
        },
        personaName: async (id) => (id.endsWith('1') ? 'Jac0M0f0' : ''),
        initTxn: async () => ({ transId: 't1' }),
        finalizeTxn: async (orderId) => { charged.push(orderId); return { transId: 't1' }; },
    });
    const app = express();
    app.use(express.json());
    app.use('/api/steam', steam);
    app.use('/api/account', require('./account'));
    const server = http.createServer(app).listen(0);
    const port = server.address().port;
    const call = (method, url, body, token) => new Promise((resolve) => {
        const req = http.request({ port, path: url, method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) } }, (r) => {
            let d = '';
            r.on('data', (x) => (d += x));
            r.on('end', () => resolve({ status: r.statusCode, body: d ? JSON.parse(d) : {} }));
        });
        req.end(body ? JSON.stringify(body) : undefined);
    });
    const q = (sql, params) => pool.query(sql, params);

    // A Steam account with no player yet: told so, then made one
    let r = await call('POST', '/api/steam/login', { ticket: 'aaaaaaaaaaaaaaaa1' });
    assert.equal(r.status, 404);
    assert.equal(r.body.code, 'no_account');
    r = await call('POST', '/api/steam/login', { ticket: 'bad' });
    assert.equal(r.status, 401, 'a bad ticket is refused');
    r = await call('POST', '/api/steam/login', { ticket: 'aaaaaaaaaaaaaaaa1', create: true });
    assert.equal(r.status, 201);
    assert.ok(r.body.token && r.body.created);
    assert.equal(r.body.player.username, 'Jac0M0f0', 'named after the Steam name');
    assert.equal(r.body.player.karat, 500);
    const steamToken = r.body.token;
    // Signing in again finds the same player
    r = await call('POST', '/api/steam/login', { ticket: 'aaaaaaaaaaaaaaaa1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.created, false);
    // A second Steam account whose name is taken / empty: a free name
    await q(`INSERT INTO players (username, email, password_hash, email_verified) VALUES ('Brawler', 'b@x', 'x', true)`);
    r = await call('POST', '/api/steam/login', { ticket: 'aaaaaaaaaaaaaaaa2', create: true });
    assert.equal(r.status, 201);
    assert.ok(/^Brawler\d{4}$/.test(r.body.player.username), `a free name (${r.body.player.username})`);

    // An email player links Steam account 3; account 1 is someone else's already
    const jwt = require('jsonwebtoken');
    const { rows: [mail] } = await q(`INSERT INTO players (username, email, password_hash, email_verified) VALUES ('Mailer', 'm@x', 'x', true) RETURNING id`);
    const mailToken = jwt.sign({ sub: mail.id, username: 'Mailer' }, process.env.JWT_SECRET);
    r = await call('POST', '/api/steam/link', { ticket: 'aaaaaaaaaaaaaaaa1' }, mailToken);
    assert.equal(r.status, 409, "someone else's Steam account");
    r = await call('POST', '/api/steam/link', { ticket: 'aaaaaaaaaaaaaaaa3' }, mailToken);
    assert.equal(r.status, 200);
    r = await call('POST', '/api/steam/login', { ticket: 'aaaaaaaaaaaaaaaa3' });
    assert.equal(r.body.player.username, 'Mailer', 'now Steam signs them in');

    // A Steam wallet purchase: granted once
    r = await call('POST', '/api/steam/purchase/init', { bundleId: 'cb_1200' }, steamToken);
    assert.equal(r.status, 200);
    const orderId = r.body.orderId;
    r = await call('POST', '/api/steam/purchase/finalize', { orderId }, mailToken);
    assert.equal(r.status, 404, "not someone else's order");
    r = await call('POST', '/api/steam/purchase/finalize', { orderId }, steamToken);
    assert.equal(r.status, 200);
    assert.equal(r.body.contrabandGranted, 1200);
    assert.equal(r.body.newContraband, 1200);
    r = await call('POST', '/api/steam/purchase/finalize', { orderId }, steamToken);
    assert.equal(r.status, 409, 'not twice');
    assert.deepEqual(charged, [orderId], 'charged once');
    r = await call('POST', '/api/steam/purchase/init', { bundleId: 'cb_500' }, mailToken);
    assert.equal(r.status, 200, 'a linked email player can buy too');
    const { rows: [{ count }] } = await q('SELECT count(*)::int AS count FROM payment_grants');
    assert.equal(count, 1);

    // Deleting a Steam-only account: "DELETE", no password
    r = await call('POST', '/api/account/delete', { confirm: 'nope' }, steamToken);
    assert.equal(r.status, 400);
    r = await call('POST', '/api/account/delete', { confirm: 'DELETE' }, mailToken);
    assert.equal(r.status, 400, 'a player with a password still needs it');
    r = await call('POST', '/api/account/delete', { confirm: 'DELETE' }, steamToken);
    assert.equal(r.status, 200);
    const { rows: gone } = await q(`SELECT 1 FROM players WHERE username = 'Jac0M0f0'`);
    assert.equal(gone.length, 0);

    server.close();
    await pool.end();
    console.log('steam: ok');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
