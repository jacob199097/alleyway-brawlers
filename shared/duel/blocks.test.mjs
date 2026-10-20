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

// Loot with its own discard count: draw 3, then discard 1 (or none)
st = board();
const hand1 = st.sides.player.hand.length;
st._doFx('player', -1, src, { do: 'loot', amount: 3, discard_n: 1 });
assert.equal(st.sides.player.hand.length, hand1 + 3, 'drew 3');
assert.equal((st.pending.kind ? st.pending : st._asks[0]).count, 1, 'then discards 1');
st = board();
st._doFx('player', -1, src, { do: 'loot', amount: 2, discard_n: 0 });
assert.ok(!st.pending.kind && !st._asks.length, 'discard 0: nothing to discard');

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

// Attacking a DEF character and falling short costs the difference in Morale (as against ATK);
// beating it doesn't (unless the attack pierces)
st = board([{}], [{ defense: 1500 }]);
st.cardAt('opponent', 0).position = 'def';
st._recalc();
assert.ok(st._attack('player', 0, 0), 'attacks the DEF card');
assert.equal(st.sides.player.morale, 6000 - 500, 'lost 1500 - 1000 = 500 Morale');
assert.ok(st.cardAt('opponent', 0) && !st.cardAt('opponent', 0).downed, 'and the defender is fine');

// "Only ones ...": KO one enemy with a status passes over the healthy one; bounce all in DEF leaves ATK ones
st = board([], [{}, {}]);
st.cardAt('opponent', 1).poison = { amt: 100, left: 2 };
st._doFx('player', -1, src, all('ko', { only: 'statused' }));
assert.ok(st.cardAt('opponent', 0) && !st.cardAt('opponent', 1), 'only the POISONED one is KO\'d');
st = board([], [{}, {}]);
st.cardAt('opponent', 0).position = 'def';
st._doFx('player', -1, src, all('bounce', { only: 'def' }));
assert.ok(!st.cardAt('opponent', 0) && st.cardAt('opponent', 1), 'only the DEF one went back to the hand');
assert.ok(!st.fxCan('player', -1, src, all('bounce', { only: 'def' })), 'none left in DEF: it would do nothing');

// REWIND: an enemy's gains are undone; one already weakened isn't picked (that would help it)
st = board([], [{}, {}]);
st.cardAt('opponent', 0).mods.push({ atk: 500, def: 0, until_turn: 99 });
st.cardAt('opponent', 1).mods.push({ atk: -500, def: 0, until_turn: 99 });
st._recalc();
st._doFx('player', -1, src, all('rewind'));
assert.equal(st.cardAt('opponent', 0).attack, 1000, 'back to its printed 1000 ATK');
assert.equal(st.cardAt('opponent', 1).attack, 500, 'the weakened one keeps its -500');

// BARRICADE: soaks Morale damage until its owner's next turn; Morale paid as a cost goes past it
st = board();
st._doFx('player', -1, src, { do: 'barricade', amount: 800 });
st._damage('player', 1000);
assert.equal(st.sides.player.morale, 6000 - 200, '800 of the 1000 held back');
assert.equal(st.sides.player.barricade, 0, 'and it is spent');
st._doFx('player', -1, src, { do: 'barricade', amount: 500 });
st._damage('player', 300, true);
assert.equal(st.sides.player.morale, 5800 - 300, 'a paid cost is not blocked');

// JAM: the opponent can't spring an Ambush until the end of their next turn
const trap = { id: 'trap', name: 'Trap', cardType: 'ambush', clanTag: 'test', effects: [{ when: 'defend', do: 'down', target: 'attacker' }] };
for (const jam of [false, true]) {
    st = board([{ attack: 2000 }], [{}]);
    st.sides.opponent.field[5] = st.makeCard({ ...trap, face_down: true });
    if (jam) st._doFx('player', -1, src, { do: 'jam' });
    st._attack('player', 0, 0);
    const asked = [st.pending, ...st._asks].some(a => a && a.key === 'ambush');
    assert.equal(asked, !jam, jam ? 'jammed: no Ambush to spring' : 'not jammed: the Ambush can spring');
}

// A KO that sets off another "KO all enemies" doesn't trip over the ones already gone
st = board([{ effects: [{ when: 'foe_ko', do: 'ko', target: 'enemies' }] }], [{}, {}, {}]);
st._doFx('player', -1, src, all('ko'));
assert.ok([0, 1, 2].every(s => st.cardAt('opponent', s) == null), 'all three KO\'d, no error');

// An attack whose own trigger removes its target ends there
st = board([{ effects: [{ when: 'attack', do: 'bounce', target: 'enemies' }] }], [{}]);
assert.ok(st._attack('player', 0, 0));
assert.equal(st.cardAt('opponent', 0), null, 'the target went back to the hand');
assert.ok(st.takeEvents().some(e => e.type === 'effect' && /target is gone/.test(e.text)), 'and the attack ended');

// "At the end of your turn: if this card is Downed, it stands back up" (Sprintz) works while it's Downed
st = board([{ downed: true, position: 'def', effects: [{ when: 'turn_end', do: 'stand', target: 'self' }] }]);
st._runFx('player', 0, st.cardAt('player', 0), 'turn_end');
assert.ok(!st.cardAt('player', 0).downed, 'it stood back up');

// A search: only its owner learns what it found (public_text for the others), unless it reveals
st = board();
st._doFx('player', -1, src, { do: 'search', amount: 1 });
let said = st.takeEvents().find(e => e.type === 'effect' && /searches/.test(e.text));
assert.match(said.text, /Grunt/, 'its owner sees the card');
assert.equal(said.public_text, 'Source: searches the deck for a card', 'the others only see that it searched');
st = board();
st._doFx('player', -1, src, { do: 'search', amount: 1, reveal: true });
said = st.takeEvents().find(e => e.type === 'effect' && /searches/.test(e.text));
assert.ok(!('public_text' in said), 'reveal: everyone sees it');

// A Striver that evolves this turn can't use its new form's Activate abilities until the next turn
CARD_CATALOG.block_evo_lv1 = { ...CARD_CATALOG.block_grunt, id: 'block_evo_lv1', name: 'Evo', subtype: 'striver', promotesTo: 'block_evo_lv2' };
CARD_CATALOG.block_evo_lv2 = { ...CARD_CATALOG.block_grunt, id: 'block_evo_lv2', name: 'Evo', subtype: 'striver', level: 2,
    effects: [{ when: 'activate', do: 'draw', amount: 1 }] };
st = board([{ id: 'block_evo_lv1', subtype: 'striver', promotesTo: 'block_evo_lv2' }]);
st._promote('player', 0, 'test');
st._flushAsks();
assert.ok(st._answer('player', 'atk'), 'the position asked for');
assert.equal(st.cardAt('player', 0).id, 'block_evo_lv2', 'it evolved');
assert.deepEqual(st.activations('player', 0), [], 'its ability waits a turn');
st.turn += 2;
assert.deepEqual(st.activations('player', 0), [1], 'and works on the next turn');

// Evolving keeps the card's buffs and debuffs, but not its statuses
st = board([{ id: 'block_evo_lv1', subtype: 'striver', promotesTo: 'block_evo_lv2' }]);
st.cardAt('player', 0).mods = [{ atk: 700, def: 0, until_turn: 99 }, { atk: 0, def: -100, until_turn: 99 }];
st.cardAt('player', 0).poison = { amt: 100, left: 2 };
st._promote('player', 0, 'test');
st._flushAsks();
st._answer('player', 'atk');
st._recalc();
const evo = st.cardAt('player', 0);
assert.equal(evo.mods.length, 2, 'both changes carried over');
assert.equal(evo.attack, 1000 + 700, 'ATK still +700');
assert.equal(evo.defense, 400 - 100, 'DEF still -100');
assert.ok(evo.poison === undefined, 'the poison is gone');

console.log('blocks: ok');
