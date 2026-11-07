// Rules fixes and additions, 0.9.125: an attacker that promotes on the way hits with its new form's
// stats (Malachar into his "?" level), "when your opponent deploys" offers the character just deployed
// first, INFILTRATE attacks directly past standing characters and Guards, no going-second Authority in
// a free-for-all, and rules.leader_influence (a Turf Defense boss's leader). duel_state.gd plays the
// same rules, which the golden test checks.
//   node shared/duel/rules_fixes.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT, LEADER } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';
import { choose } from './DuelAI.js';

const answer = (st) => {
    while (st.pending && st.pending.kind) {
        st.doAction(st.pending.side, st.pending.kind === 'discard'
            ? { kind: 'discard', uid: st.sides[st.pending.side].hand[0].uid } : { kind: 'choose', option: st.pending.options[0].id });
    }
};
CARD_CATALOG.rf_grunt = { id: 'rf_grunt', name: 'Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 1000, defense: 400, rarity: 1, clanTag: 'test', effectKey: '' };
function duel(first = 'player', opts = {}) {
    const deck = Array(40).fill('rf_grunt');
    const st = new DuelState({ player: deck, opponent: deck }, opts.hideouts || {}, opts.leaders || { player: 'card_unde_001', opponent: 'card_unde_001' }, first, -1, opts.rules || {});
    st.start();
    answer(st);
    st.turn = 3;
    st.phase = 'brawl';
    st.active = first;
    st.takeEvents();
    return st;
}

// Malachar (LV1) promotes as he attacks a leader; his LV2 is "?" (+500 ATK per Underworld character in
// the Gutter): the hit is his new ATK, not 0
let st = duel('player', { hideouts: { player: ['card_unde_015', 'card_unde_016'] } });
st.sides.player.field[0] = st.makeCard({ id: 'card_unde_014' });
st.sides.player.hideout = [st.makeCard({ id: 'card_unde_015' }), st.makeCard({ id: 'card_unde_016' })];
st.sides.player.gutter.push(st.makeCard({ id: 'card_unde_014' }), st.makeCard({ id: 'card_unde_014' }));
st._recalc();
let before = st.sides.opponent.leader.influence;
assert.ok(st.doAction('player', { kind: 'attack', from: 0, target: LEADER }));
answer(st);
assert.equal(st.cardAt('player', 0).id, 'card_unde_015', 'promoted');
assert.equal(before - st.sides.opponent.leader.influence, st.cardAt('player', 0).attack, 'the leader takes his new ATK');
assert.ok(st.cardAt('player', 0).attack > 0);

// Nix LV3: "When your opponent deploys: STASIS one enemy (choose)": the character just deployed first
st = duel('opponent');
st.phase = 'deployment';
st.sides.player.field[1] = st.makeCard({ id: 'card_nebu_006' });
st.sides.opponent.field[0] = st.makeCard({ id: 'rf_grunt' });
st.sides.opponent.authority = 9;
st._recalc();
const newcomer = st.sides.opponent.hand[0];
assert.ok(st.doAction('opponent', { kind: 'summon', uid: newcomer.uid, slot: 2, position: 'atk' }));
assert.equal(st.pending.side, 'player');
assert.equal(st.pending.options[0].slot, 2, 'the one just deployed is offered first');

// INFILTRATE: a direct attack past standing characters, and past a Guard
st = duel();
st.sides.player.field[0] = st.makeCard({ id: 'rf_grunt', effects: [{ when: 'passive', do: 'infiltrate' }] });
st.sides.player.field[1] = st.makeCard({ id: 'rf_grunt' });
st.sides.opponent.field[0] = st.makeCard({ id: 'rf_grunt' });
st._recalc();
assert.ok(st.attackTargets('player', 'opponent', 0).includes(DIRECT), 'INFILTRATE: direct');
assert.ok(!st.attackTargets('player', 'opponent', 1).includes(DIRECT), 'without it: not while they have a standing character');
st.sides.opponent.field[1] = st.makeCard({ id: 'rf_grunt', effects: [{ when: 'passive', do: 'guard' }] });
st._recalc();
assert.deepEqual(st.attackTargets('player', 'opponent', 0).sort(), [DIRECT, 1].sort(), 'past a Guard too');
const morale = st.sides.opponent.morale;
assert.ok(st.doAction('player', { kind: 'attack', from: 0, target: DIRECT }));
answer(st);
assert.equal(st.sides.opponent.morale, morale - 1000, 'it hits their Morale');
assert.ok(!st.doAction('player', { kind: 'attack', from: 1, target: DIRECT }), 'the other one can\'t');

// Free-for-all: no extra Authority for going later (1v1 still has it)
const ffa = new DuelState({ p1: Array(40).fill('rf_grunt'), p2: Array(40).fill('rf_grunt'), p3: Array(40).fill('rf_grunt') }, {}, {}, 'p1', -1, { order: ['p1', 'p2', 'p3'] });
ffa.start();
answer(ffa);
for (let i = 0; i < 20 && ffa.active === 'p1'; i++) { ffa.doAction('p1', { kind: 'next' }); answer(ffa); }
assert.equal(ffa.active, 'p2');
assert.equal(ffa.sides.p2.authority, ffa.sides.p2.authority_max, 'p2: no extra Authority on its first turn');
assert.equal(SECOND_BONUS(), 1, 'a duel still gives the second player 1 extra');
function SECOND_BONUS() {
    const d = new DuelState({ player: Array(40).fill('rf_grunt'), opponent: Array(40).fill('rf_grunt') }, {}, {}, 'player', -1);
    d.start();
    answer(d);
    while (d.active === 'player' && d.winner === '') { d.doAction('player', { kind: 'next' }); answer(d); }
    return d.sides.opponent.authority - d.sides.opponent.authority_max;
}

// rules.leader_influence: that seat's leader starts with k times its Influence
const base = duel('player').sides.opponent.leader.influence;
const boss = duel('player', { rules: { leader_influence: { opponent: 2 } } });
assert.equal(boss.sides.opponent.leader.influence, base * 2);
assert.equal(boss.sides.opponent.leader.influence_max, base * 2);
assert.equal(boss.sides.player.leader.influence, base, 'only that seat');

// The CPU (above Easy) promotes Malachar by attacking the dormant leader rather than finishing a Downed character,
// and deploys him in ATK to do it; a weaker card goes in ATK when it can beat something this turn
st = duel('player');
st.sides.player.field[0] = st.makeCard({ id: 'card_unde_014' });
st.sides.player.hideout = [st.makeCard({ id: 'card_unde_015' }), st.makeCard({ id: 'card_unde_016' })];
st.sides.opponent.field[1] = st.makeCard({ id: 'rf_grunt' });
st.sides.opponent.field[1].downed = true;
st._recalc();
assert.ok(st.leaderDormant('opponent'));
for (const level of ['normal', 'hard']) assert.equal(choose(st, 'player', level).target, LEADER, level + ': attacks the leader to promote');
st.phase = 'deployment';
st.sides.player.field[0] = null;
st.sides.player.hand = [st.makeCard({ id: 'card_unde_014' })];
st.sides.player.authority = 9;
st.sides.opponent.field[2] = st.makeCard({ id: 'card_unde_014' });
st.sides.opponent.field[2].attack = st.sides.opponent.field[2].base_attack = 3000;
st._recalc();
assert.equal(choose(st, 'player', 'normal').position, 'atk', 'Malachar deploys in ATK to promote');
assert.equal(choose(st, 'player', 'easy').position, 'def', 'Easy: by raw strength');
st.sides.player.hideout = [];
st.sides.player.hand = [st.makeCard({ id: 'rf_grunt' })];
st.sides.opponent.field[1] = null;
st._recalc();
assert.equal(choose(st, 'player', 'normal').position, 'def', 'nothing it can beat: DEF');
st.sides.opponent.field[3] = st.makeCard({ id: 'rf_grunt' });
st.sides.opponent.field[3].attack = st.sides.opponent.field[3].base_attack = 800;
st._recalc();
assert.equal(st.cardAt('opponent', 3).attack, 800);
assert.equal(choose(st, 'player', 'normal').position, 'atk', 'a trade: it can down the 800 now');

console.log('Rules fixes (promote-then-hit, deployed first, INFILTRATE, FFA Authority, boss Influence, CPU promotes and trades): all good');
