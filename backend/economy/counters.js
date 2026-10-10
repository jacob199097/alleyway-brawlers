'use strict';

// A player's running totals (player_counters): matches won with each clan, KOs, packs opened, ...
// Achievements (economy/achievements.js) are measured against them. db = the pool or a client
// inside a transaction.

/** Add amount to a total. */
async function bump(db, playerId, key, amount = 1) {
    if (!amount) return;
    await db.query(
        `INSERT INTO player_counters (player_id, key, value) VALUES ($1, $2, $3)
         ON CONFLICT (player_id, key) DO UPDATE SET value = player_counters.value + EXCLUDED.value`,
        [playerId, key, amount]);
}

/** Keep the highest value seen (e.g. most KOs in one match). */
async function best(db, playerId, key, value) {
    await db.query(
        `INSERT INTO player_counters (player_id, key, value) VALUES ($1, $2, $3)
         ON CONFLICT (player_id, key) DO UPDATE SET value = GREATEST(player_counters.value, EXCLUDED.value)`,
        [playerId, key, value]);
}

async function counters(db, playerId) {
    const { rows } = await db.query('SELECT key, value FROM player_counters WHERE player_id = $1', [playerId]);
    return Object.fromEntries(rows.map(r => [r.key, r.value]));
}

module.exports = { bump, best, counters };
