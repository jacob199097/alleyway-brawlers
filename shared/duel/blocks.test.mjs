// Card Forge blocks that move cards and change the rules of a brawl do what their text says:
// loot, top of the deck, exile, swapped ATK / DEF, BOUNTY, LIFESTEAL (shared/duel/DuelState.js;
// duel_state.gd plays the same rules, which the golden test checks).
//   node shared/duel/blocks.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';

CARD_CATALOG.block_grunt = { id: 'block_grunt', name: 'Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 1000, defense: 400, rarity: 1, clanTag: 'test', effectKey: '' };

/** A board in the brawl phase of turn 3, player to act; decks of plain grunts. */
function board(player = [], opponent = []) {
    const st = new DuelState({ player: Array(10).fill('block_grunt'), opponent: Array(10).fill('block_grunt') }, {}, {}, 'player', -1);
    st.turn = 3;
    st.phase = 'brawl';
    for (const [side, cards] of [['player', player], ['opponent', opponent]]) {
        cards.forEach((spec, slot) => {
            if (!spec) return;
            st.sides[side].field[slot] = st.makeCard({ id: 'block_grunt', effectKey: '', ...spec });
        });
    }
    st._recalc();
    st.takeEvents();
    return st;
}
const src = { id: 'src', name: 'Source', cardType: 'hustle', clanTag: 'test' };
const all = (what, extra = {}) => ({ do: what, target: 'enemies', ...extra });

// Loot: draw 2, then discard 2
let st = board();
const hand0 = st.sides.player.hand.length;
st._doFx('player', -1, src, { do: 'loot', amount: 2 });
assert.equal(st.sides.player.hand.length, hand0 + 2, 'drew 2');
const ask = st.pending.kind ? st.pending : st._asks[0];   // (asked once the effect is done)
assert.equal(ask.kind, 'discard');
assert.equal(ask.count, 2, 'then discards 2');

// Top of the deck: off the field, onto the top of its owner's deck (drawn next)
st = board([], [{}]);
const deck0 = st.sides.opponent.deck.length;
const target = st.cardAt('opponent', 0);
st._doFx('player', -1, src, all('topdeck'));
assert.equal(st.cardAt('opponent', 0), null, 'it left the field');
assert.equal(st.sides.opponent.deck.length, deck0 + 1);
assert.equal(st.sides.opponent.deck[st.sides.opponent.deck.length - 1].uid, target.uid, 'on top');
assert.ok(st.takeEvents().some(e => e.type === 'topdeck'));

// Exile: gone, and not in the Gutter
st = board([], [{}]);
st._doFx('player', -1, src, all('exile'));
assert.equal(st.cardAt('opponent', 0), null, 'it left the field');
assert.equal(st.sides.opponent.gutter.length, 0, 'not in the Gutter');
assert.ok(st.takeEvents().some(e => e.type === 'ko' && e.exiled), 'shown leaving');

// Swap: ATK and DEF trade places until the turn ends
st = board([], [{}]);
st._doFx('player', -1, src, all('swap', { until: 'turn' }));
st._recalc();
assert.deepEqual([st.cardAt('opponent', 0).attack, st.cardAt('opponent', 0).defense], [400, 1000], 'swapped');
st.cardAt('opponent', 0).mods = st.cardAt('opponent', 0).mods.filter(m => m.until_turn > st.turn);   // (the turn ends)
st._recalc();
assert.deepEqual([st.cardAt('opponent', 0).attack, st.cardAt('opponent', 0).defense], [1000, 400], 'back after the turn');

// BOUNTY: when the marked enemy is KO'd, whoever marked it draws
st = board([], [{}]);
st._doFx('player', -1, src, all('bounty', { amount: 2 }));
assert.ok(st.statuses(st.cardAt('opponent', 0)).includes('bounty'), 'it shows');
const before = st.sides.player.hand.length;
st._ko('opponent', 0);
assert.equal(st.sides.player.hand.length, before + 2, 'the bounty pays 2 cards');
assert.equal(st.sides.opponent.gutter[0].bounty, undefined, 'and is gone from the card');

// LIFESTEAL: the Morale it takes in a brawl, its owner gains
st = board([{ effects: [{ when: 'passive', do: 'lifesteal' }] }], []);
st.sides.player.morale = 3000;
assert.ok(st._attack('player', 0, DIRECT), 'attacks directly');
assert.equal(st.sides.opponent.morale, 6000 - 1000);
assert.equal(st.sides.player.morale, 4000, 'gained the 1000 it dealt');

// CLEANSE: an ally in STASIS (which nothing else can target) and one POISONED get their statuses back to none
st = board([{}, {}], [{}]);
st.cardAt('player', 0).stasis_until = st.turn + 2;
st.cardAt('player', 1).poison = { amt: 200, left: 3 };
st.cardAt('player', 1).stun_until = st.turn + 1;
assert.ok(st.inStasis(st.cardAt('player', 0)));
st._doFx('player', -1, src, { do: 'cleanse', target: 'allies' });
assert.ok(!st.inStasis(st.cardAt('player', 0)), 'out of STASIS');
assert.deepEqual(st.statuses(st.cardAt('player', 1)), [], 'no POISON or STUN');
assert.equal(st.takeEvents().filter(e => e.type === 'cleanse').length, 2);
assert.ok(!st.fxCan('player', -1, src, { do: 'cleanse', target: 'allies' }), 'nothing left to cleanse: it would do nothing');

// A leader on the field can't be sent to the deck or removed from the game (like back to the hand)
st = board([], [{ cardType: 'leader' }]);
assert.ok(!st.fxCan('player', -1, src, { do: 'topdeck', target: 'enemies' }));
assert.ok(!st.fxCan('player', -1, src, { do: 'exile', target: 'enemies' }));

console.log('blocks: ok');
