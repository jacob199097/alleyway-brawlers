'use strict';

/**
 * FREE-FOR-ALL: 3-4 players, every one for themselves (server-authoritative, like onlineMatch.js).
 * The rules are the shared engine with seats p1..p4 (shared/duel/DuelState.js: every opponent is an
 * enemy, the last one standing wins).
 *
 * Lobby: players who queue (ffa:queue) go into the open lobby (up to 4), whose LOBBY_SECS timer starts
 * when it opens. Each readies up (ffa:ready). With 4 in and all ready it starts at once; otherwise when
 * the timer runs out: players who aren't ready drop out, and CPUs fill empty seats up to 3 players.
 * A lobby nobody is ready in closes.
 *
 * Match: each player sees it from their own seat: theirs is "player", the others "foe1".."foe3" in
 * turn order after them (the view's \`seats\` lists them all in turn order). Actions name opponents the
 * same way (attack.foe, a "choose an opponent" answer); they're translated back here. A player who
 * goes out is told their place and rewards straight away (ffa:out) and may watch the rest or leave
 * (ffa:quit). Conceding, being away too long or disconnected puts a player out; the game goes on.
 *
 *   client → server  ffa:queue, ffa:ready {ready}, ffa:leave (the lobby), ffa:action {matchId, action},
 *                    ffa:concede {matchId}, ffa:quit (stop watching after going out), ffa:resync
 *   server → client  ffa:lobby {lobbyId, secs, players: [{username, level, avatar_url, title, ready, you}], min, max},
 *                    ffa:left {reason}, ffa:error {message},
 *                    ffa:start {matchId, resync, players: {player: profile, foe1: ...}, view, clock},
 *                    ffa:update {matchId, events, view, clock, away},
 *                    ffa:out {matchId, place, players, rewards, achievements},
 *                    ffa:over {matchId, place, places: {player: 1, foe1: 3, ...}, rewards, achievements}
 * Rewards by place (economy/postMatch.js resolveFfaMatch): 1st a win, 2nd between a win and a loss,
 * the rest a loss.
 */

const { randomUUID } = require('crypto');
const { viewFor, filterEvent, statsFilter } = require('./onlineMatch');

const LOBBY_SECS   = 60;
const MAX_PLAYERS  = 4;
const MIN_PLAYERS  = 3;
const TURN_SECS    = 90;
const AWAY_SECS    = 15;
const AFK_FORFEIT  = 8;
const RECONNECT_SECS = 45;
const BOT_MOVE_MS  = 350;
const SEATS = ['p1', 'p2', 'p3', 'p4'];

const engine = import('../../shared/duel/DuelState.js');
const cpu = import('../../shared/duel/DuelAI.js');

// ── Perspective ─────────────────────────────────────────────────────────────

/** Seat → what \`viewer\` calls it: their own is "player", then foe1, foe2, ... in turn order. */
function namesFor(seats, viewer) {
    const i = seats.indexOf(viewer);
    const out = {};
    seats.forEach((s, k) => {
        const d = (k - i + seats.length) % seats.length;
        out[s] = d === 0 ? 'player' : `foe${d}`;
    });
    return out;
}

/** Deep copy with every seat name (values and keys) renamed. */
function rename(v, names) {
    if (typeof v === 'string') return names[v] ?? v;
    if (Array.isArray(v)) return v.map(x => rename(x, names));
    if (v && typeof v === 'object') {
        const out = {};
        for (const [k, val] of Object.entries(v)) out[names[k] ?? k] = rename(val, names);
        return out;
    }
    return v;
}

/** An action as \`seat\` named things → the engine's seat names. */
function actionFrom(action, seats, seat) {
    const back = Object.fromEntries(Object.entries(namesFor(seats, seat)).map(([s, n]) => [n, s]));
    const a = { ...action };
    if (typeof a.foe === 'string') a.foe = back[a.foe] ?? a.foe;
    if (typeof a.option === 'string' && back[a.option]) a.option = back[a.option];
    return a;
}

function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
}

/**
 * @param {object} deps
 * @param {(playerId) => Promise<{deck, hideout, leader, deckId}|{error}>} deps.loadSetup
 * @param {(playerId) => Promise<object>} deps.loadProfile
 * @param {(playerId) => boolean} [deps.isBusyElsewhere]  in a 1v1 match or about to start one
 * @param {(playerId) => void} [deps.leaveOtherQueue]     take them out of the 1v1 queue
 * @param {(args) => Promise<object>} [deps.resolveFfa]   {playerId, place, humans} → rewards
 * @param {(m) => Promise<Array>} [deps.recordMatch]  achievements and clan mastery
 * @param {(deckId, outcome) => Promise} [deps.recordDeck]
 * @param {(playerId, questId, amount) => Promise} [deps.incrementDailyQuest]
 * @param {(playerId) => Promise} [deps.recordDailyWin]
 * @param {number} [deps.lobbySecs] [deps.turnSecs] [deps.awaySecs] [deps.reconnectSecs] [deps.botMoveMs]  (tests)
 */
function createFfaService(io, deps) {
    const sockets = new Map();
    let lobby = null;                 // the open lobby: {id, players: [{entry, ready}], endsAt, timer}
    const inLobby = new Map();        // playerId → lobby
    const byPlayer = new Map();       // playerId → match (until they leave it)
    const matches = new Map();
    const emitTo = (id, ev, data) => sockets.get(id)?.emit(ev, data);
    const busy = (id) => inLobby.has(id) || byPlayer.has(id);
    const secs = (k, d) => deps[k] ?? d;

    async function prepare(playerId) {
        const [setup, profile] = await Promise.all([deps.loadSetup(playerId), deps.loadProfile(playerId)]);
        if (setup.error) throw new Error(setup.error);
        return { playerId, setup, profile };
    }

    function profileOf(e) {
        const p = e.profile || {};
        return { username: p.username, level: p.level, avatar_url: p.avatar_url, title: p.title || null,
            card_back: p.card_back || null, cpu: !!e.bot };
    }

    // ── Lobby ──
    function lobbyNews(l) {
        const left = Math.max(0, Math.round((l.endsAt - Date.now()) / 1000));
        for (const p of l.players) {
            emitTo(p.entry.playerId, 'ffa:lobby', {
                lobbyId: l.id, secs: left, min: MIN_PLAYERS, max: MAX_PLAYERS,
                players: l.players.map(q => ({ ...profileOf(q.entry), ready: q.ready, you: q === p })),
            });
        }
    }

    function openLobby() {
        const l = { id: randomUUID(), players: [], endsAt: Date.now() + secs('lobbySecs', LOBBY_SECS) * 1000, timer: null, over: false };
        l.timer = setTimeout(() => lobbyTimeUp(l), secs('lobbySecs', LOBBY_SECS) * 1000);
        return l;
    }

    function leaveLobby(playerId, reason = '') {
        const l = inLobby.get(playerId);
        if (!l) return;
        inLobby.delete(playerId);
        l.players = l.players.filter(p => p.entry.playerId !== playerId);
        if (reason) emitTo(playerId, 'ffa:left', { reason });
        if (!l.players.length) closeLobby(l);
        else lobbyNews(l);
    }

    function closeLobby(l) {
        l.over = true;
        clearTimeout(l.timer);
        if (lobby === l) lobby = null;
    }

    function lobbyTimeUp(l) {
        if (l.over) return;
        for (const p of l.players.filter(q => !q.ready)) leaveLobby(p.entry.playerId, 'You weren\'t ready in time.');
        if (l.over || !l.players.length) return closeLobby(l);
        startFromLobby(l).catch(err => console.error('[FFA] Start failed:', err));
    }

    async function startFromLobby(l) {
        closeLobby(l);
        const entries = l.players.map(p => p.entry);
        for (const e of entries) inLobby.delete(e.playerId);
        const { cpuSetup, randomCpuClan } = await cpu;
        let n = 0;
        while (entries.length < MIN_PLAYERS) {
            n += 1;
            entries.push({ playerId: `cpu:${randomUUID()}`, bot: true, level: 'normal', setup: cpuSetup(randomCpuClan()),
                profile: { username: `CPU ${n}`, level: 1, avatar_url: 'cpu' } });
        }
        await startMatch(shuffle(entries));
    }

    // ── Match ──
    async function startMatch(entries) {
        const { DuelState } = await engine;
        const seats = SEATS.slice(0, entries.length);
        const decks = {}, hideouts = {}, leaders = {};
        seats.forEach((s, i) => {
            decks[s] = entries[i].setup.deck;
            hideouts[s] = entries[i].setup.hideout;
            leaders[s] = entries[i].setup.leader;
        });
        const first = seats[Math.floor(Math.random() * seats.length)];
        const seed = 1 + Math.floor(Math.random() * 2147483646);
        const state = new DuelState(decks, hideouts, leaders, first, seed);
        const match = { id: randomUUID(), mode: 'ffa', state, seats: {}, over: false, timer: null, startedAt: Date.now(),
            humans: entries.filter(e => !e.bot).length };
        seats.forEach((s, i) => {
            match.seats[s] = { ...entries[i], seat: s, connected: true, grace: null, idle: 0, kos: 0, promotes: 0, awakens: 0,
                cardsPlayed: 0, settled: null, watching: !entries[i].bot };
        });
        matches.set(match.id, match);
        for (const e of entries) if (!e.bot) byPlayer.set(e.playerId, match);
        state.start();
        const events = state.takeEvents();
        for (const s of seats) if (!match.seats[s].bot) sendStart(match, s, false);
        broadcast(match, events);
        console.log(`[FFA] ${entries.map(e => e.profile.username).join(' vs ')} — ${match.id}`);
    }

    const seatOf = (match, playerId) => Object.keys(match.seats).find(s => match.seats[s].playerId === playerId);
    const toAct = (st) => (st.pending && st.pending.side ? st.pending.side : st.active);

    function viewOf(match, seat) {
        const st = match.state;
        return rename(viewFor(st, seat), namesFor(st.seats, seat));
    }

    function playersFor(match, seat) {
        const names = namesFor(match.state.seats, seat);
        return Object.fromEntries(match.state.seats.map(s => [names[s], profileOf(match.seats[s])]));
    }

    function sendStart(match, seat, resync) {
        emitTo(match.seats[seat].playerId, 'ffa:start', {
            matchId: match.id, mode: 'ffa', resync, players: playersFor(match, seat), view: viewOf(match, seat),
            clock: Math.max(0, Math.round(((match.clockEnds || Date.now()) - Date.now()) / 1000)) || secs('turnSecs', TURN_SECS),
        });
    }

    function broadcast(match, events) {
        const st = match.state;
        for (const ev of events) {
            const s = match.seats[ev.side];
            if (!s) continue;
            if (['summon', 'set', 'hustle'].includes(ev.type)) s.cardsPlayed += 1;
            if (ev.type === 'promote') s.promotes += 1;
            if (ev.type === 'awaken') s.awakens += 1;
        }
        // A KO counts for whoever was attacking at the time (the active player)
        for (const ev of events) if (ev.type === 'ko' && ev.side !== st.active && match.seats[st.active]) match.seats[st.active].kos += 1;
        const clock = st.winner ? 0 : armTimer(match);
        const away = !st.winner && match.seats[toAct(st)].idle > 0;
        for (const seat of Object.keys(match.seats)) {
            const s = match.seats[seat];
            if (s.bot || !s.watching) continue;
            const names = namesFor(st.seats, seat);
            emitTo(s.playerId, 'ffa:update', {
                matchId: match.id, clock, away,
                events: rename(events.map(ev => statsFilter(filterEvent(ev, seat), seat)), names),
                view: rename(viewFor(st, seat), names),
            });
        }
        // Players who just went out hear their place (and get their rewards) straight away
        for (const seat of Object.keys(match.seats)) {
            if (st.sides[seat].out && !match.seats[seat].settled && !st.winner) settle(match, seat, 'ffa:out');
        }
        if (st.winner) finish(match);
    }

    function armTimer(match) {
        clearTimeout(match.timer);
        const s = match.seats[toAct(match.state)];
        if (s.bot) {
            match.timer = setTimeout(() => botMove(match), secs('botMoveMs', BOT_MOVE_MS));
            match.clockEnds = null;
            return secs('turnSecs', TURN_SECS);
        }
        const t = s.idle > 0 ? secs('awaySecs', AWAY_SECS) : secs('turnSecs', TURN_SECS);
        match.timer = setTimeout(() => autoPlay(match), t * 1000);
        match.clockEnds = Date.now() + t * 1000;
        return t;
    }

    async function botMove(match) {
        if (match.over) return;
        const { choose } = await cpu;
        const st = match.state;
        const seat = toAct(st);
        if (!match.seats[seat].bot) return armTimer(match);
        let action = choose(st, seat, match.seats[seat].level || 'normal');
        if (!Object.keys(action).length || !st.doAction(seat, action)) {
            if (!st.doAction(seat, { kind: 'next' })) return autoPlay(match);
        }
        broadcast(match, st.takeEvents());
    }

    function autoPlay(match) {
        if (match.over) return;
        const st = match.state;
        const p = st.pending;
        const seat = toAct(st);
        const s = match.seats[seat];
        s.idle += 1;
        if (s.idle >= AFK_FORFEIT) {
            st.concede(seat, 'afk');
            return broadcast(match, st.takeEvents());
        }
        let action = { kind: 'next' };
        if (p && p.kind === 'choose') action = { kind: 'choose', option: p.options[0].id };
        else if (p && p.kind === 'discard') action = { kind: 'discard', uid: st.sides[seat].hand[0].uid };
        if (st.doAction(seat, action)) broadcast(match, st.takeEvents());
        else armTimer(match);
    }

    function act(playerId, matchId, action) {
        const match = byPlayer.get(playerId);
        if (!match || match.id !== matchId || match.over) return emitTo(playerId, 'ffa:error', { message: 'Match not found.' });
        const seat = seatOf(match, playerId);
        if (!action || typeof action !== 'object' || typeof action.kind !== 'string') {
            return emitTo(playerId, 'ffa:error', { message: 'Invalid action.' });
        }
        const ok = match.state.doAction(seat, actionFrom(action, match.state.seats, seat));
        if (!ok) {
            emitTo(playerId, 'ffa:error', { message: 'That move is not allowed right now.' });
            return sendStart(match, seat, true);
        }
        match.seats[seat].idle = 0;
        broadcast(match, match.state.takeEvents());
    }

    /** A player's result (once): their place, rewards, achievements; told with \`event\`. */
    async function settle(match, seat, event) {
        const s = match.seats[seat];
        if (s.settled) return s.settled;
        const place = match.state.places[seat] || match.state.sides[seat].out || 0;
        s.settled = { place, rewards: null, achievements: [] };
        if (!s.bot) {
            const outcome = place === 1 ? 'win' : 'loss';
            try {
                s.settled.rewards = await deps.resolveFfa?.({ playerId: s.playerId, place, humans: match.humans }) || null;
            } catch (err) {
                console.error('[FFA] Rewards failed:', err.message);
            }
            if (s.setup?.deckId) deps.recordDeck?.(s.setup.deckId, outcome)?.catch?.(() => {});
            if (s.cardsPlayed > 0) deps.incrementDailyQuest?.(s.playerId, 'daily_play_10', Math.min(40, s.cardsPlayed))?.catch?.(() => {});
            if (place === 1) deps.recordDailyWin?.(s.playerId)?.catch?.(() => {});
            s.settled.achievements = await deps.recordMatch?.({
                playerId: s.playerId, outcome, mode: match.humans >= 2 ? 'ffa' : 'cpu_ffa', difficulty: null,
                clan: await deckClan(s.setup), kos: s.kos, promotes: s.promotes, awakens: s.awakens,
                morale: match.state.sides[seat].morale,
            })?.catch?.(() => []) || [];
            if (event && s.watching) {
                emitTo(s.playerId, event, { matchId: match.id, place, ...placesFor(match, seat),
                    rewards: s.settled.rewards, achievements: s.settled.achievements, turns: match.state.turn });
            }
        }
        return s.settled;
    }

    function placesFor(match, seat) {
        const names = namesFor(match.state.seats, seat);
        const places = {};
        for (const s of match.state.seats) if (match.state.places[s]) places[names[s]] = match.state.places[s];
        return { places, players: playersFor(match, seat) };
    }

    async function finish(match) {
        if (match.over) return;
        match.over = true;
        clearTimeout(match.timer);
        for (const s of Object.values(match.seats)) clearTimeout(s.grace);
        matches.delete(match.id);
        for (const seat of Object.keys(match.seats)) {
            const s = match.seats[seat];
            if (s.bot) continue;
            await settle(match, seat, null);
            if (byPlayer.get(s.playerId) === match) byPlayer.delete(s.playerId);
            if (s.watching) {
                emitTo(s.playerId, 'ffa:over', { matchId: match.id, place: s.settled.place, ...placesFor(match, seat),
                    rewards: s.settled.rewards, achievements: s.settled.achievements, turns: match.state.turn });
            }
        }
        const winner = match.state.winner ? match.seats[match.state.winner] : null;
        console.log(`[FFA] Match ${match.id} over — winner ${winner?.profile?.username ?? 'none'}`);
    }

    function goOut(match, seat, reason) {
        if (match.over || match.state.sides[seat].out) return;
        match.state.concede(seat, reason);
        broadcast(match, match.state.takeEvents());
    }

    // ── Sockets ──
    function register(socket, playerData) {
        const me = playerData.playerId;
        sockets.set(me, socket);

        socket.on('ffa:queue', async () => {
            if (busy(me) || deps.isBusyElsewhere?.(me)) return socket.emit('ffa:error', { message: 'You are already in a match.' });
            let entry;
            try {
                entry = await prepare(me);
            } catch (err) {
                return socket.emit('ffa:error', { message: err.message || 'Could not load your deck.' });
            }
            if (busy(me)) return;
            deps.leaveOtherQueue?.(me);
            if (!lobby || lobby.over || lobby.players.length >= MAX_PLAYERS) lobby = openLobby();
            const l = lobby;
            l.players.push({ entry, ready: false });
            inLobby.set(me, l);
            if (l.players.length >= MAX_PLAYERS) lobby = null;   // full: the next player opens a new one
            lobbyNews(l);
        });

        socket.on('ffa:ready', ({ ready } = {}) => {
            const l = inLobby.get(me);
            if (!l || l.over) return;
            const p = l.players.find(q => q.entry.playerId === me);
            p.ready = ready !== false;
            if (l.players.length >= MAX_PLAYERS && l.players.every(q => q.ready)) {
                startFromLobby(l).catch(err => console.error('[FFA] Start failed:', err));
            } else {
                lobbyNews(l);
            }
        });

        socket.on('ffa:leave', () => {
            leaveLobby(me);
            socket.emit('ffa:left', { reason: '' });
        });

        socket.on('ffa:action', ({ matchId, action } = {}) => act(me, matchId, action));

        socket.on('ffa:concede', ({ matchId } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId) return;
            goOut(match, seatOf(match, me), 'concede');
        });

        // Out of the match (or never coming back to watch): stop the updates
        socket.on('ffa:quit', () => {
            const match = byPlayer.get(me);
            if (!match) return;
            const seat = seatOf(match, me);
            match.seats[seat].watching = false;
            if (!match.over && !match.state.sides[seat].out) goOut(match, seat, 'concede');
            byPlayer.delete(me);
        });

        socket.on('ffa:resync', () => {
            const l = inLobby.get(me);
            if (l) return lobbyNews(l);
            const match = byPlayer.get(me);
            if (!match || match.over) return socket.emit('ffa:none', {});
            const seat = seatOf(match, me);
            const s = match.seats[seat];
            if (!s.connected) {
                s.connected = true;
                clearTimeout(s.grace);
            }
            s.watching = true;
            sendStart(match, seat, true);
        });

        socket.on('disconnect', () => {
            if (sockets.get(me) !== socket) return;
            sockets.delete(me);
            leaveLobby(me);
            const match = byPlayer.get(me);
            if (!match || match.over) return;
            const seat = seatOf(match, me);
            const s = match.seats[seat];
            s.connected = false;
            if (match.state.sides[seat].out) {
                byPlayer.delete(me);
                return;
            }
            s.grace = setTimeout(() => goOut(match, seat, 'disconnect'), secs('reconnectSecs', RECONNECT_SECS) * 1000);
        });
    }

    return { register, isBusy: busy, _matches: matches };
}

/** The clan most of a deck's cards belong to (achievements: wins with a clan). */
async function deckClan(setup) {
    const { getCard } = await engine;
    const count = {};
    for (const spec of setup?.deck || []) {
        const clan = getCard(typeof spec === 'object' ? spec.id : spec)?.clan;
        if (clan) count[clan] = (count[clan] || 0) + 1;
    }
    return Object.keys(count).sort((a, b) => count[b] - count[a])[0] || null;
}

module.exports = { createFfaService, namesFor, rename, actionFrom };
