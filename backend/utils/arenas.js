'use strict';

/**
 * THE 1v1 ARENAS (godot/data/arenas.json, the game's own list) and each one's edge for a clan: an arena's
 * "bonus" ({clan, boost: an effect such as "burn", amount} or {clan, atk, def}) goes into a match's rules
 * (DuelState rules.arena_bonus) in every mode but Ranked, where the arenas are only scenery.
 */

const fs = require('fs');
const path = require('path');

const LIST = (() => {
    try { return JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/arenas.json'), 'utf8')); }
    catch { return [{ id: 'alley' }]; }
})();
const ARENAS = LIST.map(a => String(a.id));

const RANKED_MODES = ['ranked', 'cpu_ranked'];

/** A wanted arena if it's real, else a random one. */
function pickArena(want = null) {
    return typeof want === 'string' && ARENAS.includes(want) ? want : ARENAS[Math.floor(Math.random() * ARENAS.length)];
}

/** The arena's bonus for a match in this mode (rules.arena_bonus), or null (none, or Ranked). */
function arenaBonus(id, mode) {
    if (RANKED_MODES.includes(mode)) return null;
    const b = LIST.find(a => String(a.id) === String(id))?.bonus;
    return b && typeof b === 'object' && typeof b.clan === 'string' && b.clan ? { ...b } : null;
}

module.exports = { ARENAS, pickArena, arenaBonus };
