// Tries a deck against the clans' starter decks: CPU-vs-CPU games with the real rules, like
// tools/balance.mjs, but the deck comes from a file, so a starter can be tuned before it's changed
// in shared/clans.js.
//
//   node tools/deck_test.mjs <deck.json> [--games 1000] [--vs militia,underworld] [--level normal] [--seed 1] [--cards]
//
// deck.json: { "clan": "nebula", "leader": "card_nebu_009", "deck": [["card_nebu_001", 2], ...],
//              "hideout": [["card_nebu_002", 3], ...] }   (the same shape as a starter in shared/clans.js)
// Without --vs it plays every other clan's starter. --cards adds each card's "impact" (win rate when
// drawn minus when in the deck but not drawn), the same number balance.mjs reports.
import { readFileSync } from 'node:fs';
import { DuelState } from '../shared/duel/DuelState.js';
import { choose } from '../shared/duel/DuelAI.js';
import { CARD_CATALOG } from '../shared/cards.js';
import { clanList, starterRecipe } from '../shared/clans.js';

const args = process.argv.slice(2);
const opt = (name, fallback) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const file = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && args[i - 1] !== '--cards'));
if (!file) {
    console.error('usage: node tools/deck_test.mjs <deck.json> [--games 1000] [--vs clan,clan] [--level normal] [--seed 1] [--cards]');
    process.exit(2);
}
const mine = JSON.parse(readFileSync(file, 'utf8'));
const GAMES = Number(opt('games', 1000));
const LEVEL = opt('level', 'normal');
let seed = Number(opt('seed', 1)) >>> 0 || 1;
function rand() {
    seed = (seed + 0x6D2B79F5) >>> 0;
    let t = seed;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const expand = (list) => list.flatMap(([id, n]) => Array(n).fill(id));
for (const id of [mine.leader, ...expand(mine.deck), ...expand(mine.hideout)]) {
    if (!CARD_CATALOG[id]) { console.error(`${id} isn't a card.`); process.exit(2); }
}
const size = expand(mine.deck).length;
if (size !== 40) console.warn(`(the deck has ${size} cards, not 40)`);
const seat = (r) => ({ deck: expand(r.deck), hideout: expand(r.hideout), leader: r.leader });
const foes = (opt('vs', '') ? opt('vs', '').split(',') : clanList().map(c => c.id ?? c).filter(c => c !== mine.clan));

const impact = new Map();
const card = (id) => impact.get(id) || impact.set(id, { deck: 0, deckWin: 0, drawn: 0, drawnWin: 0 }).get(id);
let all = 0, allWins = 0;
for (const foe of foes) {
    const r = starterRecipe(foe);
    if (!r) { console.error(`${foe} has no starter deck.`); continue; }
    let wins = 0, games = 0, turns = 0;
    for (let g = 0; g < GAMES; g++) {
        const meFirst = rand() < 0.5;
        const a = seat(mine), b = seat(r);
        const d = new DuelState({ player: a.deck, opponent: b.deck }, { player: a.hideout, opponent: b.hideout },
            { player: a.leader, opponent: b.leader }, meFirst ? 'player' : 'opponent', 1 + Math.floor(rand() * 2147483646));
        const drawn = new Set();
        const look = (evs) => { for (const ev of evs) if (ev.type === 'draw' && ev.side === 'player' && ev.card) drawn.add(ev.card.id); };
        d.start();
        look(d.takeEvents());
        for (let n = 0; !d.winner && n < 1500; n++) {
            const side = d.pending && d.pending.side ? d.pending.side : d.active;
            const act = choose(d, side, LEVEL);
            if (!Object.keys(act).length || !d.doAction(side, act)) { if (!d.doAction(side, { kind: 'next' })) break; }
            look(d.takeEvents());
        }
        if (!d.winner) continue;
        games += 1; turns += d.turn;
        const won = d.winner === 'player' ? 1 : 0;
        wins += won;
        for (const id of new Set(a.deck)) {
            const s = card(id);
            s.deck += 1; s.deckWin += won;
            if (drawn.has(id)) { s.drawn += 1; s.drawnWin += won; }
        }
    }
    all += games; allWins += wins;
    console.log(`vs ${foe.padEnd(11)} ${(100 * wins / games).toFixed(1)}%  (${games} games, ${(turns / games).toFixed(1)} turns)`);
}
console.log(`overall      ${(100 * allWins / all).toFixed(1)}%`);
if (args.includes('--cards')) {
    console.log('\ncard                         drawn  win drawn  impact');
    const rows = [...impact.entries()].map(([id, s]) => {
        const nd = s.deck - s.drawn;
        const imp = s.drawn && nd ? 100 * (s.drawnWin / s.drawn - (s.deckWin - s.drawnWin) / nd) : NaN;
        return { id, name: CARD_CATALOG[id].name, drawn: s.drawn, wd: 100 * s.drawnWin / Math.max(1, s.drawn), imp };
    }).sort((x, y) => y.imp - x.imp);
    for (const r of rows) console.log(`${(r.id.slice(-3) + ' ' + r.name).slice(0, 28).padEnd(28)} ${String(r.drawn).padStart(6)}  ${r.wd.toFixed(1).padStart(8)}%  ${r.imp >= 0 ? '+' : ''}${r.imp.toFixed(1)}`);
}
