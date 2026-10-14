// Each Card Forge passive does what its card text says (shared/duel/DuelState.js; duel_state.gd
// plays the same rules, which the golden test checks).
//   node shared/duel/passives.test.mjs
import assert from 'node:assert';
import { DuelState, DIRECT } from './DuelState.js';
import { CARD_CATALOG } from '../cards.js';

// A plain character for the tests to build on (no effects of its own)
CARD_CATALOG.test_grunt = { id: 'test_grunt', name: 'Test Grunt', clan: 'test', cardType: 'gang_member', level: 1,
    authority: 1, attack: 700, defense: 500, rarity: 1, clanTag: 'test', effectKey: '' };

/** A board in the brawl phase of turn 3, player to act, with these cards on the field. */
function board(player = [], opponent = []) {
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.turn = 3;
    st.phase = 'brawl';
    for (const [side, cards] of [['player', player], ['opponent', opponent]]) {
        cards.forEach((spec, slot) => {
            if (!spec) return;
            const c = st.makeCard({ id: 'test_grunt', effectKey: '', ...spec });
            for (const k of ['position', 'face_down', 'downed']) if (k in spec) c[k] = spec[k];   // makeCard resets these
            st.sides[side].field[slot] = c;
        });
    }
    st._recalc();
    return st;
}
const passive = (kind, extra = {}) => ({ effects: [{ when: 'passive', do: kind, ...extra }] });

// Guard: a standing Guard must be attacked first; a Downed one doesn't protect
let st = board([{}], [{}, passive('guard')]);
assert.deepEqual(st.attackTargets('player'), [1], 'only the Guard can be attacked');
st.cardAt('opponent', 1).downed = true;
assert.ok(st.attackTargets('player').includes(0), 'a Downed Guard protects no one');

// Attacks twice each turn
st = board([passive('double_attack')], []);
assert.ok(st._attack('player', 0, DIRECT), 'first attack');
assert.ok(st.canAttackWith('player', 0), 'ready for a second attack');
assert.ok(st._attack('player', 0, DIRECT), 'second attack');
assert.ok(!st.canAttackWith('player', 0), 'no third attack');

// PIERCE always: beating a DEF character also costs the opponent Morale (without it, nothing)
const moraleLost = (spec) => {
    const b = board([{ attack: 2000, ...spec }], [{ defense: 500, position: 'def' }]);
    const before = b.sides.opponent.morale;
    b._attack('player', 0, 0);
    return before - b.sides.opponent.morale;
};
assert.equal(moraleLost({}), 0, 'beating a DEF character costs no Morale');
assert.ok(moraleLost(passive('pierce')) > 0, 'with PIERCE it does');

// Cheaper cards: your (clan) cards cost less, never below 0
st = board([passive('cost_down', { amount: 2 }), passive('cost_down', { amount: 1, clan: 'nebula' })]);
assert.equal(st.costOf('player', { authority: 5, clanTag: 'militia' }), 3);
assert.equal(st.costOf('player', { authority: 5, clanTag: 'nebula' }), 2);
assert.equal(st.costOf('player', { authority: 1, clanTag: 'militia' }), 0);
assert.equal(st.costOf('opponent', { authority: 5, clanTag: 'militia' }), 5, "the opponent's cards cost the same");

// Stays up while you control another character
st = board([passive('no_down'), {}]);
assert.equal(st._defeat('player', 0), 'saved', 'stays standing with an ally');
st.sides.player.field[1] = null;
assert.equal(st._defeat('player', 0), 'downed', 'alone, it can be Downed');

// Immune: statuses don't land
st = board([{ effects: [{ when: 'deploy', do: 'poison', target: 'enemies', amount: 200 }] }], [passive('immune'), {}]);
st._doFx('player', 0, st.cardAt('player', 0), st.cardAt('player', 0).effects[0]);
assert.equal(st.cardAt('opponent', 0).poison, undefined, 'immune card is not POISONED');
assert.ok(st.cardAt('opponent', 1).poison, 'the other card is');

// Can't be targeted: an opponent's effect can't choose it (but "all enemies" still hits it)
st = board([{}], [passive('untargetable')]);
let chosen = null;
st._askTarget('player', 'fx', 'choose', st.cardAt('player', 0), [{ side: 'opponent', slot: 0, card: st.cardAt('opponent', 0) }], 'opponent', (e) => { chosen = e; });
assert.equal(chosen, null, 'not chosen by the opponent');
st._askTarget('opponent', 'fx', 'choose', st.cardAt('opponent', 0), [{ side: 'opponent', slot: 0, card: st.cardAt('opponent', 0) }], 'opponent', (e) => { chosen = e; });
assert.ok(chosen, 'its owner can still choose it');

// Enemy auras: a passive can weaken the other side's characters
st = board([{ attack: 1000 }], [passive('buff', { target: 'enemies', atk: -300 })]);
assert.equal(st.cardAt('player', 0).attack, 700, 'enemy aura lowers ATK');
st = board([{ attack: 1000, clanTag: 'militia' }], [passive('buff', { target: 'enemies', atk: -300, clan: 'nebula' })]);
assert.equal(st.cardAt('player', 0).attack, 1000, 'clan filter respected');

// A face-down card's passives are off
st = board([{}], [{ ...passive('guard'), face_down: true }, {}]);
assert.ok(st.attackTargets('player').includes(1), 'face-down Guard does nothing');

// An Ambush for one clan is only offered when a character of that clan is attacked
const ambushOffered = (defClan) => {
    const b = board([{ attack: 2000 }], [{ clanTag: defClan }]);
    b.sides.opponent.field[5] = b.makeCard({ id: 'test_grunt', cardType: 'ambush', effectKey: '', ambushClan: 'nebula',
        effects: [{ when: 'ambush', do: 'bounce', target: 'attacker' }] });
    b.sides.opponent.field[5].face_down = true;
    let asked = false;
    b._ask = (side, kind) => { if (kind === 'ambush') asked = true; };
    b._atkAmbush({ side: 'player', foe: 'opponent', from: 0, target: 0, att: b.cardAt('player', 0), bonus: 0 });
    return asked;
};
assert.ok(ambushOffered('nebula'), 'offered when a Nebula character is attacked');
assert.ok(!ambushOffered('militia'), 'not offered for another clan');

// Leaders: "dormant" effects work only while Dormant; an awaken condition for any clan; "awaken" effects
{
    const b = board([{ attack: 1000, clanTag: 'nebula' }, { clanTag: 'nebula' }], []);
    b.sides.player.leader = b.makeCard({ id: 'test_grunt', cardType: 'leader', attack: 3000, defense: 3000, clanTag: 'nebula',
        awakenCondition: { chars: 3, clan: 'nebula' },
        effects: [{ when: 'dormant', do: 'buff', target: 'allies', atk: 200 }, { when: 'awaken', do: 'draw', amount: 2 }] });
    b.sides.player.leader_state = 'dormant';
    b._recalc();
    assert.equal(b.cardAt('player', 0).attack, 1200, 'Dormant leader aura');
    let asked = null;
    b._ask = (side, kind, text, card, options, cb) => { asked = { kind, cb }; };
    b._checkAwaken('player');
    assert.equal(asked, null, 'two Nebula characters: not yet');
    b.sides.player.field[2] = b.makeCard({ id: 'test_grunt', clanTag: 'nebula' });
    b._checkAwaken('player');
    assert.equal(asked && asked.kind, 'awaken', 'three Nebula characters: awakens');
    const hand = b.sides.player.hand.length;
    b.sides.player.deck = [b.makeCard('test_grunt'), b.makeCard('test_grunt')];
    asked.cb('3');
    assert.equal(b.sides.player.leader_state, 'awake');
    assert.equal(b.sides.player.hand.length, hand + 2, 'awaken effect: draw 2');
    assert.equal(b.cardAt('player', 0).attack, 1000, 'the Dormant aura ends');
}

// Search filters: Authority N or less, clan, name, how many, and choosing
{
    const b = board([{}], []);
    const mk = (spec) => b.makeCard({ id: 'test_grunt', cardType: 'gang_member', ...spec });
    b.sides.player.deck = [mk({ name: 'Big', authority: 6, clanTag: 'nebula' }), mk({ name: 'Kade', authority: 2, clanTag: 'nebula' }),
        mk({ name: 'Small Fry', authority: 1, clanTag: 'militia' }), mk({ name: 'Nix', authority: 4, clanTag: 'nebula' })];
    b.sides.player.hand = [];
    const src = b.cardAt('player', 0);
    b._doFx('player', 0, src, { do: 'search', clan: 'nebula', max_auth: 4 });
    assert.deepEqual(b.sides.player.hand.map(c => c.name), ['Nix'], 'top-most NEBULA card with 4 or less Authority');
    b._doFx('player', 0, src, { do: 'search', name: 'kade' });
    assert.equal(b.sides.player.hand[1].name, 'Kade', 'by name');
    b.sides.player.deck.push(mk({ name: 'A', authority: 1 }), mk({ name: 'B', authority: 3 }));
    let ask = null;
    b._ask = (side, key, prompt, card, options, cb) => { ask = { options, cb }; };
    b._doFx('player', 0, src, { do: 'search', max_auth: 3, choose: true });
    assert.deepEqual(ask.options.map(o => o.label), ['B  (3)', 'A  (1)', 'SMALL FRY  (1)', 'SKIP'], 'choices, best first (and skipping)');
    ask.cb('1');
    assert.equal(b.sides.player.hand[2].name, 'A', 'the chosen card');
}

// Revive: a character from the Gutter onto the first empty lane; Break Ambush
{
    const b = board([{}], [{}]);
    b.sides.player.gutter = [b.makeCard({ id: 'test_grunt', name: 'Old Friend', cardType: 'gang_member', authority: 3 })];
    b.sides.player.gutter[0].downed = true;
    b._doFx('player', 0, b.cardAt('player', 0), { do: 'revive', max_auth: 4 });
    assert.equal(b.cardAt('player', 1) && b.cardAt('player', 1).name, 'Old Friend', 'revived into lane 2');
    assert.ok(!b.cardAt('player', 1).downed && b.sides.player.gutter.length === 0);
    b.sides.opponent.field[6] = b.makeCard({ id: 'test_grunt', cardType: 'ambush' });
    b.sides.opponent.field[8] = b.makeCard({ id: 'test_grunt', cardType: 'ambush' });
    b._doFx('player', 0, b.cardAt('player', 0), { do: 'break_ambush', amount: 1 });
    assert.equal(b.cardAt('opponent', 6), null, 'leftmost face-down card destroyed');
    assert.ok(b.cardAt('opponent', 8), 'only one');
}

// Triggers: when the opponent deploys; when you play a Hustle. Conditions: leader Awake, hand N+
{
    const b = board([{ effects: [{ when: 'foe_deployed', do: 'heal', amount: 300 }, { when: 'hustle_played', do: 'draw', amount: 1 }] }], [{}]);
    b.sides.player.morale = 5000;
    b._onDeploy('opponent', 0, b.cardAt('opponent', 0));
    assert.equal(b.sides.player.morale, 5300, 'foe_deployed fired');
    b.sides.player.deck = [b.makeCard('test_grunt')];
    const h = b.makeCard({ id: 'test_grunt', cardType: 'hustle', authority: 0, effects: [{ do: 'heal', amount: 100 }] });
    b.sides.player.hand = [h];
    b.sides.player.authority = 5;
    b.phase = 'deployment';
    const before = b.sides.player.hand.length;
    assert.ok(b._hustle('player', h.uid), 'hustle played');
    assert.equal(b.sides.player.hand.length, before, 'hustle left the hand and hustle_played drew one');
    b.sides.player.leader_state = 'awake';
    assert.ok(b._fxCond('player', 0, { if: 'leader_awake' }, null));
    assert.ok(b._fxCond('player', 0, { if: 'hand_ge', n: 1 }, null) && !b._fxCond('player', 0, { if: 'hand_ge', n: 5 }, null));
}

// Dormant leader: triggered effects, gifts to your characters, more awaken conditions
{
    const b = board([{ clanTag: 'nebula' }], [{}]);
    b.sides.player.leader = b.makeCard({ id: 'test_grunt', cardType: 'leader', attack: 3000, defense: 3000, clanTag: 'nebula',
        awakenCondition: { influence: 1000, ready: true },
        effects: [{ when: 'dormant_turn_start', do: 'heal', amount: 300 }, { when: 'dormant', do: 'immune', clan: 'nebula' },
            { when: 'dormant_hit', do: 'draw', amount: 1 }] });
    b.sides.player.leader.influence = 3000;
    b.sides.player.leader_state = 'dormant';
    b.sides.player.morale = 5000;
    b._leaderFx('player', 'dormant_turn_start');
    assert.equal(b.sides.player.morale, 5300, 'Dormant: start of turn heal');
    assert.ok(b._passive('player', 0, b.cardAt('player', 0), 'immune'), 'Dormant leader makes NEBULA characters immune');
    b.sides.player.deck = [b.makeCard('test_grunt')];
    const hand = b.sides.player.hand.length;
    b._hitLeader({ side: 'opponent', foe: 'player', from: 0, att: { attack: 2500 }, bonus: 0 });
    assert.equal(b.sides.player.hand.length, hand + 1, 'Dormant: drew when attacked');
    let asked = null;
    b._ask = (side, kind, text, card, options, cb) => { asked = { kind, cb }; };
    b._checkAwaken('player');
    assert.equal(asked && asked.kind, 'awaken', 'awakens at 1000 Influence or less');
    asked.cb('2');
    assert.equal(b.cardAt('player', 2).has_attacked, false, 'ready: may attack the turn it Awakens');
}

// The "Only if" clan is separate from the target clan
{
    const b = board([{ clanTag: 'nebula' }, { clanTag: 'nebula' }], [{ clanTag: 'militia' }]);
    const e = { do: 'down', target: 'enemy', if: 'adjacent', if_clan: 'nebula' };
    assert.ok(b._fxCond('player', 0, e, null), 'next to a NEBULA ally');
    assert.ok(!b._fxCond('player', 0, { ...e, if_clan: 'militia' }, null), 'no MILITIA ally next to it');
    assert.ok(b._fxCond('player', 0, { ...e, clan: 'militia', if_clan: '' }, null), 'if_clan "" = any clan, whatever the target clan');
    assert.ok(!b._fxCond('player', 0, { ...e, clan: 'militia', if_clan: undefined }, null), 'old cards: the effect clan counts');
}

// No endless attacks: "attack again" gives at most one extra attack per card each turn
{
    const b = board([{ attack: 3000, effects: [{ when: 'direct', do: 'attack_again' }] }], []);
    let attacks = 0;
    while (attacks < 10 && b.canAttackWith('player', 0) && b._attack('player', 0, DIRECT)) attacks++;
    assert.equal(attacks, 2, 'one attack plus one extra');
}

// New conditions
{
    const b = board([{}, { downed: true }], [{}]);
    b.sides.opponent.hand = [b.makeCard('test_grunt')];
    assert.ok(b._fxCond('player', 0, { if: 'foe_hand_le', n: 1 }, null) && !b._fxCond('player', 0, { if: 'foe_hand_le', n: 0 }, null));
    assert.ok(!b._fxCond('player', 0, { if: 'foe_ambush' }, null));
    b.sides.opponent.field[7] = b.makeCard({ id: 'test_grunt', cardType: 'ambush' });
    assert.ok(b._fxCond('player', 0, { if: 'foe_ambush' }, null), 'opponent has a face-down card');
    b.sides.player.authority_max = 6;
    assert.ok(b._fxCond('player', 0, { if: 'authority_ge', n: 6 }, null) && !b._fxCond('player', 0, { if: 'authority_ge', n: 7 }, null));
    assert.ok(b._fxCond('player', 0, { if: 'ally_downed' }, null) && !b._fxCond('player', 1, { if: 'ally_downed' }, null));
}

// Influence back (up to the start), more max Authority, SILENCE, elusive
{
    const b = board([{}], [{ effects: [{ when: 'passive', do: 'buff', target: 'self', atk: 500 }] }, {}]);
    b.sides.player.leader = b.makeCard({ id: 'test_grunt', cardType: 'leader', defense: 3000 });
    b.sides.player.leader.influence = 1000; b.sides.player.leader.influence_max = 3000;
    b.sides.player.leader_state = 'dormant';
    const me = b.cardAt('player', 0);
    b._doFx('player', 0, me, { do: 'influence', amount: 1500 });
    assert.equal(b.sides.player.leader.influence, 2500);
    b._doFx('player', 0, me, { do: 'influence', amount: 1500 });
    assert.equal(b.sides.player.leader.influence, 3000, 'never above where it started');
    b.sides.player.authority_max = 4; b.sides.player.authority = 1;
    b._doFx('player', 0, me, { do: 'ramp', amount: 2 });
    assert.equal(b.sides.player.authority_max, 6); assert.equal(b.sides.player.authority, 3);
    b.sides.opponent.field[1] = null;
    b._recalc();
    const atk = b.cardAt('opponent', 0).attack;
    b._doFx('player', 0, me, { do: 'silence', target: 'enemy' });
    assert.equal(b.cardAt('opponent', 0).attack, atk - 500, 'silenced: its +500 ATK passive is off');
    assert.ok(b.statuses(b.cardAt('opponent', 0)).includes('silence'));
    const e = board([{}], [{ effects: [{ when: 'passive', do: 'elusive' }] }, {}]);
    assert.deepEqual(e.attackTargets('player'), [1], 'elusive card hides behind the other');
    const e2 = board([{}], [{ effects: [{ when: 'passive', do: 'elusive' }] }, { effects: [{ when: 'passive', do: 'elusive' }] }]);
    assert.deepEqual(e2.attackTargets('player'), [0, 1], 'all elusive: all can be attacked (no lock)');
}

// "After this card attacks 3 times: draw a card" (times on attack triggers)
{
    const b = board([{ attack: 500, effects: [{ when: 'attack', do: 'draw', amount: 1, times: 3 }] }], []);
    b.sides.player.deck = [b.makeCard('test_grunt'), b.makeCard('test_grunt')];
    const drawn = () => b.sides.player.hand.length;
    const start = drawn();
    for (let i = 1; i <= 3; i++) {
        b.cardAt('player', 0).has_attacked = false;
        b._attack('player', 0, DIRECT);
        assert.equal(drawn() - start, i === 3 ? 1 : 0, `after attack ${i}`);
    }
}

// Immune to chosen statuses only
{
    const b = board([{ effects: [{ when: 'deploy', do: 'poison', target: 'enemies', amount: 200 }, { when: 'deploy', do: 'burn', target: 'enemies', amount: 200 }] }],
        [{ effects: [{ when: 'passive', do: 'immune', statuses: ['poison'] }] }]);
    const me = b.cardAt('player', 0);
    b._doFx('player', 0, me, me.effects[0]);
    b._doFx('player', 0, me, me.effects[1]);
    assert.equal(b.cardAt('opponent', 0).poison, undefined, 'immune to POISON');
    assert.ok(b.cardAt('opponent', 0).burn, 'but not to BURN');
}

console.log('all good');
