// Ranked seasons (backend/economy/seasons.js), on the server:
//
//   node backend/scripts/season.mjs                      the season running now, and what ending it would do
//   node backend/scripts/season.mjs end                  the same (nothing changes)
//   node backend/scripts/season.mjs end --apply [--name "Season 1"] [--subtitle "The Pirates arrive"] [--weeks 13]
//        ends the season: each player who played Ranked gets their reward to claim in the game (by the
//        highest rank they reached), every rank drops back, and the next season starts (--weeks 0: no end date)
//
// Season 0 ends at launch, before the wipe (docs/LAUNCH_CHECKLIST.md).
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
require('dotenv').config({ path: fileURLToPath(new URL('../.env', import.meta.url)) });
const { pool } = require('../db/pool');
const { migrate } = require('../db/migrate');
const seasons = require('../economy/seasons');

const args = process.argv.slice(2);
const opt = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
const apply = args.includes('--apply');

try {
    await migrate(pool);   // (the seasons tables exist even before the server has restarted)
    const now = await seasons.current();
    if (!now) throw new Error('No season is running.');
    console.log(`Running now: ${now.name} (number ${now.id}), since ${now.started_at.toISOString().slice(0, 10)}, ` +
        (now.ends_at ? `planned to end ${now.ends_at.toISOString().slice(0, 10)}.` : 'no end date set.'));
    const weeks = opt('--weeks');
    const r = await seasons.endSeason({ name: opt('--name'), subtitle: opt('--subtitle') || '', weeks: weeks == null ? undefined : Number(weeks) }, apply);
    console.log(`\n${apply ? 'Ended' : 'Ending it would give'} rewards to the players who played Ranked in it, by the highest rank they reached:`);
    for (const t of r.players) console.log(`  ${t.name.padEnd(13)} ${t.count}`);
    console.log(`  in all: ${r.rewards.karat} Karat, ${r.rewards.free_packs} free packs, ${r.rewards.cards} prize cards (claimed in the game)`);
    console.log(`Every rank drops back, and ${r.next.name}${r.next.subtitle ? ` ("${r.next.subtitle}")` : ''} starts` +
        (r.next.ends_at ? `, planned to end ${r.next.ends_at.toISOString().slice(0, 10)}.` : ', with no end date.'));
    if (!apply) console.log('\nNothing changed. Add --apply to end the season.');
} catch (err) {
    console.error(err.message);
    process.exitCode = 1;
} finally {
    await pool.end();
}
