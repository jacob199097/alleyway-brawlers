'use strict';

/**
 * Ranked seasons against a real Postgres (economy/seasons.js): Ranked games count and keep the season's
 * best Rank Points, casual ones don't; ending a season records each Ranked player's highest rank and
 * reward (none for those who didn't play Ranked), drops every rank back two, and starts the next season;
 * a reward is claimed once. Builds a scratch database like progression.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/economy/seasons.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_seasons_test';
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
    const { resolveMatch } = require('./postMatch');
    const seasons = require('./seasons');
    const { REWARDS } = require('./season_settings');

    assert.equal((await seasons.current()).id, 0, 'Season 0 is running');
    const player = async (name, points = 0) => (await q(
        `INSERT INTO players (username, email, password_hash, rank_points, season_peak_points) VALUES ($1, $2, 'x', $3, $3) RETURNING id`,
        [name, `${name}@x`, points])).rows[0].id;
    const legend = await player('legend', 2990);   // one Ranked win from Legend (3000)
    const rival = await player('rival', 1000);
    const casual = await player('casual', 600);
    const idle = await player('idle', 0);

    // A Ranked win takes "legend" to Legend; then losses drop it back below. A casual game doesn't count.
    await resolveMatch({ winnerId: legend, loserId: rival, p1Id: legend, p2Id: rival, matchMeta: { ranked: true } });
    for (let i = 0; i < 3; i++) await resolveMatch({ winnerId: rival, loserId: legend, p1Id: legend, p2Id: rival, matchMeta: { ranked: true } });
    await resolveMatch({ winnerId: casual, loserId: idle, p1Id: casual, p2Id: idle, matchMeta: { ranked: false } });
    const row = async (id) => (await q('SELECT rank_points, rank, season_ranked, season_peak_points FROM players WHERE id = $1', [id])).rows[0];
    let l = await row(legend);
    assert.equal(l.season_ranked, 4, 'four Ranked games counted');
    assert.equal(l.season_peak_points, 3015, 'the best Rank Points of the season are kept');
    assert.ok(l.rank_points < 3000, 'it has dropped below Legend since');
    assert.equal((await row(casual)).season_ranked, 0, 'a casual game is not a Ranked game');

    const st = await seasons.status(legend);
    assert.equal(st.me.peak_tier, 'legend', 'the game sees the highest rank reached');
    assert.equal(st.tiers.length, 6, 'every rank with its reward');

    // Looking first changes nothing
    const look = await seasons.endSeason({ name: 'Season 1', weeks: 13 }, false);
    assert.equal(look.players.find((t) => t.tier === 'legend').count, 1);
    assert.equal((await seasons.current()).id, 0, 'not ended by looking');

    const done = await seasons.endSeason({ name: 'Season 1', subtitle: 'Test', weeks: 13 }, true);
    assert.equal(done.next.id, 1);
    const now = await seasons.current();
    assert.equal(now.id, 1, 'Season 1 is running');
    assert.ok(now.ends_at > new Date(), 'with an end date');
    const ps = (await q('SELECT player_id, peak_tier, reward FROM player_seasons WHERE season = 0')).rows;
    assert.deepEqual(ps.map((r) => r.player_id).sort(), [legend, rival].sort(), 'only the players who played Ranked get a season record');
    assert.equal(ps.find((r) => r.player_id === legend).peak_tier, 'legend', 'by the highest rank reached, not the rank at the end');
    // Every rank dropped back two (Underboss 1000 → Street Tough 200; Kingpin and below to their floor)
    const rv = await row(rival);
    assert.equal(rv.rank_points, 200, 'Underboss drops back to Street Tough');
    assert.equal(rv.season_ranked, 0, 'the counts start again');
    assert.equal((await row(casual)).rank_points, 0, 'Enforcer drops back to Rookie');
    assert.equal(seasons.softReset(3500), 1000, 'Legend drops back to Underboss');

    // Claimed once, paid once
    const before = (await q('SELECT karat, free_packs FROM players WHERE id = $1', [legend])).rows[0];
    assert.equal((await seasons.unclaimed(legend)).length, 1, 'the reward waits to be claimed');
    const got = await seasons.claim(legend, 0);
    assert.equal(got.reward.karat, REWARDS.legend.karat);
    assert.equal(got.karat, before.karat + REWARDS.legend.karat, 'the Karat is paid');
    assert.equal(got.free_packs, before.free_packs + REWARDS.legend.free_packs, 'the packs are given');
    assert.equal(await seasons.claim(legend, 0), null, 'not twice');
    assert.equal((await seasons.unclaimed(legend)).length, 0);
    assert.equal(await seasons.claim(idle, 0), null, 'nothing for a player who did not play Ranked');

    await pool.end();
    console.log('seasons: ok');
})().catch(async (err) => {
    console.error(err);
    // (also as a GitHub annotation, which the Actions API shows without signing in)
    if (process.env.GITHUB_ACTIONS) console.log('::error title=seasons test::' + String(err && err.stack || err).slice(0, 900).replace(/%/g, '%25').replace(/\r?\n/g, '%0A'));
    process.exit(1);
});
