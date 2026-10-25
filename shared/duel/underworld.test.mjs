// Underworld-style Card Forge effects: a Dormant leader giving your characters UNDEAD, "give UNDEAD",
// raising a character from the opponent's Gutter, exiling cards from a Gutter (an effect and an
// Activate cost), and the opponent's Gutter as a condition / "for each" (shared/duel/DuelState.js;
// duel_state.gd plays the same rules, which the golden test checks).
//   node shared/duel/underworld.test.mjs
import assert from 'node:assert';
import { DuelState } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';

const duel = () => {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 5;
    st.phase = 'deployment';
    st.active = 'player';
    return st;
};
const unit = (st, name, atk = 1000, def = 1000, extra = {}) =>
    st.makeCard({ id: 'test_' + name.toLowerCase(), name, cardType: 'gang_member', clanTag: 'test', attack: atk, defense: def, ...extra });
const answer = (st, option) => { const a = st._asks.shift(); st._runAnswer(() => a.cb(option ?? a.options[0].id)); return a; };
const src = { name: 'Gravedigger', uid: 'x' };

// A Dormant leader: "your characters have UNDEAD"
let st = duel();
st.sides.player.leader = st.makeCard({ id: 'test_lich', name: 'Lich', cardType: 'leader', clanTag: 'test', influence: 3,
    effects: [{ when: 'dormant', do: 'undead' }] });
st.sides.player.leader_state = 'dormant';
const zombie = unit(st, 'Zombie', 1200, 800);
st.sides.player.field[1] = zombie;
st._ko('player', 1);
st._turnOver();
assert.ok(st.sides.player.field.includes(zombie), 'it rose: the Dormant leader gave it UNDEAD');
assert.deepEqual([zombie.attack, zombie.defense], [600, 400]);
// ...not once the leader is Awake
st = duel();
st.sides.player.leader = st.makeCard({ id: 'test_lich', name: 'Lich', cardType: 'leader', clanTag: 'test', effects: [{ when: 'dormant', do: 'undead' }] });
st.sides.player.leader_state = 'awake';
const corpse = unit(st, 'Corpse');
st.sides.player.field[1] = corpse;
st._ko('player', 1);
st._turnOver();
assert.ok(st.sides.player.gutter.includes(corpse), 'no gift from an Awake leader');

// "Give UNDEAD": the next KO, it rises (shown as a status); only once
st = duel();
const knight = unit(st, 'Knight', 2000, 2000);
st.sides.player.field[2] = knight;
st._doFx('player', -1, src, { do: 'give_undead', target: 'ally' });
answer(st, '2');
assert.ok(knight.undead_given && st.statuses(knight).includes('undead'));
assert.equal(st.fxCan('player', -1, src, { do: 'give_undead', target: 'ally' }), false, 'already UNDEAD: nobody else to give it to');
st._ko('player', 2);
st._turnOver();
assert.ok(st.sides.player.field.includes(knight) && knight.risen && !knight.undead_given, 'it rose');

// Raise a character from the opponent's Gutter: it fights for you
st = duel();
const fallen = unit(st, 'Fallen', 1500, 1500);
st.sides.opponent.gutter.push(fallen, st.makeCard({ id: 'test_trick', name: 'Trick', cardType: 'hustle', clanTag: 'test' }));
assert.equal(st.fxCan('player', -1, src, { do: 'revive' }), false, 'your own Gutter is empty');
assert.ok(st.fxCan('player', -1, src, { do: 'revive', from: 'foe' }));
st._events = [];
st._doFx('player', -1, src, { do: 'revive', from: 'foe' });
while (st._asks.length) answer(st);
assert.ok(st.sides.player.field.includes(fallen) && !st.sides.opponent.gutter.includes(fallen), 'on your field now');
assert.ok(st._events.some(e => e.type === 'recover' && e.from_side === 'opponent'), 'it came out of their Gutter');
st._ko('player', st.sides.player.field.indexOf(fallen));
assert.ok(st.sides.player.gutter.includes(fallen), "KO'd again: your Gutter");

// Exile cards from the opponent's Gutter (the newest), an UNDEAD one doesn't rise
st = duel();
const g = st.sides.opponent.gutter;
const old = unit(st, 'Old'), mid = unit(st, 'Mid');
const riser = unit(st, 'Riser', 1000, 1000, { effects: [{ when: 'passive', do: 'undead' }] });
g.push(old, mid);
st.sides.opponent.field[0] = riser;
st._ko('opponent', 0);
st._doFx('player', -1, src, { do: 'exile_gutter', amount: 2 });
assert.deepEqual(g, [old], 'the two newest are gone');
st._turnOver();
assert.ok(!st.sides.opponent.field.includes(riser), 'exiled: it never rises');

// The Activate cost: exile cards from your own Gutter (the oldest)
st = duel();
const lich = unit(st, 'Necro', 1000, 1000, { effects: [{ when: 'activate', do: 'damage', amount: 700, cost: 'exile_gutter', cost_n: 2 }] });
lich.deployed_turn = 1;
st.sides.player.field[0] = lich;
const bones = [unit(st, 'B1'), unit(st, 'B2'), unit(st, 'B3')];
st.sides.player.gutter.push(...bones);
st.sides.opponent.morale = 5000;
assert.ok(st.activations('player', 0).includes(1), 'enough cards in the Gutter to pay');
assert.ok(st._activate('player', 0, 1));
assert.deepEqual(st.sides.player.gutter, [bones[2]], 'the two oldest paid');
assert.equal(st.sides.opponent.morale, 4300);
st.turn += 2;
assert.ok(!st.activations('player', 0).includes(1), "one card left: it can't pay 2");

// The opponent's Gutter as a condition and a "for each"
st = duel();
st.sides.opponent.gutter.push(unit(st, 'A'), unit(st, 'B'), unit(st, 'C'));
st.sides.opponent.morale = 5000;
assert.equal(st._fxCond('player', -1, { if: 'foe_gutter_ge', n: 3 }, null), true);
assert.equal(st._fxCond('player', -1, { if: 'foe_gutter_ge', n: 4 }, null), false);
st._doFx('player', -1, src, { do: 'damage', amount: 100, per: 'foe_gutter' });
assert.equal(st.sides.opponent.morale, 4700, '100 for each card in their Gutter');
// ...counting only one kind of card (and clan): characters, not Hustles or Ambushes
st.sides.opponent.gutter.push(st.makeCard({ id: 'test_trick', name: 'Trick', cardType: 'hustle', clanTag: 'test' }));
st._doFx('player', -1, src, { do: 'damage', amount: 100, per: 'foe_gutter', per_kind: 'gang_member' });
assert.equal(st.sides.opponent.morale, 4400, 'the Hustle in their Gutter does not count');
st.sides.player.gutter.push(unit(st, 'D'), unit(st, 'E', 1000, 1000, { clanTag: 'other' }),
    st.makeCard({ id: 'test_trap', name: 'Trap', cardType: 'ambush', clanTag: 'test' }));
assert.equal(st._perCount('player', -1, { per: 'gutter' }), 3);
assert.equal(st._perCount('player', -1, { per: 'gutter', per_kind: 'gang_member' }), 2, 'characters only');
assert.equal(st._perCount('player', -1, { per: 'gutter', per_kind: 'gang_member', per_clan: 'test' }), 1, "that clan's characters only");
assert.equal(st._perCount('player', -1, { per: 'gutter', per_kind: 'ambush' }), 1);

// "You take no battle damage from brawls involving this card"
const brawl = (atkStats, defStats, guardOn) => {
    const s2 = duel();
    s2.phase = 'brawl';
    s2.turn = 5;
    const a = unit(s2, 'Att', atkStats[0], atkStats[1], guardOn === 'att' ? { effects: [{ when: 'passive', do: 'no_battle_damage' }] } : {});
    const d = unit(s2, 'Def', defStats[0], defStats[1], guardOn === 'def' ? { effects: [{ when: 'passive', do: 'no_battle_damage' }] } : {});
    a.deployed_turn = 1;
    s2.sides.player.field[1] = a;
    s2.sides.opponent.field[1] = d;
    s2.sides.player.morale = 5000;
    s2.sides.opponent.morale = 5000;
    assert.ok(s2.doAction('player', { kind: 'attack', from: 1, target: 1 }), 'the attack goes ahead');
    for (let i = 0; i < 6 && s2._asks.length; i++) answer(s2, s2._asks[0].options && s2._asks[0].options.find(o => o.id === 'no') ? 'no' : undefined);
    return [s2.sides.player.morale, s2.sides.opponent.morale];
};
assert.deepEqual(brawl([500, 0], [1500, 1000], 'att'), [5000, 5000], 'the Skeleton attacks and loses: no battle damage');
assert.deepEqual(brawl([2000, 0], [500, 0], 'def'), [5000, 5000], 'the Skeleton is attacked and loses: no battle damage');
assert.deepEqual(brawl([2000, 0], [500, 0], 'att'), [5000, 3500], 'the Skeleton wins: the opponent still takes damage');
assert.deepEqual(brawl([500, 0], [1500, 1000], ''), [4000, 5000], '(without it, the loser takes the difference)');

// Tribute (absorb): "when you deploy another character, you may tribute it: this card gains its ATK and DEF"
st = duel();
const eater = unit(st, 'Eater', 1000, 800, { effects: [{ when: 'ally_deployed', do: 'absorb', target: 'deployed' }] });
st.sides.player.field[0] = eater;
const snack = unit(st, 'Snack', 600, 400);
st.sides.player.field[2] = snack;
st._runFx('player', 0, eater, 'ally_deployed', snack);
const offer = st._asks.find(a => a.key === 'absorb');
assert.ok(offer && offer.options.some(o => o.id === 'no'), 'the player may say no');
answer(st, 'yes');
st._recalc();
assert.equal(st.sides.player.field[2], null, 'tributed');
assert.ok(st.sides.player.gutter.includes(snack));
assert.deepEqual([eater.attack, eater.defense], [1600, 1200], 'it gained its ATK and DEF');
// ...or keep it
st = duel();
const eater2 = unit(st, 'Eater', 1000, 800, { effects: [{ when: 'ally_deployed', do: 'absorb', target: 'deployed' }] });
st.sides.player.field[0] = eater2;
const keeper = unit(st, 'Keeper', 600, 400);
st.sides.player.field[2] = keeper;
st._runFx('player', 0, eater2, 'ally_deployed', keeper);
answer(st, 'no');
assert.equal(st.sides.player.field[2], keeper, 'kept');
assert.equal(eater2.attack, 1000);

// "When it attacks a leader": only at a leader
const leaderDuel = (atLeader) => {
    const s3 = duel();
    s3.phase = 'brawl';
    s3.sides.opponent.leader = s3.makeCard({ id: 'test_boss', name: 'Boss', cardType: 'leader', clanTag: 'test', influence: 3000, attack: 2000, defense: 2000 });
    s3.sides.opponent.leader_state = 'dormant';
    const a = unit(s3, 'Raider', 1000, 1000, { effects: [{ when: 'attack_leader', do: 'draw', amount: 1 }] });
    a.deployed_turn = 1;
    s3.sides.player.field[1] = a;
    s3.sides.player.deck = [s3.makeCard('test_grunt_x'), s3.makeCard('test_grunt_x')];
    if (!atLeader) s3.sides.opponent.field[1] = unit(s3, 'Mook', 100, 100);
    const before = s3.sides.player.hand.length;
    s3._attack('player', 1, atLeader ? -2 : 1);
    while (s3._asks.length) answer(s3);
    return s3.sides.player.hand.length - before;
};
assert.equal(leaderDuel(true), 1, 'attacking the leader: it draws');
assert.equal(leaderDuel(false), 0, 'attacking a character: nothing');

// SILENCE for good
st = duel();
const chatty = unit(st, 'Chatty', 1000, 1000, { effects: [{ when: 'passive', do: 'buff', target: 'self', atk: 500 }] });
st.sides.opponent.field[0] = chatty;
st._doFx('player', -1, src, { do: 'silence', target: 'enemies', until: 'forever' });
st.turn += 20;
st._recalc();
assert.ok(st.statuses(chatty).includes('silence'), 'still silenced 20 turns later');
assert.equal(chatty.attack, 1000, 'its passive stays off');

console.log('underworld: ok');
