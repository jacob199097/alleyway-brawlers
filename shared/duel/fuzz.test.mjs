// Random moves: games where each turn is played by trying every move there is in a random order (and
// now and then a CPU move, or junk the server could be sent), with starter decks and with random
// decks from every card, 2 to 4 players. Every game has to finish without the rules throwing, a
// player being left with no move, a turn that never ends, or a card with no ATK/DEF on the field.
// The same seed plays the same games, so a failure can be played again.
//   node shared/duel/fuzz.test.mjs [games] [seed]
import assert from 'node:assert';
import { DuelState } from './DuelState.js';
import { choose, cpuSetup } from './DuelAI.js';
import { CARD_CATALOG } from '../cards.js';
import { pickableClans } from '../clans.js';

const GAMES = Number(process.argv[2] || 300);
let seed = Number(process.argv[3] || 1);
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const shuffle = (a) => {
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(rnd() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
};
const clans = pickableClans().map(c => c.id);
const JUNK = [null, undefined, 'x', -5, 99, 1.5, {}, [], '0', NaN];

/** 40 random cards of a clan and Neutral, every higher Striver level twice in the Hideout, a random leader. */
function randomSetup(clan) {
    const cards = Object.entries(CARD_CATALOG).filter(([, c]) => !c.token && (c.clan === clan || c.clan === 'neutral'));
    const level = (c) => Math.trunc(Number(c.level) || 1);
    const base = cards.filter(([, c]) => c.cardType !== 'leader' && (c.cardType !== 'gang_member' || level(c) === 1)).map(([id]) => id);
    const hideout = cards.filter(([, c]) => c.cardType === 'gang_member' && level(c) > 1).flatMap(([id]) => [id, id]);
    const leaders = cards.filter(([, c]) => c.cardType === 'leader').map(([id]) => id);
    return { deck: Array.from({ length: 40 }, () => pick(base)), hideout, leader: leaders.length ? pick(leaders) : '' };
}

/** Every move a side could try now (most of them won't be allowed). */
function moves(d, side) {
    const s = d.sides[side];
    const out = [];
    const p = d.pending;
    if (p && Object.keys(p).length) {
        if (p.kind === 'discard') for (const c of s.hand) out.push({ kind: 'discard', uid: c.uid });
        for (const o of p.options || []) out.push({ kind: 'choose', option: o.id });
        return out;
    }
    for (const c of s.hand) {
        for (let slot = 0; slot < 10; slot++) {
            out.push({ kind: 'summon', uid: c.uid, slot, position: pick(['atk', 'def']) });
            out.push({ kind: 'summon', uid: c.uid, slot, position: 'atk', tribute: Math.floor(rnd() * 5) });
            out.push({ kind: 'set', uid: c.uid, slot });
        }
        out.push({ kind: 'hustle', uid: c.uid });
    }
    for (let slot = 0; slot < 10; slot++) {
        if (s.field[slot]) out.push({ kind: 'hustle', uid: s.field[slot].uid });
        out.push({ kind: 'position', slot }, { kind: 'promote', slot }, { kind: 'ability', slot }, { kind: 'flip', slot });
        for (const fx of [1, 2, 3]) out.push({ kind: 'activate', slot, fx });
        for (const foe of d.foesOf(side)) for (let target = -1; target < 5; target++) out.push({ kind: 'attack', from: slot, target, foe });
    }
    for (const c of s.gutter || []) for (const fx of [1, 2]) out.push({ kind: 'gutter', uid: c.uid, fx });
    return shuffle(out).concat([{ kind: 'next' }]);   // ('next' last, so turns have moves in them)
}

let finished = 0;
for (let g = 0; g < GAMES; g++) {
    const n = rnd() < 0.3 ? pick([3, 4]) : 2;
    const seats = n === 2 ? ['player', 'opponent'] : ['p1', 'p2', 'p3', 'p4'].slice(0, n);
    const mixed = g % 2 === 1;
    const setups = seats.map(() => mixed ? randomSetup(pick(clans)) : cpuSetup(pick(clans)));
    const gameSeed = Math.floor(rnd() * 1e9);
    const by = (k) => Object.fromEntries(seats.map((s, i) => [s, setups[i][k]]));
    const d = new DuelState(by('deck'), by('hideout'), by('leader'), seats[0], gameSeed);
    d.start();
    const whose = () => (d.pending && Object.keys(d.pending).length) ? d.pending.side : d.active;
    let move = null, turn = -1, sameTurn = 0;
    const where = () => `game ${g} (${n} players, ${mixed ? 'random' : 'starter'} decks, seed ${gameSeed}), turn ${d.turn}, last move ${JSON.stringify(move)}`;
    try {
        for (let step = 0; step < 4000 && d.winner === ''; step++) {
            if (rnd() < 0.05) {   // junk is refused, whoever sends it
                move = { kind: pick(['summon', 'set', 'hustle', 'attack', 'position', 'promote', 'ability', 'flip', 'activate', 'gutter', 'choose', 'discard', 'next', 'bogus']),
                    uid: pick(JUNK), slot: pick(JUNK), from: pick(JUNK), target: pick(JUNK), foe: pick([...JUNK, 'nobody']), option: pick(JUNK), fx: pick(JUNK),
                    tributes: pick([[], [9, 9], ['a'], null]) };
                for (const side of seats) d.doAction(side, move);
                if (d.winner !== '') break;
            }
            const who = whose();
            let ok = false;
            if (rnd() < 0.35) {
                move = choose(d, who, pick(['easy', 'normal', 'hard']));
                ok = d.doAction(who, move);
            }
            for (const m of ok ? [] : moves(d, who)) {
                move = m;
                if (d.doAction(who, m)) {
                    ok = true;
                    break;
                }
            }
            assert.ok(ok, `${who} has no move: ${where()}`);
            for (const [side, s] of Object.entries(d.sides)) {
                assert.ok(Number.isFinite(s.morale), `${side}'s Morale is ${s.morale}: ${where()}`);
                for (const c of s.field.slice(0, 5)) {
                    if (c) assert.ok(Number.isFinite(c.attack ?? 0) && Number.isFinite(c.defense ?? 0), `${c.name} has ATK ${c.attack} DEF ${c.defense}: ${where()}`);
                }
            }
            sameTurn = d.turn === turn ? sameTurn + 1 : 0;
            turn = d.turn;
            assert.ok(sameTurn < 600, `the turn never ends: ${where()}`);
        }
    } catch (err) {
        if (err instanceof assert.AssertionError) throw err;
        throw new Error(`${err.message}: ${where()}\n${err.stack}`);
    }
    if (d.winner !== '') finished++;
}
assert.ok(finished >= GAMES * 0.95, `only ${finished} of ${GAMES} games finished`);
console.log(`random moves: ${GAMES} games, ${finished} finished: ok`);
