'use strict';

// Mid-match weather (utils/weather.js): fronts from the arena's own list, over turn ranges that don't overlap, each
// with its effect (godot/data/weather.json) except in Ranked and weekly challenges, and none where an arena has none.
//   node backend/utils/weather.test.cjs

const assert = require('assert');
const { weatherPlan, WEATHER_FX } = require('./weather');
const arenas = require('../../godot/data/arenas.json');

let seed = 7;
const rand = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };

for (const a of arenas) {
    const plan = weatherPlan(a.id, 'casual', false, rand);
    if (!(a.weather || []).length) { assert.deepEqual(plan, [], `${a.id}: no weather of its own, none`); continue; }
    assert.ok(plan.length > 0, `${a.id}: some weather over a long match`);
    let last = 0;
    for (const f of plan) {
        assert.ok(a.weather.includes(f.kind), `${a.id}: ${f.kind} is one of its kinds`);
        assert.ok(f.from >= last && f.until - f.from >= 3 && f.until - f.from <= 5, `${a.id}: 3-5 turns, after the last one`);
        assert.deepEqual(f.bonus, WEATHER_FX[f.kind], `${a.id}: ${f.kind} carries its effect`);
        last = f.until;
    }
    for (const plain of [weatherPlan(a.id, 'ranked', false, rand), weatherPlan(a.id, 'cpu_ranked', false, rand), weatherPlan(a.id, 'casual', true, rand)]) {
        assert.ok(plain.every(f => f.bonus === undefined), `${a.id}: only scenery in Ranked and challenges`);
    }
}
for (const k of Object.keys(WEATHER_FX).filter(k => !k.startsWith('_'))) {
    assert.ok(['boost', 'atk', 'def', 'direct'].some(x => WEATHER_FX[k][x] !== undefined), `${k}: an effect the engines apply`);
}
console.log('Weather: OK');
