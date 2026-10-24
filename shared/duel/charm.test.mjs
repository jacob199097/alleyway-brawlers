// CHARM, UNDEAD, "PROMOTE one of your Strivers", a Heavy's tribute damage, "that character" (the one
// just deployed), flipping Continuous Ambushes (shared/duel/DuelState.js; duel_state.gd plays the same
// rules, which the golden test checks).
//   node shared/duel/charm.test.mjs
import assert from 'node:assert';
import { DuelState, BACK } from './DuelState.js';
import { choose } from './DuelAI.js';

const duel = () => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 5;
    st.phase = 'deployment';
    st.active = 'player';
    return st;
};
const unit = (st, name, atk = 1000, def = 1000, extra = {}) =>
    st.makeCard({ id: 'test_' + name.toLowerCase(), name, cardType: 'gang_member', clanTag: 'test', attack: atk, defense: def, ...extra });
const answer = (st, option) => { const a = st._asks.shift(); st._runAnswer(() => a.cb(option ?? a.options[0].id)); return a; };
const src = { name: 'Siren', uid: 'x' };

// CHARM: the enemy character comes over for the turn (it can attack), then goes back to its own lane
let st = duel();
const brute = unit(st, 'Brute', 2000, 1500);
brute.has_attacked = true;
st.sides.opponent.field[2] = brute;
st._doFx('player', -1, src, { do: 'charm', target: 'enemy' });
answer(st, '2');
assert.equal(st.sides.opponent.field[2], null, 'it left its owner');
assert.equal(st.sides.player.field[0], brute, "it's in your first empty lane");
assert.ok(brute.charmed && !brute.has_attacked, 'charmed, and ready to attack');
assert.ok(st.statuses(brute).includes('charm'));
st._turnOver();
assert.equal(st.sides.player.field[0], null);
assert.equal(st.sides.opponent.field[2], brute, 'the turn over: back in its own lane');
assert.ok(!brute.charmed);
// KO'd while charmed: to its owner's Gutter
st = duel();
const pawn = unit(st, 'Pawn');
st.sides.opponent.field[1] = pawn;
st._doFx('player', -1, src, { do: 'charm', target: 'enemy' });
answer(st, '1');
st._ko('player', 0);
assert.ok(st.sides.opponent.gutter.includes(pawn) && !st.sides.player.gutter.includes(pawn), "KO'd: its owner's Gutter");
// no room on your side: nothing happens
st = duel();
for (const l of [0, 1, 2, 3, 4]) st.sides.player.field[l] = unit(st, 'Mine' + l);
st.sides.opponent.field[0] = unit(st, 'Far');
assert.equal(st.fxCan('player', -1, src, { do: 'charm', target: 'enemy' }), false, 'no empty lane: CHARM can do nothing');

// UNDEAD: the first KO, it rises at the end of the turn, in DEF with half its ATK and DEF; the second, it stays
st = duel();
const ghoul = unit(st, 'Ghoul', 1600, 1200, { effects: [{ when: 'passive', do: 'undead' }] });
st.sides.player.field[3] = ghoul;
st._ko('player', 3);
assert.ok(st.sides.player.gutter.includes(ghoul));
st._turnOver();
const back = st.sides.player.field.find(c => c === ghoul);
assert.ok(back, 'it rose');
assert.equal(ghoul.position, 'def');
assert.deepEqual([ghoul.attack, ghoul.defense], [800, 600], 'half its ATK and DEF');
st._ko('player', st.sides.player.field.indexOf(ghoul));
st._turnOver();
assert.ok(st.sides.player.gutter.includes(ghoul), 'only once');

// A Heavy's tribute damage: the ATK of the characters it sacrificed
st = duel();
st.sides.opponent.morale = 6000;
const heavy = unit(st, 'Heavy', 3000, 3000, { subtype: 'heavy', tributeCost: 1 });
heavy.tribute_atk = 1800;
st._doFx('player', 0, heavy, { do: 'tribute_damage' });
assert.equal(st.sides.opponent.morale, 4200);

// PROMOTE one of your Strivers (Kade LV1 -> LV2)
st = duel();
const kade = st.makeCard('card_nebu_001');
st.sides.player.field[0] = kade;
st._doFx('player', -1, src, { do: 'promote_ally', target: 'ally' });
answer(st, '0');          // which Striver
answer(st, 'atk');        // its position
assert.equal(st.sides.player.field[0].id, 'card_nebu_002', 'it promoted');

// "that character": a deploy trigger aims at the character just deployed
st = duel();
const watcher = unit(st, 'Watcher', 500, 500, { effects: [{ when: 'foe_deployed', do: 'swap', target: 'deployed', until: 'turn' }] });
st.sides.player.field[0] = watcher;
const newcomer = unit(st, 'Newcomer', 2000, 400);
st.sides.opponent.field[1] = newcomer;
st._runFx('player', 0, watcher, 'foe_deployed', newcomer);
st._recalc();
assert.deepEqual([newcomer.attack, newcomer.defense], [400, 2000], 'that character swapped');

// Flipping a Continuous Ambush: from the turn after it was set; its "when sprung" effects happen
st = duel();
st.sides.player.morale = 3000;
const wall = st.makeCard({ id: 'test_wall', name: 'Wall', cardType: 'ambush', subtype: 'continuous', clanTag: 'test',
    effects: [{ when: 'defend', do: 'heal', amount: 500 }] });
wall.face_down = true;
wall.set_turn = st.turn;
st.sides.player.field[BACK[0]] = wall;
assert.equal(st.canFlip('player', BACK[0]), false, 'not the turn it was set');
st.turn += 2;
assert.ok(st.canFlip('player', BACK[0]));
assert.deepEqual(choose(st, 'player'), { kind: 'flip', slot: BACK[0] }, 'the CPU flips it');
assert.ok(st.doAction('player', { kind: 'flip', slot: BACK[0] }));
assert.ok(!wall.face_down && st.sides.player.field[BACK[0]] === wall, 'face-up, and it stays');
assert.equal(st.sides.player.morale, 3500, 'its effects happened');
// ...and on the opponent's turn it's offered at the start of their turn
st = duel();
const trap = st.makeCard({ id: 'test_trap', name: 'Trap', cardType: 'ambush', subtype: 'continuous', clanTag: 'test', effects: [{ when: 'defend', do: 'draw', amount: 1 }] });
trap.face_down = true;
trap.set_turn = 1;
st.sides.opponent.field[BACK[1]] = trap;
st._asks = [];
st._offerFlips();
const offer = st._asks.find(a => a.key === 'flip');
assert.ok(offer && offer.side === 'opponent' && offer.options[0].id === 'no', "offered to its owner on the other player's turn");

console.log('charm: ok');
