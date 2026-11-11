'use strict';

/**
 * RANKED SEASONS (the numbers: season_settings.js; prize cards: shared/seasons.js).
 *
 * Rank Points always belong to the current season (seasons: the row with no ended_at). While it runs,
 * postMatch.js counts each player's Ranked games (players.season_ranked) and keeps the most Rank Points
 * they've had (players.season_peak_points). When it ends (endSeason, run by backend/scripts/season.mjs):
 *   - everyone who played Ranked in it gets a player_seasons row: the highest rank they reached, and
 *     its reward (REWARDS; Legend: the season's prize card too), which they claim in the game;
 *   - every rank drops SOFT_RESET_TIERS ranks, to the bottom of that rank, and the counts start again;
 *   - the next season starts.
 * Season 0 is the pre-launch season: it ends before the launch wipe, which keeps player_seasons, so
 * its rewards are claimed on the new accounts.
 */

const { pool } = require('../db/pool');
const { REWARDS, SOFT_RESET_TIERS, DEFAULT_WEEKS } = require('./season_settings');
const { RANK_TIERS, calcRank } = require('./postMatch');

const TIER_NAMES = { rookie: 'Rookie', street_tough: 'Street Tough', enforcer: 'Enforcer', underboss: 'Underboss', kingpin: 'Kingpin', legend: 'Legend' };
const shared = () => import('../../shared/seasons.js');

const seasonOut = (s) => s && { id: s.id, name: s.name, subtitle: s.subtitle || '', started_at: s.started_at, ends_at: s.ends_at || null };

/** The season running now (the newest one not ended). */
async function current(db = pool) {
    const { rows: [s] } = await db.query('SELECT * FROM seasons WHERE ended_at IS NULL ORDER BY id DESC LIMIT 1');
    return s || null;
}

/** A tier's reward, with the season's prize card for Legend ({karat, free_packs, cards: [game ids]}). */
async function rewardFor(tier, season) {
    const r = REWARDS[tier] || REWARDS.rookie;
    const cards = r.prize ? (await shared()).seasonPrize(season) : [];
    return { karat: r.karat, free_packs: r.free_packs, cards };
}

/** Where a rank drops to at a new season: the bottom of the rank SOFT_RESET_TIERS below. → Rank Points */
function softReset(points) {
    const i = RANK_TIERS.findIndex((t) => t.tier === calcRank(points).tier);
    return RANK_TIERS[Math.max(0, i - SOFT_RESET_TIERS)].min;
}

/** For the game: the season, what each rank pays, the player's season so far and any rewards to claim. */
async function status(playerId) {
    const s = await current();
    const { rows: [p] } = await pool.query('SELECT rank_points, season_ranked, season_peak_points FROM players WHERE id = $1', [playerId]);
    if (!p) return null;
    const tiers = [];
    for (const t of RANK_TIERS) tiers.push({ tier: t.tier, name: TIER_NAMES[t.tier], min: t.min, reward: await rewardFor(t.tier, s ? s.id : 0) });
    return {
        season: seasonOut(s),
        tiers,
        me: { points: p.rank_points, tier: calcRank(p.rank_points).tier, ranked: p.season_ranked,
            peak_points: p.season_peak_points, peak_tier: calcRank(p.season_peak_points).tier },
        unclaimed: await unclaimed(playerId),
        soft_reset_tiers: SOFT_RESET_TIERS,
    };
}

/** Finished seasons whose rewards the player hasn't taken yet, oldest first. */
async function unclaimed(playerId) {
    const { rows } = await pool.query(
        `SELECT ps.season, s.name, ps.peak_tier, ps.peak_points, ps.ranked_games, ps.reward
           FROM player_seasons ps JOIN seasons s ON s.id = ps.season
          WHERE ps.player_id = $1 AND ps.claimed_at IS NULL ORDER BY ps.season`, [playerId]);
    return rows.map((r) => ({ season: r.season, name: r.name, peak_tier: r.peak_tier, peak_tier_name: TIER_NAMES[r.peak_tier] || r.peak_tier,
        peak_points: r.peak_points, ranked_games: r.ranked_games, reward: r.reward }));
}

/** Takes a finished season's reward. → {season, name, peak_tier, reward, karat, free_packs}, or null (none, or taken). */
async function claim(playerId, season) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [row] } = await client.query(
            `UPDATE player_seasons SET claimed_at = NOW()
              WHERE player_id = $1 AND season = $2 AND claimed_at IS NULL RETURNING peak_tier, reward`, [playerId, season]);
        if (!row) { await client.query('ROLLBACK'); return null; }
        const reward = row.reward || {};
        const { rows: [p] } = await client.query(
            'UPDATE players SET karat = karat + $2, free_packs = free_packs + $3 WHERE id = $1 RETURNING karat, free_packs',
            [playerId, Number(reward.karat) || 0, Number(reward.free_packs) || 0]);
        const cards = [];
        for (const id of reward.cards || []) {
            const { rows: [card] } = await client.query('SELECT id FROM cards WHERE art_url = $1', [id]);
            if (!card) { console.error(`[Seasons] Prize card ${id} isn't in the cards table`); continue; }
            await client.query(
                `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)
                 ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = player_inventory.quantity + 1`, [playerId, card.id]);
            cards.push(id);
        }
        const { rows: [s] } = await client.query('SELECT name FROM seasons WHERE id = $1', [season]);
        await client.query('COMMIT');
        return { season, name: s ? s.name : `Season ${season}`, peak_tier: row.peak_tier, peak_tier_name: TIER_NAMES[row.peak_tier] || row.peak_tier,
            reward: { ...reward, cards }, karat: p.karat, free_packs: p.free_packs };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Ends the current season and starts the next. With apply false, only says what it would do.
 *   next: { name, subtitle, weeks } (weeks: the new season's planned length; 0 = no end date)
 * → { season, players: [{tier, count}], rewards: {karat, free_packs, cards}, next, applied }
 */
async function endSeason({ name, subtitle = '', weeks = DEFAULT_WEEKS } = {}, apply = false) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const s = await current(client);
        if (!s) throw new Error('No season is running.');
        const { rows: players } = await client.query(
            'SELECT id, rank_points, season_ranked, season_peak_points FROM players WHERE season_ranked > 0 FOR UPDATE');
        const byTier = {}, totals = { karat: 0, free_packs: 0, cards: 0 };
        for (const p of players) {
            const tier = calcRank(p.season_peak_points).tier;
            const reward = await rewardFor(tier, s.id);
            byTier[tier] = (byTier[tier] || 0) + 1;
            totals.karat += reward.karat; totals.free_packs += reward.free_packs; totals.cards += reward.cards.length;
            if (apply) await client.query(
                `INSERT INTO player_seasons (player_id, season, ranked_games, peak_points, peak_tier, final_points, reward)
                 VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (player_id, season) DO NOTHING`,
                [p.id, s.id, p.season_ranked, p.season_peak_points, tier, p.rank_points, JSON.stringify(reward)]);
        }
        const nextName = name || `Season ${s.id + 1}`;
        const ends = Number(weeks) > 0 ? new Date(Date.now() + Number(weeks) * 7 * 86400000) : null;
        if (apply) {
            // Every rank drops back; the season's counts start again from the new Rank Points
            const { rows: all } = await client.query('SELECT id, rank_points FROM players');
            for (const p of all) {
                const pts = softReset(p.rank_points);
                await client.query(
                    'UPDATE players SET rank_points = $2, rank = $3, season_ranked = 0, season_peak_points = $2 WHERE id = $1',
                    [p.id, pts, calcRank(pts).tier]);
            }
            await client.query('UPDATE seasons SET ended_at = NOW() WHERE id = $1', [s.id]);
            await client.query('INSERT INTO seasons (id, name, subtitle, ends_at) VALUES ($1, $2, $3, $4)', [s.id + 1, nextName, subtitle, ends]);
            await client.query('COMMIT');
        } else {
            await client.query('ROLLBACK');
        }
        return {
            season: seasonOut(s),
            players: RANK_TIERS.map((t) => ({ tier: t.tier, name: TIER_NAMES[t.tier], count: byTier[t.tier] || 0 })),
            rewards: totals,
            next: { id: s.id + 1, name: nextName, subtitle, ends_at: ends },
            applied: apply,
        };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { current, status, unclaimed, claim, endSeason, softReset, rewardFor, TIER_NAMES };
