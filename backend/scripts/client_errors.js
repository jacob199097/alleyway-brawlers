'use strict';
// Prints the game's error reports (routes/telemetry.js), grouped, newest first.
//   node backend/scripts/client_errors.js [days=7]
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

(async () => {
    const days = Math.max(1, Number(process.argv[2]) || 7);
    try {
        const { rows } = await pool.query(
            `SELECT kind, message, location, MAX(version) AS version, SUM(count)::int AS times,
                    COUNT(DISTINCT player_id)::int AS players, MAX(created_at) AS last, MAX(detail) AS detail
             FROM   client_errors
             WHERE  created_at > NOW() - make_interval(days => $1)
             GROUP  BY kind, message, location
             ORDER  BY last DESC
             LIMIT  40`, [days]);
        if (!rows.length) console.log(`No error reports in the last ${days} day(s).`);
        for (const r of rows) {
            console.log(`\n[${r.kind}] ${r.message}`);
            console.log(`  at ${r.location || '?'}  ·  ${r.times}x  ·  ${r.players} player(s)  ·  v${r.version}  ·  last ${r.last.toISOString()}`);
            if (r.detail) console.log('  ' + r.detail.split('\n').slice(0, 8).join('\n  '));
        }
    } catch (err) {
        console.error(err.code === '42P01' ? 'No reports yet (the table is created by the first report).' : err.message);
    } finally {
        await pool.end();
    }
})();
