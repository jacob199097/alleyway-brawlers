// Luck (Card Forge): coin flips and die rolls decide whether an effect happens
// (shared/duel/DuelState.js _luckGate; duel_state.gd rolls the same, which the golden test checks).
//   node shared/duel/luck.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';

const grunt = { id: 'luck_grunt', name: 'Lucky', cardType: 'gang_member', clanTag: 'test', attack: 500, defense: 500 };
const fresh = (seed = 7) => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', seed);
    st.turn = 3;
    st.phase = 'deployment';
    st.sides.player.morale = 3000;
    return st;
};
const lucks = (st) => st.takeEvents().filter(e => e.type === 'luck');

// A coin: heads (1) and the effect happens, tails (0) and it doesn't; every flip is announced
let st = fresh();
let heads = 0, tails = 0;
for (let i = 0; i < 200; i++) {
    const before = st.sides.player.morale;
    st._doFx('player', -1, grunt, { do: 'heal', amount: 100, luck: 'coin' });
    const [ev] = lucks(st);
    assert.equal(ev.kind, 'coin');
    assert.equal(ev.won, ev.value === 1);
    assert.equal(st.sides.player.morale - before, ev.won ? 100 : 0, 'heals on heads only');
    if (ev.won) heads++; else tails++;
    st.sides.player.morale = 3000;
}
assert.ok(heads > 70 && tails > 70, `a fair coin (${heads} heads, ${tails} tails)`);

// A die needing 4+: it happens on 4, 5 or 6
st = fresh();
const faces = new Set();
for (let i = 0; i < 120; i++) {
    st._doFx('player', -1, grunt, { do: 'heal', amount: 100, luck: 'die', luck_on: 4 });
    const [ev] = lucks(st);
    assert.ok(ev.value >= 1 && ev.value <= 6);
    assert.equal(ev.won, ev.value >= 4);
    faces.add(ev.value);
}
assert.equal(faces.size, 6, 'every face comes up');

// "If tails": no roll of its own, it follows the last one
st = fresh();
for (let i = 0; i < 40; i++) {
    st.sides.player.morale = 3000;
    st._doFx('player', -1, grunt, { do: 'heal', amount: 100, luck: 'coin' });
    st._doFx('player', -1, grunt, { do: 'heal', amount: 1000, if_luck: 'lost' });
    const ev = lucks(st);
    assert.equal(ev.length, 1, 'one flip for both effects');
    assert.equal(st.sides.player.morale, ev[0].won ? 3100 : 4000, 'heads heals 100, tails 1000');
}
assert.equal(fresh()._luckGate('player', -1, grunt, { if_luck: 'won' }), false, 'nothing to follow before a roll');

// For each pip: the effect is multiplied by the die
st = fresh();
for (let i = 0; i < 30; i++) {
    st.sides.player.morale = 1000;
    st._doFx('player', -1, grunt, { do: 'heal', amount: 100, per: 'roll' });
    const [ev] = lucks(st);
    assert.equal(st.sides.player.morale - 1000, 100 * ev.value, 'heals 100 per pip');
}

// The same seed rolls the same (replays, the server and the game agree)
const seq = (seed) => { const s = fresh(seed); return Array.from({ length: 12 }, () => (s._luckGate('player', -1, grunt, { luck: 'die' }), s._roll)); };
assert.deepEqual(seq(42), seq(42));
assert.notDeepEqual(seq(42), seq(43));

console.log('luck: ok');
