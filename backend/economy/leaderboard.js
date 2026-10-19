'use strict';

/**
 * The ranked leaderboard: every player by Rank Points (then wins), the top N, and where the asking
 * player stands. Only what anyone may see: name, picture, level, rank, record, clan and title.
 */

const { pool } = require('../db/pool');
const achievements = require('./achievements');

const RANKED = `SELECT id, username, level, rank, rank_points, wins, losses, avatar_url, chosen_clan, title AS title_id,
                       RANK() OVER (ORDER BY rank_points DESC, wins DESC) AS place
                  FROM players`;

async function shown(row) {
    if (!row) return null;
    const { title_id: titleId, ...rest } = row;
    return { ...rest, place: Number(row.place), title: await achievements.titleText(titleId) };
}

/** → { top: [players...], me: the asking player's row (with place), total: how many are ranked } */
async function leaderboard(playerId, limit = 50) {
    const n = Math.max(1, Math.min(100, Number(limit) || 50));
    const { rows: top } = await pool.query(`${RANKED} ORDER BY place, username LIMIT $1`, [n]);
    const { rows: [me] } = await pool.query(`SELECT * FROM (${RANKED}) t WHERE id = $1`, [playerId]);
    const { rows: [{ count }] } = await pool.query('SELECT COUNT(*)::int AS count FROM players');
    return { top: await Promise.all(top.map(shown)), me: await shown(me), total: count };
}

module.exports = { leaderboard };
