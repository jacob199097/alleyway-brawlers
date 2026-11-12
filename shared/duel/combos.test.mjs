// New Card Forge building blocks (shared/duel/DuelState.js; duel_state.gd plays the same rules, which
// the golden test checks): triggers foe_hustle, ally_promoted, ally_downed, heal_gained, self_gutter;
// targets neighbors / opposite; conditions foe_statused, hustles_ge, morale_behind / morale_ahead;
// "for each" hustles_turn, statused, lost_1000; actions tax and reshuffle; the cost_up passive.
//   node shared/duel/combos.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';

const duel = () => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 4;
    st.phase = 'deployment';
    st.active = 'player';
    return st;
};
let uid = 0;
const unit = (st, effects = [], atk = 1000, def = 1000, extra = {}) => st.makeCard({ id: `test_${uid++}`, name: `Unit ${uid}`, cardType: 'gang_member',
    clanTag: 'test', attack: atk, defense: def, authority: 2, effects, ...extra });
const put = (st, side, slot, c) => { st.sides[side].field[slot] = c; c.deployed_turn = 1; st._recalc(); return c; };
const answerAll = (st) => { while (st._asks.length) { const a = st._asks.shift(); st._runAnswer(() => a.cb(a.options[0].id)); } };

// TAX: the opponent's next turn has less Authority
let st = duel();
let c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'tax', amount: 2 });
assert.equal(st.sides.opponent.tax, 2);
st.sides.opponent.authority_max = 4;
st.sides.opponent.turns = 3;
st.active = 'opponent';
st._beginTurn();
answerAll(st);
assert.equal(st.sides.opponent.authority, 5 - 2, 'their 5 Authority, less the TAX');
assert.equal(st.sides.opponent.tax, 0, 'it is used up');

// cost_up: the opponent's cards cost more while the passive is on the field
st = duel();
put(st, 'opponent', 2, unit(st, [{ when: 'passive', do: 'cost_up', amount: 1 }]));
const card = st.makeCard({ id: 'test_cost', name: 'Cost', cardType: 'gang_member', clanTag: 'test', attack: 100, defense: 100, authority: 3 });
assert.equal(st.costOf('player', card), 4);
assert.equal(st.costOf('opponent', card), 3, "not the passive's own side");

// reshuffle: the oldest Gutter cards (not tokens) back into the deck
st = duel();
c = put(st, 'player', 0, unit(st));
const g = [unit(st), unit(st, [], 1, 1, { token: true }), unit(st), unit(st)];
st.sides.player.gutter.push(...g);
st._doFx('player', 0, c, { do: 'reshuffle', amount: 2 });
assert.equal(st.sides.player.deck.length, 2);
assert.ok(st.sides.player.deck.includes(g[0]) && st.sides.player.deck.includes(g[2]), 'the oldest two that are not tokens');
assert.ok(st.takeEvents().some(e => e.type === 'recycle' && e.count === 2));

// neighbors: the allies in the lanes next to it; opposite: the enemy across (lane 1 faces lane 5)
st = duel();
c = put(st, 'player', 2, unit(st));
const left = put(st, 'player', 1, unit(st)), right = put(st, 'player', 3, unit(st)), far = put(st, 'player', 0, unit(st));
st._doFx('player', 2, c, { do: 'buff', target: 'neighbors', atk: 300, until: 'turn' });
st._recalc();
assert.equal(left.attack, 1300);
assert.equal(right.attack, 1300);
assert.equal(far.attack, 1000, 'not the one two lanes away');
const across = put(st, 'opponent', 4, unit(st)), other = put(st, 'opponent', 0, unit(st));
c = put(st, 'player', 0, far);
st._doFx('player', 0, far, { do: 'down', target: 'opposite' });
assert.ok(across.downed, "lane 1's opposite is their lane 5");
assert.ok(!other.downed);

// foe_hustle: the opponent plays a Hustle
st = duel();
const watcher = put(st, 'opponent', 0, unit(st, [{ when: 'foe_hustle', do: 'buff', target: 'self', atk: 200, until: 'forever' }]));
const hustle = st.makeCard({ id: 'test_h', name: 'Hustle', cardType: 'hustle', clanTag: 'test', authority: 0, effects: [{ do: 'draw', amount: 1 }] });
st.sides.player.hand.push(hustle);
st.sides.player.deck.push(unit(st), unit(st));
st.sides.player.authority = 3;
assert.ok(st.doAction('player', { kind: 'hustle', uid: hustle.uid }));
st._recalc();
answerAll(st);
assert.equal(watcher.attack, 1200, 'the opponent playing a Hustle set it off');
// hustles_turn / hustles_ge: Hustles played this turn
assert.equal(st._hustlesThisTurn('player'), 1);
assert.ok(st._fxCond('player', 0, { if: 'hustles_ge', n: 1 }, null));
assert.equal(st._perCount('player', 0, { per: 'hustles_turn' }), 1);
st.turn += 1;
assert.equal(st._hustlesThisTurn('player'), 0, 'a new turn starts the count again');

// ally_downed: another of your characters is Downed
st = duel();
const avenger = put(st, 'player', 0, unit(st, [{ when: 'ally_downed', do: 'buff', target: 'self', atk: 500, until: 'forever' }]));
const victim = put(st, 'player', 1, unit(st));
st._defeat('player', 1);
st._recalc();
assert.ok(victim.downed);
assert.equal(avenger.attack, 1500);

// heal_gained: you gain Morale (and it can't set itself off again)
st = duel();
st.sides.player.morale = 3000;
const healer = put(st, 'player', 0, unit(st, [{ when: 'heal_gained', do: 'heal', amount: 100 }, { when: 'heal_gained', do: 'damage', amount: 300 }]));
st._heal('player', healer, 500, 0);
assert.equal(st.sides.player.morale, 3600, '500, then its own +100 once (no loop)');
assert.equal(st.sides.opponent.morale, 6000 - 300);

// self_gutter: milled or discarded into the Gutter
st = duel();
const milled = unit(st, [{ when: 'self_gutter', do: 'damage', amount: 400 }]);
st.sides.player.deck.push(unit(st), milled);
c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'mill_self', amount: 1 });
assert.equal(st.sides.opponent.morale, 5600, 'milled: it hits');
const tossed = unit(st, [{ when: 'self_gutter', do: 'draw', amount: 1 }]);
st.sides.player.hand.push(tossed);
st.sides.player.deck.push(unit(st));
const handBefore = st.sides.player.hand.length;
st._discardAt('player', st.sides.player.hand.indexOf(tossed));
assert.equal(st.sides.player.hand.length, handBefore, 'discarded: one card out, one drawn');

// ...and a milled card can put itself onto the field ("The Gravedigger Herald")
st = duel();
const digger = unit(st, [{ when: 'self_gutter', do: 'revive', amount: 1, name: 'Gravedigger', position: 'def' }], 1200, 1000, { name: 'The Gravedigger Herald' });
st.sides.player.deck.push(unit(st), digger);
c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'mill_self', amount: 1 });
assert.ok(st.sides.player.field.includes(digger), 'it rose from the Gutter');
assert.equal(digger.position, 'def');
assert.ok(!st.sides.player.gutter.includes(digger));

// ally_promoted: a Striver of yours PROMOTES
st = duel();
const fan = put(st, 'player', 0, unit(st, [{ when: 'ally_promoted', do: 'draw', amount: 1 }]));
st.sides.player.deck.push(unit(st));
const before = st.sides.player.hand.length;
st._runFx('player', 0, fan, 'ally_promoted', fan);
assert.equal(st.sides.player.hand.length, before + 1);

// Conditions and counts: foe_statused, statused, morale_behind / ahead, lost_1000
st = duel();
const sick = put(st, 'opponent', 0, unit(st));
assert.ok(!st._fxCond('player', 0, { if: 'foe_statused' }, null));
sick.poison = 100;
assert.ok(st._fxCond('player', 0, { if: 'foe_statused' }, null));
assert.equal(st._perCount('player', 0, { per: 'statused' }), 1);
st.sides.player.morale = 3500;
assert.ok(st._fxCond('player', 0, { if: 'morale_behind' }, null));
assert.ok(!st._fxCond('player', 0, { if: 'morale_ahead' }, null));
assert.ok(st._fxCond('opponent', 0, { if: 'morale_ahead' }, null));
assert.equal(st._perCount('player', 0, { per: 'lost_1000' }), 2, '2500 lost: 2 thousands');

// REMAINS: a token with it goes to the Gutter when it's KO'd (a plain token vanishes); never back to the hand
{
    const st = duel();
    const g0 = st.sides.player.gutter.length;
    const bones = put(st, 'player', 1, unit(st, [{ when: 'passive', do: 'brittle' }, { when: 'passive', do: 'remains' }], 500, 0, { token: true }));
    const plainTok = put(st, 'player', 2, unit(st, [], 500, 0, { token: true }));
    st._ko('player', 1); st._ko('player', 2);
    assert.equal(st.sides.player.gutter.length, g0 + 1, 'only the REMAINS token reaches the Gutter');
    assert.ok(st.sides.player.gutter.includes(bones) && !st.sides.player.gutter.includes(plainTok));
    const digger = unit(st, [{ when: 'deploy', do: 'recover', amount: 1 }]);
    const hand0 = st.sides.player.hand.length;
    st.sides.player.gutter = [bones];
    assert.equal(st.fxCan('player', 0, digger, digger.effects[0]), false, "recover can't take a token");
    st._doFx('player', 0, digger, digger.effects[0]);
    assert.equal(st.sides.player.hand.length, hand0, 'the token stays in the Gutter');
}
// A "?" card keeps the stats its own passive gives it while Downed; other passives stop; SILENCE takes all
{
    const st = duel();
    st.sides.player.gutter = [unit(st), unit(st), unit(st)];
    const q = put(st, 'player', 1, unit(st, [{ when: 'passive', do: 'buff', target: 'self', per: 'gutter', atk: 400, def: 250 }], 0, 0, { varStats: true }));
    const plain = put(st, 'player', 2, unit(st, [{ when: 'passive', do: 'buff', target: 'self', atk: 300 }], 1000, 1000));
    assert.equal(q.attack, 1200);
    q.downed = true; plain.downed = true; st._recalc();
    assert.equal(q.attack, 1200, '"?" stats stay while Downed');
    assert.equal(q.defense, 750);
    assert.equal(plain.attack, 1000, "a normal card's passive buff stops while Downed");
    q.silence_until = st.turn; st._recalc();
    assert.equal(q.attack, 0, 'SILENCE still takes them');
}
// BRITTLE: KO'd instead of going Down, from a brawl or an effect (a token just vanishes)
st = duel();
const bones = put(st, 'player', 1, unit(st, [{ when: 'passive', do: 'brittle' }], 500, 0, { token: true }));
assert.equal(st._defeat('player', 1), 'ko', 'a lost brawl KOs it');
assert.equal(st.sides.player.field[1], null);
assert.ok(!st.sides.player.gutter.includes(bones), 'a token vanishes');
const brittle = put(st, 'opponent', 2, unit(st, [{ when: 'passive', do: 'brittle' }]));
c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'down', target: 'enemies' });
assert.equal(st.sides.opponent.field[2], null, 'DOWN KOs it');
assert.ok(st.sides.opponent.gutter.includes(brittle), 'to the Gutter, like any KO');
const shocked = put(st, 'opponent', 3, unit(st, [{ when: 'passive', do: 'brittle' }], 1000, 300));
st._doFx('player', 0, c, { do: 'shock', target: 'enemies', amount: 500 });
assert.equal(st.sides.opponent.field[3], null, 'SHOCK past its DEF KOs it');
const plain = put(st, 'opponent', 4, unit(st));
st._doFx('player', 0, c, { do: 'down', target: 'enemies' });
assert.ok(plain.downed, 'without BRITTLE it just goes Down');
// An effect that Downs now sets off "when it's Downed" and "when another of your characters is Downed"
st = duel();
const riser = put(st, 'opponent', 0, unit(st, [{ when: 'self_downed', do: 'stand', target: 'self', once: true }]));
const friend = put(st, 'opponent', 1, unit(st, [{ when: 'ally_downed', do: 'buff', target: 'self', atk: 200, until: 'forever' }]));
c = put(st, 'player', 0, unit(st));
st._doFx('player', 0, c, { do: 'down', target: 'enemies' });
st._recalc();
assert.ok(!riser.downed, "its own \"when it's Downed: it stands back up\" happened");
assert.equal(friend.attack, 1200, '"when another of your characters is Downed" happened');

// ACTIVATE with a follow-up ("Flip a coin. If heads, draw 2 cards. If tails, draw 1 card.") is one ability
{
    const st = duel();
    st.sides.player.deck = [unit(st), unit(st), unit(st), unit(st)];
    const ruby = put(st, 'player', 0, unit(st, [
        { when: 'activate', do: 'draw', amount: 2, luck: 'coin' }, { when: 'activate', do: 'draw', amount: 1, if_luck: 'lost' }]));
    assert.deepEqual(st.activations('player', 0), [1], 'one ability, not ACTIVATE 1 and 2');
    const before = st.sides.player.hand.length;
    assert.ok(st.doAction('player', { kind: 'activate', slot: 0, fx: 1 }));
    answerAll(st);
    const drew = st.sides.player.hand.length - before;
    assert.ok(drew === 2 || drew === 1, `heads draws 2, tails 1 (drew ${drew})`);
    assert.deepEqual(st.activations('player', 0), [], 'once per turn');
    void ruby;
}

// "When this card attacks: put an enemy in STASIS": chosen before the brawl, from cards still on the field
{
    const st = duel();
    st.phase = 'brawl';
    st.turn = 5;
    const alysse = put(st, 'player', 0, unit(st, [{ when: 'attack', do: 'stasis', target: 'enemy' }], 3000, 1000));
    const weak = put(st, 'opponent', 1, unit(st, [], 500, 500));
    const other = put(st, 'opponent', 2, unit(st, [], 1500, 1500));
    assert.ok(st.doAction('player', { kind: 'attack', from: 0, target: 1 }));
    assert.equal(st.pending.key !== undefined || st.pending.kind === 'choose', true, 'the attack asks first');
    assert.equal(st.cardAt('opponent', 1), weak, 'the brawl waits for the choice');
    // Choose the other one: then the brawl happens
    assert.ok(st.doAction('player', { kind: 'choose', option: '2' }));
    assert.ok(st.inStasis(other), 'the chosen card is in STASIS');
    assert.ok(weak.downed || st.cardAt('opponent', 1) == null, 'then the brawl went ahead');
    void alysse;
}

// An Ambush's cost is paid out of the opponent's sight (hidden_spend), until the Authority refills
{
    const st = duel();
    st.phase = 'deployment';
    st.sides.player.authority = 4;
    const trap = st.makeCard({ id: 'test_trap', name: 'Trap', cardType: 'ambush', clanTag: 'test', authority: 3, effects: [] });
    st.sides.player.hand.push(trap);
    st.takeEvents();
    assert.ok(st.doAction('player', { kind: 'set', uid: trap.uid, slot: 5 }));
    const ev = st.takeEvents().find(e => e.type === 'authority');
    assert.equal(st.sides.player.authority, 1);
    assert.ok(ev.hidden && ev.shown === 4 && ev.value === 1, 'its event says what the opponent may see');
    assert.equal(st._counts().player.hidden_spend, 3);
}

// COLLATERAL (target "collateral"): when it KOs (or Downs) a character in a brawl, the effect hits the
// characters in the lanes either side of that one, and only those
{
    const st = duel();
    st.phase = 'brawl';
    st.turn = 5;
    const att = put(st, 'player', 0, unit(st, [{ when: 'ko', do: 'poison', target: 'collateral', amount: 200 },
        { when: 'down', do: 'buff', target: 'collateral', atk: -300, until: 'turn' }], 3000, 1000));
    const victim = put(st, 'opponent', 2, unit(st, [], 500, 500));
    victim.downed = true;   // (attacked while Downed: KO'd)
    const l = put(st, 'opponent', 1, unit(st, [], 1000, 1000)), r = put(st, 'opponent', 3, unit(st, [], 1000, 1000)), far = put(st, 'opponent', 4, unit(st, [], 1000, 1000));
    assert.ok(st.doAction('player', { kind: 'attack', from: 0, target: 2 }));
    answerAll(st);
    assert.equal(st.cardAt('opponent', 2), null, 'the victim is KO\'d');
    assert.ok(l.poison && r.poison, 'the characters either side of it are POISONED');
    assert.ok(!far.poison, 'not one two lanes away');
    assert.ok(!att.poison, 'not the attacker');
    // Downing one (not a KO): the "when it Downs" effect hits its neighbours instead
    const st2 = duel();
    st2.phase = 'brawl';
    st2.turn = 5;
    put(st2, 'player', 0, unit(st2, [{ when: 'down', do: 'buff', target: 'collateral', atk: -300, until: 'turn' }], 3000, 1000));
    put(st2, 'opponent', 2, unit(st2, [], 500, 500));
    const l2 = put(st2, 'opponent', 1, unit(st2, [], 1000, 1000)), r2 = put(st2, 'opponent', 3, unit(st2, [], 1000, 1000));
    assert.ok(st2.doAction('player', { kind: 'attack', from: 0, target: 2 }));
    answerAll(st2);
    st2._recalc();
    assert.equal(l2.attack, 700, 'the Downed one\'s left neighbour loses 300 ATK');
    assert.equal(r2.attack, 700, 'and its right one');
}

// Target "opposite_wide": the enemies in the lane across from it and the lanes either side of that one
{
    const st = duel();
    const c = put(st, 'player', 1, unit(st));   // (lane 2 faces their lane 4)
    const e = [0, 1, 2, 3, 4].map(i => put(st, 'opponent', i, unit(st)));
    st._doFx('player', 1, c, { do: 'stoke', target: 'opposite_wide', amount: 200 });
    assert.deepEqual(e.map(x => x.burn ? x.burn.amt : 0), [0, 0, 200, 200, 200], 'the one across and the two beside it');
    assert.ok(!c.burn, 'not itself');
    // With nobody straight across, the lanes beside that one are still hit; at the edge there is only one
    const st2 = duel();
    const c2 = put(st2, 'player', 0, unit(st2));   // (lane 1 faces their lane 5)
    const side = put(st2, 'opponent', 3, unit(st2)), far = put(st2, 'opponent', 2, unit(st2));
    st2._doFx('player', 0, c2, { do: 'stoke', target: 'opposite_wide', amount: 200 });
    assert.ok(side.burn && !far.burn);
}

// Trigger "foe_burned": when your opponent takes BURN damage. total: once that much has been taken
// (counted while the card is on the field, then counted again from nothing)
{
    const st = duel();
    st.sides.player.morale = 5000;
    const watcher = put(st, 'player', 0, unit(st, [{ when: 'foe_burned', do: 'heal', amount: 100, total: 800 }]));
    const lit = put(st, 'opponent', 2, unit(st));
    lit.burn = { amt: 300, left: 3 };
    st._statusTicks('opponent');
    st._statusTicks('opponent');
    assert.equal(st.sides.player.morale, 5000, '600 BURN damage so far: not yet');
    assert.equal(watcher.fx_count.foe_burned1, 600);
    st._statusTicks('opponent');
    assert.equal(st.sides.player.morale, 5100, '900: it happens');
    assert.equal(st.sides.opponent.morale, 6000 - 900);
    assert.ok(!watcher.fx_count.foe_burned1, 'and the count starts again');
    // BURN damage a BARRICADE holds isn't taken; the player's own BURN damage doesn't count
    lit.burn = { amt: 900, left: 3 };
    st.sides.opponent.barricade = 900;
    st._statusTicks('opponent');
    watcher.burn = { amt: 900, left: 3 };
    st._statusTicks('player');
    assert.ok(!watcher.fx_count || !watcher.fx_count.foe_burned1);
    assert.equal(st.sides.player.morale, 5100 - 900);
    // Without a total: every time
    const st2 = duel();
    st2.sides.player.morale = 5000;
    put(st2, 'player', 0, unit(st2, [{ when: 'foe_burned', do: 'heal', amount: 100 }]));
    put(st2, 'opponent', 2, unit(st2)).burn = { amt: 100, left: 3 };
    st2._statusTicks('opponent');
    st2._statusTicks('opponent');
    assert.equal(st2.sides.player.morale, 5200);
}

// BLIND: until its owner's next turn ends, each of its attacks is a coin flip: tails, it misses (the attack is used up)
{
    const st = duel();
    const c = put(st, 'player', 0, unit(st, [], 1000, 1000));
    const foe = put(st, 'opponent', 2, unit(st, [], 3000, 1000));
    const safe = put(st, 'opponent', 3, unit(st, [{ when: 'passive', do: 'immune', statuses: ['blind'] }]));
    st._doFx('player', 0, c, { do: 'blind', target: 'enemies' });
    assert.equal(foe.blind_until, 5, "through its owner's next turn");
    assert.ok(st.statuses(foe).includes('blind'));
    assert.ok(!safe.blind_until, 'not one that is immune to it');
    st.active = 'opponent';
    st.turn = 5;
    st.phase = 'brawl';
    st.takeEvents();
    st._luck = () => 0.9;   // tails
    assert.ok(st.doAction('opponent', { kind: 'attack', from: 2, target: 0 }));
    let evs = st.takeEvents();
    assert.ok(evs.some(e => e.type === 'luck' && !e.won) && evs.some(e => e.type === 'miss' && e.from === 2 && e.target === 0));
    assert.ok(!evs.some(e => e.type === 'attack'), 'no brawl');
    assert.ok(st.cardAt('player', 0) === c && !c.downed, 'its target is untouched');
    assert.ok(foe.has_attacked && !st.canAttackWith('opponent', 2), 'the attack is used up');
    foe.has_attacked = false;
    st._luck = () => 0.1;   // heads
    assert.ok(st.doAction('opponent', { kind: 'attack', from: 2, target: 0 }));
    answerAll(st);
    evs = st.takeEvents();
    assert.ok(evs.some(e => e.type === 'attack') && !evs.some(e => e.type === 'miss'));
    assert.ok(c.downed || st.cardAt('player', 0) !== c, 'heads: it hits');
    // It wears off after that turn, and CLEANSE takes it away
    st.turn = 6;
    assert.ok(!st.statuses(foe).includes('blind'));
    foe.blind_until = 99;
    assert.ok(st._afflicted(foe));
    st._doFx('opponent', 3, safe, { do: 'cleanse', target: 'allies' });
    assert.ok(!foe.blind_until);
}

console.log('combos: ok');
