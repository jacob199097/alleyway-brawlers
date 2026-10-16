'use strict';
// The balance of real matches, as JSON for tools/live_balance.mjs (which turns it into a page):
// clan win rates (against players and against the CPU), each card's numbers as players use it, the
// leaders, who goes first, and the weekly challenge.
//
//   node backend/scripts/balance_dashboard.js [--days 30] > balance.json
//
// Matches come from match_stats (every finished match since 0.7.19). Older matches still in
// match_replays (each player's last 30) are played again on the rules engine to fill in, so the
// numbers start with the history the server already has. Card numbers count players' decks only
// (CPU decks are the starter decks).
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const arg = (name, fallback) => {
    const i = process.argv.indexOf(`--${name}`);
    return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : fallback;
};
const DAYS = Math.max(1, Number(arg('days', 30)) || 30);

(async () => {
    const { DuelState } = await import('../../shared/duel/DuelState.js');
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const clanOf = (ids) => {
        const n = {};
        for (const id of ids) { const c = CARD_CATALOG[id]?.clan; if (c) n[c] = (n[c] || 0) + 1; }
        return Object.keys(n).sort((a, b) => n[b] - n[a])[0] || null;
    };

    const matches = [];
    const has = async (table) => (await pool.query('SELECT to_regclass($1) AS t', [table])).rows[0].t != null;
    if (await has('match_stats')) {   // (created by db/migrate_mastery_challenge.sql when the server starts)
        const { rows: stats } = await pool.query(
            `SELECT id, created_at, mode, version, data FROM match_stats WHERE created_at > NOW() - $1::interval`, [`${DAYS} days`]);
        for (const r of stats) matches.push({ id: r.id, at: r.created_at, mode: r.mode, version: r.version, ...r.data });
    }

    // Older matches from their replays (not already counted)
    const seen = new Set(matches.map(m => m.id));
    let replayed = 0, skipped = 0;
    if (await has('match_replays')) {
        const { rows: reps } = await pool.query(
            `SELECT id, created_at, mode, data FROM match_replays WHERE created_at > NOW() - $1::interval`, [`${DAYS} days`]);
        for (const r of reps) {
            if (seen.has(r.id)) continue;
            const rec = r.data;
            try {
                const st = new DuelState(rec.decks, rec.hideouts, rec.leaders, rec.first, rec.seed, rec.rules || {});
                const drawn = { player: new Set(), opponent: new Set() }, played = { player: new Set(), opponent: new Set() };
                const look = (events) => {
                    for (const ev of events) {
                        if (!ev.card || !drawn[ev.side]) continue;
                        if (ev.type === 'draw') drawn[ev.side].add(ev.card.id);
                        else if (['summon', 'set', 'hustle', 'lasting', 'promote', 'awaken'].includes(ev.type)) played[ev.side].add(ev.card.id);
                    }
                };
                st.start();
                look(st.takeEvents());
                for (const [seat, action] of rec.actions) { st.doAction(seat, action); look(st.takeEvents()); }
                if (!st.winner) { skipped += 1; continue; }   // (ended by a concession or going AFK: no recorded winner)
                const side = (seat) => {
                    const deck = [...new Set((rec.decks[seat] || []).map(x => (typeof x === 'object' ? x.id : x)))];
                    return { bot: String(rec.playerIds?.[seat] || '').startsWith('cpu:'), clan: clanOf(deck), leader: rec.leaders?.[seat] || '',
                        deck, drawn: [...drawn[seat]], played: [...played[seat]], won: st.winner === seat };
                };
                matches.push({ id: r.id, at: r.created_at, mode: r.mode, version: rec.version || null, turns: st.turn,
                    winner: st.winner, first: rec.first, challenge: null, player: side('player'), opponent: side('opponent'), replayed: true });
                replayed += 1;
            } catch (err) {
                skipped += 1;
            }
        }
    }

    // ── Totals ──
    const pct = (a, b) => (b ? Math.round((1000 * a) / b) / 10 : null);
    const modes = {};
    let firstWins = 0, decided = 0, turns = 0;
    const clans = {};      // clan → {pvp: {games, wins}, cpu: {games, wins}}
    const leaders = {};    // leader id → {games, wins} (players' seats)
    const cards = {};      // card id → counters (players' seats)
    const challenge = { games: 0, wins: 0 };
    const card = (id) => (cards[id] ||= { deck: 0, deckWin: 0, drawn: 0, drawnWin: 0, played: 0, playedWin: 0 });
    for (const m of matches) {
        modes[m.mode] = (modes[m.mode] || 0) + 1;
        turns += m.turns || 0;
        if (m.winner) { decided += 1; if (m.winner === m.first) firstWins += 1; }
        if (m.challenge || m.mode === 'cpu_challenge') { challenge.games += 1; if (!m.player?.bot ? m.player?.won : m.opponent?.won) challenge.wins += 1; }
        for (const seat of ['player', 'opponent']) {
            const s = m[seat], o = m[seat === 'player' ? 'opponent' : 'player'];
            if (!s || s.bot) continue;
            const kind = o?.bot ? 'cpu' : 'pvp';
            const won = s.won ? 1 : 0;
            if (s.clan) {
                clans[s.clan] ||= { pvp: { games: 0, wins: 0 }, cpu: { games: 0, wins: 0 } };
                clans[s.clan][kind].games += 1;
                clans[s.clan][kind].wins += won;
            }
            if (s.leader) {
                leaders[s.leader] ||= { games: 0, wins: 0 };
                leaders[s.leader].games += 1;
                leaders[s.leader].wins += won;
            }
            const drawn = new Set(s.drawn || []), played = new Set(s.played || []);
            for (const id of s.deck || []) {
                const c = card(id);
                c.deck += 1; c.deckWin += won;
                if (drawn.has(id)) { c.drawn += 1; c.drawnWin += won; }
                if (played.has(id)) { c.played += 1; c.playedWin += won; }
            }
        }
    }
    const out = {
        generated_at: new Date().toISOString(), days: DAYS,
        matches: matches.length, from_replays: replayed, skipped, modes,
        first_player_wins: pct(firstWins, decided), avg_turns: matches.length ? Math.round((10 * turns) / matches.length) / 10 : null,
        challenge: { ...challenge, win_rate: pct(challenge.wins, challenge.games) },
        clans: Object.entries(clans).map(([id, c]) => ({
            id, name: Object.values(CARD_CATALOG).find(x => x.clan === id)?.clanName || id,
            pvp: { ...c.pvp, win_rate: pct(c.pvp.wins, c.pvp.games) }, cpu: { ...c.cpu, win_rate: pct(c.cpu.wins, c.cpu.games) },
        })),
        leaders: Object.entries(leaders).filter(([id]) => CARD_CATALOG[id]).map(([id, l]) => ({ id, name: CARD_CATALOG[id]?.name || id, ...l, win_rate: pct(l.wins, l.games) })),
        cards: Object.entries(cards).filter(([id]) => CARD_CATALOG[id]).map(([id, c]) => {   // (retired cards are left out)
            const notDrawn = c.deck - c.drawn, notDrawnWin = c.deckWin - c.drawnWin;
            const winDrawn = pct(c.drawnWin, c.drawn), winNot = pct(notDrawnWin, notDrawn);
            const k = CARD_CATALOG[id] || {};
            return { id, name: k.name || id, clan: k.clan || '', type: k.cardType === 'gang_member' ? (k.subtype || 'brawler') : (k.cardType || ''),
                authority: k.authority ?? null, rarity: k.rarity ?? null, in_decks: c.deck, drawn: c.drawn,
                play_rate: pct(c.played, c.drawn), win_drawn: winDrawn, win_played: pct(c.playedWin, c.played),
                impact: winDrawn != null && winNot != null ? Math.round(10 * (winDrawn - winNot)) / 10 : null };
        }).sort((a, b) => b.in_decks - a.in_decks),
    };
    process.stdout.write(JSON.stringify(out));
    await pool.end();
})().catch(async (err) => {
    console.error(err);
    await pool.end();
    process.exit(1);
});
