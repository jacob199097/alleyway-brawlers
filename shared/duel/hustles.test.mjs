// Hustles that search the deck can be played (online too: your view of your own deck has its
// cards), and Hustles can be set face-down in the back row and activated when you choose (paying then)
// (shared/duel/DuelState.js; duel_state.gd plays the same rules, which the golden test checks).
//   node shared/duel/hustles.test.mjs
import assert from 'node:assert';
import { createRequire } from 'node:module';
import { DuelState, BACK } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';
import { choose } from './DuelAI.js';

const { viewFor } = createRequire(import.meta.url)('../../backend/socket/onlineMatch.js');

const SUPERNOVA = 'card_nebu_010';   // Hustle (1): search the deck for a NEBULA card with 4 or less Authority
const STATIC = 'card_mili_002';      // Militia character: ACTIVATE, search for a MILITIA character (4 or less)

/** A duel on turn 3, player to act in the deployment phase; `hand` comes off the top of the deck. */
function duel(deck, hand = [], authority = 5) {
    const st = new DuelState({ player: [...deck, ...hand], opponent: ['card_nebu_011', 'card_nebu_011'] }, {}, {}, 'player', -1);
    for (let i = 0; i < hand.length; i++) st.sides.player.hand.push(st.sides.player.deck.pop());
    st.turn = 3;
    st.phase = 'deployment';
    st.sides.player.authority = st.sides.player.authority_max = authority;
    return st;
}
const inHand = (st, id) => st.sides.player.hand.find(c => c.id === id);

// Supernova Run: playable with a Nebula card of 4 or less Authority in the deck, and it finds it
let st = duel(['card_nebu_011', 'card_nebu_003'], [SUPERNOVA]);
assert.ok(st.canHustle('player', inHand(st, SUPERNOVA)), 'Supernova Run can be played');
assert.ok(st.doAction('player', { kind: 'hustle', uid: inHand(st, SUPERNOVA).uid }));
assert.equal(st.pending.key, 'fx_pick');
assert.equal(st.pending.options[0].card.id, 'card_nebu_011', 'each option carries its card (the game shows them to pick from)');
st.takeEvents();
st.doAction('player', { kind: 'choose', option: st.pending.options[0].id });
assert.ok(inHand(st, 'card_nebu_011'), 'it found Sprintz (Authority 1)');
assert.ok(st.takeEvents().some(e => e.type === 'shuffle' && e.side === 'player'), 'then the deck is shuffled');
assert.ok(!inHand(st, 'card_nebu_003'), 'not the Authority 7 Kade');
st = duel(['card_nebu_003'], [SUPERNOVA]);
assert.ok(!st.canHustle('player', inHand(st, SUPERNOVA)), 'nothing to find: it can\'t be played');

// Online: your view of your own deck has its cards (in no particular order), so the game knows
// a search has something to find; the opponent's deck is only a count
st = duel(['card_nebu_011', 'card_nebu_003', 'card_mili_006'], [SUPERNOVA]);
const view = viewFor(st, 'player');
assert.deepEqual(view.sides.player.deck.map(c => c.id), ['card_mili_006', 'card_nebu_003', 'card_nebu_011'], 'own deck: sorted by card');
assert.ok(view.sides.opponent.deck.every(c => Object.keys(c).length === 0), "the opponent's deck stays hidden");
const seen = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
Object.assign(seen, { turn: view.turn, active: view.active, phase: view.phase, pending: view.pending, sides: view.sides });
assert.ok(seen.canHustle('player', seen.sides.player.hand[0]), 'from that view, Supernova Run can be played');

// Static's ACTIVATE: finds a Militia character of 4 or less Authority
st = duel(['card_mili_006', 'card_mili_001'], [STATIC]);
st.doAction('player', { kind: 'summon', uid: inHand(st, STATIC).uid, slot: 2, position: 'atk' });
assert.deepEqual(st.activations('player', 2), [1], 'Static can activate');
st.doAction('player', { kind: 'activate', slot: 2, fx: 1 });
if (st.pending.key) st.doAction('player', { kind: 'choose', option: st.pending.options[0].id });
assert.ok(inHand(st, 'card_mili_006'), 'it found Rook (Authority 2)');

// Setting a Hustle: free, face-down in the back row; activated whenever there's the Authority
st = duel(['card_nebu_011', 'card_nebu_011'], [SUPERNOVA], 0);
let card = inHand(st, SUPERNOVA);
assert.ok(!st.canHustle('player', card), 'no Authority to play it');
assert.ok(st.canSet('player', card, 5), 'but it can be set');
assert.ok(st.doAction('player', { kind: 'set', uid: card.uid, slot: 5 }));
assert.equal(st.sides.player.field[5], card);
assert.ok(card.face_down, 'face-down');
assert.equal(st.sides.player.authority, 0, 'setting it cost nothing');
assert.ok(!st.canHustle('player', card), 'not without the Authority');
st.sides.player.authority = 3;
assert.ok(st.canHustle('player', card), 'the turn it was set, once there is the Authority');
st.takeEvents();
// Activated from the back row, in any phase you act in, paying its cost then
st.phase = 'brawl';
assert.ok(st.canHustle('player', card), 'even in the brawl');
assert.ok(st.doAction('player', { kind: 'hustle', uid: card.uid }));
if (st.pending.key) st.doAction('player', { kind: 'choose', option: st.pending.options[0].id });
assert.equal(st.sides.player.field[5], null, 'it left the back row');
assert.ok(st.sides.player.gutter.includes(card) && !card.face_down, 'into the Gutter, face-up');
assert.equal(st.sides.player.authority, 2, 'paid 1 Authority');
assert.ok(inHand(st, 'card_nebu_011'), 'its search happened');
const ev = st.takeEvents().find(e => e.type === 'hustle');
assert.equal(ev.slot, 5);
assert.equal(ev.set, true);

// The opponent sees only a face-down card; an attack can't spring a set Hustle
st = duel(['card_nebu_011'], [SUPERNOVA, 'card_nebu_007']);
st.doAction('player', { kind: 'set', uid: inHand(st, SUPERNOVA).uid, slot: 5 });
assert.equal(viewFor(st, 'opponent').sides.player.field[5].name, undefined, "the opponent doesn't see what it is");

// A set Continuous / Equip Hustle stays in its slot when activated, face-up
st = duel(['card_mili_006'], ['card_mili_013'], 0);
card = inHand(st, 'card_mili_013');
st.sides.player.field[1] = st.makeCard('card_mili_006');
st.doAction('player', { kind: 'set', uid: card.uid, slot: 7 });
st.turn = 5;
st.sides.player.authority = 3;
assert.ok(st.doAction('player', { kind: 'hustle', uid: card.uid }));
if (st.pending.key) st.doAction('player', { kind: 'choose', option: st.pending.options[0].id });
assert.equal(st.sides.player.field[7], card, 'Improvised Armor stays in slot 7');
assert.ok(!card.face_down && card.equipped_to === st.sides.player.field[1].uid, 'face-up, equipped');

// The CPU sets a Hustle it can't use yet, and activates it once it can
st = duel(['card_nebu_011', 'card_nebu_011'], [SUPERNOVA], 0);
assert.deepEqual(choose(st, 'player'), { kind: 'set', uid: inHand(st, SUPERNOVA).uid, slot: BACK[0] });
st.doAction('player', choose(st, 'player'));
st.turn = 5;
st.sides.player.authority = 1;
assert.deepEqual(choose(st, 'player'), { kind: 'hustle', uid: st.sides.player.field[BACK[0]].uid });

// "All characters" (Card Forge target all): a Hustle Downs every character on both sides; a
// character's effect hits every other character, not itself
CARD_CATALOG.test_lockdown = { id: 'test_lockdown', name: 'Lockdown', clan: 'test', cardType: 'hustle', authority: 1,
    rarity: 1, clanTag: 'test', effectKey: '', effects: [{ do: 'down', target: 'all' }] };
st = duel(['card_nebu_011'], ['test_lockdown']);
st.sides.player.field[1] = st.makeCard('card_nebu_011');
st.sides.opponent.field[2] = st.makeCard('card_nebu_011');
st.sides.opponent.field[3] = st.makeCard('card_nebu_011');
assert.ok(st.doAction('player', { kind: 'hustle', uid: inHand(st, 'test_lockdown').uid }));
assert.ok([st.cardAt('player', 1), st.cardAt('opponent', 2), st.cardAt('opponent', 3)].every(c => c.downed), 'everyone is Downed, yours too');
st = duel(['card_nebu_011'], []);
for (const [side, slot] of [['player', 0], ['player', 1], ['opponent', 2]]) st.sides[side].field[slot] = st.makeCard('card_nebu_011');
const quake = st.sides.player.field[0];
quake.effects = [{ when: 'deploy', do: 'down', target: 'all' }];
st._runFx('player', 0, quake, 'deploy');
assert.ok(!quake.downed && st.cardAt('player', 1).downed && st.cardAt('opponent', 2).downed, 'every other character, not the card itself');
// The CPU plays it only when it hits more of the opponents' characters than its own
st = duel(['card_nebu_011'], ['test_lockdown']);
st.sides.player.field[1] = st.makeCard('card_nebu_011');
st.sides.opponent.field[2] = st.makeCard('card_nebu_011');
assert.notEqual(choose(st, 'player').kind, 'hustle', 'one each: not worth it');
st.sides.opponent.field[3] = st.makeCard('card_nebu_011');
assert.equal(choose(st, 'player').kind, 'hustle', 'two of theirs, one of ours: worth it');

console.log('hustles: ok');
