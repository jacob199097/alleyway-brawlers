'use strict';

/**
 * ONLINE MATCHES (server-authoritative)
 *
 * The server runs every online duel with the shared rules engine (shared/duel/DuelState.js,
 * the same rules as the Godot client's CPU duels). Clients only send actions; the server
 * validates them, applies them, and sends each player the resulting events, filtered so
 * neither player learns the other's hand, deck or face-down cards.
 *
 * Socket.io events (Godot client, scripts/net.gd):
 * CPU matches (VS CPU and Ranked) run here too, against a server-side CPU (shared/duel/DuelAI.js),
 * so their rewards come from a result the server saw rather than one a client reported.
 *
 *   Matches against players start with Scissors Paper Rock (mp:rps, mp:rps_pick {rpsId, pick},
 *   mp:rps_result, mp:rps_choose, mp:rps_first {rpsId, goFirst}, mp:rps_decided, mp:rps_cancel);
 *   the winner chooses to go first or second.
 *   client → server  mp:queue, mp:cancel, mp:cpu {ranked, difficulty}, mp:challenge {targetPlayerId}, mp:accept {fromPlayerId},
 *                    mp:decline {fromPlayerId}, mp:action {matchId, action}, mp:concede {matchId},
 *                    mp:resync, mp:rematch, mp:rematch_decline, mp:spectate {targetPlayerId}, mp:unspectate
 *   server → client  mp:queued, mp:cancelled, mp:error {message}, mp:challenge {fromPlayerId, fromUsername},
 *                    mp:declined {byUsername}, mp:start {matchId, you, opponent, view, resync, clock},
 *                    mp:update {matchId, events, view, clock, away}, mp:opponent {status, graceSecs?},
 *                    mp:over {matchId, result, reason, rewards}, mp:none (resync with no match),
 *                    mp:rematch_offer {fromUsername}, mp:rematch_sent, mp:rematch_declined {message}
 *   clock = seconds the player who acts next has before a safe move is played for them;
 *   away = that player was auto-played last time (so they get AWAY_SECS).
 *
 *   Spectators (friends of a player, mp:spectate) get mp:start {spectate: true, ...} and every
 *   mp:update and mp:over from that player's side, with both hands and all face-down cards hidden
 *   (viewer "spectator" owns no seat). Players get mp:spectators {count} when it changes.
 *
 * Every player sees the match from their own side: their seat is always "player".
 * Database access is passed in (createOnlineService), so tests can run it without Postgres.
 */

const { randomUUID } = require('crypto');

const TURN_SECS        = 90;    // a player who doesn't act for this long is auto-played
// Once auto-played, a player who still isn't acting gets AWAY_SECS per move, and loses after
// AFK_FORFEIT auto-played moves in a row (any move of their own resets it)
const AWAY_SECS        = 15;
const AFK_FORFEIT      = 8;
const RECONNECT_SECS   = 45;    // a disconnected player loses after this long
const REMATCH_SECS     = 60;    // after a match against a player, either can offer a rematch this long
const CHALLENGE_SECS   = 60;
const BOT_MOVE_MS      = 350;   // the server CPU's think time between moves
// Emotes: a fixed list (no free text), at most one every EMOTE_GAP_MS and MAX_EMOTES a match
// Scissors Paper Rock decides who goes first in matches against players
const RPS_PICK_SECS    = 15;    // a player who doesn't pick in time throws at random
const RPS_CHOOSE_SECS  = 10;    // the winner's first/second choice (goes first if no answer)
const RPS_BEATS        = { rock: 'scissors', paper: 'rock', scissors: 'paper' };
const EMOTES           = ['hello', 'nice', 'wp', 'thinking', 'oops', 'hurry', 'gotcha', 'gg'];
const EMOTE_GAP_MS     = 2500;
const MAX_EMOTES       = 30;
const GAME_VERSION     = (() => { try { return require('../../shared/game_version.json').latest; } catch { return ''; } })();

const engine = import('../../shared/duel/DuelState.js');
const cpu = import('../../shared/duel/DuelAI.js');

// ── Perspective and hidden information ──────────────────────────────────────

const other = (seat) => (seat === 'player' ? 'opponent' : 'player');

/** Deep copy with "player" and "opponent" swapped (values and keys) — the other seat's view. */
function swapSides(v) {
    if (v === 'player') return 'opponent';
    if (v === 'opponent') return 'player';
    if (Array.isArray(v)) return v.map(swapSides);
    if (v && typeof v === 'object') {
        const out = {};
        for (const [k, val] of Object.entries(v)) out[swapSides(k)] = swapSides(val);
        return out;
    }
    return v;
}

function redact(c) {
    return { uid: c.uid, face_down: true, position: c.position, downed: c.downed,
        has_attacked: c.has_attacked, deployed_turn: c.deployed_turn, cardType: c.cardType, mods: [] };
}

/** What `viewer` may see of one event (still in server seats; swapped afterwards). */
function filterEvent(ev, viewer) {
    if (ev.side === viewer) return ev;
    switch (ev.type) {
        case 'draw': return { ...ev, card: { uid: ev.card.uid } };
        case 'summon': return ev.card.face_down ? { ...ev, card: redact(ev.card) } : ev;
        case 'set': return { ...ev, card: redact(ev.card) };
        case 'bounce': return { ...ev, card: { uid: ev.card.uid } };   // back into a hidden hand
        case 'prompt': return { type: 'prompt', side: ev.side, kind: ev.kind, key: 'hidden', counts: ev.counts };
        case 'answered': return { type: 'answered', side: ev.side, key: ev.key, option: '', counts: ev.counts };
    }
    return ev;
}

/** Stats for the other side's face-down cards stay hidden. */
function statsFilter(ev, viewer) {
    if (ev.type !== 'stats') return ev;
    const values = {};
    for (const [seat, slots] of Object.entries(ev.values)) {
        values[seat] = seat === viewer ? slots : Object.fromEntries(Object.entries(slots).filter(([, v]) => !v[4]));
    }
    return { ...ev, values };
}

/** The whole board as `viewer` may see it (server seats; swapped afterwards). */
function viewFor(state, viewer) {
    const sides = {};
    for (const seat of ['player', 'opponent']) {
        const s = state.sides[seat];
        const own = seat === viewer;
        sides[seat] = {
            morale: s.morale, authority: s.authority, authority_max: s.authority_max,
            brutus_bonus: s.brutus_bonus, promoted: s.promoted, mentor_used: s.mentor_used,
            leader_state: s.leader_state, leader: s.leader ? structuredClone(s.leader) : null,
            hand: own ? structuredClone(s.hand) : s.hand.map(c => ({ uid: c.uid })),
            deck: s.deck.map(() => ({})),
            hideout: own ? structuredClone(s.hideout) : s.hideout.map(c => ({ uid: c.uid })),
            gutter: structuredClone(s.gutter),
            field: s.field.map(c => (c == null ? null : (own || !c.face_down) ? structuredClone(c) : redact(c))),
        };
    }
    let pending = {};
    if (state.pending && Object.keys(state.pending).length) {
        if (state.pending.side === viewer) {
            pending = { ...state.pending };
            delete pending.cb;
        } else {
            pending = { kind: state.pending.kind, side: state.pending.side };
        }
    }
    return { turn: state.turn, active: state.active, phase: state.phase, winner: state.winner, pending, sides };
}

function forSeat(v, seat) {
    return seat === 'player' ? v : swapSides(v);
}

// ── Service ─────────────────────────────────────────────────────────────────

/**
 * @param {object} deps
 * @param {(playerId) => Promise<{deck, hideout, leader}|{error}>} deps.loadSetup
 * @param {(playerId) => Promise<{username, level, avatar_url}>} deps.loadProfile
 * @param {(args) => Promise<object>} deps.resolveMatch       rewards per playerId
 * @param {(playerId, questId, amount) => Promise} [deps.incrementDailyQuest]
 * @param {(playerId) => Promise} [deps.recordDailyWin]
 * @param {(args) => Promise<object>} [deps.resolveCpuMatch]  {playerId, outcome, ranked, turns} → rewards
 * @param {number} [deps.turnSecs] [deps.awaySecs]  shorter move clocks (tests)
 * @param {(a, b) => Promise<boolean>} [deps.areFriends]  may a watch b's match (mp:spectate)
 */
function createOnlineService(io, deps) {
    const sockets = new Map();       // playerId → socket (latest connection)
    const queue = [];                // [{ playerId, setup, profile }]
    const matches = new Map();       // matchId → match
    const byPlayer = new Map();      // playerId → match
    const challenges = new Map();    // "from:to" → expiry
    const rpsByPlayer = new Map();   // playerId → Scissors Paper Rock session before a match
    const rematchable = new Map();   // playerId → { opp, until } after a match against a player
    const rematchAsks = new Map();   // playerId → the opponent they offered a rematch to
    const watching = new Map();      // spectator playerId → { match, seat } (the seat they watch from)
    const busy = (id) => byPlayer.has(id) || rpsByPlayer.has(id);

    const emitTo = (playerId, event, data) => sockets.get(playerId)?.emit(event, data);

    async function prepare(playerId) {
        const [setup, profile] = await Promise.all([deps.loadSetup(playerId), deps.loadProfile(playerId)]);
        if (setup.error) throw new Error(setup.error);
        return { playerId, setup, profile };
    }

    // ── Scissors Paper Rock (who goes first) ──
    function startRps(a, b, mode) {
        const rps = { id: randomUUID(), a, b, mode, round: 0, picks: {}, timer: null, over: false };
        rpsByPlayer.set(a.playerId, rps);
        rpsByPlayer.set(b.playerId, rps);
        rpsRound(rps);
    }

    function rpsRound(rps) {
        rps.round += 1;
        rps.picks = {};
        for (const [me, foe] of [[rps.a, rps.b], [rps.b, rps.a]]) {
            emitTo(me.playerId, 'mp:rps', { rpsId: rps.id, round: rps.round, secs: RPS_PICK_SECS, mode: rps.mode, opponent: foe.profile });
        }
        clearTimeout(rps.timer);
        rps.timer = setTimeout(() => rpsResolve(rps), RPS_PICK_SECS * 1000 + 500);
    }

    function rpsPick(playerId, rpsId, pick) {
        const rps = rpsByPlayer.get(playerId);
        if (!rps || rps.over || rps.id !== rpsId || !RPS_BEATS[pick] || rps.picks[playerId] || rps.chooser) return;
        rps.picks[playerId] = pick;
        if (rps.picks[rps.a.playerId] && rps.picks[rps.b.playerId]) rpsResolve(rps);
    }

    function rpsResolve(rps) {
        if (rps.over || rps.chooser) return;
        clearTimeout(rps.timer);
        const throws = Object.keys(RPS_BEATS);
        for (const p of [rps.a, rps.b]) rps.picks[p.playerId] ||= throws[Math.floor(Math.random() * 3)];
        const pa = rps.picks[rps.a.playerId], pb = rps.picks[rps.b.playerId];
        const winner = pa === pb ? null : RPS_BEATS[pa] === pb ? rps.a : rps.b;
        for (const [me, foe] of [[rps.a, rps.b], [rps.b, rps.a]]) {
            emitTo(me.playerId, 'mp:rps_result', { rpsId: rps.id, round: rps.round,
                you: rps.picks[me.playerId], opponent: rps.picks[foe.playerId],
                outcome: !winner ? 'draw' : winner === me ? 'win' : 'loss' });
        }
        if (!winner) {
            rps.timer = setTimeout(() => rpsRound(rps), 2200);
            return;
        }
        rps.chooser = winner;
        rps.timer = setTimeout(() => {
            emitTo(winner.playerId, 'mp:rps_choose', { rpsId: rps.id, secs: RPS_CHOOSE_SECS });
            rps.timer = setTimeout(() => rpsDecide(rps, winner.playerId, true), RPS_CHOOSE_SECS * 1000 + 500);
        }, 1600);
    }

    function rpsDecide(rps, playerId, goFirst) {
        if (rps.over || !rps.chooser || rps.chooser.playerId !== playerId) return;
        rps.over = true;
        clearTimeout(rps.timer);
        const firstPlayer = goFirst ? rps.chooser : (rps.chooser === rps.a ? rps.b : rps.a);
        for (const p of [rps.a, rps.b]) {
            emitTo(p.playerId, 'mp:rps_decided', { rpsId: rps.id, first: p === firstPlayer ? 'you' : 'opponent' });
        }
        rps.timer = setTimeout(() => {
            rpsByPlayer.delete(rps.a.playerId);
            rpsByPlayer.delete(rps.b.playerId);
            // Seat "player" is a, so the first player's seat follows from who that is
            startMatch(rps.a, rps.b, rps.mode, firstPlayer === rps.a ? 'player' : 'opponent')
                .catch(err => console.error('[Online] Start failed:', err));
        }, 1800);
    }

    /** A player left during Scissors Paper Rock: no match; a queued opponent goes back in the queue. */
    function rpsCancel(rps, leaver) {
        if (rps.over && !rpsByPlayer.has(leaver)) return;
        rps.over = true;
        clearTimeout(rps.timer);
        rpsByPlayer.delete(rps.a.playerId);
        rpsByPlayer.delete(rps.b.playerId);
        const stay = rps.a.playerId === leaver ? rps.b : rps.a;
        const requeue = rps.mode === 'casual' && sockets.get(stay.playerId)?.connected;
        emitTo(stay.playerId, 'mp:rps_cancel', { requeued: requeue,
            message: requeue ? 'Your opponent left. Finding you another match…' : 'Your opponent left before the match started.' });
        if (requeue) {
            queue.push(stay);
            emitTo(stay.playerId, 'mp:queued', { position: queue.length });
        }
    }

    async function startMatch(a, b, mode, firstSeat = null) {
        const { DuelState } = await engine;
        const first = firstSeat || (Math.random() < 0.5 ? 'player' : 'opponent');
        const seed = 1 + Math.floor(Math.random() * 2147483646);
        const decks = { player: a.setup.deck, opponent: b.setup.deck };
        const hideouts = { player: a.setup.hideout, opponent: b.setup.hideout };
        const leaders = { player: a.setup.leader, opponent: b.setup.leader };
        const state = new DuelState(decks, hideouts, leaders, first, seed);
        const match = {
            id: randomUUID(), mode, state, startedAt: Date.now(), over: false, timer: null,
            seats: {
                player: { ...a, connected: true, grace: null, cardsPlayed: 0, idle: 0 },
                opponent: { ...b, connected: true, grace: null, cardsPlayed: 0, idle: 0 },
            },
        };
        // Everything needed to play the match again (replays: routes/replays.js, replaySteps)
        match.record = {
            id: match.id, version: GAME_VERSION, mode, seed, first,
            decks: structuredClone(decks), hideouts: structuredClone(hideouts), leaders: structuredClone(leaders),
            playerIds: { player: a.playerId, opponent: b.playerId },
            profiles: { player: profileOf(match.seats.player), opponent: profileOf(match.seats.opponent) },
            actions: [],
        };
        matches.set(match.id, match);
        byPlayer.set(a.playerId, match);
        byPlayer.set(b.playerId, match);
        stopWatching(a.playerId);
        stopWatching(b.playerId);
        state.start();
        const events = state.takeEvents();
        for (const seat of ['player', 'opponent']) sendStart(match, seat, false);
        broadcast(match, events);
        console.log(`[Online] ${a.profile.username} vs ${b.profile.username} (${mode}) — ${match.id}`);
    }

    function profileOf(seat) {
        return { username: seat.profile.username, level: seat.profile.level, avatar_url: seat.profile.avatar_url };
    }

    /** The server CPU's seat: a random clan's starter deck (shared/clans.js). */
    async function cpuSeat(ranked, level) {
        const { cpuSetup, randomCpuClan } = await cpu;
        return {
            playerId: `cpu:${randomUUID()}`, bot: true, setup: cpuSetup(randomCpuClan()), level,
            profile: { username: ranked ? 'RANKED CPU' : 'CPU', level: 1, avatar_url: 'profile_002' },
        };
    }

    const seatToAct = (st) => (st.pending && st.pending.side ? st.pending.side : st.active);

    function sendStart(match, seat, resync) {
        const s = match.seats[seat];
        emitTo(s.playerId, 'mp:start', {
            matchId: match.id, mode: match.mode, resync,
            you: profileOf(s), opponent: profileOf(match.seats[other(seat)]),
            view: forSeat(viewFor(match.state, seat), seat),
            clock: Math.max(0, Math.round(((match.clockEnds || Date.now()) - Date.now()) / 1000)) || TURN_SECS,
        });
    }

    function broadcast(match, events) {
        for (const ev of events) {
            if (['summon', 'set', 'hustle'].includes(ev.type)) match.seats[ev.side].cardsPlayed += 1;
        }
        const clock = match.state.winner ? 0 : armTimer(match);
        const away = !match.state.winner && match.seats[seatToAct(match.state)].idle > 0;
        for (const seat of ['player', 'opponent']) {
            const visible = events.map(ev => statsFilter(filterEvent(ev, seat), seat));
            emitTo(match.seats[seat].playerId, 'mp:update', {
                matchId: match.id,
                events: forSeat(visible, seat),
                view: forSeat(viewFor(match.state, seat), seat),
                clock, away,
            });
        }
        if (match.spectators?.size) {
            // What nobody's seat owns: hands, draws and face-down cards stay hidden
            const visible = events.map(ev => statsFilter(filterEvent(ev, 'spectator'), 'spectator'));
            const view = viewFor(match.state, 'spectator');
            for (const [id, seat] of match.spectators) {
                emitTo(id, 'mp:update', { matchId: match.id, events: forSeat(visible, seat), view: forSeat(view, seat), clock, away });
            }
        }
        if (match.state.winner) finish(match, match.state.winner, match.state.endReason || 'morale');
    }

    /** Whoever has to act next gets TURN_SECS (AWAY_SECS if they were just auto-played); then the
     *  server plays a safe move for them. When it's the server CPU's move, it plays after a short
     *  pause instead. Returns the seconds given. */
    function armTimer(match) {
        clearTimeout(match.timer);
        const s = match.seats[seatToAct(match.state)];
        if (s.bot) {
            match.timer = setTimeout(() => botMove(match), BOT_MOVE_MS);
            match.clockEnds = null;
            return TURN_SECS;
        }
        const secs = s.idle > 0 ? (deps.awaySecs ?? AWAY_SECS) : (deps.turnSecs ?? TURN_SECS);
        match.timer = setTimeout(() => autoPlay(match), secs * 1000);
        match.clockEnds = Date.now() + secs * 1000;
        return secs;
    }

    async function botMove(match) {
        if (match.over) return;
        const { choose } = await cpu;
        const st = match.state;
        const seat = seatToAct(st);
        if (!match.seats[seat].bot) return armTimer(match);
        let action = choose(st, seat, match.seats[seat].level || 'normal');
        if (!Object.keys(action).length || !st.doAction(seat, action)) {
            action = { kind: 'next' };
            if (!st.doAction(seat, action)) return autoPlay(match);
        }
        match.record.actions.push([seat, action]);
        broadcast(match, st.takeEvents());
    }

    function autoPlay(match) {
        if (match.over) return;
        const st = match.state;
        const p = st.pending;
        const seat = p && p.side ? p.side : st.active;
        match.seats[seat].idle += 1;
        if (match.seats[seat].idle >= AFK_FORFEIT) return finish(match, other(seat), 'afk');
        let action = { kind: 'next' };
        if (p && p.kind === 'choose') action = { kind: 'choose', option: p.options[0].id };
        else if (p && p.kind === 'discard') action = { kind: 'discard', uid: st.sides[seat].hand[0].uid };
        if (st.doAction(seat, action)) {
            match.record.actions.push([seat, action]);
            broadcast(match, st.takeEvents());
        }
    }

    function act(playerId, matchId, action) {
        const match = byPlayer.get(playerId);
        if (!match || match.id !== matchId || match.over) return emitTo(playerId, 'mp:error', { message: 'Match not found.' });
        const seat = match.seats.player.playerId === playerId ? 'player' : 'opponent';
        if (!action || typeof action !== 'object' || typeof action.kind !== 'string') {
            return emitTo(playerId, 'mp:error', { message: 'Invalid action.' });
        }
        // Actions name slots relative to their owner, so they need no perspective swap
        const ok = match.state.doAction(seat, action);
        deps.onAction?.(match, seat, action, ok);
        if (!ok) {
            emitTo(playerId, 'mp:error', { message: 'That move is not allowed right now.' });
            return sendStart(match, seat, true);
        }
        match.seats[seat].idle = 0;
        match.record.actions.push([seat, action]);
        broadcast(match, match.state.takeEvents());
    }

    async function finish(match, winnerSeat, reason) {
        if (match.over) return;
        match.over = true;
        clearTimeout(match.timer);
        for (const seat of Object.values(match.seats)) clearTimeout(seat.grace);
        matches.delete(match.id);
        byPlayer.delete(match.seats.player.playerId);
        byPlayer.delete(match.seats.opponent.playerId);
        const winner = winnerSeat ? match.seats[winnerSeat] : null;
        const loser = winnerSeat ? match.seats[other(winnerSeat)] : null;
        let rewards = {};
        const bot = Object.values(match.seats).find(s => s.bot);
        if (bot) {
            // CPU match: only the human is rewarded, from the result the server saw
            const human = Object.values(match.seats).find(s => !s.bot);
            try {
                rewards[human.playerId] = await deps.resolveCpuMatch?.({
                    playerId: human.playerId,
                    outcome: !winnerSeat ? 'draw' : winner === human ? 'win' : 'loss',
                    ranked: match.mode === 'cpu_ranked', turns: match.state.turn, difficulty: bot.level || 'normal',
                }) || null;
                if (human.cardsPlayed > 0) deps.incrementDailyQuest?.(human.playerId, 'daily_play_10', Math.min(40, human.cardsPlayed))?.catch?.(() => {});
            } catch (err) {
                console.error('[Online] CPU match rewards failed:', err.message);
            }
        } else try {
            rewards = await deps.resolveMatch({
                winnerId: winner?.playerId ?? null, loserId: loser?.playerId ?? null,
                p1Id: match.seats.player.playerId, p2Id: match.seats.opponent.playerId,
                matchMeta: {
                    turns: match.state.turn, ranked: match.mode === 'ranked',
                    p1MoraleEnd: match.state.sides.player.morale, p2MoraleEnd: match.state.sides.opponent.morale,
                    durationSecs: Math.round((Date.now() - match.startedAt) / 1000),
                },
            }) || {};
            if (winner) deps.recordDailyWin?.(winner.playerId)?.catch?.(() => {});
            for (const s of Object.values(match.seats)) {
                if (s.cardsPlayed > 0) deps.incrementDailyQuest?.(s.playerId, 'daily_play_10', Math.min(40, s.cardsPlayed))?.catch?.(() => {});
            }
        } catch (err) {
            console.error('[Online] Rewards failed:', err.message);
        }
        for (const seat of ['player', 'opponent']) {
            const s = match.seats[seat];
            emitTo(s.playerId, 'mp:over', {
                matchId: match.id, reason,
                result: !winnerSeat ? 'draw' : winnerSeat === seat ? 'win' : 'loss',
                rewards: rewards[s.playerId] || null,
                player_morale: match.state.sides[seat].morale,
                opponent_morale: match.state.sides[other(seat)].morale,
                turns: match.state.turn,
            });
        }
        if (!bot) {
            // Either player can offer a rematch for a while (mp:rematch)
            const until = Date.now() + REMATCH_SECS * 1000;
            const [p, o] = [match.seats.player.playerId, match.seats.opponent.playerId];
            rematchable.set(p, { opp: o, until });
            rematchable.set(o, { opp: p, until });
            rematchAsks.delete(p);
            rematchAsks.delete(o);
        }
        for (const [id, seat] of match.spectators || []) {
            watching.delete(id);
            emitTo(id, 'mp:over', {
                matchId: match.id, reason, spectate: true,
                result: !winnerSeat ? 'draw' : winnerSeat === seat ? 'win' : 'loss',
                player_morale: match.state.sides[seat].morale,
                opponent_morale: match.state.sides[other(seat)].morale,
                turns: match.state.turn,
            });
        }
        match.spectators?.clear();
        console.log(`[Online] Match ${match.id} over (${reason}) — winner ${winner?.profile.username ?? 'none'}`);
        match.record.end = { winner: winnerSeat || '', reason, turns: match.state.turn };
        Promise.resolve(deps.saveReplay?.(match.record)).catch(err => console.error('[Online] Replay save failed:', err.message));
    }

    // ── Spectators ──
    function spectatorStart(match, id, seat) {
        emitTo(id, 'mp:start', {
            matchId: match.id, mode: match.mode, resync: true, spectate: true,
            you: profileOf(match.seats[seat]), opponent: profileOf(match.seats[other(seat)]),
            view: forSeat(viewFor(match.state, 'spectator'), seat),
            clock: Math.max(0, Math.round(((match.clockEnds || Date.now()) - Date.now()) / 1000)) || TURN_SECS,
        });
    }

    function tellWatchers(match) {
        const count = match.spectators?.size || 0;
        for (const seat of ['player', 'opponent']) emitTo(match.seats[seat].playerId, 'mp:spectators', { matchId: match.id, count });
    }

    function stopWatching(id) {
        const w = watching.get(id);
        if (!w) return;
        watching.delete(id);
        w.match.spectators?.delete(id);
        if (!w.match.over) tellWatchers(w.match);
    }

    /** `playerId` won't rematch: their opponent is told, and neither can ask any more. */
    function declineRematch(playerId, message) {
        const r = rematchable.get(playerId);
        if (!r) return;
        rematchable.delete(playerId);
        rematchable.delete(r.opp);
        rematchAsks.delete(playerId);
        rematchAsks.delete(r.opp);
        if (r.until >= Date.now()) emitTo(r.opp, 'mp:rematch_declined', { message });
    }

    function leaveQueue(playerId) {
        const i = queue.findIndex(e => e.playerId === playerId);
        if (i >= 0) queue.splice(i, 1);
        return i >= 0;
    }

    function register(socket, playerData) {
        const me = playerData.playerId;
        sockets.set(me, socket);

        socket.on('mp:queue', async () => {
            if (busy(me)) return socket.emit('mp:error', { message: 'You are already in a match.' });
            if (queue.some(e => e.playerId === me)) return socket.emit('mp:queued', { position: queue.length });
            let entry;
            try {
                entry = await prepare(me);
            } catch (err) {
                return socket.emit('mp:error', { message: err.message || 'Could not load your deck.' });
            }
            const rival = queue.find(e => e.playerId !== me);
            if (rival) {
                leaveQueue(rival.playerId);
                startRps(rival, entry, 'casual');
            } else {
                queue.push(entry);
                socket.emit('mp:queued', { position: queue.length });
            }
        });

        // A match against the server CPU (VS CPU, or Ranked when ranked is true)
        socket.on('mp:cpu', async ({ ranked, difficulty } = {}) => {
            if (busy(me)) return socket.emit('mp:error', { message: 'You are already in a match.' });
            leaveQueue(me);
            try {
                const entry = await prepare(me);
                const level = ranked === true ? 'hard' : ['easy', 'normal', 'hard'].includes(difficulty) ? difficulty : 'normal';
                await startMatch(entry, await cpuSeat(ranked === true, level), ranked === true ? 'cpu_ranked' : 'cpu');
            } catch (err) {
                socket.emit('mp:error', { message: err.message || 'Could not start the match.' });
            }
        });

        // Emotes go to the opponent only (a CPU doesn't read them)
        socket.on('mp:emote', ({ matchId, key } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId || match.over || !EMOTES.includes(key)) return;
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            const s = match.seats[seat];
            const now = Date.now();
            if (now - (s.lastEmote || 0) < EMOTE_GAP_MS || (s.emotes || 0) >= MAX_EMOTES) return;
            s.lastEmote = now;
            s.emotes = (s.emotes || 0) + 1;
            emitTo(match.seats[other(seat)].playerId, 'mp:emote', { matchId, key });
        });

        socket.on('mp:cancel', () => {
            leaveQueue(me);
            socket.emit('mp:cancelled', {});
        });

        socket.on('mp:challenge', ({ targetPlayerId } = {}) => {
            if (typeof targetPlayerId !== 'string' || targetPlayerId === me) return;
            if (!sockets.get(targetPlayerId)?.connected) {
                return socket.emit('mp:error', { message: 'That player is offline.' });
            }
            if (busy(targetPlayerId)) return socket.emit('mp:error', { message: 'That player is in a match.' });
            challenges.set(`${me}:${targetPlayerId}`, Date.now() + CHALLENGE_SECS * 1000);
            emitTo(targetPlayerId, 'mp:challenge', { fromPlayerId: me, fromUsername: playerData.username });
            socket.emit('mp:challengeSent', { targetPlayerId });
        });

        socket.on('mp:decline', ({ fromPlayerId } = {}) => {
            if (challenges.delete(`${fromPlayerId}:${me}`)) {
                emitTo(fromPlayerId, 'mp:declined', { byUsername: playerData.username });
            }
        });

        socket.on('mp:accept', async ({ fromPlayerId } = {}) => {
            const key = `${fromPlayerId}:${me}`;
            const expires = challenges.get(key);
            challenges.delete(key);
            if (!expires || expires < Date.now()) return socket.emit('mp:error', { message: 'That challenge has expired.' });
            if (busy(me) || busy(fromPlayerId)) return socket.emit('mp:error', { message: 'A player is already in a match.' });
            leaveQueue(me);
            leaveQueue(fromPlayerId);
            try {
                const [a, b] = await Promise.all([prepare(fromPlayerId), prepare(me)]);
                startRps(a, b, 'friendly');
            } catch (err) {
                socket.emit('mp:error', { message: err.message || 'Could not start the match.' });
                emitTo(fromPlayerId, 'mp:error', { message: err.message || 'Could not start the match.' });
            }
        });

        // Rematch: both players ask (the second ask starts it, with Scissors Paper Rock again)
        socket.on('mp:rematch', async () => {
            const r = rematchable.get(me);
            if (!r || r.until < Date.now()) return socket.emit('mp:rematch_declined', { message: 'The rematch offer has expired.' });
            if (!sockets.get(r.opp)?.connected) return socket.emit('mp:rematch_declined', { message: 'Your opponent has left.' });
            if (busy(me) || busy(r.opp)) return socket.emit('mp:rematch_declined', { message: 'Your opponent is already in another match.' });
            if (rematchAsks.get(r.opp) !== me) {
                rematchAsks.set(me, r.opp);
                emitTo(r.opp, 'mp:rematch_offer', { fromUsername: playerData.username });
                return socket.emit('mp:rematch_sent', {});
            }
            rematchAsks.delete(me);
            rematchAsks.delete(r.opp);
            rematchable.delete(me);
            rematchable.delete(r.opp);
            leaveQueue(me);
            leaveQueue(r.opp);
            try {
                const [a, b] = await Promise.all([prepare(r.opp), prepare(me)]);
                startRps(a, b, 'friendly');
            } catch (err) {
                for (const id of [me, r.opp]) emitTo(id, 'mp:rematch_declined', { message: err.message || 'Could not start the rematch.' });
            }
        });

        // Declining an offer, or leaving the results screen
        socket.on('mp:rematch_decline', () => declineRematch(me, 'Your opponent left.'));

        // Watch a friend's match (players are told how many are watching)
        socket.on('mp:spectate', async ({ targetPlayerId } = {}) => {
            if (typeof targetPlayerId !== 'string' || targetPlayerId === me) return;
            if (busy(me)) return socket.emit('mp:error', { message: "You can't watch while you're in a match." });
            const match = byPlayer.get(targetPlayerId);
            if ((!match || match.over) && rpsByPlayer.has(targetPlayerId)) {
                return socket.emit('mp:error', { message: 'Their match is about to start. Try again in a moment.' });
            }
            if (!match || match.over) return socket.emit('mp:error', { message: "They aren't in a match right now." });
            try {
                if (deps.areFriends && !(await deps.areFriends(me, targetPlayerId))) {
                    return socket.emit('mp:error', { message: 'You can only watch your friends.' });
                }
            } catch (err) {
                return socket.emit('mp:error', { message: 'Could not check your friends list.' });
            }
            if (match.over) return socket.emit('mp:error', { message: 'That match just ended.' });
            stopWatching(me);
            leaveQueue(me);
            const seat = match.seats.player.playerId === targetPlayerId ? 'player' : 'opponent';
            match.spectators ||= new Map();
            match.spectators.set(me, seat);
            watching.set(me, { match, seat });
            spectatorStart(match, me, seat);
            tellWatchers(match);
        });

        socket.on('mp:unspectate', () => stopWatching(me));

        socket.on('mp:action', ({ matchId, action } = {}) => act(me, matchId, action));

        socket.on('mp:rps_pick', ({ rpsId, pick } = {}) => rpsPick(me, rpsId, pick));
        socket.on('mp:rps_first', ({ rpsId, goFirst } = {}) => {
            const rps = rpsByPlayer.get(me);
            if (rps && rps.id === rpsId) rpsDecide(rps, me, goFirst !== false);
        });

        socket.on('mp:concede', ({ matchId } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId) return;
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            finish(match, other(seat), 'concede');
        });

        // A client (re)connecting mid-match asks for the board again
        socket.on('mp:resync', () => {
            const w = watching.get(me);
            if (w && !w.match.over) return spectatorStart(w.match, me, w.seat);
            const match = byPlayer.get(me);
            if (!match) return socket.emit('mp:none', {});
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            const s = match.seats[seat];
            if (!s.connected) {
                s.connected = true;
                clearTimeout(s.grace);
                emitTo(match.seats[other(seat)].playerId, 'mp:opponent', { status: 'back' });
            }
            sendStart(match, seat, true);
        });

        socket.on('disconnect', () => {
            if (sockets.get(me) !== socket) return;   // an older connection closing
            sockets.delete(me);
            leaveQueue(me);
            stopWatching(me);
            declineRematch(me, 'Your opponent has left.');
            const rps = rpsByPlayer.get(me);
            if (rps) rpsCancel(rps, me);
            const match = byPlayer.get(me);
            if (!match || match.over) return;
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            const s = match.seats[seat];
            s.connected = false;
            emitTo(match.seats[other(seat)].playerId, 'mp:opponent', { status: 'disconnected', graceSecs: RECONNECT_SECS });
            s.grace = setTimeout(() => finish(match, other(seat), 'disconnect'), RECONNECT_SECS * 1000);
        });
    }

    return { register, isInMatch: (playerId) => busy(playerId), _matches: matches };
}

// ── Database-backed dependencies (production) ───────────────────────────────

/**
 * The player's active 40-card deck as rules-engine card specs (stats from the DB, rules from
 * the shared catalog), the promoted forms they own for its Strivers, and the deck's leader.
 */
async function loadSetupFromDb(pool, playerId) {
    const { getCard, nextForm } = await engine;
    const { rows: decks } = await pool.query(
        `SELECT id, leader_card_id FROM decks WHERE player_id = $1
         ORDER BY is_active DESC, updated_at DESC LIMIT 1`, [playerId]);
    if (!decks.length) return { error: 'You need a complete 40-card deck to play online.' };
    const { rows } = await pool.query(
        `SELECT c.id, c.name, c.card_type, c.authority, c.attack, c.defense, c.rarity, c.art_url,
                LEAST(dc.copies, pi.quantity) AS copies
         FROM   deck_cards dc
         JOIN   cards c             ON c.id = dc.card_id
         JOIN   player_inventory pi ON pi.card_id = c.id AND pi.player_id = $2
         WHERE  dc.deck_id = $1`, [decks[0].id, playerId]);
    const total = rows.reduce((s, r) => s + r.copies, 0);
    if (total !== 40) return { error: 'You need a complete 40-card deck to play online.' };
    const spec = (r) => {
        const out = { id: r.art_url };
        for (const k of ['name', 'authority', 'attack', 'defense', 'rarity']) if (r[k] != null) out[k] = r[k];
        return out;
    };
    const deck = [];
    for (const r of rows) {
        if (!Object.keys(getCard(r.art_url)).length) {
            return { error: `${r.name} isn't playable online yet. Take it out of your deck to play.` };
        }
        for (let i = 0; i < r.copies; i++) deck.push(spec(r));
    }
    const { rows: inv } = await pool.query(
        `SELECT c.name, c.authority, c.attack, c.defense, c.rarity, c.art_url, pi.quantity
         FROM player_inventory pi JOIN cards c ON c.id = pi.card_id WHERE pi.player_id = $1`, [playerId]);
    const owned = new Map(inv.map(r => [r.art_url, r]));
    const hideout = [];
    const seen = new Set();
    for (const r of rows) {
        let next = nextForm(r.art_url);
        while (next && !seen.has(next)) {
            seen.add(next);
            const o = owned.get(next);
            if (o) for (let i = 0; i < Math.min(3, o.quantity); i++) hideout.push(spec(o));
            next = nextForm(next);
        }
    }
    let leader = '';
    if (decks[0].leader_card_id) {
        const { rows: lr } = await pool.query('SELECT art_url FROM cards WHERE id = $1', [decks[0].leader_card_id]);
        if (lr.length && Object.keys(getCard(lr[0].art_url)).length) leader = lr[0].art_url;
    }
    return { deck, hideout, leader };
}

async function loadProfileFromDb(pool, playerId) {
    const { rows } = await pool.query('SELECT username, level, avatar_url FROM players WHERE id = $1', [playerId]);
    return rows[0] || { username: 'Player', level: 1, avatar_url: null };
}

/**
 * Play a recorded match again and return what `seat` saw: the mp:start message, every mp:update
 * and the mp:over result. complete is false if today's rules refuse a recorded move (a replay
 * from an older version of the game); it then stops there.
 */
async function replaySteps(rec, seat) {
    const { DuelState } = await engine;
    const st = new DuelState(rec.decks, rec.hideouts, rec.leaders, rec.first, rec.seed);
    st.start();
    // Snapshots (structuredClone): the view shares objects with the live state, which later moves change
    const view = () => structuredClone(forSeat(viewFor(st, seat), seat));
    const pack = (events) => ({
        matchId: 'replay', view: view(),
        events: structuredClone(forSeat(events.map(ev => statsFilter(filterEvent(ev, seat), seat)), seat)),
    });
    const start = { matchId: 'replay', mode: rec.mode, resync: false, replay: true,
        you: rec.profiles[seat], opponent: rec.profiles[other(seat)], view: view() };
    const updates = [pack(st.takeEvents())];
    let complete = true;
    for (const [s, a] of rec.actions) {
        if (!st.doAction(s, a)) {
            complete = false;
            break;
        }
        updates.push(pack(st.takeEvents()));
    }
    const end = rec.end || {};
    const over = { matchId: 'replay', reason: end.reason || 'morale', turns: end.turns || st.turn,
        result: !end.winner ? 'draw' : end.winner === seat ? 'win' : 'loss' };
    return { start, updates, over, complete, version: rec.version || '' };
}

module.exports = { createOnlineService, loadSetupFromDb, loadProfileFromDb, swapSides, viewFor, filterEvent, statsFilter, replaySteps };
