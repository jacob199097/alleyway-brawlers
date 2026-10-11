// Each Card Forge passive does what its card text says (shared/duel/DuelState.js; duel_state.gd
// plays the same rules, which the golden test checks).
//   node shared/duel/passives.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT } from './DuelState.js';

/** A board in the brawl phase of turn 3, player to act, with these cards on the field. */
function board(player = [], opponent = []) {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 3;
    st.phase = 'brawl';
    for (const [side, cards] of [['player', player], ['opponent', opponent]]) {
        cards.forEach((spec, slot) => {
            if (!spec) return;
            const c = st.makeCard({ id: 'lion_grunt', effectKey: '', clanTag: 'lion', ...spec });
            for (const k of ['position', 'face_down', 'downed']) if (k in spec) c[k] = spec[k];   // makeCard resets these
            st.sides[side].field[slot] = c;
        });
    }
    st._recalc();
    return st;
}
const passive = (kind, extra = {}) => ({ effects: [{ when: 'passive', do: kind, ...extra }] });

// Guard: a standing Guard must be attacked first; a Downed one doesn't protect
let st = board([{}], [{}, passive('guard')]);
assert.deepEqual(st.attackTargets('player'), [1], 'only the Guard can be attacked');
st.cardAt('opponent', 1).downed = true;
assert.ok(st.attackTargets('player').includes(0), 'a Downed Guard protects no one');

// Attacks twice each turn
st = board([passive('double_attack')], []);
assert.ok(st._attack('player', 0, DIRECT), 'first attack');
assert.ok(st.canAttackWith('player', 0), 'ready for a second attack');
assert.ok(st._attack('player', 0, DIRECT), 'second attack');
assert.ok(!st.canAttackWith('player', 0), 'no third attack');

// PIERCE always: beating a DEF character also costs the opponent Morale (without it, nothing)
const moraleLost = (spec) => {
    const b = board([{ attack: 2000, ...spec }], [{ defense: 500, position: 'def' }]);
    const before = b.sides.opponent.morale;
    b._attack('player', 0, 0);
    return before - b.sides.opponent.morale;
};
assert.equal(moraleLost({}), 0, 'beating a DEF character costs no Morale');
assert.ok(moraleLost(passive('pierce')) > 0, 'with PIERCE it does');

// Cheaper cards: your (clan) cards cost less, never below 0
st = board([passive('cost_down', { amount: 2 }), passive('cost_down', { amount: 1, clan: 'nebula' })]);
assert.equal(st.costOf('player', { authority: 5, clanTag: 'lion' }), 3);
assert.equal(st.costOf('player', { authority: 5, clanTag: 'nebula' }), 2);
assert.equal(st.costOf('player', { authority: 1, clanTag: 'lion' }), 0);
assert.equal(st.costOf('opponent', { authority: 5, clanTag: 'lion' }), 5, "the opponent's cards cost the same");

// Stays up while you control another character
st = board([passive('no_down'), {}]);
assert.equal(st._defeat('player', 0), 'saved', 'stays standing with an ally');
st.sides.player.field[1] = null;
assert.equal(st._defeat('player', 0), 'downed', 'alone, it can be Downed');

// Immune: statuses don't land
st = board([{ effects: [{ when: 'deploy', do: 'poison', target: 'enemies', amount: 200 }] }], [passive('immune'), {}]);
st._doFx('player', 0, st.cardAt('player', 0), st.cardAt('player', 0).effects[0]);
assert.equal(st.cardAt('opponent', 0).poison, undefined, 'immune card is not POISONED');
assert.ok(st.cardAt('opponent', 1).poison, 'the other card is');

// Can't be targeted: an opponent's effect can't choose it (but "all enemies" still hits it)
st = board([{}], [passive('untargetable')]);
let chosen = null;
st._askTarget('player', 'fx', 'choose', st.cardAt('player', 0), [{ side: 'opponent', slot: 0, card: st.cardAt('opponent', 0) }], 'opponent', (e) => { chosen = e; });
assert.equal(chosen, null, 'not chosen by the opponent');
st._askTarget('opponent', 'fx', 'choose', st.cardAt('opponent', 0), [{ side: 'opponent', slot: 0, card: st.cardAt('opponent', 0) }], 'opponent', (e) => { chosen = e; });
assert.ok(chosen, 'its owner can still choose it');

// Enemy auras: a passive can weaken the other side's characters
st = board([{ attack: 1000 }], [passive('buff', { target: 'enemies', atk: -300 })]);
assert.equal(st.cardAt('player', 0).attack, 700, 'enemy aura lowers ATK');
st = board([{ attack: 1000, clanTag: 'lion' }], [passive('buff', { target: 'enemies', atk: -300, clan: 'nebula' })]);
assert.equal(st.cardAt('player', 0).attack, 1000, 'clan filter respected');

// A face-down card's passives are off
st = board([{}], [{ ...passive('guard'), face_down: true }, {}]);
assert.ok(st.attackTargets('player').includes(1), 'face-down Guard does nothing');

console.log('all good');
