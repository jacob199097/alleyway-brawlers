// The game's achievements, as Steamworks needs them (Stats & Achievements → Achievements): each
// one's API name must be the game's own achievement id, so Steam gets them when the game unlocks
// them (godot/scripts/steam.gd unlock()). Run it after adding a clan (each clan adds two).
//
//   node tools/steam_achievements.mjs          a table to copy from
//   node tools/steam_achievements.mjs --csv    API name, display name, description
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { definitions } = require('../backend/economy/achievements.js');
const list = await definitions();
if (process.argv.includes('--csv')) {
    const q = (s) => `"${String(s).replace(/"/g, '""')}"`;
    console.log('api_name,display_name,description');
    for (const a of list) console.log([a.id, a.name, a.desc].map(q).join(','));
} else {
    for (const a of list) console.log(`${a.id.padEnd(24)} ${a.name.padEnd(26)} ${a.desc}`);
    console.log(`\n${list.length} achievements`);
}
