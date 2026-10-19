'use strict';

/**
 * THE DAILY REWARD: once per (UTC) day, a reward from a seven-day track that grows toward a free pack
 * on day 7, then starts over. Claim on consecutive days to move along it; miss a day and it's back to
 * day 1. The server decides the day and pays the reward (players.daily_streak / daily_claimed_on).
 */

const { pool } = require('../db/pool');

const REWARDS = [
    { karat: 100 }, { dust: 50 }, { karat: 150 }, { dust: 100 },
    { karat: 200 }, { dust: 150 }, { karat: 300, free_packs: 1 },
];
const TODAY = "(now() AT TIME ZONE 'UTC')::date";

/** Which of the seven days a streak of n is on (1-7). */
const dayOf = (n) => ((Math.max(1, n) - 1) % REWARDS.length) + 1;

/** → { day: today's (or the next) day 1-7, claimed: whether today's is taken, streak, rewards } */
async function status(playerId) {
    const { rows: [p] } = await pool.query(
        `SELECT daily_streak AS streak, daily_claimed_on = ${TODAY} AS today, daily_claimed_on = ${TODAY} - 1 AS yesterday
           FROM players WHERE id = $1`, [playerId]);
    if (!p) return null;
    const streak = Number(p.streak) || 0;
    const claimed = !!p.today;
    const next = claimed ? streak : p.yesterday ? streak + 1 : 1;
    return { day: dayOf(next), claimed, streak: claimed ? streak : next - 1, rewards: REWARDS };
}

/** Takes today's reward → { day, reward, karat, dust, free_packs }, or null if it's already been taken. */
async function claim(playerId) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [s] } = await client.query(
            `UPDATE players SET
                 daily_streak = CASE WHEN daily_claimed_on = ${TODAY} - 1 THEN daily_streak + 1 ELSE 1 END,
                 daily_claimed_on = ${TODAY}
               WHERE id = $1 AND (daily_claimed_on IS NULL OR daily_claimed_on < ${TODAY})
               RETURNING daily_streak`, [playerId]);
        if (!s) {
            await client.query('ROLLBACK');
            return null;
        }
        const day = dayOf(s.daily_streak);
        const reward = REWARDS[day - 1];
        const { rows: [p] } = await client.query(
            `UPDATE players SET karat = karat + $2, dust = dust + $3, free_packs = free_packs + $4
               WHERE id = $1 RETURNING karat, dust, free_packs`,
            [playerId, reward.karat || 0, reward.dust || 0, reward.free_packs || 0]);
        await client.query('COMMIT');
        return { day, reward, karat: p.karat, dust: p.dust, free_packs: p.free_packs };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { status, claim, REWARDS };
