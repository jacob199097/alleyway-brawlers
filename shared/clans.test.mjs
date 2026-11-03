// Neutral cards and the one-clan deck rule (shared/clans.js): Neutral isn't a clan of its own (no
// starter, pack or pick), and a deck holds only its leader's clan and Neutral cards.
//   node shared/clans.test.mjs
import assert from 'node:assert';
import { clanList, pickableClans, deckClanProblem, starterRecipe, NEUTRAL } from './clans.js';

// A catalogue with a clan and enough Neutral cards for a deck of their own
const catalog = {};
for (let i = 1; i <= 15; i++) {
    catalog[`card_neut_${i}`] = { id: `card_neut_${i}`, name: `Neutral ${i}`, clan: NEUTRAL, cardType: 'gang_member', rarity: 1, authority: 1 };
    catalog[`card_test_${i}`] = { id: `card_test_${i}`, name: `Test ${i}`, clan: 'test', cardType: 'gang_member', rarity: 1, authority: 1 };
}
catalog.card_test_lead = { id: 'card_test_lead', name: 'Test Leader', clan: 'test', cardType: 'leader', rarity: 4 };

assert.deepEqual(clanList(catalog).map(c => c.id), ['test'], 'Neutral is not a clan');
assert.deepEqual(pickableClans(catalog).map(c => c.id), ['test'], 'nobody starts as Neutral');
assert.ok(starterRecipe('test', catalog).deck.every(([id]) => catalog[id].clan === 'test'), "a starter is its clan's cards");

const card = (name, clan) => ({ name, clan });
assert.equal(deckClanProblem('nebula', [card('A', 'nebula'), card('B', NEUTRAL)]), '', "the leader's clan and Neutral");
assert.equal(deckClanProblem('nebula', [card('B', NEUTRAL)]), '', 'Neutral only');
assert.match(deckClanProblem('nebula', [card('A', 'nebula'), card('Cinder', 'arsonists')]), /^Cinder isn't a Nebula or Neutral card/);
assert.equal(deckClanProblem('', [card('A', 'militia'), card('B', NEUTRAL), card('C', 'militia')]), '', 'no leader: one clan');
assert.match(deckClanProblem('', [card('A', 'militia'), card('B', 'wildcard')]), /one clan's cards and Neutral cards \(this one has Militia and Wildcard\)/);
assert.equal(deckClanProblem('', []), '');

console.log('clans and Neutral cards: ok');
