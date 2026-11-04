// PLUNDER (an opponent's card becomes yours: from their hand, deck, Gutter or field) and Gutter
// abilities (Card Forge "When: In your Gutter": used from your Gutter on your turn, once a turn each,
// paying a cost; exile_self: the card leaves the game). shared/duel/DuelState.js; duel_state.gd plays
// the same rules, which the golden test checks.
//   node shared/duel/plunder.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';

CARD_CATALOG.pl_grunt = { id: 'pl_grunt', name: 'Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 1000, defense: 400, rarity: 1, clanTag: 'test', effectKey: '' };

/** A board in the deployment phase of turn 3, player to act, with hands and Gutters as given. */
function board({ player = [], opponent = [], hand = {}, gutter = {} } = {}) {
    const st = new DuelState({ player: Array(10).fill('pl_grunt'), opponent: Array(10).fill('pl_grunt') }, {}, {}, 'player', -1);
    st.turn = 3;
    st.phase = 'deployment';
    for (const [side, cards] of [['player', player], ['opponent', opponent]]) {
        cards.forEach((spec, slot) => { if (spec) st.sides[side].field[slot] = st.makeCard({ id: 'pl_grunt', effectKey: '', ...spec }); });
        st.sides[side].hand = (hand[side] || []).map(spec => st.makeCard({ id: 'pl_grunt', effectKey: '', ...spec }));
        st.sides[side].gutter = (gutter[side] || []).map(spec => st.makeCard({ id: 'pl_grunt', effectKey: '', ...spec }));
    }
    st.sides.player.authority = 5;
    st._recalc();
    st.takeEvents();
    return st;
}
const src = { id: 'src', name: 'Hook', cardType: 'hustle', clanTag: 'pirates' };
const answer = (st, pick = (a) => a.options[0].id) => {
    const ask = st._asks.find(a => a.side === 'player');
    assert.ok(ask, 'asked');
    st._runAnswer(() => ask.cb(pick(ask)));
    return ask;
};

// From the hand (random): one of their cards moves to yours, shown to everyone
let st = board({ hand: { opponent: [{ name: 'A' }, { name: 'B' }] } });
st._doFx('player', -1, src, { do: 'plunder', from: 'hand' });
assert.equal(st.sides.opponent.hand.length, 1, 'their hand loses one');
assert.equal(st.sides.player.hand.length, 1, 'yours gains it');
let ev = st.takeEvents().find(e => e.type === 'plunder');
assert.ok(ev && ev.from === 'hand' && ev.from_side === 'opponent' && ev.card.name, 'a plunder event with the card');

// From the hand, choose: look at it and pick (the strongest first)
st = board({ hand: { opponent: [{ name: 'Small', authority: 1 }, { name: 'Big', authority: 6 }] } });
st._doFx('player', -1, src, { do: 'plunder', from: 'hand', choose: true });
const ask = answer(st);
assert.equal(ask.options[0].card.name, 'Big', 'the strongest card is offered first');
assert.equal(st.sides.player.hand[0].name, 'Big');

// From the deck: the top cards
st = board();
const top = st.sides.opponent.deck.at(-1);
st._doFx('player', -1, src, { do: 'plunder', from: 'deck', amount: 2 });
assert.equal(st.sides.player.hand.length, 2, 'two from the deck');
assert.ok(st.sides.player.hand.includes(top), 'the top card first');

// From the Gutter: an UNDEAD card waiting to rise is taken before it can (the Underworld counter); no tokens
st = board({ gutter: { opponent: [{ name: 'Bones', token: true }, { name: 'Ghoul', rise_turn: 3 }] } });
st._doFx('player', -1, src, { do: 'plunder', from: 'gutter' });
assert.deepEqual(st.sides.player.hand.map(c => c.name), ['Ghoul'], 'the Ghoul, not the token');
assert.equal(st.sides.player.hand[0].rise_turn, undefined, 'it won\'t rise');
assert.deepEqual(st.sides.opponent.gutter.map(c => c.name), ['Bones']);
st = board({ gutter: { opponent: [{ name: 'Bones', token: true }] } });
assert.equal(st.fxCan('player', -10, src, { do: 'plunder', from: 'gutter' }), false, 'nothing but a token: nothing to plunder');

// From the field: one of their characters is yours for good (not a leader), can't attack this turn
st = board({ opponent: [{ name: 'Brute', attack: 2000 }] });
st._doFx('player', -1, src, { do: 'plunder', from: 'field', target: 'enemy' });
answer(st);
assert.equal(st.cardAt('opponent', 0), null, 'gone from their side');
const stolen = st.characters('player').find(x => x.card.name === 'Brute');
assert.ok(stolen, 'on yours');
assert.ok(stolen.card.has_attacked && !stolen.card.charmed, 'for good, attacking from next turn');
st.cardAt('player', stolen.slot).defense = 0;
st._ko('player', stolen.slot);
assert.ok(st.sides.player.gutter.some(c => c.name === 'Brute'), 'KO\'d, it goes to the plunderer\'s Gutter');
st = board({ player: [{}, {}, {}, {}, {}], opponent: [{}] });
assert.equal(st.fxCan('player', -10, src, { do: 'plunder', from: 'field', target: 'enemy' }), false, 'no room: can\'t');

// Gutter abilities: from the Gutter, on your turn, once a turn each
const ghost = (cost, extra = {}) => ({ name: 'Ghost', effects: [{ when: 'gutter', do: 'damage', amount: 300, cost, cost_n: 2, ...extra }] });
st = board({ gutter: { player: [ghost('authority')] } });
const uid = st.sides.player.gutter[0].uid;
assert.deepEqual(st.gutterActivations('player', uid), [1], 'usable');
let morale = st.sides.opponent.morale;
assert.ok(st.doAction('player', { kind: 'gutter', uid, fx: 1 }));
assert.equal(st.sides.opponent.morale, morale - 300, 'it happens');
assert.equal(st.sides.player.authority, 3, 'paid 2 Authority');
assert.deepEqual(st.gutterActivations('player', uid), [], 'once a turn');
st.turn = 5;
assert.deepEqual(st.gutterActivations('player', uid), [1], 'again on a later turn');
st.active = 'opponent';
assert.deepEqual(st.gutterActivations('player', uid), [], 'not on the opponent\'s turn');

// exile_self: the card leaves the game to do it
st = board({ gutter: { player: [ghost('exile_self')] } });
assert.ok(st.doAction('player', { kind: 'gutter', uid: st.sides.player.gutter[0].uid, fx: 1 }));
assert.equal(st.sides.player.gutter.length, 0, 'exiled');
assert.ok(st.takeEvents().some(e => e.type === 'gutter_exile'), 'shown leaving the Gutter');

// exile_gutter (other cards) doesn't count the card itself
st = board({ gutter: { player: [ghost('exile_gutter'), {}] } });
assert.deepEqual(st.gutterActivations('player', st.sides.player.gutter[0].uid), [], 'one other card: not enough for 2');

// A Hustle's Gutter ability doesn't happen when it's played (only from the Gutter)
st = board();
const h = st.makeCard({ id: 'pl_grunt', name: 'Spook', cardType: 'hustle', authority: 0,
    effects: [{ do: 'draw', amount: 1 }, { when: 'gutter', do: 'damage', amount: 500, cost: 'exile_self' }] });
st.sides.player.hand = [h];
morale = st.sides.opponent.morale;
assert.ok(st.doAction('player', { kind: 'hustle', uid: h.uid }));
assert.equal(st.sides.opponent.morale, morale, 'no damage when played');
assert.ok(st.sides.player.gutter.includes(h), 'in the Gutter');
assert.deepEqual(st.gutterActivations('player', h.uid), [1], 'now usable from there');

console.log('PLUNDER and Gutter abilities: all good');
