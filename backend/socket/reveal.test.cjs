'use strict';
// MARKED (Card Forge passive "reveal", e.g. Marked Cards): while a player has it face-up, the server's
// view shows them their opponent's hand and face-down cards. Nobody else sees more, and an ally (Turf
// Defense) isn't an opponent.
//   node backend/socket/reveal.test.cjs
const path = require('path');
const assert = require('assert');
const { viewFor } = require(path.join(__dirname, 'onlineMatch.js'));

(async () => {
    const { DuelState } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelState.js').replace(/\\/g, '/'));
    let uid = 0;
    const card = (st, extra = {}) => st.makeCard({ id: `t_${uid++}`, name: `Card ${uid}`, cardType: 'gang_member', clanTag: 'test',
        attack: 1000, defense: 1000, authority: 1, effects: [], ...extra });
    const marked = (st) => card(st, { name: 'Marked Cards', cardType: 'hustle', subtype: 'continuous',
        effects: [{ when: 'passive', do: 'reveal' }] });

    // 1v1: Marked Cards face-up in the player's back row
    const st = new DuelState({ player: [], opponent: [] }, {}, {}, 'player', -1);
    st.sides.opponent.hand = [card(st, { name: 'Secret Plan' })];
    const ambush = card(st, { name: 'Hidden Trap', cardType: 'ambush' });
    ambush.face_down = true;
    st.sides.opponent.field[6] = ambush;
    const hidden = (v) => v.sides.opponent.hand[0].name === undefined && v.sides.opponent.field[6].name === undefined;
    assert.ok(!st.reveals('player'));
    assert.ok(hidden(viewFor(st, 'player')), 'without it, their hand and face-down cards are hidden');
    const m = marked(st);
    st.sides.player.field[5] = m;
    assert.ok(st.reveals('player') && !st.reveals('opponent'));
    let v = viewFor(st, 'player');
    assert.equal(v.sides.opponent.hand[0].name, 'Secret Plan', 'their hand is shown');
    assert.equal(v.sides.opponent.field[6].name, 'Hidden Trap', 'their face-down cards are shown');
    assert.ok(hidden(viewFor(st, 'spectator')), 'a spectator still sees nothing hidden');
    assert.equal(viewFor(st, 'opponent').sides.player.hand.length, 0);
    // Set face-down itself, it does nothing
    m.face_down = true;
    assert.ok(!st.reveals('player') && hidden(viewFor(st, 'player')), 'face-down, it does nothing');
    m.face_down = false;
    // A Dormant leader with it, or a character with it, does the same
    st.sides.player.field[5] = null;
    st.sides.player.field[1] = card(st, { effects: [{ when: 'passive', do: 'reveal' }] });
    assert.ok(st.reveals('player'), 'a character with it');
    st.sides.player.field[1] = null;
    st.sides.player.leader = card(st, { cardType: 'leader', effects: [{ when: 'dormant', do: 'reveal' }] });
    st.sides.player.leader_state = 'dormant';
    assert.ok(st.reveals('player'), 'a Dormant leader with it');
    st.sides.player.leader_state = 'awake';
    assert.ok(!st.reveals('player'), '(only while it is Dormant)');

    // Turf Defense: it shows the boss's hand, not the ally's
    const co = new DuelState({ p1: [], p2: [], boss: [] }, {}, {}, 'p1', -1,
        { order: ['p1', 'p2', 'boss'], teams: { p1: 'crew', p2: 'crew', boss: 'boss' } });
    co.sides.p2.hand = [card(co, { name: 'Ally Card' })];
    co.sides.boss.hand = [card(co, { name: 'Boss Card' })];
    co.sides.p1.field[5] = marked(co);
    v = viewFor(co, 'p1');
    assert.equal(v.sides.boss.hand[0].name, 'Boss Card', "the boss's hand is shown");
    assert.equal(v.sides.p2.hand[0].name, undefined, "the ally's hand stays hidden");
    console.log('reveal: ok');
})().catch((e) => { console.error(e); process.exit(1); });
