'use strict';
// Starts every player's progression again: level 1 with 0 XP, and the Rookie ranked tier with
// 0 Rank Points. Cards, decks, currencies, achievements and match history are kept.
//
//   node backend/scripts/reset_progress.js            shows what would change
//   node backend/scripts/reset_progress.js --apply    does it
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const apply = process.argv.includes('--apply');

(async () => {
    const { rows: [n] } = await pool.query(
        `SELECT COUNT(*)::int AS players,
                COUNT(*) FILTER (WHERE level <> 1 OR xp <> 0)::int AS leveled,
                COUNT(*) FILTER (WHERE rank <> 'rookie' OR rank_points <> 0)::int AS ranked
         FROM players`);
    console.log(`${n.players} players: ${n.leveled} above level 1 / with XP, ${n.ranked} with a rank above Rookie or Rank Points.`);
    if (!apply) {
        console.log('Nothing changed. Run again with --apply to reset them all to level 1 and Rookie.');
    } else {
        const { rowCount } = await pool.query(
            `UPDATE players SET level = 1, xp = 0, rank = 'rookie', rank_points = 0
             WHERE level <> 1 OR xp <> 0 OR rank <> 'rookie' OR rank_points <> 0`);
        console.log(`Reset ${rowCount} players to level 1 (0 XP) and Rookie (0 Rank Points).`);
    }
    await pool.end();
})().catch(async (err) => {
    console.error(err.message);
    process.exitCode = 1;
    await pool.end();
});
