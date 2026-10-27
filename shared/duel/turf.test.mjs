// Turf Defense rules: two players (a team) against a boss. Teammates aren't foes, the boss has its
// own Morale, draws and gets Authority extra, and its phases fire as its Morale drops; the team wins
// when the boss is out, the boss when both players are (shared/duel/DuelState.js; duel_state.gd plays
// the same rules, which the golden test checks).
//   node shared/duel/turf.test.mjs
import assert from 'node:assert';
import { DuelState, choose, cpuSetup } from './DuelAI.js';
import { CARD_CATALOG } from '../cards.js';
import { BOSSES, bossSetup, turfRules, prizeLine, prizeCardIds } from '../turf.js';

const SEATS = ['p1', 'p2', 'boss'];
const rules = (extra = {}) => ({
    order: SEATS, teams: { p1: 'crew', p2: 'crew', boss: 'boss' }, morale: { boss: 10000 },
    boss: { seat: 'boss', name: 'Test Boss', draw: 1, authority: 1, phases: [
        { below: 6600, label: 'ENRAGED', fx: [{ do: 'heal', amount: 500 }] },
        { below: 3300, label: 'LAST STAND', fx: [{ do: 'buff', target: 'allies', atk: 500, until: 'forever' }] },
    ] },
    ...extra,
});
const empty = () => new DuelState({ p1: [], p2: [], boss: [] }, {}, {}, 'p1', -1, rules());

// Seats, teams and Morale
let st = empty();
assert.deepEqual(st.seats, SEATS, 'turn order from rules.order: both players, then the boss');
assert.deepEqual(st.foesOf('p1'), ['boss'], "a teammate isn't a foe");
assert.deepEqual(st.foesOf('p2'), ['boss']);
assert.deepEqual(st.foesOf('boss'), ['p1', 'p2'], 'the boss fights both');
assert.equal(st.sides.boss.morale, 10000);
assert.equal(st.sides.boss.max_morale, 10000);
assert.equal(st.sides.p1.morale, 6000);

// Healing stops at the boss's own most Morale, not 6000
st.sides.boss.morale = 9800;
st._heal('boss', { name: 'Test' }, 1000, -10);
assert.equal(st.sides.boss.morale, 10000);

// Phases: each once, in order, as Morale drops past them; their effects run as the boss
st = empty();
st._damage('boss', 3000);   // 7000: none yet
assert.equal(st.sides.boss.boss_phase ?? 0, 0);
st._damage('boss', 500);    // 6500: ENRAGED, which heals 500 (back to 7000)
assert.equal(st.sides.boss.boss_phase, 1);
assert.equal(st.sides.boss.morale, 7000, 'the phase healed it');
const ev = st.takeEvents().filter(e => e.type === 'boss_phase');
assert.deepEqual(ev.map(e => [e.phase, e.label]), [[1, 'ENRAGED']]);
st._damage('boss', 4000);   // 3000: LAST STAND
assert.equal(st.sides.boss.boss_phase, 2);
st._damage('boss', 1000);
assert.equal(st.sides.boss.boss_phase, 2, 'no more phases');

// The boss draws and gets Authority extra at the start of its turn
const card = (n) => ({ id: 'test_' + n, name: n, cardType: 'gang_member', clanTag: 'test', attack: 500, defense: 500, authority: 1 });
st = new DuelState({ p1: [card('a'), card('b')], p2: [card('c'), card('d')], boss: [card('e'), card('f'), card('g'), card('h')] }, {}, {}, 'p1', -1, rules());
st.turn = 3;
st.active = 'boss';
st.sides.boss.turns = 1;
const handBefore = st.sides.boss.hand.length;
st._beginTurn();
assert.equal(st.sides.boss.hand.length, handBefore + 2, 'its draw and one extra');
assert.equal(st.sides.boss.authority, st.sides.boss.authority_max + 1, 'one extra Authority this turn');

// The team wins when the boss is out (both players first); the boss when both players are
st = empty();
st._damage('boss', 20000);
assert.equal(st.winner, 'p1');
assert.equal(st.places.p1, 1);
assert.equal(st.places.p2, 1, 'both players win together');
st = empty();
st._damage('p1', 6000);
assert.equal(st.winner, '', 'one player out: the other fights on');
assert.ok(st.sides.p1.out);
assert.deepEqual(st.foesOf('boss'), ['p2']);
st._damage('p2', 6000);
assert.equal(st.winner, 'boss');

// Whole CPU games: always a winner, and only ever a team (both players placed 1st together, or the boss)
let crew = 0;
for (let g = 0; g < 16; g++) {
    const setups = { p1: cpuSetup(['nebula', 'militia', 'wildcard', 'underworld'][g % 4]), p2: cpuSetup(['militia', 'nebula', 'underworld', 'wildcard'][g % 4]),
        boss: cpuSetup(['underworld', 'wildcard', 'militia', 'nebula'][g % 4]) };
    const game = new DuelState(Object.fromEntries(SEATS.map(s => [s, setups[s].deck])), Object.fromEntries(SEATS.map(s => [s, setups[s].hideout])),
        Object.fromEntries(SEATS.map(s => [s, setups[s].leader])), 'p1', 2000 + g, rules());
    game.start();
    let moves = 0;
    while (game.winner === '' && moves < 6000) {
        const who = game.pending.side || game.active;
        let a = choose(game, who, 'normal');
        if (!Object.keys(a).length || !game.doAction(who, a)) {
            a = { kind: 'next' };
            assert.ok(game.doAction(who, a), `game ${g}: ${who} can always move on (${JSON.stringify(game.pending).slice(0, 200)})`);
        }
        moves += 1;
        for (const e of game.takeEvents()) {
            // nobody ever attacks a teammate
            if (e.type === 'attack' && e.foe) assert.ok(!game._teammates(e.side, e.foe), `game ${g}: ${e.side} attacked teammate ${e.foe}`);
        }
    }
    assert.notEqual(game.winner, '', `game ${g} finished`);
    if (game.winner !== 'boss') {
        crew += 1;
        assert.ok(game.sides.boss.out, `game ${g}: the crew won, so the boss is out`);
    } else {
        assert.ok(game.sides.p1.out && game.sides.p2.out, `game ${g}: the boss won, so both players are out`);
    }
}
console.log(`turf: ok (the crew won ${crew} of 16 CPU games)`);

// each_foe: a phase's damage hits both players
st = new DuelState({ p1: [], p2: [], boss: [] }, {}, {}, 'p1', -1, rules({ boss: { seat: 'boss', name: 'B', phases: [
    { below: 9000, label: 'SLAM', fx: [{ do: 'damage', amount: 700, each_foe: true }] }] } }));
st._damage('boss', 1500);
assert.equal(st.sides.p1.morale, 5300);
assert.equal(st.sides.p2.morale, 5300, 'both players took it');

// The boss never decks out: its Gutter goes back into its deck (a player still loses on an empty deck)
st = new DuelState({ p1: [], p2: [], boss: [] }, {}, {}, 'p1', 5, rules());
st.sides.boss.gutter.push(st.makeCard(card('x')), st.makeCard(card('y')));
st._draw('boss');
assert.equal(st.winner, '');
assert.equal(st.sides.boss.hand.length, 1);
assert.equal(st.sides.boss.deck.length + st.sides.boss.gutter.length, 1);
assert.ok(st.takeEvents().some(e => e.type === 'recycle' && e.count === 2));
st._draw('p1');
assert.ok(st.sides.p1.out, 'a player with an empty deck is out');

// The real bosses (godot/data/bosses.json): every level's deck is a full deck of real cards, and two
// normal CPUs can play it through. "node shared/duel/turf.test.mjs --games 20" shows how each one does.
// Prizes: a Striver comes with every level it promotes to, and no boss plays a prize
for (const boss of BOSSES) {
    const line = prizeLine(boss.prize);
    assert.ok(line.length >= 1 && line[0] === boss.prize, `${boss.id}: its prize line starts with the prize`);
    for (const id of line.slice(0, -1)) assert.ok(line.includes(CARD_CATALOG[id].promotesTo), `${boss.id}: ${id} promotes within the line`);
}
assert.ok(prizeCardIds().size >= BOSSES.length, 'every boss has its own prize');
const games = Number(process.argv[process.argv.indexOf('--games') + 1]) || 2;
const clans = ['nebula', 'militia', 'wildcard', 'underworld'];
for (const boss of BOSSES) {
    for (const lv of boss.levels) {
        const b = bossSetup(boss, lv);
        assert.equal(b.deck.length, 40, `${boss.id} ${lv.level}: 40 cards`);
        for (const id of [...b.deck, ...b.hideout, b.leader, boss.prize]) assert.ok(CARD_CATALOG[id], `${boss.id}: ${id} is a card`);
        for (const [id, n] of lv.add || []) assert.ok(b.deck.filter(x => x === id).length >= n, `${boss.id} ${lv.level}: ${id} in the deck`);
        let won = 0;
        for (let g = 0; g < games; g++) {
            const p1 = cpuSetup(clans[g % 4]), p2 = cpuSetup(clans[(g + 1 + lv.level) % 4]);
            const game = new DuelState({ p1: p1.deck, p2: p2.deck, boss: b.deck }, { p1: p1.hideout, p2: p2.hideout, boss: b.hideout },
                { p1: p1.leader, p2: p2.leader, boss: b.leader }, 'p1', 9000 + g * 7 + lv.level, turfRules(boss, lv));
            game.start();
            let moves = 0;
            while (game.winner === '' && moves < 8000) {
                const who = game.pending.side || game.active;
                const a = choose(game, who, who === 'boss' ? lv.ai : 'normal');
                if (!Object.keys(a).length || !game.doAction(who, a)) assert.ok(game.doAction(who, { kind: 'next' }), `${boss.id} ${lv.level}: ${who} stuck`);
                moves += 1;
                game.takeEvents();
            }
            assert.notEqual(game.winner, '', `${boss.id} ${lv.level} game ${g} finished`);
            if (game.winner !== 'boss') won += 1;
        }
        if (games > 2) console.log(`  ${boss.id} ${lv.name}: the crew won ${won} of ${games}`);
    }
}
console.log('turf bosses: ok');
