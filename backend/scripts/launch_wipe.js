'use strict';
// The launch wipe (docs/LAUNCH_CHECKLIST.md): every pre-launch account starts again, as if it had just
// signed up and picked its clan.
//
//   Kept:   the account (login, name, bio, Steam link, the day it was made), friends and chat, a profile
//           picture everyone has or one given by hand, the finished season's rewards still to claim
//           (seasons, player_seasons), payment records, the balance dashboard's match data.
//   Reset:  the collection and decks (back to the chosen clan's starter deck), Karat (what a new account
//           gets), Contraband, Dust, packs, the mailbox, level, XP, rank, Rank Points, the win / loss
//           record, the daily reward and quests, achievements (with their titles, card backs and
//           pictures), clan mastery, veteran cards, the turf map, Turf Defense clears, match history and
//           replays, every auction and bid.
//
//   node backend/scripts/launch_wipe.js              shows what it would do (nothing changes)
//   node backend/scripts/launch_wipe.js --apply      does it, all or nothing
//        --bought keep|drop   needed when Contraband purchases are on record. keep: each player gets
//                             the Contraband they bought back. drop: they were test purchases (Stripe in
//                             test mode, Steam's sandbox), so they go like the rest
//        --no-mail            no "fresh start" mail to each player
//        --season-running     wipe although no season has been ended (the season's rewards are lost)
//        --starters-on        wipe although GIVE_ALL_STARTERS is still on (the server gives every
//                             clan's starter back when it starts)
//
// Before --apply: end Season 0 (backend/scripts/season.mjs end --apply), take a backup
// (node tools/backup_db.mjs --now on the PC), and stop the game server so no match writes old progress
// back: sudo systemctl stop alleyway-backend, wipe, sudo systemctl start alleyway-backend.
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const START_KARAT = 500;   // what a new account gets (routes/auth.js, routes/steam.js)

// Every table, so a new one can't be forgotten: the wipe stops if it meets a table that is in neither list.
const CLEARED = {
    auctions: 'auctions', auction_bids: 'bids',
    decks: 'decks', deck_cards: null, deck_hideout: null,   // (null: goes with its deck)
    player_inventory: 'cards in collections (different cards per player)',
    player_packs: 'unopened packs', player_mail: 'mails', player_starter_grants: null,
    player_daily_quests: 'daily quests', player_quest_claims: 'quest claims',
    player_counters: 'achievement counters', player_achievements: 'achievements',
    clan_mastery: 'clan mastery records', weekly_challenge_wins: 'weekly challenge wins',
    card_veterans: 'veteran card records',
    territory_influence: 'turf map scores', territory_claims: 'turf map payouts',
    boss_clears: 'Turf Defense records',
    matches: 'matches in the history', solo_matches: 'CPU match records', match_replays: 'replays',
};
const KEPT = ['players', 'friendships', 'messages', 'seasons', 'player_seasons', 'payment_grants', 'steam_orders',
    'player_avatar_gifts', 'match_stats', 'client_errors', 'site_counts', 'cards', 'level_thresholds'];

/**
 * The wipe, inside the caller's transaction. → { lines: what it did, problems: why --apply must not go ahead }
 * opts: bought 'keep' | 'drop', mail (default true), seasonRunning, startersOn (see the top of the file).
 */
async function wipe(client, opts = {}) {
    const lines = [], problems = [];
    const q = (sql, params) => client.query(sql, params);
    const num = async (sql, params) => Number((await q(sql, params)).rows[0].n);
    const { pickableClans, starterRecipe, freeAvatars } = await import('../../shared/clans.js');
    const onboarding = require('../routes/onboarding');

    const { rows: tables } = await q(`SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename`);
    const here = new Set(tables.map(t => t.tablename));
    const unknown = [...here].filter(t => !(t in CLEARED) && !KEPT.includes(t));
    if (unknown.length) {
        throw new Error(`The wipe doesn't know these tables: ${unknown.join(', ')}. Add each to CLEARED or KEPT in backend/scripts/launch_wipe.js first.`);
    }

    const players = await num('SELECT COUNT(*) AS n FROM players');
    lines.push(`${players} accounts, all kept: login, name, friends (${await num('SELECT COUNT(*) AS n FROM friendships')}) and chat messages (${await num('SELECT COUNT(*) AS n FROM messages')}).`);

    // The season's rewards are recorded when it ends: wiping first would lose them
    const ended = await num('SELECT COUNT(*) AS n FROM seasons WHERE ended_at IS NOT NULL');
    const waiting = await num('SELECT COUNT(*) AS n FROM player_seasons WHERE claimed_at IS NULL');
    if (ended) lines.push(`${waiting} season rewards still to claim, kept.`);
    else if (opts.seasonRunning) lines.push('No season has been ended: its rewards are lost (--season-running).');
    else problems.push('No season has been ended yet. End Season 0 first (node backend/scripts/season.mjs end --apply), or its rewards are lost. To wipe anyway: --season-running.');
    if (onboarding.GIVE_ALL_STARTERS) {
        if (opts.startersOn) lines.push('GIVE_ALL_STARTERS is on: the server gives every clan\'s starter back when it starts (--starters-on).');
        else problems.push('GIVE_ALL_STARTERS is still on in backend/routes/onboarding.js: the server would give every clan\'s starter back when it starts. Set it to false and deploy first, or say --starters-on.');
    }

    // Contraband that was bought (free developer grants, "dev_...", never count)
    const { rows: bought } = await q(
        `SELECT player_id, SUM(contraband)::int AS contraband, COUNT(*)::int AS n,
                COUNT(*) FILTER (WHERE payment_intent_id LIKE 'steam:%')::int AS steam
         FROM payment_grants WHERE payment_intent_id NOT LIKE 'dev\\_%' AND player_id IS NOT NULL GROUP BY player_id`);
    if (bought.length) {
        const n = bought.reduce((s, b) => s + b.n, 0), steam = bought.reduce((s, b) => s + b.steam, 0);
        const total = bought.reduce((s, b) => s + b.contraband, 0);
        const what = `${n} Contraband purchases on record (${steam} through Steam, ${n - steam} by card) from ${bought.length} accounts, ${total} Contraband in all`;
        if (opts.bought === 'keep') lines.push(`${what}: each account gets what it bought back (--bought keep).`);
        else if (opts.bought === 'drop') lines.push(`${what}: not given back (--bought drop). The payment records stay.`);
        else problems.push(`${what}. Say --bought keep (give it back) or --bought drop (they were test purchases).`);
    }

    // Everything that is progress
    lines.push('Started again:');
    const { rows: [inv] } = await q('SELECT COUNT(*)::int AS n, COALESCE(SUM(quantity), 0)::int AS copies FROM player_inventory');
    for (const table of ['auction_bids', ...Object.keys(CLEARED).filter(t => t !== 'auction_bids')]) {
        if (!here.has(table)) continue;   // (made the first time it's used: routes/replays.js)
        const { rowCount } = await q(`DELETE FROM ${table}`);
        if (CLEARED[table]) lines.push(`  ${String(rowCount).padStart(7)} ${CLEARED[table]}${table === 'player_inventory' ? `, ${inv.copies} copies` : ''}`);
    }

    const { rows: [was] } = await q(
        `SELECT COALESCE(SUM(karat), 0)::bigint AS karat, COALESCE(SUM(contraband), 0)::bigint AS contraband,
                COALESCE(SUM(dust), 0)::bigint AS dust, COALESCE(SUM(free_packs), 0)::bigint AS free_packs,
                COUNT(*) FILTER (WHERE level > 1 OR xp > 0)::int AS leveled,
                COUNT(*) FILTER (WHERE rank <> 'rookie' OR rank_points > 0)::int AS ranked
         FROM players`);
    await q(
        `UPDATE players SET karat = $1, contraband = 0, dust = 0, free_packs = 0, level = 1, xp = 0,
                rank = 'rookie', rank_points = 0, season_ranked = 0, season_peak_points = 0,
                wins = 0, losses = 0, draws = 0, first_win_date = NULL, daily_streak = 0, daily_claimed_on = NULL,
                title = NULL, card_back = NULL`, [START_KARAT]);
    lines.push(`  ${String(was.karat).padStart(7)} Karat, ${was.contraband} Contraband, ${was.dust} Dust and ${was.free_packs} free packs: every account back to ${START_KARAT} Karat and nothing else`);
    lines.push(`  ${String(was.leveled).padStart(7)} accounts above level 1 and ${was.ranked} above Rookie: all back to level 1 and Rookie, with a clean win / loss record`);
    if (opts.bought === 'keep') {
        for (const b of bought) await q('UPDATE players SET contraband = $1 WHERE id = $2', [b.contraband, b.player_id]);
    }
    // A picture that was unlocked goes; one everyone has, or one given by hand, stays
    const { rowCount: pictures } = await q(
        `UPDATE players p SET avatar_url = NULL
         WHERE avatar_url IS NOT NULL AND NOT (avatar_url = ANY($1::text[]))
           AND NOT EXISTS (SELECT 1 FROM player_avatar_gifts g WHERE g.player_id = p.id AND g.avatar = p.avatar_url)`, [freeAvatars()]);
    lines.push(`  ${String(pictures).padStart(7)} profile pictures that were unlocked: back to the default (titles and card backs too)`);

    // The chosen clan's starter, as onboarding gives it
    const clans = new Map(pickableClans().map(c => [c.id, c]));
    const { rows: chose } = await q('SELECT id, chosen_clan FROM players WHERE chosen_clan IS NOT NULL ORDER BY created_at');
    const starters = {};
    let again = 0;
    for (const p of chose) {
        const clan = clans.get(p.chosen_clan);
        if (!clan) {   // (a clan that can't be picked any more: they choose again)
            await q('UPDATE players SET chosen_clan = NULL WHERE id = $1', [p.id]);
            again += 1;
            continue;
        }
        await onboarding.seedStarter(client, p.id, starterRecipe(clan.id), clan.name);
        await q('INSERT INTO player_starter_grants (player_id, clan) VALUES ($1, $2)', [p.id, clan.id]);
        starters[clan.name] = (starters[clan.name] || 0) + 1;
    }
    const given = Object.entries(starters).map(([name, n]) => `${n} ${name}`).join(', ');
    lines.push(`Starter decks given back: ${given || 'none'}. ${players - chose.length + again} accounts pick a clan when they next sign in.`);

    if (opts.mail !== false) {
        const { rowCount } = await q(
            `INSERT INTO player_mail (player_id, subject, body)
             SELECT p.id, 'AlleyWay Brawlers has launched', $1 ||
                    CASE WHEN EXISTS (SELECT 1 FROM player_seasons s WHERE s.player_id = p.id AND s.claimed_at IS NULL)
                         THEN $2 ELSE '' END || $3
             FROM players p`,
            ['AlleyWay Brawlers has launched, and everyone starts from the same line.\n\n' +
             'Kept: your account, your name, your friends and your messages.\n' +
             'Started again: your collection (you have your clan\'s starter deck), Karat, Dust, packs, level, rank and achievements.\n\n',
             'You played Ranked before the launch: your season reward is waiting for you to claim.\n\n',
             'Thank you for playing before the launch. See you in the alley.']);
        lines.push(`${rowCount} accounts get a mail that says what was kept and what started again.`);
    }
    return { lines, problems };
}

/** Run the wipe in one transaction; without apply (or with problems) everything is rolled back.
 *  → { lines, problems, applied } */
async function run(pool, opts = {}) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const r = await wipe(client, opts);
        const applied = !!opts.apply && !r.problems.length;
        await client.query(applied ? 'COMMIT' : 'ROLLBACK');
        return { ...r, applied };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { run, wipe, START_KARAT };

if (require.main === module) {
    const { pool } = require('../db/pool');
    const args = process.argv.slice(2);
    const boughtAt = args.indexOf('--bought');
    const bought = boughtAt >= 0 ? args[boughtAt + 1] : undefined;
    const apply = args.includes('--apply');
    (async () => {
        if (bought !== undefined && !['keep', 'drop'].includes(bought)) throw new Error('--bought takes keep or drop.');
        const r = await run(pool, {
            apply, bought, mail: !args.includes('--no-mail'),
            seasonRunning: args.includes('--season-running'), startersOn: args.includes('--starters-on'),
        });
        console.log(`${apply ? 'The launch wipe' : 'The launch wipe would do this'}:\n`);
        for (const l of r.lines) console.log(l);
        if (r.problems.length) {
            console.log(`\n${apply ? 'Stopped, nothing changed' : 'Before it can run with --apply'}:`);
            for (const p of r.problems) console.log(`  - ${p}`);
            if (apply) process.exitCode = 1;
        }
        if (r.applied) console.log('\nDone. Start the game server again.');
        else if (!apply) console.log('\nNothing changed. Run again with --apply to do it.');
    })().catch((err) => {
        console.error('Failed, nothing changed:', err.message);
        process.exitCode = 1;
    }).finally(() => pool.end());
}
