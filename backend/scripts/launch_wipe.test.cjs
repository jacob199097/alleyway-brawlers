'use strict';

/**
 * The launch wipe (scripts/launch_wipe.js) against a real Postgres: a dry run changes nothing, --apply is
 * refused until the season has ended, the starters are off and bought Contraband has an answer; then
 * every account starts again with its clan's starter and the kept things are still there. Builds a
 * scratch database like economy/auction.test.cjs:
 *
 *   DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=... node backend/scripts/launch_wipe.test.cjs
 */

process.env.DB_NAME = process.env.DB_NAME || 'turf_war_wipe_test';
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
    require('child_process').execFileSync(process.execPath, [path.join(__dirname, 'sync_cards.mjs')], { stdio: 'inherit' });
    const { run, START_KARAT } = require('./launch_wipe');
    const onboarding = require('../routes/onboarding');
    const { pickableClans, starterRecipe, freeAvatars } = await import('../../shared/clans.js');
    const [clanA, clanB] = pickableClans();

    const q = (sql, params) => pool.query(sql, params);
    const count = async (sql, params) => Number((await q(sql, params)).rows[0].n);
    const rows = async (table) => count(`SELECT COUNT(*) AS n FROM ${table}`);
    const one = async (id) => (await q('SELECT * FROM players WHERE id = $1', [id])).rows[0];
    const player = async (name, clan, avatar) => (await q(
        `INSERT INTO players (username, email, password_hash, chosen_clan, avatar_url, profile_bio, steam_id,
                karat, contraband, dust, free_packs, level, xp, rank, rank_points, season_ranked, season_peak_points,
                wins, losses, draws, first_win_date, daily_streak, daily_claimed_on, title, card_back)
         VALUES ($1, $2, 'hash', $3, $4, 'my bio', $5, 9000, 700, 80, 3, 14, 250, 'enforcer', 340, 12, 400,
                30, 20, 1, CURRENT_DATE, 6, CURRENT_DATE, 'first_blood', 'back_gold') RETURNING id`,
        [name, name + '@x', clan, avatar, 'steam-' + name])).rows[0].id;

    // Four accounts: two with a clan, one that never picked, one whose clan can't be picked any more
    const free = freeAvatars()[0];
    const ana = await player('ana', clanA.id, free);                       // a picture everyone has
    const ben = await player('ben', clanB.id, `clan:${clanB.id}`);         // a picture from an achievement
    const cat = await player('cat', null, 'card:gift');                    // a picture given by hand
    const dan = await player('dan', 'a_clan_long_gone', 'level:10');       // a picture from a level
    await q(`INSERT INTO player_avatar_gifts (player_id, avatar) VALUES ($1, 'card:gift')`, [cat]);

    // Progress of every kind
    const { rows: someCards } = await q(`SELECT id, art_url, rarity FROM cards WHERE card_type <> 'leader' ORDER BY art_url LIMIT 5`);
    for (const id of [ana, ben, cat, dan]) {
        for (const card of someCards) {
            await q('INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 3)', [id, card.id]);
        }
        const { rows: [deck] } = await q(`INSERT INTO decks (player_id, name, is_active) VALUES ($1, 'My best deck', TRUE) RETURNING id`, [id]);
        await q('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, 3)', [deck.id, someCards[0].id]);
        await q('INSERT INTO deck_hideout (deck_id, card_id, copies) VALUES ($1, $2, 1)', [deck.id, someCards[1].id]);
        await q(`INSERT INTO player_mail (player_id, subject, body) VALUES ($1, 'Old news', 'From before the launch')`, [id]);
        await q(`INSERT INTO player_packs (player_id, pack_type, quantity) VALUES ($1, (enum_range(NULL::pack_type))[1], 2)`, [id]);
        await q(`INSERT INTO player_daily_quests (player_id, quest_id, progress) VALUES ($1, 'win_3', 2)`, [id]);
        await q(`INSERT INTO player_quest_claims (player_id, quest_id) VALUES ($1, 'first_win')`, [id]);
        await q(`INSERT INTO player_counters (player_id, key, value) VALUES ($1, 'kos', 40)`, [id]);
        await q(`INSERT INTO player_achievements (player_id, achievement_id) VALUES ($1, 'first_blood')`, [id]);
        await q(`INSERT INTO clan_mastery (player_id, clan, xp, games, wins) VALUES ($1, $2, 500, 9, 5)`, [id, clanA.id]);
        await q(`INSERT INTO weekly_challenge_wins (player_id, week) VALUES ($1, 7)`, [id]);
        await q(`INSERT INTO card_veterans (player_id, card_id, wins, plays) VALUES ($1, $2, 30, 60)`, [id, someCards[0].art_url]);
        await q(`INSERT INTO territory_influence (week, district, clan, player_id, points) VALUES (CURRENT_DATE, 'alley', $2, $1, 12)`, [id, clanA.id]);
        await q(`INSERT INTO territory_claims (player_id, week, karat) VALUES ($1, CURRENT_DATE, 50)`, [id]);
        await q(`INSERT INTO boss_clears (player_id, boss_id, level, clears, attempts) VALUES ($1, 'boss', 1, 1, 2)`, [id]);
        await q(`INSERT INTO solo_matches (player_id, outcome) VALUES ($1, 'win')`, [id]);
        await q(`INSERT INTO player_starter_grants (player_id, clan) VALUES ($1, 'every_clan')`, [id]);
    }
    await q(`INSERT INTO matches (player_one_id, player_two_id, winner_id, turns) VALUES ($1, $2, $1, 9)`, [ana, ben]);
    const { rows: [sale] } = await q(
        `INSERT INTO auctions (seller_id, card_id, rarity, start_price, high_bid, high_bidder, bids, ends_at)
         VALUES ($1, $2, $3, 100, 120, $4, 1, NOW() + INTERVAL '1 day') RETURNING id`, [ana, someCards[0].id, someCards[0].rarity, ben]);
    await q('INSERT INTO auction_bids (auction_id, bidder_id, amount) VALUES ($1, $2, 120)', [sale.id, ben]);
    await q(`CREATE TABLE IF NOT EXISTS match_replays (id UUID PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        mode TEXT NOT NULL, p1 TEXT NOT NULL, p2 TEXT NOT NULL, data JSONB NOT NULL)`);
    await q(`INSERT INTO match_replays (id, mode, p1, p2, data) VALUES (uuid_generate_v4(), 'online', $1, $2, '{}')`, [ana, ben]);
    // Things that stay
    await q(`INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1, $2, 'accepted')`, [ana, ben]);
    await q(`INSERT INTO messages (sender_id, receiver_id, body) VALUES ($1, $2, 'gg')`, [ana, ben]);
    await q(`INSERT INTO match_stats (id, mode, data) VALUES (uuid_generate_v4(), 'online', '{}')`);
    await q(`INSERT INTO player_seasons (player_id, season, ranked_games, peak_points, peak_tier, final_points)
             VALUES ($1, 0, 12, 400, 'enforcer', 340)`, [ben]);
    // Ben bought Contraband twice and was given some by the developer switch (that one never counts)
    await q(`INSERT INTO payment_grants (payment_intent_id, player_id, bundle_id, contraband) VALUES
             ('pi_real', $1, 'cb_500', 500), ('steam:41', $1, 'cb_1200', 1200), ('dev_abc', $1, 'cb_7000', 7000)`, [ben]);

    const snapshot = async () => {
        const out = {};
        for (const t of ['players', 'decks', 'player_inventory', 'player_mail', 'auctions', 'auction_bids', 'matches',
            'player_achievements', 'card_veterans', 'boss_clears', 'match_replays', 'friendships', 'payment_grants']) out[t] = await rows(t);
        out.ana = await one(ana);
        return out;
    };
    const before = await snapshot();

    // ── A dry run: what it would do and why it can't yet, and nothing changes ──
    let r = await run(pool, {});
    assert.equal(r.applied, false);
    assert.equal(r.problems.length, 3, r.problems.join(' | '));
    assert.match(r.problems[0], /No season has been ended/);
    assert.match(r.problems[1], /GIVE_ALL_STARTERS/);
    assert.match(r.problems[2], /2 Contraband purchases on record \(1 through Steam, 1 by card\) from 1 accounts, 1700 Contraband/);
    assert.ok(r.lines.some(l => /4 accounts, all kept/.test(l)), r.lines.join('\n'));
    assert.ok(r.lines.some(l => /\b4 decks\b/.test(l)), r.lines.join('\n'));
    assert.deepEqual(await snapshot(), before, 'a dry run changes nothing');

    // ── --apply with those problems: refused, nothing changes ──
    r = await run(pool, { apply: true });
    assert.equal(r.applied, false);
    assert.deepEqual(await snapshot(), before, 'a refused wipe changes nothing');

    // ── A table the wipe has never heard of stops it ──
    await q('CREATE TABLE brand_new_progress (id INT)');
    await assert.rejects(run(pool, { apply: true }), /doesn't know these tables: brand_new_progress/);
    await q('DROP TABLE brand_new_progress');
    assert.deepEqual(await snapshot(), before);

    // ── The season ended, the starters off, bought Contraband kept: it goes ahead ──
    await q('UPDATE seasons SET ended_at = NOW() WHERE id = 0');
    onboarding.GIVE_ALL_STARTERS = false;
    r = await run(pool, { apply: true, bought: 'nonsense' });
    assert.equal(r.applied, false, 'an answer that is neither keep nor drop is no answer');
    r = await run(pool, { apply: true, bought: 'keep' });
    assert.deepEqual(r.problems, []);
    assert.equal(r.applied, true);
    assert.ok(r.lines.some(l => /1 season rewards still to claim, kept/.test(l)), r.lines.join('\n'));

    // Everything that is progress is gone
    for (const t of ['auctions', 'auction_bids', 'player_packs', 'player_daily_quests', 'player_quest_claims', 'player_counters',
        'player_achievements', 'clan_mastery', 'weekly_challenge_wins', 'card_veterans', 'territory_influence',
        'territory_claims', 'boss_clears', 'matches', 'solo_matches', 'match_replays']) {
        assert.equal(await rows(t), 0, `${t} is cleared`);
    }
    // What stays
    assert.equal(await rows('players'), 4);
    assert.equal(await rows('friendships'), 1);
    assert.equal(await rows('messages'), 1);
    assert.equal(await rows('match_stats'), 1);
    assert.equal(await rows('player_seasons'), 1);
    assert.equal(await rows('payment_grants'), 3);
    assert.equal(await rows('player_avatar_gifts'), 1);
    assert.ok(await rows('cards') > 100);

    // Each account is as new, with its login, name, bio and Steam link
    for (const [id, name] of [[ana, 'ana'], [ben, 'ben'], [cat, 'cat'], [dan, 'dan']]) {
        const p = await one(id);
        assert.deepEqual([p.username, p.email, p.password_hash, p.profile_bio, p.steam_id], [name, name + '@x', 'hash', 'my bio', 'steam-' + name]);
        assert.deepEqual([p.karat, p.dust, p.free_packs, p.level, p.xp, p.rank, p.rank_points, p.season_ranked, p.season_peak_points],
            [START_KARAT, 0, 0, 1, 0, 'rookie', 0, 0, 0], name);
        assert.deepEqual([p.wins, p.losses, p.draws, p.first_win_date, p.daily_streak, p.daily_claimed_on, p.title, p.card_back],
            [0, 0, 0, null, 0, null, null, null], name);
        assert.equal(p.contraband, id === ben ? 1700 : 0, `${name}: only Contraband that was bought comes back`);
        assert.equal(await count(`SELECT COUNT(*) AS n FROM player_mail WHERE player_id = $1`, [id]), 1, 'one mail: the fresh start');
    }
    const mail = async (id) => (await q('SELECT subject, body FROM player_mail WHERE player_id = $1', [id])).rows[0];
    assert.equal((await mail(ana)).subject, 'AlleyWay Brawlers has launched');
    assert.doesNotMatch((await mail(ana)).body, /season reward/);
    assert.match((await mail(ben)).body, /season reward is waiting/);

    // Pictures: one everyone has and one given by hand stay, unlocked ones go
    assert.equal((await one(ana)).avatar_url, free);
    assert.equal((await one(ben)).avatar_url, null);
    assert.equal((await one(cat)).avatar_url, 'card:gift');
    assert.equal((await one(dan)).avatar_url, null);

    // The chosen clan's starter, and only that
    for (const [id, clan] of [[ana, clanA], [ben, clanB]]) {
        const recipe = starterRecipe(clan.id);
        assert.equal((await one(id)).chosen_clan, clan.id);
        const { rows: decks } = await q('SELECT id, name, is_active FROM decks WHERE player_id = $1', [id]);
        assert.deepEqual(decks.map(d => [d.name, d.is_active]), [[`${clan.name} Starter`, true]]);
        assert.equal(await count('SELECT COALESCE(SUM(copies), 0) AS n FROM deck_cards WHERE deck_id = $1', [decks[0].id]), 40);
        const copies = recipe.deck.reduce((s, [, n]) => s + n, 0) + recipe.hideout.reduce((s, [, n]) => s + n, 0) + 1;
        assert.equal(await count('SELECT COALESCE(SUM(quantity), 0) AS n FROM player_inventory WHERE player_id = $1', [id]), copies,
            'the starter\'s cards and nothing from before');
        const { rows: grants } = await q('SELECT clan FROM player_starter_grants WHERE player_id = $1', [id]);
        assert.deepEqual(grants.map(g => g.clan), [clan.id]);
    }
    // No clan, or a clan that is gone: nothing yet, they pick when they sign in
    for (const id of [cat, dan]) {
        assert.equal((await one(id)).chosen_clan, null);
        assert.equal(await count('SELECT COUNT(*) AS n FROM decks WHERE player_id = $1', [id]), 0);
        assert.equal(await count('SELECT COUNT(*) AS n FROM player_inventory WHERE player_id = $1', [id]), 0);
    }

    // ── Run again: nothing left to lose, the same end; --bought drop and --no-mail do what they say ──
    r = await run(pool, { apply: true, bought: 'drop', mail: false });
    assert.equal(r.applied, true);
    assert.equal((await one(ben)).contraband, 0, 'dropped: bought Contraband is not given back');
    assert.equal(await rows('payment_grants'), 3, 'the payment records stay');
    assert.equal(await rows('player_mail'), 0, 'no mail when told so');
    assert.equal(await rows('decks'), 2);
    assert.equal((await one(ana)).karat, START_KARAT);

    // ── The two "anyway" switches ──
    await q('UPDATE seasons SET ended_at = NULL');
    onboarding.GIVE_ALL_STARTERS = true;
    r = await run(pool, { bought: 'drop' });
    assert.equal(r.problems.length, 2);
    r = await run(pool, { bought: 'drop', seasonRunning: true, startersOn: true });
    assert.deepEqual(r.problems, []);
    assert.equal(r.applied, false, 'still a dry run without apply');

    await pool.end();
    console.log('launch wipe: ok');
})().catch((err) => {
    console.error(err);
    process.exit(1);
});
