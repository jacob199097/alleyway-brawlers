'use strict';
// Arena bonuses (backend/utils/arenas.js): every arena but the Back Alley and the Rooftop has an effect, for
// every player alike, in every mode but Ranked.
//   node backend/utils/arenas.test.cjs
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { ARENAS, EFFECTS, pickArena, arenaBonus } = require('./arenas');

// The effects an arena may make stronger: ones whose amount is points (or, PLUNDER, cards)
const BOOSTS = ['damage', 'heal', 'drain', 'burn', 'stoke', 'poison', 'corrode', 'bleed', 'shock', 'suppress', 'rally', 'plunder'];

const list = JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/arenas.json'), 'utf8'));
for (const a of list) {
    const b = a.bonus;
    if (['alley', 'rooftop'].includes(a.id)) {
        assert.equal(b, undefined, `${a.id}: the plain arenas have none`);
        assert.equal(arenaBonus(a.id, 'casual'), null, `${a.id}: no bonus`);
        continue;
    }
    assert.ok(b && typeof b === 'object', `${a.id}: an effect`);
    assert.ok(typeof b.title === 'string' && b.title === b.title.toUpperCase() && b.title.length > 2, `${a.id}: a title in capitals`);
    assert.equal(b.clan, undefined, `${a.id}: for every clan alike`);
    for (const k of Object.keys(b)) assert.ok(k === 'title' || k === 'amount' || EFFECTS.includes(k), `${a.id}: what's ${k}?`);
    assert.ok(EFFECTS.some(k => b[k] !== undefined), `${a.id}: it changes something`);
    if (b.boost !== undefined) {
        assert.ok(Array.isArray(b.boost) && b.boost.length > 0 && b.boost.every(k => BOOSTS.includes(k)), `${a.id}: boosts effects with an amount`);
        assert.ok(Number.isInteger(b.amount) && b.amount > 0, `${a.id}: by an amount`);
    }
    for (const k of ['atk', 'def', 'direct', 'authority', 'draw', 'morale']) {
        if (b[k] !== undefined) assert.ok(Number.isInteger(b[k]) && b[k] !== 0, `${a.id}: ${k} a whole number`);
    }
    for (const k of ['direct', 'authority', 'draw']) if (b[k] !== undefined) assert.ok(b[k] > 0, `${a.id}: ${k} more, not less`);
    for (const mode of ['casual', 'cpu', 'friendly', 'coop', 'ffa']) assert.deepEqual(arenaBonus(a.id, mode), b, `${a.id}: on in ${mode}`);
    for (const mode of ['ranked', 'cpu_ranked']) assert.equal(arenaBonus(a.id, mode), null, `${a.id}: scenery only in ${mode}`);
}
const titles = list.filter(a => a.bonus).map(a => a.bonus.title);
assert.equal(new Set(titles).size, titles.length, 'every arena its own title');
const one = list.find(a => a.bonus);
const got = arenaBonus(one.id, 'casual');
got.title = 'CHANGED';
assert.equal(arenaBonus(one.id, 'casual').title, one.bonus.title, 'a match gets its own copy');
assert.equal(arenaBonus('nowhere', 'casual'), null);
assert.equal(pickArena(ARENAS[0]), ARENAS[0], 'a wanted arena');
assert.ok(ARENAS.includes(pickArena('nowhere')), 'else a random one');
console.log('arenas: ok');
