'use strict';

/**
 * MID-MATCH WEATHER: an arena's "weather" (godot/data/arenas.json) names the fronts that can roll in; this plans
 * a match's (rules.weather: [{from, until, kind, bonus}], turn ranges) and both rules engines apply the front over
 * the turn being played (DuelState _weather). Each kind's effect is godot/data/weather.json's, shaped like an
 * arena's bonus. In Ranked and weekly challenges the weather is only scenery (no bonus). The game draws it all
 * (duel.gd WEATHER) from the same plan, so both players see the same sky.
 */

const fs = require('fs');
const path = require('path');
const { RANKED_MODES } = require('./arenas');

const read = (f, fallback) => {
    try { return JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data', f), 'utf8')); }
    catch { return fallback; }
};
const ARENAS = read('arenas.json', []);
const FX = read('weather.json', {});

/** The match's weather plan: now and then a front from the arena's list for 3-5 turns, then clear skies. */
function weatherPlan(arenaId, mode, challenge = false, rand = Math.random) {
    const kinds = (ARENAS.find(a => String(a.id) === String(arenaId))?.weather || []).filter(k => typeof k === 'string');
    if (!kinds.length) return [];
    const scenery = challenge || RANKED_MODES.includes(mode);
    const between = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
    const out = [];
    let t = between(3, 6);
    while (t < 60) {
        if (rand() < 0.8) {
            const kind = kinds[Math.floor(rand() * kinds.length)];
            const lasts = between(3, 5);
            const fx = FX[kind];
            out.push({ from: t, until: t + lasts, kind, ...(fx && !scenery ? { bonus: JSON.parse(JSON.stringify(fx)) } : {}) });
            t += lasts;
        }
        t += between(3, 6);
    }
    return out;
}

module.exports = { weatherPlan, WEATHER_FX: FX };
