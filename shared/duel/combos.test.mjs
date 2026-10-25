// New Card Forge building blocks (shared/duel/DuelState.js; duel_state.gd plays the same rules, which
// the golden test checks): triggers foe_hustle, ally_promoted, ally_downed, heal_gained, self_gutter;
// targets neighbors / opposite; conditions foe_statused, hustles_ge, morale_behind / morale_ahead;
// "for each" hustles_turn, statused, lost_1000; actions tax and reshuffle; the cost_up passive.
//   node shared/duel/combos.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';

const duel = () => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 4;
    st.phase = 'deployment';
    st.active = 'player';
    return st;
};
let uid = 0;
const unit = (st, effects = [], atk = 1000, def = 1000, extra = {}) => st.makeCard({ id: `test_${uid++}`, name: `Unit ${uid}`, cardType: 'gang_member',
    clanTag: 'test', attack: atk, defense: def, authority: 2, effects, ...extra });
const put = (st, side, slot, c) => { st.sides[side].field[slot] = c; c.deployed_turn = 1; st._recalc(); return c; };
const answerAll = (st) => { while (st._asks.length) { const a = st._asks.shift(); st._runAnswer(() => a.cb(a.options[0].id)); } };

// TAX: the opponent's next turn has less Authority
let st = duel();
let c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'tax', amount: 2 });
assert.equal(st.sides.opponent.tax, 2);
st.sides.opponent.authority_max = 4;
st.sides.opponent.turns = 3;
st.active = 'opponent';
st._beginTurn();
answerAll(st);
assert.equal(st.sides.opponent.authority, 5 - 2, 'their 5 Authority, less the TAX');
assert.equal(st.sides.opponent.tax, 0, 'it is used up');

// cost_up: the opponent's cards cost more while the passive is on the field
st = duel();
put(st, 'opponent', 2, unit(st, [{ when: 'passive', do: 'cost_up', amount: 1 }]));
const card = st.makeCard({ id: 'test_cost', name: 'Cost', cardType: 'gang_member', clanTag: 'test', attack: 100, defense: 100, authority: 3 });
assert.equal(st.costOf('player', card), 4);
assert.equal(st.costOf('opponent', card), 3, "not the passive's own side");

// reshuffle: the oldest Gutter cards (not tokens) back into the deck
st = duel();
c = put(st, 'player', 0, unit(st));
const g = [unit(st), unit(st, [], 1, 1, { token: true }), unit(st), unit(st)];
st.sides.player.gutter.push(...g);
st._doFx('player', 0, c, { do: 'reshuffle', amount: 2 });
assert.equal(st.sides.player.deck.length, 2);
assert.ok(st.sides.player.deck.includes(g[0]) && st.sides.player.deck.includes(g[2]), 'the oldest two that are not tokens');
assert.ok(st.takeEvents().some(e => e.type === 'recycle' && e.count === 2));

// neighbors: the allies in the lanes next to it; opposite: the enemy across (lane 1 faces lane 5)
st = duel();
c = put(st, 'player', 2, unit(st));
const left = put(st, 'player', 1, unit(st)), right = put(st, 'player', 3, unit(st)), far = put(st, 'player', 0, unit(st));
st._doFx('player', 2, c, { do: 'buff', target: 'neighbors', atk: 300, until: 'turn' });
st._recalc();
assert.equal(left.attack, 1300);
assert.equal(right.attack, 1300);
assert.equal(far.attack, 1000, 'not the one two lanes away');
const across = put(st, 'opponent', 4, unit(st)), other = put(st, 'opponent', 0, unit(st));
c = put(st, 'player', 0, far);
st._doFx('player', 0, far, { do: 'down', target: 'opposite' });
assert.ok(across.downed, "lane 1's opposite is their lane 5");
assert.ok(!other.downed);

// foe_hustle: the opponent plays a Hustle
st = duel();
const watcher = put(st, 'opponent', 0, unit(st, [{ when: 'foe_hustle', do: 'buff', target: 'self', atk: 200, until: 'forever' }]));
const hustle = st.makeCard({ id: 'test_h', name: 'Hustle', cardType: 'hustle', clanTag: 'test', authority: 0, effects: [{ do: 'draw', amount: 1 }] });
st.sides.player.hand.push(hustle);
st.sides.player.deck.push(unit(st), unit(st));
st.sides.player.authority = 3;
assert.ok(st.doAction('player', { kind: 'hustle', uid: hustle.uid }));
st._recalc();
answerAll(st);
assert.equal(watcher.attack, 1200, 'the opponent playing a Hustle set it off');
// hustles_turn / hustles_ge: Hustles played this turn
assert.equal(st._hustlesThisTurn('player'), 1);
assert.ok(st._fxCond('player', 0, { if: 'hustles_ge', n: 1 }, null));
assert.equal(st._perCount('player', 0, { per: 'hustles_turn' }), 1);
st.turn += 1;
assert.equal(st._hustlesThisTurn('player'), 0, 'a new turn starts the count again');

// ally_downed: another of your characters is Downed
st = duel();
const avenger = put(st, 'player', 0, unit(st, [{ when: 'ally_downed', do: 'buff', target: 'self', atk: 500, until: 'forever' }]));
const victim = put(st, 'player', 1, unit(st));
st._defeat('player', 1);
st._recalc();
assert.ok(victim.downed);
assert.equal(avenger.attack, 1500);

// heal_gained: you gain Morale (and it can't set itself off again)
st = duel();
st.sides.player.morale = 3000;
const healer = put(st, 'player', 0, unit(st, [{ when: 'heal_gained', do: 'heal', amount: 100 }, { when: 'heal_gained', do: 'damage', amount: 300 }]));
st._heal('player', healer, 500, 0);
assert.equal(st.sides.player.morale, 3600, '500, then its own +100 once (no loop)');
assert.equal(st.sides.opponent.morale, 6000 - 300);

// self_gutter: milled or discarded into the Gutter
st = duel();
const milled = unit(st, [{ when: 'self_gutter', do: 'damage', amount: 400 }]);
st.sides.player.deck.push(unit(st), milled);
c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'mill_self', amount: 1 });
assert.equal(st.sides.opponent.morale, 5600, 'milled: it hits');
const tossed = unit(st, [{ when: 'self_gutter', do: 'draw', amount: 1 }]);
st.sides.player.hand.push(tossed);
st.sides.player.deck.push(unit(st));
const handBefore = st.sides.player.hand.length;
st._discardAt('player', st.sides.player.hand.indexOf(tossed));
assert.equal(st.sides.player.hand.length, handBefore, 'discarded: one card out, one drawn');

// ally_promoted: a Striver of yours PROMOTES
st = duel();
const fan = put(st, 'player', 0, unit(st, [{ when: 'ally_promoted', do: 'draw', amount: 1 }]));
st.sides.player.deck.push(unit(st));
const before = st.sides.player.hand.length;
st._runFx('player', 0, fan, 'ally_promoted', fan);
assert.equal(st.sides.player.hand.length, before + 1);

// Conditions and counts: foe_statused, statused, morale_behind / ahead, lost_1000
st = duel();
const sick = put(st, 'opponent', 0, unit(st));
assert.ok(!st._fxCond('player', 0, { if: 'foe_statused' }, null));
sick.poison = 100;
assert.ok(st._fxCond('player', 0, { if: 'foe_statused' }, null));
assert.equal(st._perCount('player', 0, { per: 'statused' }), 1);
st.sides.player.morale = 3500;
assert.ok(st._fxCond('player', 0, { if: 'morale_behind' }, null));
assert.ok(!st._fxCond('player', 0, { if: 'morale_ahead' }, null));
assert.ok(st._fxCond('opponent', 0, { if: 'morale_ahead' }, null));
assert.equal(st._perCount('player', 0, { per: 'lost_1000' }), 2, '2500 lost: 2 thousands');

console.log('combos: ok');
