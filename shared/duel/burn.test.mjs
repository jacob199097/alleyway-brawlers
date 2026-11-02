// The Arsonists' burn: STOKE builds on a BURN already there, "for each BURNING enemy" counts them,
// "only if it's BURNING" picks them out, immunity to BURN covers STOKE, and a Dormant leader can
// BURN or deal Morale damage at the end of its owner's turn (shared/duel/DuelState.js; duel_state.gd
// plays the same rules, which the golden test checks).
//   node shared/duel/burn.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';

CARD_CATALOG.burn_grunt = { id: 'burn_grunt', name: 'Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 1000, defense: 400, rarity: 1, clanTag: 'test', effectKey: '' };

/** A board in the brawl phase of turn 3, player to act. */
function board(player = [], opponent = []) {
    const st = new DuelState({ player: Array(10).fill('burn_grunt'), opponent: Array(10).fill('burn_grunt') }, {}, {}, 'player', -1);
    st.turn = 3;
    st.phase = 'brawl';
    for (const [side, cards] of [['player', player], ['opponent', opponent]]) {
        cards.forEach((spec, slot) => {
            if (!spec) return;
            st.sides[side].field[slot] = st.makeCard({ id: 'burn_grunt', effectKey: '', ...spec });
        });
    }
    st._recalc();
    st.takeEvents();
    return st;
}
const src = { id: 'src', name: 'Torch', cardType: 'hustle', clanTag: 'arsonists' };
const burn = { amt: 200, left: 1 };

// STOKE on a character that isn't burning: it BURNS
let st = board([], [{}]);
st._doFx('player', -1, src, { do: 'stoke', target: 'enemies', amount: 200 });
assert.deepEqual(st.cardAt('opponent', 0).burn, { amt: 200, left: 3 }, 'STOKE starts a BURN');

// STOKE on a burning one: the burn grows and lasts another 3 turns (BURN would only refresh it)
st = board([], [{ burn: { ...burn } }]);
st._doFx('player', -1, src, { do: 'stoke', target: 'enemies', amount: 300 });
assert.deepEqual(st.cardAt('opponent', 0).burn, { amt: 500, left: 3 }, 'STOKE adds to the burn');
st = board([], [{ burn: { ...burn } }]);
st._doFx('player', -1, src, { do: 'burn', target: 'enemies', amount: 300 });
assert.deepEqual(st.cardAt('opponent', 0).burn, { amt: 300, left: 3 }, 'BURN takes the bigger amount, no more');

// One enemy to STOKE: the hottest fire is offered first
st = board([], [{ burn: { amt: 100, left: 2 } }, {}, { burn: { amt: 400, left: 2 } }]);
st._doFx('player', -1, src, { do: 'stoke', target: 'enemy', amount: 200 });
const ask = st._asks.find(a => a.side === 'player');
assert.ok(ask, 'asked which enemy');
assert.equal(ask.options[0].slot, 2, 'the one burning for 400 first');
st._runAnswer(() => ask.cb(ask.options[0].id));
assert.equal(st.cardAt('opponent', 2).burn.amt, 600);

// Immune to BURN: immune to STOKE too
st = board([], [{ effects: [{ when: 'passive', do: 'immune', statuses: ['burn'] }] }]);
st._doFx('player', -1, src, { do: 'stoke', target: 'enemies', amount: 200 });
assert.equal(st.cardAt('opponent', 0).burn, undefined, 'immune to BURN stops STOKE');

// For each BURNING enemy
st = board([], [{ burn: { ...burn } }, {}, { burn: { ...burn } }]);
let morale = st.sides.opponent.morale;
st._doFx('player', -1, src, { do: 'damage', amount: 300, per: 'burning' });
assert.equal(st.sides.opponent.morale, morale - 600, '300 for each of 2 burning enemies');
st = board([], [{}]);
morale = st.sides.opponent.morale;
st._doFx('player', -1, src, { do: 'damage', amount: 300, per: 'burning' });
assert.equal(st.sides.opponent.morale, morale, 'none burning: nothing');

// Only if it's BURNING
st = board([], [{}, { burn: { ...burn } }]);
st._doFx('player', -1, src, { do: 'down', target: 'enemies', only: 'burning' });
assert.ok(!st.cardAt('opponent', 0).downed, 'not burning: untouched');
assert.ok(st.cardAt('opponent', 1).downed, 'burning: Downed');

// A Dormant leader at the end of its owner's turn: Morale damage, or BURN an enemy
const leader = (effects) => {
    const s = board([], [{}]);
    s.sides.player.leader = s.makeCard({ id: 'test_cinder', name: 'Cinder', cardType: 'leader', clanTag: 'arsonists', attack: 2800, defense: 2000, effects });
    s.sides.player.leader_state = 'dormant';
    return s;
};
st = leader([{ when: 'dormant_turn_end', do: 'damage', amount: 200 }]);
morale = st.sides.opponent.morale;
st._leaderFx('player', 'dormant_turn_end');
assert.equal(st.sides.opponent.morale, morale - 200, 'Dormant: 200 Morale damage');
st = leader([{ when: 'dormant_turn_end', do: 'burn', target: 'enemy', amount: 200 }]);
st._leaderFx('player', 'dormant_turn_end');
const pick = st._asks.find(a => a.side === 'player');   // (asked even with one enemy: it may be skipped)
st._runAnswer(() => pick.cb(pick.options[0].id));
assert.deepEqual(st.cardAt('opponent', 0).burn, { amt: 200, left: 3 }, 'Dormant: BURN an enemy');

// "Choose 2": two different enemies, one after the other; SKIP stops
st = board([], [{}, {}, {}]);
st._doFx('player', -1, src, { do: 'burn', target: 'enemy', amount: 200, count: 2 });
let a1 = st._asks.find(a => a.side === 'player');
assert.ok(a1 && /1 of 2/.test(a1.prompt), 'asked for the first of 2');
const first = a1.options[0];
st._runAnswer(() => a1.cb(first.id));
let a2 = st._asks.find(a => a.side === 'player' && a !== a1);
assert.ok(a2 && /2 of 2/.test(a2.prompt), 'then the second');
assert.ok(!a2.options.some(o => o.slot === first.slot), 'not the same one again');
st._runAnswer(() => a2.cb(a2.options[0].id));
assert.equal([0, 1, 2].filter(i => st.cardAt('opponent', i).burn).length, 2, 'two enemies burning');
st = board([], [{}, {}, {}]);
st._doFx('player', -1, src, { do: 'burn', target: 'enemy', amount: 200, count: 2 });
a1 = st._asks.find(a => a.side === 'player');
st._runAnswer(() => a1.cb('skip'));
assert.equal([0, 1, 2].filter(i => st.cardAt('opponent', i).burn).length, 0, 'SKIP: none');
assert.ok(!st._asks.some(a => a.side === 'player' && a !== a1), 'and nothing more asked');

// Any status: "only POISONED ones", "for each STUNNED enemy"
st = board([], [{ poison: { amt: 100, left: 2 } }, {}]);
st._doFx('player', -1, src, { do: 'down', target: 'enemies', only: 'st_poison' });
assert.ok(st.cardAt('opponent', 0).downed && !st.cardAt('opponent', 1).downed, 'only the POISONED one is Downed');
st = board([], [{ stun_until: 99 }, { stun_until: 99 }, {}]);
morale = st.sides.opponent.morale;
st._doFx('player', -1, src, { do: 'damage', amount: 100, per: 'st_stun' });
assert.equal(st.sides.opponent.morale, morale - 200, '100 for each of 2 STUNNED enemies');

console.log('burn: ok');
