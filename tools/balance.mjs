// Balance report: plays CPU-vs-CPU games with the real rules (shared/duel) and reports how each card
// does, so you can spot cards that are too strong, too weak, or hard to play.
//
//   node tools/balance.mjs [--clan nebula] [--games 2000] [--level normal] [--seed 1] [--html report.html]
//
// Every game gives both players a random legal 40-card deck from the clan's cards (up to 3 copies
// each, plus the promoted forms in the Hideout and a leader), so each card turns up in many decks.
// With several clans and no --clan, decks come from random clans and you also get clan win rates.
//
// Per card:
//   in deck    games it was in a deck
//   drawn      games it was drawn (in the opening hand or later)
//   played     share of the games it was drawn in that it was also played (or promoted into)
//   win drawn  win rate of the games it was drawn in
//   impact     win rate when drawn minus win rate when in the deck but not drawn: how much
//              drawing it helps. The clearest single number; positive = good card.
// Cards seen in fewer than --min games (default 60) aren't flagged: their numbers are noise.
import { writeFileSync } from 'node:fs';
import { DuelState } from '../shared/duel/DuelState.js';
import { choose } from '../shared/duel/DuelAI.js';
import { CARD_CATALOG } from '../shared/cards.js';
import { clanList } from '../shared/clans.js';

const args = process.argv.slice(2);
const opt = (name, fallback) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const GAMES = Number(opt('games', 2000));
const LEVEL = opt('level', 'normal');
const MIN = Number(opt('min', 60));
const HTML = opt('html', '');
const MAX_ACTIONS = 1500;
let seed = Number(opt('seed', 1)) >>> 0 || 1;

// Small seeded random numbers (mulberry32), so a report can be repeated exactly
function rand() {
    seed = (seed + 0x6D2B79F5) >>> 0;
    let t = seed;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (list) => list[Math.floor(rand() * list.length)];

const allClans = clanList().map(c => c.id);
const wantClan = opt('clan', '');
if (wantClan && !allClans.includes(wantClan)) {
    console.error(`No clan "${wantClan}". Clans: ${allClans.join(', ') || '(none)'}`);
    process.exit(2);
}
const level = (c) => Math.trunc(Number(c.level) || 1);
const deckLegal = (c) => c.cardType !== 'leader' && !(c.cardType === 'gang_member' && level(c) > 1);
const pools = {};
for (const clan of allClans) {
    const cards = Object.values(CARD_CATALOG).filter(c => c.clan === clan);
    const legal = cards.filter(deckLegal).map(c => c.id);
    if (legal.length * 3 < 40) continue;
    pools[clan] = { legal, leaders: cards.filter(c => c.cardType === 'leader').map(c => c.id) };
}
const clans = wantClan ? [wantClan] : Object.keys(pools);
if (!clans.length || !pools[clans[0]]) {
    console.error('No clan has enough cards for a 40-card deck yet.');
    process.exit(2);
}

function nextForm(id) {
    const c = CARD_CATALOG[id];
    if (c && c.promotesTo) return CARD_CATALOG[c.promotesTo] ? c.promotesTo : '';
    const m = /^(.*_lv)(\d)$/.exec(id);
    const g = m ? `${m[1]}${Number(m[2]) + 1}` : '';
    return g && CARD_CATALOG[g] ? g : '';
}

/** A random legal deck: 40 cards, up to 3 of each, promoted forms in the Hideout. */
function randomDeck(clan) {
    const { legal, leaders } = pools[clan];
    const copies = new Map();
    const deck = [];
    while (deck.length < 40) {
        const id = pick(legal);
        if ((copies.get(id) || 0) >= 3) continue;
        copies.set(id, (copies.get(id) || 0) + 1);
        deck.push(id);
    }
    const hideout = [];
    for (const id of copies.keys()) {
        for (let n = nextForm(id); n; n = nextForm(n)) hideout.push(n, n, n);
    }
    return { clan, deck, hideout, leader: leaders.length ? pick(leaders) : '', unique: new Set(copies.keys()) };
}

// ── Play ─────────────────────────────────────────────────────────────────────
const stats = new Map();   // card id → counters
const stat = (id) => {
    if (!stats.has(id)) stats.set(id, { deck: 0, deckWin: 0, drawn: 0, drawnWin: 0, played: 0, playedWin: 0, timesPlayed: 0 });
    return stats.get(id);
};
const clanRecord = {};     // clan → {games, wins}
const totals = { games: 0, firstWins: 0, turns: 0, deckOut: 0, unfinished: 0, refused: 0 };
const started = Date.now();

for (let g = 0; g < GAMES; g++) {
    const seats = { player: randomDeck(pick(clans)), opponent: randomDeck(pick(clans)) };
    const first = rand() < 0.5 ? 'player' : 'opponent';
    const d = new DuelState(
        { player: seats.player.deck, opponent: seats.opponent.deck },
        { player: seats.player.hideout, opponent: seats.opponent.hideout },
        { player: seats.player.leader, opponent: seats.opponent.leader },
        first, 1 + Math.floor(rand() * 2147483646));
    const drawn = { player: new Set(), opponent: new Set() };
    const played = { player: new Map(), opponent: new Map() };
    const look = (events) => {
        for (const ev of events) {
            if (!ev.side || !ev.card) continue;
            if (ev.type === 'draw') drawn[ev.side].add(ev.card.id);
            else if (['summon', 'set', 'hustle', 'promote'].includes(ev.type)) {
                const id = ev.card.id;
                played[ev.side].set(id, (played[ev.side].get(id) || 0) + 1);
            }
        }
    };
    d.start();
    look(d.takeEvents());
    let n = 0;
    while (!d.winner && n < MAX_ACTIONS) {
        const side = d.pending && d.pending.side ? d.pending.side : d.active;
        let a = choose(d, side, LEVEL);
        if (!Object.keys(a).length || !d.doAction(side, a)) {
            totals.refused += 1;
            if (!d.doAction(side, { kind: 'next' })) break;
        }
        look(d.takeEvents());
        n += 1;
    }
    totals.games += 1;
    if (!d.winner) { totals.unfinished += 1; continue; }
    totals.turns += d.turn;
    if (d.winner === first) totals.firstWins += 1;
    if (d.endReason === 'deck_out') totals.deckOut += 1;
    for (const side of ['player', 'opponent']) {
        const won = d.winner === side ? 1 : 0;
        const s = seats[side];
        clanRecord[s.clan] ||= { games: 0, wins: 0 };
        clanRecord[s.clan].games += 1;
        clanRecord[s.clan].wins += won;
        for (const id of s.unique) {
            const st = stat(id);
            st.deck += 1; st.deckWin += won;
            if (drawn[side].has(id)) {
                st.drawn += 1; st.drawnWin += won;
                const wasPlayed = played[side].has(id) || [...played[side].keys()].some(p => promotesFrom(p, id));
                if (wasPlayed) { st.played += 1; st.playedWin += won; st.timesPlayed += played[side].get(id) || 0; }
            }
        }
    }
    if ((g + 1) % 250 === 0) process.stderr.write(`  ${g + 1}/${GAMES} games…\r`);
}
process.stderr.write(' '.repeat(30) + '\r');

/** True if `later` is a promoted form of `id` (e.g. kade_lv2 of kade_lv1). */
function promotesFrom(later, id) {
    for (let n = nextForm(id); n; n = nextForm(n)) if (n === later) return true;
    return false;
}

// ── Report ───────────────────────────────────────────────────────────────────
const pct = (a, b) => (b ? (100 * a) / b : NaN);
const rows = [...stats.entries()].map(([id, s]) => {
    const notDrawn = s.deck - s.drawn, notDrawnWin = s.deckWin - s.drawnWin;
    const c = CARD_CATALOG[id] || {};
    const row = {
        id, name: c.name || id, type: c.cardType === 'gang_member' ? (c.subtype || 'brawler') : c.cardType,
        authority: c.authority ?? '', rarity: c.rarity ?? '',
        deck: s.deck, drawn: s.drawn, playRate: pct(s.played, s.drawn),
        winDrawn: pct(s.drawnWin, s.drawn), winPlayed: pct(s.playedWin, s.played),
        impact: pct(s.drawnWin, s.drawn) - pct(notDrawnWin, notDrawn),
    };
    row.flag = '';
    if (s.drawn >= MIN) {
        if (row.impact >= 8) row.flag = 'STRONG';
        else if (row.impact <= -5) row.flag = 'WEAK';
        if (row.playRate < 35) row.flag = (row.flag ? row.flag + ', ' : '') + 'STUCK IN HAND';
    } else row.flag = 'few games';
    return row;
}).sort((a, b) => (b.impact || -1e9) - (a.impact || -1e9));

const f1 = (v) => (Number.isFinite(v) ? v.toFixed(1) : '—');
const sgn = (v) => (Number.isFinite(v) ? (v > 0 ? '+' : '') + v.toFixed(1) : '—');
const secs = ((Date.now() - started) / 1000).toFixed(0);
const finished = totals.games - totals.unfinished;
const lines = [];
lines.push(`Balance report: ${totals.games} games (${clans.join(', ')}; CPU ${LEVEL}; seed ${opt('seed', 1)}) in ${secs}s`);
lines.push(`First player wins ${f1(pct(totals.firstWins, finished))}% · average ${f1(totals.turns / Math.max(1, finished))} turns · ` +
    `deck-outs ${f1(pct(totals.deckOut, finished))}% · unfinished ${totals.unfinished}${totals.refused ? ` · CPU moves refused ${totals.refused}` : ''}`);
if (Object.keys(clanRecord).length > 1) {
    lines.push('Clans: ' + Object.entries(clanRecord).map(([k, v]) => `${k} ${f1(pct(v.wins, v.games))}%`).join(' · '));
}
lines.push('');
const cols = [['Card', 22], ['Type', 9], ['Auth', 5], ['In deck', 8], ['Drawn', 7], ['Played', 7], ['Win drawn', 10], ['Impact', 7], ['', 0]];
lines.push(cols.map(([h, w]) => h.padEnd(w)).join(''));
for (const r of rows) {
    lines.push([String(r.name).slice(0, 21).padEnd(22), String(r.type).padEnd(9), String(r.authority).padEnd(5),
        String(r.deck).padEnd(8), String(r.drawn).padEnd(7), (f1(r.playRate) + '%').padEnd(7),
        (f1(r.winDrawn) + '%').padEnd(10), sgn(r.impact).padEnd(7), r.flag].join(''));
}
lines.push('');
lines.push('Impact = win rate when drawn minus when in the deck but not drawn. STRONG ≥ +8, WEAK ≤ -5,');
lines.push(`STUCK IN HAND = played in under 35% of the games it was drawn. Needs ${MIN}+ games drawn to be flagged.`);
console.log(lines.join('\n'));

if (HTML) {
    const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
    const body = rows.map(r => `<tr class="${r.flag.startsWith('STRONG') ? 'strong' : r.flag.startsWith('WEAK') ? 'weak' : ''}">` +
        `<td>${esc(r.name)}</td><td>${esc(r.type)}</td><td>${r.authority}</td><td>${r.rarity}</td><td>${r.deck}</td><td>${r.drawn}</td>` +
        `<td>${f1(r.playRate)}%</td><td>${f1(r.winDrawn)}%</td><td>${f1(r.winPlayed)}%</td><td>${sgn(r.impact)}</td><td>${esc(r.flag)}</td></tr>`).join('\n');
    writeFileSync(HTML, `<!doctype html><meta charset="utf-8"><title>Balance report</title>
<style>body{font:14px system-ui,sans-serif;margin:24px;background:#12121c;color:#e6e6f0}table{border-collapse:collapse}
th,td{padding:5px 10px;border-bottom:1px solid #2a2a3a;text-align:right}th{cursor:pointer;color:#f4d35e;position:sticky;top:0;background:#12121c}
td:first-child,th:first-child,td:nth-child(2),td:last-child{text-align:left}tr.strong td{color:#8ef0a0}tr.weak td{color:#ff8a94}p{color:#aab}</style>
<h1>Balance report</h1><p>${lines.slice(0, 3).map(esc).join('<br>')}</p>
<table id="t"><thead><tr><th>Card</th><th>Type</th><th>Authority</th><th>Rarity</th><th>In deck</th><th>Drawn</th><th>Played when drawn</th>
<th>Win when drawn</th><th>Win when played</th><th>Impact</th><th>Flag</th></tr></thead><tbody>${body}</tbody></table>
<p>Impact = win rate when drawn minus win rate when in the deck but not drawn. Click a heading to sort.</p>
<script>document.querySelectorAll('th').forEach((th,i)=>th.onclick=()=>{const tb=document.querySelector('tbody');
const rows=[...tb.rows];const num=(r)=>parseFloat(r.cells[i].textContent.replace(/[%+]/g,''));const dir=th.dataset.d=th.dataset.d==='1'?'-1':'1';
rows.sort((a,b)=>{const x=num(a),y=num(b);return (isNaN(x)||isNaN(y)?a.cells[i].textContent.localeCompare(b.cells[i].textContent):x-y)*dir;});
rows.forEach(r=>tb.appendChild(r));});</script>`);
    console.log(`\nWrote ${HTML}`);
}
