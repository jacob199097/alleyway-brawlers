// Awakening mid-turn: a Dormant leader that Awakens at low Morale (General Graves: Morale 2000 or
// less) is offered the field the moment an attack drops its owner's Morale that low, in the middle
// of the other player's Brawl phase; "stay Dormant" isn't asked again until the next turn, and the
// start of the owner's turn still asks (shared/duel/DuelState.js; duel_state.gd plays the same rules,
// which the golden test checks).
//   node shared/duel/awaken.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';

const duel = () => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 6;
    st.phase = 'brawl';
    st.active = 'opponent';
    st.sides.player.leader = st.makeCard({ id: 'test_graves', name: 'Graves', cardType: 'leader', clanTag: 'test',
        attack: 2950, defense: 2500, awakenCondition: { morale: 2000 } });
    st.sides.player.leader_state = 'dormant';
    st.sides.player.morale = 2300;
    return st;
};
const unit = (st, name, atk, def) => st.makeCard({ id: 'test_' + name.toLowerCase(), name, cardType: 'gang_member', clanTag: 'test', attack: atk, defense: def });
const attack = (st) => {
    const mine = unit(st, 'Grunt', 1000, 800);
    st.sides.player.field[1] = mine;
    const theirs = unit(st, 'Bruiser', 1400, 1000);
    theirs.deployed_turn = 1;
    st.sides.opponent.field[2] = theirs;
    st._recalc();
    st._attack('opponent', 2, 1);   // 1400 vs 1000 ATK: 400 battle damage
};

// Dropping to 2000 or less in the opponent's Brawl phase: Graves is offered the field at once
let st = duel();
attack(st);
assert.equal(st.sides.player.morale, 1900);
let ask = st._asks.find(a => a.key === 'awaken');
assert.ok(ask, 'Graves is offered the field right away');
assert.equal(ask.side, 'player');
st._asks.splice(st._asks.indexOf(ask), 1);
st._runAnswer(() => ask.cb('0'));
assert.equal(st.sides.player.leader_state, 'awake');
assert.equal(st.sides.player.field[0], st.sides.player.leader, 'he takes lane 1');
// ...and, arriving on the opponent's turn, he can attack on his owner's next turn
st._endTurn();
while (st._asks.length) { const x = st._asks.shift(); st._runAnswer(() => x.cb(x.options[0].id)); }
assert.equal(st.active, 'player');
assert.equal(st.sides.player.field[0].has_attacked, false, "ready to attack on his owner's turn");   // (the test's empty deck ends the game on the draw, so not canAttackWith)

// "Stay Dormant": not asked again this turn, however much more Morale is lost; asked next turn
st = duel();
attack(st);
ask = st._asks.find(a => a.key === 'awaken');
st._asks.splice(st._asks.indexOf(ask), 1);
st._runAnswer(() => ask.cb('wait'));
st._damage('player', 300);
assert.ok(!st._asks.some(a => a.key === 'awaken'), 'not asked again this turn');
assert.equal(st.sides.player.leader_state, 'dormant');
st.turn += 1;
st._damage('player', 100);
assert.ok(st._asks.some(a => a.key === 'awaken'), 'asked again the next turn');

// Above 2000: nothing is asked
st = duel();
st.sides.player.morale = 5000;
attack(st);
assert.ok(!st._asks.some(a => a.key === 'awaken'));

console.log('awaken: ok');
