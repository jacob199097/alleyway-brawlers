// Free-for-all rules (3-4 players; shared/duel/DuelState.js, the same as duel_state.gd): turn order,
// attacks on a chosen opponent, every-opponent effects, choosing an opponent, eliminations, places,
// round-long durations, and whole CPU games to the end.
//   node shared/duel/ffa.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT } from './DuelState.js';
import { choose, cpuSetup } from './DuelAI.js';
import { CARD_CATALOG } from '../cards.js';

CARD_CATALOG.test_grunt = { id: 'test_grunt', name: 'Test Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 700, defense: 500, rarity: 1, clanTag: 'test', effectKey: '' };
const SEATS = ['p1', 'p2', 'p3', 'p4'];

/** A 4-player board in the brawl phase of turn 5 (everyone has had a turn), p1 to act. */
function board(fields = {}, seats = SEATS) {
    const st = new DuelState(Object.fromEntries(seats.map(s => [s, Array(10).fill('test_grunt')])), {}, {}, seats[0], -1);
    st.turn = 5;
    st.phase = 'brawl';
    for (const s of seats) st.sides[s].turns = 1;
    for (const [side, cards] of Object.entries(fields)) {
        cards.forEach((spec, slot) => {
            if (!spec) return;
            const c = st.makeCard({ id: 'test_grunt', effectKey: '', ...spec });
            for (const k of ['position', 'face_down', 'downed']) if (k in spec) c[k] = spec[k];
            st.sides[side].field[slot] = c;
        });
    }
    st._recalc();
    return st;
}
const fx = (when, extra) => ({ effects: [{ when, ...extra }] });

// ── Seats and turn order ──
let st = board();
assert.ok(st.ffa, 'four decks make a free-for-all');
assert.deepEqual(st.foesOf('p1'), ['p2', 'p3', 'p4'], "p1's opponents, in turn order");
assert.deepEqual(st.foesOf('p3'), ['p4', 'p1', 'p2'], "p3's opponents start with the next player");
assert.equal(st._nextSeat('p4'), 'p1', 'turn order wraps round');
// (seat order comes from the names, not the order the decks are given in)
assert.deepEqual(new DuelState({ p3: [], p1: [], p2: [] }, {}, {}, 'p1', -1).seats, ['p1', 'p2', 'p3']);

// ── No attacks until everyone has had a turn (the whole first round) ──
st = board({ p4: [{}], p1: [{}] });
st.active = 'p4';
st.turn = 4;   // the last player's first turn
assert.ok(st.noAttacksYet() && !st.canAttackWith('p4', 0), "the fourth player's first turn: no attacks yet");
st.turn = 5;   // round two
st.active = 'p1';
assert.ok(!st.noAttacksYet() && st.canAttackWith('p1', 0), 'from round two, attacks');
st = board({}, ['p1', 'p2', 'p3']);
st.turn = 3;
assert.ok(st.noAttacksYet(), 'three players: their first three turns');

// ── Attacks go at a chosen opponent ──
st = board({ p1: [{ attack: 2000 }], p3: [{ attack: 500 }] });
assert.deepEqual(st.attackTargets('p1', 'p2'), [DIRECT], 'p2 has nobody standing: a direct attack');
assert.deepEqual(st.attackTargets('p1', 'p3'), [0], "p3's character must be fought first");
assert.ok(!st.doAction('p1', { kind: 'attack', from: 0, target: 0, foe: 'p1' }), "you can't attack yourself");
assert.ok(st.doAction('p1', { kind: 'attack', from: 0, target: DIRECT, foe: 'p4' }), 'attack p4 directly');
assert.equal(st.sides.p4.morale, 6000 - 2000, 'p4 lost the Morale');
assert.equal(st.sides.p2.morale, 6000, 'nobody else did');
const att = st.takeEvents().find(e => e.type === 'attack');
assert.equal(att.foe, 'p4', 'the attack event says who it went at');

// ── "Enemies" means every opponent; "an enemy" can be any of their cards ──
st = board({ p1: [fx('deploy', { do: 'down', target: 'enemies' })], p2: [{}], p3: [{}, {}], p4: [{}] });
st._doFx('p1', 0, st.cardAt('p1', 0), st.cardAt('p1', 0).effects[0]);
assert.ok(['p2', 'p3', 'p4'].every(s => st.characters(s).every(x => x.card.downed)), 'every opponent is hit');
st = board({ p1: [fx('deploy', { do: 'ko', target: 'enemy' })], p2: [{ attack: 900 }], p4: [{ attack: 1500 }] });
st._doFx('p1', 0, st.cardAt('p1', 0), st.cardAt('p1', 0).effects[0]);
st._flushAsks();
assert.equal(st.pending.key, 'fx', 'the player picks the card');
assert.deepEqual(st.pending.options.map(o => o.id), ['p4:0', 'p2:0', 'skip'], "cards on several boards are named side:slot, best first");
assert.ok(st.doAction('p1', { kind: 'choose', option: 'p2:0' }));
assert.equal(st.cardAt('p2', 0), null, "p2's card is KO'd");
assert.ok(st.cardAt('p4', 0), "p4's isn't");

// ── "When an enemy character is KO'd": every opponent's cards notice ──
st = board({ p1: [{}], p2: [fx('foe_ko', { do: 'heal', amount: 500 })], p3: [fx('foe_ko', { do: 'heal', amount: 500 })] });
for (const s of ['p2', 'p3']) st.sides[s].morale = 5000;
st._ko('p1', 0);
assert.equal(st.sides.p2.morale, 5500);
assert.equal(st.sides.p3.morale, 5500);

// ── "Your opponent" effects: the one in the brawl, or the one the player chooses ──
st = board({ p1: [fx('deploy', { do: 'damage', amount: 300 })], p2: [{}], p3: [{}] });
st.sides.p3.morale = 2000;
st._doFx('p1', 0, st.cardAt('p1', 0), st.cardAt('p1', 0).effects[0]);
st._flushAsks();
assert.equal(st.pending.key, 'foe', 'outside a brawl, the player chooses the opponent');
assert.deepEqual(st.pending.options.map(o => o.id), ['p3', 'p2', 'p4'], 'lowest Morale first');
assert.ok(st.doAction('p1', { kind: 'choose', option: 'p2' }));
assert.equal(st.sides.p2.morale, 5700, 'p2 takes the damage');
st = board({ p1: [{ attack: 2000, effects: [{ when: 'attack', do: 'damage', amount: 300 }] }], p3: [{ attack: 100 }] });
assert.ok(st.doAction('p1', { kind: 'attack', from: 0, target: 0, foe: 'p3' }));
assert.equal(st.pending.key, undefined, 'no question in a brawl');
assert.equal(st.sides.p3.morale, 6000 - 300 - 1900, 'the opponent being attacked takes it');

// ── Elimination: out in last place, cards gone, skipped in turn order; last one standing wins ──
st = board({ p1: [{ attack: 2000 }, { attack: 2000 }], p2: [{}], p3: [{}] });
st.sides.p4.morale = 1000;
assert.ok(st.doAction('p1', { kind: 'attack', from: 0, target: DIRECT, foe: 'p4' }));
assert.equal(st.sides.p4.out, 4, 'the first one out finishes 4th');
assert.deepEqual(st.foesOf('p1'), ['p2', 'p3'], 'p4 is no longer an opponent');
assert.ok(st.takeEvents().some(e => e.type === 'eliminated' && e.side === 'p4' && e.place === 4));
assert.equal(st.winner, '', 'the game goes on');
st.sides.p2.morale = 500;
st.sides.p2.field[0] = null;
assert.ok(st.doAction('p1', { kind: 'attack', from: 1, target: DIRECT, foe: 'p2' }));
assert.equal(st.sides.p2.out, 3);
assert.equal(st._nextSeat('p1'), 'p3', 'the turn passes over players who are out');
st.sides.p3.morale = 1;
st._damage('p3', 5);
assert.equal(st.winner, 'p1', 'the last one standing wins');
assert.deepEqual(st.places, { p4: 4, p2: 3, p3: 2, p1: 1 });

// The active player going out ends their turn: the next player's begins
st = board({ p1: [{ attack: 100 }], p2: [{ attack: 3000 }] });
st.sides.p1.morale = 1000;
assert.ok(st.doAction('p1', { kind: 'attack', from: 0, target: 0, foe: 'p2' }));
assert.ok(st.sides.p1.out, 'p1 lost the brawl and their last Morale');
assert.equal(st.active, 'p2', "p2's turn begins");
assert.ok(st.characters('p1').length === 0, "p1's cards have left");

// ── Durations: "until the next turn" lasts the whole round; owner's next turn counts seats ──
st = board();
assert.equal(st._until({ until: 'next_turn' }), 5 + 3, 'through all three opponents');
assert.equal(st._ownerNextTurn('p1'), 5 + 4, "the active player's next turn is a full round away");
assert.equal(st._ownerNextTurn('p3'), 5 + 2);

// ── Authority: +1 each turn after your first; later seats get +1 on their first turn ──
st = new DuelState(Object.fromEntries(SEATS.map(s => [s, Array(20).fill('test_grunt')])), {}, {}, 'p1', -1);
st.start();
while (st.pending.kind) st.doAction(st.pending.side, { kind: 'choose', option: 'keep' });
const firstTurn = {};
for (let i = 0; i < 6; i++) {
    firstTurn[st.active] ??= st.sides[st.active].authority;
    st.doAction(st.active, { kind: 'next' });
    while (st.active && st.pending.kind === 'discard') st.doAction(st.pending.side, { kind: 'discard', uid: st.sides[st.pending.side].hand[0].uid });
    while (st.phase !== 'deployment' && st.canAct(st.active)) st.doAction(st.active, { kind: 'next' });
}
assert.deepEqual(firstTurn, { p1: 1, p2: 2, p3: 2, p4: 2 }, 'going later: one extra Authority on the first turn');
assert.equal(st.sides.p1.authority_max, 2, "p1's second turn: 2 max Authority");

// ── Whole CPU games, 3 and 4 players, to the end ──
for (let g = 0; g < 24; g++) {
    const seats = SEATS.slice(0, g % 2 ? 3 : 4);
    const clans = ['nebula', 'militia'];
    const setups = Object.fromEntries(seats.map((s, i) => [s, cpuSetup(clans[(g + i) % 2])]));
    const game = new DuelState(Object.fromEntries(seats.map(s => [s, setups[s].deck])),
        Object.fromEntries(seats.map(s => [s, setups[s].hideout])), Object.fromEntries(seats.map(s => [s, setups[s].leader])),
        seats[g % seats.length], 1000 + g);
    game.start();
    let moves = 0;
    while (game.winner === '' && moves < 6000) {
        const who = game.pending.side || game.active;
        let a = choose(game, who, ['easy', 'normal', 'hard'][g % 3]);
        if (!Object.keys(a).length || !game.doAction(who, a)) {
            a = { kind: 'next' };
            assert.ok(game.doAction(who, a), `game ${g}: ${who} can always move on (${JSON.stringify(game.pending)})`);
        }
        moves += 1;
    }
    assert.notEqual(game.winner, '', `game ${g} (${seats.length} players) finished`);
    assert.equal(Object.keys(game.places).length, seats.length, `game ${g}: everyone has a place`);
    assert.deepEqual(Object.values(game.places).sort(), seats.map((_, i) => i + 1), `game ${g}: places 1..${seats.length}`);
}

console.log('FFA rules: all good');
