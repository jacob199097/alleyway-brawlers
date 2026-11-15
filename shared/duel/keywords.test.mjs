// The keywords added 2026-11-15 (shared/duel/DuelState.js; duel_state.gd plays the same rules, which the
// golden test checks): BRACE, RECKLESS, RALLY, TAUNT, HEIST, ECHO, SHROUD, CORRODE, DEBT and CONFUSE.
//   node shared/duel/keywords.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT } from './DuelState.js';

let uid = 0;
const duel = (phase = 'deployment') => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 4;
    st.phase = phase;
    st.active = 'player';
    for (const side of ['player', 'opponent']) st.sides[side].deck = Array.from({ length: 10 }, () => st.makeCard({ id: `deck_${uid++}`, name: 'Filler', cardType: 'gang_member', clanTag: 'test', attack: 100, defense: 100, authority: 9 }));
    return st;
};
const unit = (st, effects = [], atk = 1000, def = 1000, extra = {}) => st.makeCard({ id: `test_${uid++}`, name: `Unit ${uid}`, cardType: 'gang_member',
    clanTag: 'test', attack: atk, defense: def, authority: 2, effects, ...extra });
const put = (st, side, slot, c) => { st.sides[side].field[slot] = c; c.deployed_turn = 1; st._recalc(); return c; };
const answerAll = (st) => { while (st._asks.length) { const a = st._asks.shift(); st._runAnswer(() => a.cb(a.options[0].id)); } };
const attack = (st, from, target) => { const ok = st.doAction('player', { kind: 'attack', from, target }); answerAll(st); return ok; };
const coins = (st, ...rolls) => { st._luck = () => rolls.length ? rolls.shift() : 0.1; };   // < 0.5 heads, else tails

// BRACE X: the first time each turn it's attacked, the attacker loses X ATK
let st = duel('brawl');
let a1 = put(st, 'player', 0, unit(st, [], 1500, 1000));
let a2 = put(st, 'player', 1, unit(st, [], 1500, 1000));
let wall = put(st, 'opponent', 0, unit(st, [{ when: 'passive', do: 'brace', amount: 600 }], 1000, 1000));
assert.ok(attack(st, 0, 0));
assert.equal(a1.attack, 900, 'the attacker lost 600 ATK');
assert.ok(a1.downed && !wall.downed, '900 against 1000: the attacker lost the brawl');
assert.ok(attack(st, 1, 0));
assert.equal(a2.attack, 1500, 'only the first attack each turn');
assert.ok(wall.downed);

// RECKLESS X: +X ATK for its brawl, then it goes Down
st = duel('brawl');
let wild = put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'reckless', amount: 500 }], 1000, 1000));
let foe = put(st, 'opponent', 0, unit(st, [], 1300, 1000));
assert.ok(attack(st, 0, 0));
assert.ok(foe.downed, '1500 beats 1300');
assert.ok(wild.downed, 'and the reckless one goes Down after');
assert.equal(st.sides.opponent.morale, 6000 - 200);

// RALLY N: the other characters of yours get +N ATK this turn
st = duel();
let rallier = put(st, 'player', 0, unit(st));
let mate = put(st, 'player', 1, unit(st));
st._doFx('player', 0, rallier, { do: 'rally', amount: 300 });
st._recalc();
assert.equal(mate.attack, 1300);
assert.equal(rallier.attack, 1000, 'not itself');
assert.ok(st.fxCan('player', 0, rallier, { do: 'rally', amount: 300 }));
st._endTurn();
answerAll(st);
assert.equal(mate.attack, 1000, 'only this turn');

// TAUNT: a standing one must be attacked: no other target, no direct attack, not even with INFILTRATE
st = duel('brawl');
let sneak = put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'infiltrate' }]));
let taunt = put(st, 'opponent', 2, unit(st, [{ when: 'passive', do: 'taunt' }], 500, 500));
put(st, 'opponent', 3, unit(st, [{ when: 'passive', do: 'guard' }]));
assert.deepEqual(st.attackTargets('player', 'opponent', 0), [2]);
taunt.downed = true;
assert.ok(st.attackTargets('player', 'opponent', 0).includes(3), 'a Downed one does not taunt');
void sneak;

// HEIST X: Morale damage in a brawl draws X
st = duel('brawl');
st.sides.player.deck = [unit(st), unit(st)];
put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'heist', amount: 1 }], 2000, 1000));
put(st, 'opponent', 0, unit(st, [], 1500, 1000));
assert.ok(attack(st, 0, 0));
assert.equal(st.sides.player.hand.length, 1, 'beat an ATK character: drew 1');
st = duel('brawl');
st.sides.player.deck = [unit(st)];
put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'heist' }], 2000, 1000));
assert.ok(attack(st, 0, DIRECT));
assert.equal(st.sides.player.hand.length, 1, 'a direct attack too');
st = duel('brawl');
st.sides.player.deck = [unit(st)];
put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'heist' }], 2000, 1000));
put(st, 'opponent', 0, unit(st, [], 500, 1500, { position: 'def' })).position = 'def';
assert.ok(attack(st, 0, 0));
assert.equal(st.sides.player.hand.length, 0, 'beating a DEF character costs no Morale: no draw');

// ECHO: a "when played" effect happens again at the start of your next turn
st = duel();
st.sides.player.deck = [unit(st), unit(st), unit(st), unit(st)];
let echo = unit(st, [{ when: 'deploy', do: 'draw', amount: 1, echo: true }]);
st.sides.player.hand.push(echo);
st.sides.player.authority = 5;
assert.ok(st.doAction('player', { kind: 'summon', uid: echo.uid, slot: 0, position: 'atk' }));
answerAll(st);
assert.equal(st.sides.player.hand.length, 1, 'drew 1 when played');
st._endTurn();
answerAll(st);
st._endTurn();
answerAll(st);
assert.equal(st.sides.player.hand.length, 1 + 1 + 1, 'the turn draw and the ECHO');
assert.ok(!st.sides.player.echoes, 'once');
// ...not if it left the field
st = duel();
st.sides.player.deck = [unit(st), unit(st), unit(st), unit(st)];
echo = unit(st, [{ when: 'deploy', do: 'draw', amount: 1, echo: true }]);
st.sides.player.hand.push(echo);
st.sides.player.authority = 5;
st.doAction('player', { kind: 'summon', uid: echo.uid, slot: 0, position: 'atk' });
answerAll(st);
st._ko('player', 0);
st._endTurn();
answerAll(st);
st._endTurn();
answerAll(st);
assert.equal(st.sides.player.hand.length, 1 + 1, 'just the turn draw');
// ...a Hustle's echoes from the Gutter
st = duel();
st.sides.player.deck = [unit(st), unit(st), unit(st), unit(st)];
const trick = st.makeCard({ id: 'test_echo_h', name: 'Echo Trick', cardType: 'hustle', clanTag: 'test', authority: 0, effects: [{ do: 'damage', amount: 300, echo: true }] });
st.sides.player.hand.push(trick);
assert.ok(st.doAction('player', { kind: 'hustle', uid: trick.uid }));
answerAll(st);
assert.equal(st.sides.opponent.morale, 5700);
st._endTurn();
answerAll(st);
st._endTurn();
answerAll(st);
assert.equal(st.sides.opponent.morale, 5400, 'it happened again');

// SHROUD: can't be attacked or targeted by the opponent until it attacks
st = duel('brawl');
let ghost = put(st, 'opponent', 0, unit(st, [{ when: 'passive', do: 'shroud' }]));
let att = put(st, 'player', 0, unit(st, [], 2000, 1000));
assert.deepEqual(st.attackTargets('player', 'opponent', 0), [DIRECT], 'not attackable, and it does not block a direct attack');
assert.ok(!st.fxCan('player', 0, att, { do: 'ko', target: 'enemy' }), 'an enemy effect cannot choose it');
st.active = 'opponent';
st.turn = 5;
assert.ok(st.doAction('opponent', { kind: 'attack', from: 0, target: 0 }));
answerAll(st);
assert.ok(ghost.unshrouded, 'it attacked: the SHROUD is gone');
st.active = 'player';
st.turn = 6;
ghost.downed = false;
assert.ok(st.attackTargets('player', 'opponent', 0).includes(0));
st._doFx('opponent', 0, ghost, { do: 'cleanse', target: 'self' });
assert.ok(ghost.unshrouded, 'CLEANSE does not bring it back');

// CORRODE X: at the start of its owner's next 3 turns, it loses X DEF
st = duel();
let src = put(st, 'player', 0, unit(st));
let rust = put(st, 'opponent', 0, unit(st, [], 1000, 1000));
st._doFx('player', 0, src, { do: 'corrode', target: 'enemies', amount: 200 });
assert.ok(st.statuses(rust).includes('corrode'));
for (let i = 0; i < 4; i++) { st._endTurn(); answerAll(st); }
assert.equal(rust.defense, 1000 - 400, 'two of its turns so far');
for (let i = 0; i < 2; i++) { st._endTurn(); answerAll(st); }
assert.equal(rust.defense, 1000 - 600);
assert.ok(!st.statuses(rust).includes('corrode'), 'done after 3');
for (let i = 0; i < 2; i++) { st._endTurn(); answerAll(st); }
assert.equal(rust.defense, 400);
// CLEANSE takes it away, and immunity to CORRODE keeps it off
st = duel();
src = put(st, 'player', 0, unit(st));
rust = put(st, 'opponent', 0, unit(st));
let proof = put(st, 'opponent', 1, unit(st, [{ when: 'passive', do: 'immune', statuses: ['corrode'] }]));
st._doFx('player', 0, src, { do: 'corrode', target: 'enemies', amount: 200 });
assert.ok(rust.corrode && !proof.corrode);
st._doFx('opponent', 0, rust, { do: 'cleanse', target: 'self' });
assert.ok(!rust.corrode);

// DEBT N: the opponent's next card costs N more, until the end of their next turn
st = duel();
src = put(st, 'player', 0, unit(st));
st._doFx('player', 0, src, { do: 'debt', amount: 2 });
const hand = [unit(st), unit(st)];
st.sides.opponent.hand.push(...hand);
assert.equal(st.costOf('opponent', hand[0]), 4);
assert.equal(st.costOf('player', hand[0]), 2, 'not your own cards');
st._endTurn();
answerAll(st);
st.sides.opponent.authority = 6;
assert.ok(st.doAction('opponent', { kind: 'summon', uid: hand[0].uid, slot: 0, position: 'atk' }));
assert.equal(st.sides.opponent.authority, 2, 'paid 4');
assert.equal(st.costOf('opponent', hand[1]), 2, 'paid off: the next one costs as usual');
// ...and it runs out after their next turn if they play nothing
st = duel();
src = put(st, 'player', 0, unit(st));
st._doFx('player', 0, src, { do: 'debt', amount: 2 });
st._endTurn();
answerAll(st);
assert.equal(st.costOf('opponent', hand[1]), 4);
st._endTurn();
answerAll(st);
assert.equal(st.costOf('opponent', hand[1]), 2);

// CONFUSE: each attack flips a coin; tails, a random other target (an enemy, or one of its own side)
st = duel('brawl');
let dizzy = put(st, 'player', 0, unit(st, [], 2000, 1000));
let mine = put(st, 'player', 1, unit(st, [], 500, 500));
let meant = put(st, 'opponent', 0, unit(st, [], 1000, 1000));
let other = put(st, 'opponent', 1, unit(st, [], 1000, 1000));
st._doFx('opponent', 0, meant, { do: 'confuse', target: 'enemy' });
answerAll(st);
assert.ok(st.statuses(dizzy).includes('confuse'));
coins(st, 0.1);   // heads: as chosen
assert.ok(attack(st, 0, 0));
assert.ok(meant.downed && !other.downed);
st = duel('brawl');
dizzy = put(st, 'player', 0, unit(st, [], 2000, 1000));
mine = put(st, 'player', 1, unit(st, [], 500, 500));
meant = put(st, 'opponent', 0, unit(st, [], 1000, 1000));
other = put(st, 'opponent', 1, unit(st, [], 1000, 1000));
dizzy.confuse_until = 99;
coins(st, 0.9, 0.0);   // tails, then the first of the others: the enemy in lane 2
assert.ok(attack(st, 0, 0));
assert.ok(!meant.downed && other.downed, 'it hit the wrong enemy');
st = duel('brawl');
dizzy = put(st, 'player', 0, unit(st, [], 2000, 1000));
mine = put(st, 'player', 1, unit(st, [], 500, 500));
meant = put(st, 'opponent', 0, unit(st, [], 1000, 1000));
dizzy.confuse_until = 99;
coins(st, 0.9, 0.99);   // tails, then the last of the others: its own ally
assert.ok(attack(st, 0, 0));
assert.ok(mine.downed && !meant.downed, 'it hit its own ally');
assert.equal(st.sides.player.morale, 6000 - 1500, 'its own side lost the difference');
const evs = st.takeEvents();
assert.ok(evs.some(e => e.type === 'attack' && e.foe === 'player' && e.target === 1 && e.confused), 'the attack is shown on its own side');
// immunity and CLEANSE work as for BLIND
st = duel();
src = put(st, 'player', 0, unit(st));
proof = put(st, 'opponent', 1, unit(st, [{ when: 'passive', do: 'immune', statuses: ['confuse'] }]));
st._doFx('player', 0, src, { do: 'confuse', target: 'enemies' });
assert.ok(!proof.confuse_until);

// "When it's KO'd / Downed: ... the attacker": the character that beat it in the brawl
st = duel('brawl');
let avenger = put(st, 'opponent', 0, unit(st, [{ when: 'self_ko', do: 'ko', target: 'attacker' }], 1000, 1000));
let hitter = put(st, 'player', 0, unit(st, [], 2000, 1000));
avenger.downed = true;
avenger.position = 'def';
assert.ok(attack(st, 0, 0));
assert.ok(!st.cardAt('opponent', 0), "the Downed avenger was KO'd");
assert.ok(!st.cardAt('player', 0), "and it KO'd the character that KO'd it");
st = duel('brawl');
let spiteful = put(st, 'opponent', 0, unit(st, [{ when: 'self_downed', do: 'poison', target: 'attacker', amount: 200 }], 1000, 1000));
hitter = put(st, 'player', 0, unit(st, [], 2000, 1000));
assert.ok(attack(st, 0, 0));
assert.ok(spiteful.downed && hitter.poison, 'Downed, it POISONED the attacker');
st = duel();
let quiet = put(st, 'opponent', 0, unit(st, [{ when: 'self_ko', do: 'ko', target: 'attacker' }]));
let bystander = put(st, 'player', 1, unit(st));
src = put(st, 'player', 0, unit(st));
st._doFx('player', 0, src, { do: 'ko', target: 'enemies' });
assert.ok(!st.cardAt('opponent', 0) && st.cardAt('player', 0) === src && st.cardAt('player', 1) === bystander, "KO'd by an effect: no character beat it, nothing happens");

// An "immune" passive can ignore BRACE, TAUNT and SHROUD (named in its list; never by default)
const ignores = (...kinds) => [{ when: 'passive', do: 'immune', statuses: ['stun', ...kinds] }];
st = duel('brawl');
put(st, 'opponent', 0, unit(st, [{ when: 'passive', do: 'taunt' }]));
put(st, 'opponent', 1, unit(st));
put(st, 'opponent', 2, unit(st, [{ when: 'passive', do: 'shroud' }]));
put(st, 'player', 0, unit(st, [{ when: 'passive', do: 'immune' }], 2000, 1000));
put(st, 'player', 1, unit(st, ignores('taunt'), 2000, 1000));
put(st, 'player', 2, unit(st, ignores('shroud', 'taunt'), 2000, 1000));
assert.deepEqual(st.attackTargets('player', 'opponent', 0), [0], 'immune to every status still has to attack the TAUNT');
assert.deepEqual(st.attackTargets('player', 'opponent', 1), [0, 1], 'ignoring TAUNT: any it can see (not the SHROUDED one)');
assert.deepEqual(st.attackTargets('player', 'opponent', 2), [0, 1, 2], 'ignoring SHROUD too: that one as well');
const seer = st.cardAt('player', 2);
assert.ok(st._fxTargets('player', 2, seer, { do: 'ko', target: 'enemy' }, {}, 'any').some(x => x.slot === 2), 'its effects can choose the SHROUDED one');
assert.ok(!st._noTarget('opponent', 2, st.cardAt('opponent', 2), seer, 'player', 2), 'it sees through SHROUD');
assert.ok(st._noTarget('opponent', 2, st.cardAt('opponent', 2), st.cardAt('player', 0), 'player', 0), 'another card does not');
st = duel('brawl');
let braced = put(st, 'opponent', 0, unit(st, [{ when: 'passive', do: 'brace', amount: 600 }], 1000, 1000));
let steady = put(st, 'player', 0, unit(st, ignores('brace'), 1500, 1000));
assert.ok(attack(st, 0, 0));
assert.equal(steady.attack, 1500, 'ignoring BRACE: no ATK lost');
assert.ok(braced.downed, 'and it won the brawl');

// "Only if an enemy is SUPPRESSED" (foe_st_<status>): any status an enemy character has
st = duel();
src = put(st, 'player', 0, unit(st));
let pinned = put(st, 'opponent', 0, unit(st));
assert.ok(!st._fxCond('player', 0, { if: 'foe_st_suppress' }, null), 'no enemy SUPPRESSED yet');
st._doFx('player', 0, src, { do: 'suppress', target: 'enemies', amount: 100 });
assert.ok(st._fxCond('player', 0, { if: 'foe_st_suppress' }, null), 'now one is');
assert.ok(!st._fxCond('player', 0, { if: 'foe_st_corrode' }, null), 'but none is CORRODED');
assert.ok(!st._fxCond('opponent', 0, { if: 'foe_st_suppress' }, null), "the SUPPRESSED one is the opponent's own");
void pinned;

console.log('keywords: all passed');
