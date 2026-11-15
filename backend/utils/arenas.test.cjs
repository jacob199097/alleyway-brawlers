'use strict';
// Arena bonuses (backend/utils/arenas.js): every mode but Ranked gets the arena's edge for a clan.
//   node backend/utils/arenas.test.cjs
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { ARENAS, pickArena, arenaBonus } = require('./arenas');

const list = JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/arenas.json'), 'utf8'));
const withBonus = list.filter(a => a.bonus);
assert.ok(withBonus.length > 0, 'some arenas have a bonus');
for (const a of withBonus) {
    const b = a.bonus;
    assert.ok(typeof b.clan === 'string' && b.clan, `${a.id}: a clan`);
    assert.ok((typeof b.boost === 'string' && Number.isInteger(b.amount) && b.amount > 0) || Number.isInteger(b.atk) || Number.isInteger(b.def),
        `${a.id}: a boost with an amount, or ATK / DEF`);
    for (const mode of ['casual', 'cpu', 'friendly', 'coop', 'ffa']) assert.deepEqual(arenaBonus(a.id, mode), b, `${a.id}: on in ${mode}`);
    for (const mode of ['ranked', 'cpu_ranked']) assert.equal(arenaBonus(a.id, mode), null, `${a.id}: scenery only in ${mode}`);
}
const plain = list.find(a => !a.bonus);
if (plain) assert.equal(arenaBonus(plain.id, 'casual'), null, 'an arena with no bonus');
assert.equal(arenaBonus('nowhere', 'casual'), null);
assert.equal(pickArena(ARENAS[0]), ARENAS[0], 'a wanted arena');
assert.ok(ARENAS.includes(pickArena('nowhere')), 'else a random one');
console.log('arenas: ok');
