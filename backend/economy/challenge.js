'use strict';

/**
 * THE WEEKLY CHALLENGE (shared/challenges.js): this week's rules twist, played against the
 * server CPU (socket/onlineMatch.js, mp:cpu {challenge: true}). The first win each week pays
 * REWARD, once (weekly_challenge_wins).
 */

const { pool } = require('../db/pool');

const shared = () => import('../../shared/challenges.js');

/** This week's challenge and whether the player has already won it: {week, id, name, text, ends_at, reward, won}. */
async function status(playerId) {
    const { weeklyChallenge, REWARD } = await shared();
    const c = weeklyChallenge();
    const { rowCount } = await pool.query('SELECT 1 FROM weekly_challenge_wins WHERE player_id = $1 AND week = $2', [playerId, c.week]);
    return { week: c.week, id: c.id, name: c.name, text: c.text, ends_at: c.ends_at, reward: { ...REWARD }, won: rowCount > 0 };
}

/** A won challenge match from `week`: pays the reward the first time → a banner, or null. */
async function claim(playerId, week) {
    const { weeklyChallenge, REWARD } = await shared();
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rowCount } = await client.query(
            'INSERT INTO weekly_challenge_wins (player_id, week) VALUES ($1, $2) ON CONFLICT DO NOTHING', [playerId, week]);
        if (!rowCount) {
            await client.query('ROLLBACK');
            return null;
        }
        await client.query('UPDATE players SET karat = karat + $1, free_packs = free_packs + $2 WHERE id = $3',
            [REWARD.karat, REWARD.free_packs, playerId]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
    const c = weeklyChallenge();
    return { id: `challenge:${week}`, heading: 'WEEKLY CHALLENGE', name: c.week === week ? c.name : 'Weekly Challenge',
        desc: 'Won this week\'s challenge', reward: { ...REWARD } };
}

module.exports = { status, claim };
