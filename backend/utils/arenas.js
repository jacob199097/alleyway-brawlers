'use strict';

/**
 * THE 1v1 ARENAS (godot/data/arenas.json, the game's own list) and each one's effect: an arena's "bonus"
 * (a title, then any of: boost (effect kinds) + amount, atk, def, direct, authority, draw, morale; see
 * _arenaBoost in shared/duel/DuelState.js) goes into a match's rules (DuelState rules.arena_bonus) for every
 * card and player alike, in every mode but Ranked, where the arenas are only scenery.
 */

const fs = require('fs');
const path = require('path');

const LIST = (() => {
    try { return JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/arenas.json'), 'utf8')); }
    catch { return [{ id: 'alley' }]; }
})();
const ARENAS = LIST.map(a => String(a.id));

const RANKED_MODES = ['ranked', 'cpu_ranked'];

/** What an arena's bonus can change (more than its title). */
const EFFECTS = ['boost', 'atk', 'def', 'direct', 'authority', 'draw', 'morale'];

/** A wanted arena if it's real, else a random one. */
function pickArena(want = null) {
    return typeof want === 'string' && ARENAS.includes(want) ? want : ARENAS[Math.floor(Math.random() * ARENAS.length)];
}

/** The arena's bonus for a match in this mode (rules.arena_bonus), or null (none, or Ranked). */
function arenaBonus(id, mode) {
    if (RANKED_MODES.includes(mode)) return null;
    const b = LIST.find(a => String(a.id) === String(id))?.bonus;
    return b && typeof b === 'object' && EFFECTS.some(k => b[k] !== undefined) ? JSON.parse(JSON.stringify(b)) : null;
}

module.exports = { ARENAS, EFFECTS, RANKED_MODES, pickArena, arenaBonus };
