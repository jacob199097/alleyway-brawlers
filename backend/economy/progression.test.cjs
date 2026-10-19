'use strict';

/**
 * Crafting and achievements against a real Postgres. It builds a scratch database from
 * db/schema.sql + db/migrate.js + backend/scripts/sync_cards.mjs (the Card Forge cards), so point it at a server where it may do that:
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
    require('child_process').execFileSync(process.execPath, [path.join(__dirname, '../scripts/sync_cards.mjs')], { stdio: 'inherit' });
    const crafting = require('./crafting');
    const achievements = require('./achievements');
    // A card that isn't a free picture (the free pictures are some of the cards' own art): owning it
    // never makes it a picture
    const { freeAvatars } = await import('../../shared/clans.js');
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const free = freeAvatars();
    const portrait = 'card:' + Object.values(CARD_CATALOG).find(c => !c.token && !free.includes('card:' + c.id)).id;

    const q = (sql, params) => pool.query(sql, params);
    const { rows: [me] } = await q(`INSERT INTO players (username, email, password_hash) VALUES ('tester', 't@x', 'x') RETURNING id`);
    const id = me.id;
    const cardId = async (gameId) => (await q('SELECT id FROM cards WHERE art_url = $1', [gameId])).rows[0].id;
    const give = async (gameId, n) => q(
        `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, $3)
         ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = $3`, [id, await cardId(gameId), n]);
    const owned = async (gameId) => (await q(
        'SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2', [id, await cardId(gameId)])).rows[0]?.quantity || 0;
    const { rows: [{ rarity: kadeRarity }] } = await q(`SELECT rarity FROM cards WHERE art_url = 'card_nebu_001'`);
    const value = crafting.VALUES[kadeRarity];

    // ── Crafting ──
    await give('card_nebu_001', 5);   // 2 extras
    await give('card_nebu_009', 2);  // a leader: 1 extra
    let s = await crafting.summary(id);
    assert.equal(s.dust, 0);
    assert.equal(s.extras, 3);

    // A deck using 3 Kades protects them
    const { rows: [deck] } = await q(`INSERT INTO decks (player_id, name) VALUES ($1, 'd') RETURNING id`, [id]);
    await q('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, 3)', [deck.id, await cardId('card_nebu_001')]);
    await rejects(crafting.scrap(id, 'card_nebu_001', 3), /decks use 3/);
    let r = await crafting.scrap(id, 'card_nebu_001', 1);
    assert.equal(r.quantity, 4);
    assert.equal(r.gained, value.scrap);
    await rejects(crafting.scrap(id, 'card_nebu_011'), /don't own/);

    r = await crafting.scrapExtras(id);
    assert.equal(await owned('card_nebu_001'), 3);
    assert.equal(await owned('card_nebu_009'), 1);
    assert.equal(r.scrapped, 2);
    s = await crafting.summary(id);
    assert.equal(s.extras, 0);
    assert.equal(s.dust, r.dust);

    // Crafting costs Dust, stops at 3 copies and only makes cards that are in the game
    await q('UPDATE players SET dust = 0 WHERE id = $1', [id]);   // scrapping the spare leader may have paid enough
    await rejects(crafting.craft(id, 'card_nebu_011'), /need \d+ Dust/);
    await q('UPDATE players SET dust = 10000 WHERE id = $1', [id]);
    r = await crafting.craft(id, 'card_nebu_011');
    assert.equal(r.quantity, 1);
    assert.equal(await owned('card_nebu_011'), 1);
    await rejects(crafting.craft(id, 'card_nebu_001'), /all a deck can use/);
    await rejects(crafting.craft(id, 'card_nebu_009'), /all a deck can use/);
    await rejects(crafting.craft(id, 'not_a_card'), /can't be crafted/);
    const dustBefore = (await crafting.summary(id)).dust;
    await rejects(crafting.craft(id, 'card_nebu_001'), /all a deck can use/);
    assert.equal((await crafting.summary(id)).dust, dustBefore, 'a refused craft costs nothing');

    // ── Achievements ──
    let fresh = await achievements.check(id);
    assert.ok(fresh.some(a => a.id === 'craft_1'), 'Craftsman unlocks after crafting');
    assert.equal((await achievements.check(id)).length, 0, 'nothing unlocks twice');

    const karat0 = (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;
    await q('UPDATE players SET wins = 1 WHERE id = $1', [id]);   // resolveMatch counts the win
    fresh = await achievements.recordMatch({ playerId: id, outcome: 'win', mode: 'cpu', difficulty: 'hard',
        clan: 'nebula', kos: 5, promotes: 1, awakens: 1, morale: 6000 });
    const got = fresh.map(a => a.id).sort();
    assert.deepEqual(got, ['awaken', 'first_win', 'flawless', 'hard_cpu', 'rampage'].sort());
    const karat1 = (await q('SELECT karat FROM players WHERE id = $1', [id])).rows[0].karat;
    assert.equal(karat1 - karat0, 100 + 150 + 200, 'First Blood, Awakening and Machine Breaker pay Karat');

    // Cosmetics: only what's unlocked can be worn
    assert.deepEqual(await achievements.equip(id, { title: 'flawless' }), { ok: true });
    assert.ok((await achievements.equip(id, { title: 'wins_100' })).error);
    assert.ok((await achievements.equip(id, { back: 'nebula' })).error);
    assert.ok((await achievements.equip(id, { avatar: 'clan:nebula' })).error);
    assert.deepEqual(await achievements.equip(id, { avatar: free[0] }), { ok: true }, 'everyone has the free pictures');
    assert.ok((await achievements.equip(id, { avatar: portrait })).error, 'only unlocked pictures');
    for (let i = 0; i < 9; i++) {
        await achievements.recordMatch({ playerId: id, outcome: 'win', mode: 'casual', clan: 'nebula', morale: 3000 });
    }
    const { rows: [lp] } = await q('SELECT last_played_at FROM players WHERE id = $1', [id]);
    assert.ok(lp.last_played_at, 'a finished match sets when they last played');
    const ov = await achievements.overview(id);
    const loyal = ov.achievements.find(a => a.id === 'clan_nebula_10');
    assert.ok(loyal && loyal.unlocked, 'Nebula Loyalist unlocks after 10 Nebula wins');
    assert.equal(ov.achievements.find(a => a.id === 'online_25').progress, 9);
    assert.ok(ov.cosmetics.backs.includes('nebula'));
    assert.deepEqual(await achievements.equip(id, { back: 'nebula', avatar: 'clan:nebula' }), { ok: true });
    assert.deepEqual(await achievements.equip(id, { title: null, back: null }), { ok: true });
    assert.equal(ov.equipped.title, 'flawless');
    assert.equal(await achievements.titleText('flawless'), 'Untouchable');

    // Collector: a title and Dust, but owning a card still doesn't make it a picture
    await q(`INSERT INTO player_inventory (player_id, card_id, quantity)
             SELECT $1, id, 1 FROM cards ON CONFLICT DO NOTHING`, [id]);
    await achievements.check(id);
    const coll = (await achievements.overview(id)).achievements.find(a => a.id === 'collect_25');
    assert.equal(coll.unlocked, (await q('SELECT COUNT(*)::int AS n FROM cards')).rows[0].n >= 25);
    assert.ok((await achievements.equip(id, { avatar: portrait })).error, 'owned cards are not pictures');

    // Clan mastery: the 10 Nebula wins above are 1000 XP, level 3 (Karat at 2, a picture at 3)
    const mastery = require('./mastery');
    const { rows: [ms] } = await q(`SELECT xp, wins, games FROM clan_mastery WHERE player_id = $1 AND clan = 'nebula'`, [id]);
    assert.equal(ms.xp, 1000);
    assert.equal(ms.wins, 10);
    const nebula = (await mastery.overview(id)).find(m => m.clan === 'nebula');
    assert.equal(nebula.level, 3);
    const pic = nebula.rewards.find(r => r.level === 3).reward.avatar;
    assert.ok(pic && (await achievements.cosmetics(id)).avatars.includes(pic), 'the level 3 picture can be worn');
    assert.deepEqual(await achievements.equip(id, { avatar: pic }), { ok: true });
    // ...and the post-match screen's view of it
    const prog = await mastery.progress(id, 'nebula', 'win');
    assert.equal(prog.xp, 1000);
    assert.equal(prog.gained, 100);
    assert.deepEqual(prog.levels, mastery.LEVELS);
    assert.equal((await mastery.progress(id, 'militia', 'loss')), null, 'no Militia games yet');

    // The weekly challenge pays once a week
    const challenge = require('./challenge');
    const purse = async () => (await q('SELECT karat, free_packs FROM players WHERE id = $1', [id])).rows[0];
    const before = await purse();
    const week = await challenge.status(id);
    assert.equal(week.won, false);
    assert.ok(await challenge.claim(id, week.week), 'the first win pays');
    assert.equal(await challenge.claim(id, week.week), null, 'only once a week');
    const after = await purse();
    assert.equal(after.karat - before.karat, week.reward.karat);
    assert.equal(after.free_packs - before.free_packs, week.reward.free_packs);
    assert.equal((await challenge.status(id)).won, true);

    // Packs: only the pack's clan, NEW for cards the player didn't have, and the clan's collection
    const { openPack } = require('./packOpener');
    const { rows: [opener] } = await q(`INSERT INTO players (username, email, password_hash, karat) VALUES ('opener', 'o@x', 'x', 400) RETURNING id`);
    const pack = await openPack(opener.id, 'militia');
    assert.equal(pack.cardsReceived.length, 3);
    assert.ok(pack.cardsReceived.every(c => c.clan === 'militia'), 'a Militia pack has only Militia cards');
    assert.ok(pack.cardsReceived.every(c => c.isNew && c.owned === 1), 'all new to a new player');
    assert.equal(pack.collection.owned, 3);
    assert.equal(pack.collection.total, Object.values(CARD_CATALOG).filter(c => c.clan === 'militia' && !c.token).length);
    assert.equal(pack.newKarat, 200);

    // Free-for-all places: 1st a win, 2nd between a win and a loss, the rest a loss
    const { resolveFfaMatch } = require('./postMatch');
    const { rows: [ffaP] } = await q(`INSERT INTO players (username, email, password_hash) VALUES ('ffa', 'f@x', 'x') RETURNING id`);
    const second = await resolveFfaMatch({ playerId: ffaP.id, place: 2, humans: 3 });
    assert.equal(second.xpEarned, 100);
    assert.equal(second.karatEarned, 25);
    const third = await resolveFfaMatch({ playerId: ffaP.id, place: 3, humans: 3 });
    assert.equal(third.karatEarned, 10);
    const first = await resolveFfaMatch({ playerId: ffaP.id, place: 1, humans: 3 });
    assert.equal(first.outcome, 'win');
    const rec = (await q('SELECT wins, losses FROM players WHERE id = $1', [ffaP.id])).rows[0];
    assert.deepEqual([rec.wins, rec.losses], [1, 2], 'a win and two losses');
    const vsCpu = await resolveFfaMatch({ playerId: ffaP.id, place: 1, humans: 1 });
    assert.ok(vsCpu.karatEarned < first.karatEarned, 'against CPUs only it pays like a CPU match');

    // The leaderboard: by Rank Points, then wins; everyone sees where they stand, and no currencies
    const { leaderboard } = require('./leaderboard');
    const lb1 = (await q(`INSERT INTO players (username, email, password_hash, rank_points, wins) VALUES ('lb_top', 'lb1@x', 'x', 900, 3) RETURNING id`)).rows[0].id;
    await q(`INSERT INTO players (username, email, password_hash, rank_points, wins) VALUES ('lb_two', 'lb2@x', 'x', 900, 1)`);
    const board = await leaderboard(id, 50);
    assert.equal(board.top[0].id, lb1, 'most Rank Points first');
    assert.equal(board.top[1].username, 'lb_two', 'a tie goes to the one with more wins');
    assert.equal(board.top[0].place, 1);
    assert.equal(board.me.id, id, 'the asking player sees their own place');
    assert.ok(board.me.place >= 3);
    assert.ok(!('karat' in board.top[0]) && !('email' in board.top[0]), 'no currencies or emails');
    assert.ok(board.total >= 3);

    // CPU seats never record anything
    assert.deepEqual(await achievements.recordMatch({ playerId: 'cpu:x', outcome: 'win' }), []);

    await pool.end();
    console.log('all good');
})().catch(async (err) => {
    console.error(err);
    process.exit(1);
});
