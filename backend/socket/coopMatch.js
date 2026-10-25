'use strict';

/**
 * TURF DEFENSE: two players together against a boss, a clan's leader at full power played by the
 * server CPU (server-authoritative like onlineMatch.js). The rules are the shared engine with seats
 * p1, p2 and boss on two teams; shared/turf.js builds the boss's deck and rules from
 * godot/data/bosses.json (its Morale, extra draws and Authority, and the phases that fire as its
 * Morale drops).
 *
 * Quick match: a player queues for a boss level they've unlocked (coop:queue {boss, level}); the
 * first two waiting for the same one are paired. Everyone else online hears that someone is looking
 * (coop:looking), so the other player can jump in. Each player sees the match from their own seat:
 * theirs is "player", their partner "ally", the boss "boss". A player who goes out watches on while
 * their partner fights; both win when the boss's Morale is gone, both lose when both are out.
 * Rewards are paid at the end, to both (economy/turf.js).
 *
 *   client → server  coop:queue {boss, level}, coop:leave, coop:action {matchId, action},
 *                    coop:emote {matchId, key}, coop:concede {matchId}, coop:quit, coop:resync
 *   server → client  coop:queue {boss, level, since}, coop:left {reason}, coop:error {message}, coop:none,
 *                    coop:looking {username, boss, level, boss_name, level_name} (to everyone else),
 *                    coop:start {matchId, mode: 'coop', resync, boss: bossInfo, players: {player, ally, boss}, view, clock},
 *                    coop:update {matchId, events, view, clock, away}, coop:emote {matchId, key},
 *                    coop:over {matchId, won, rewards, achievements, mastery, turns, boss}
 */

const { randomUUID } = require('crypto');
const { viewFor, filterEvent, statsFilter } = require('./onlineMatch');
const { rename } = require('./ffaMatch');

const TURN_SECS   = 90;
const AWAY_SECS   = 15;
const AFK_FORFEIT = 8;
const RECONNECT_SECS = 45;
const BOT_MOVE_MS  = 450;
const BOT_EVENT_MS = 160;   // and this much more for each event its last move made (the players' screens animate them)
const BOT_MAX_MS   = 3200;
const LOOKING_GAP_MS = 60 * 1000;   // a player's "looking for a partner" news goes out at most this often
// Quick messages to your partner (no free text), at most one every EMOTE_GAP_MS and MAX_EMOTES a match
const EMOTES = ['boss', 'help', 'nice', 'tank', 'wait', 'thanks', 'go', 'gg'];
const EMOTE_GAP_MS = 2000;
const MAX_EMOTES = 60;

const engine = import('../../shared/duel/DuelState.js');
const cpu = import('../../shared/duel/DuelAI.js');
const turf = import('../../shared/turf.js');

/** Seat → what `viewer` calls it: their own "player", their partner "ally", the boss "boss". */
function namesFor(viewer) {
    return { p1: viewer === 'p1' ? 'player' : 'ally', p2: viewer === 'p2' ? 'player' : 'ally', boss: 'boss' };
}

/** An action as `seat` named things → the engine's seat names. */
function actionFrom(action, seat) {
    const back = Object.fromEntries(Object.entries(namesFor(seat)).map(([s, n]) => [n, s]));
    const a = { ...action };
    if (typeof a.foe === 'string') a.foe = back[a.foe] ?? a.foe;
    if (typeof a.option === 'string' && back[a.option]) a.option = back[a.option];
    return a;
}

/**
 * @param {object} deps
 * @param {(playerId) => Promise<{deck, hideout, leader, deckId}|{error}>} deps.loadSetup
 * @param {(playerId) => Promise<object>} deps.loadProfile
 * @param {(playerId) => Promise<object>} deps.loadClears   {bossId: {level: {clears}}} (economy/turf.js)
 * @param {(args) => Promise<object>} deps.resolveTurf      {playerId, bossId, level, won, turns} → rewards
 * @param {(playerId) => boolean} [deps.isBusyElsewhere]    in another match or queue
 * @param {(playerId) => void} [deps.leaveOtherQueue]
 * @param {(m) => Promise<Array>} [deps.recordMatch]        achievements
 * @param {(playerId, clan, outcome) => Promise} [deps.masteryProgress]
 * @param {(deckId, outcome) => Promise} [deps.recordDeck]
 * @param {(playerId, questId, amount) => Promise} [deps.incrementDailyQuest]
 * @param {number} [deps.turnSecs] [deps.awaySecs] [deps.reconnectSecs] [deps.botMoveMs] [deps.botEventMs]  (tests)
 */
function createCoopService(io, deps) {
    const sockets = new Map();
    const queues = new Map();         // "boss:level" → [entry] waiting (in the order they came)
    const queued = new Map();         // playerId → its queue key
    const byPlayer = new Map();       // playerId → match (until they leave it)
    const matches = new Map();
    const lastLooking = new Map();    // playerId → when their last coop:looking went out
    const emitTo = (id, ev, data) => sockets.get(id)?.emit(ev, data);
    const busy = (id) => queued.has(id) || byPlayer.has(id);
    const secs = (k, d) => deps[k] ?? d;

    function profileOf(e) {
        const p = e.profile || {};
        return { username: p.username, level: p.level, avatar_url: p.avatar_url, title: p.title || null,
            card_back: p.card_back || null, cpu: !!e.bot, boss: !!e.bot };
    }

    // ── Quick match ──
    function leaveQueue(playerId, reason = '') {
        const key = queued.get(playerId);
        if (!key) return;
        queued.delete(playerId);
        const q = (queues.get(key) || []).filter(e => e.playerId !== playerId);
        if (q.length) queues.set(key, q);
        else queues.delete(key);
        if (reason) emitTo(playerId, 'coop:left', { reason });
    }

    /** How many are waiting for each boss level ({"archon:1": 1}): the Turf Defense screen shows it. */
    function waiting() {
        return Object.fromEntries([...queues.entries()].map(([k, q]) => [k, q.length]));
    }

    async function queue(me, socket, bossId, level) {
        if (busy(me) || deps.isBusyElsewhere?.(me)) return socket.emit('coop:error', { message: 'You are already in a match.' });
        const { findBoss, bossLevel } = await turf;
        const boss = findBoss(String(bossId ?? ''));
        const lv = bossLevel(boss, level);
        if (!boss || !lv) return socket.emit('coop:error', { message: 'That boss isn\'t on the streets.' });
        let entry;
        try {
            const clears = await deps.loadClears(me);
            if (lv.level > 1 && !(clears?.[boss.id]?.[lv.level - 1]?.clears > 0)) {
                const before = bossLevel(boss, lv.level - 1);
                return socket.emit('coop:error', { message: `Beat ${boss.name} on ${before.name} first.` });
            }
            const [setup, profile] = await Promise.all([deps.loadSetup(me), deps.loadProfile(me)]);
            if (setup.error) throw new Error(setup.error);
            entry = { playerId: me, setup, profile, since: Date.now() };
        } catch (err) {
            return socket.emit('coop:error', { message: err.message || 'Could not load your deck.' });
        }
        if (busy(me) || deps.isBusyElsewhere?.(me)) return;
        deps.leaveOtherQueue?.(me);
        const key = `${boss.id}:${lv.level}`;
        const q = queues.get(key) || [];
        const partner = q.find(e => e.playerId !== me && sockets.get(e.playerId)?.connected !== false);
        if (partner) {
            leaveQueue(partner.playerId);
            startMatch(boss, lv, [partner, entry]).catch(err => {
                console.error('[Turf] Start failed:', err);
                for (const e of [partner, entry]) emitTo(e.playerId, 'coop:error', { message: 'The match could not start.' });
            });
            return;
        }
        q.push(entry);
        queues.set(key, q);
        queued.set(me, key);
        socket.emit('coop:queue', { boss: boss.id, level: lv.level, since: entry.since });
        // Everyone else online hears it (their game shows a "join them" pop-up)
        if (Date.now() - (lastLooking.get(me) || 0) > LOOKING_GAP_MS) {
            lastLooking.set(me, Date.now());
            for (const [id, s] of sockets) {
                if (id !== me && !busy(id) && !deps.isBusyElsewhere?.(id)) {
                    s.emit('coop:looking', { username: entry.profile?.username || 'A player', boss: boss.id, level: lv.level,
                        boss_name: boss.name, level_name: lv.name });
                }
            }
        }
    }

    // ── Match ──
    async function startMatch(boss, lv, players) {
        const { DuelState } = await engine;
        const { bossSetup, turfRules, bossInfo } = await turf;
        const b = bossSetup(boss, lv);
        const humans = Math.random() < 0.5 ? players : [players[1], players[0]];
        const entries = {
            p1: humans[0], p2: humans[1],
            boss: { playerId: `cpu:${randomUUID()}`, bot: true, level: lv.ai || 'normal', setup: b,
                profile: { username: boss.name, level: lv.level, avatar_url: 'cpu' } },
        };
        const seats = ['p1', 'p2', 'boss'];
        const pick = (k) => Object.fromEntries(seats.map(s => [s, entries[s].setup[k]]));
        const seed = 1 + Math.floor(Math.random() * 2147483646);
        const state = new DuelState(pick('deck'), pick('hideout'), pick('leader'), 'p1', seed, turfRules(boss, lv));
        const match = { id: randomUUID(), mode: 'coop', state, seats: {}, over: false, timer: null, startedAt: Date.now(),
            boss, lv, info: bossInfo(boss, lv) };
        for (const s of seats) {
            match.seats[s] = { ...entries[s], seat: s, connected: true, grace: null, idle: 0, kos: 0, promotes: 0, awakens: 0,
                cardsPlayed: 0, damage: 0, settled: null, watching: !entries[s].bot };
        }
        matches.set(match.id, match);
        for (const s of ['p1', 'p2']) byPlayer.set(entries[s].playerId, match);
        state.start();
        const events = state.takeEvents();
        for (const s of ['p1', 'p2']) sendStart(match, s, false);
        broadcast(match, events);
        console.log(`[Turf] ${humans.map(e => e.profile?.username).join(' + ')} vs ${boss.name} (${lv.name}) — ${match.id}`);
    }

    const seatOf = (match, playerId) => ['p1', 'p2'].find(s => match.seats[s].playerId === playerId);
    const partnerOf = (seat) => (seat === 'p1' ? 'p2' : 'p1');
    const toAct = (st) => (st.pending && st.pending.side ? st.pending.side : st.active);

    function viewOf(match, seat) {
        return rename(viewFor(match.state, seat), namesFor(seat));
    }

    function playersFor(match, seat) {
        const names = namesFor(seat);
        return Object.fromEntries(Object.keys(match.seats).map(s => [names[s], profileOf(match.seats[s])]));
    }

    function sendStart(match, seat, resync) {
        emitTo(match.seats[seat].playerId, 'coop:start', {
            matchId: match.id, mode: 'coop', resync, boss: match.info, players: playersFor(match, seat), view: viewOf(match, seat),
            arena: match.boss.arena,
            clock: Math.max(0, Math.round(((match.clockEnds || Date.now()) - Date.now()) / 1000)) || secs('turnSecs', TURN_SECS),
        });
    }

    function broadcast(match, events) {
        const st = match.state;
        match.lastEvents = events.length;
        for (const ev of events) {
            const s = match.seats[ev.side];
            if (!s) continue;
            if (['summon', 'set', 'hustle'].includes(ev.type)) s.cardsPlayed += 1;
            if (ev.type === 'promote') s.promotes += 1;
            if (ev.type === 'awaken') s.awakens += 1;
        }
        // A KO of the boss's characters counts for whoever was attacking at the time (the active player)
        for (const ev of events) if (ev.type === 'ko' && ev.side === 'boss' && match.seats[st.active] && st.active !== 'boss') match.seats[st.active].kos += 1;
        const clock = st.winner ? 0 : armTimer(match);
        const away = !st.winner && match.seats[toAct(st)].idle > 0;
        for (const seat of ['p1', 'p2']) {
            const s = match.seats[seat];
            if (!s.watching) continue;
            const names = namesFor(seat);
            emitTo(s.playerId, 'coop:update', {
                matchId: match.id, clock, away,
                events: rename(events.map(ev => statsFilter(filterEvent(ev, seat), seat)), names),
                view: rename(viewFor(st, seat), names),
            });
        }
        if (st.winner) finish(match);
    }

    function armTimer(match) {
        clearTimeout(match.timer);
        const s = match.seats[toAct(match.state)];
        if (s.bot) {
            // The boss moves at the pace the players' screens can show it
            const wait = Math.min(BOT_MAX_MS, secs('botMoveMs', BOT_MOVE_MS) + secs('botEventMs', BOT_EVENT_MS) * (match.lastEvents || 0));
            match.timer = setTimeout(() => botMove(match), wait);
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
        const action = choose(st, seat, match.seats[seat].level || 'normal');
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
        if (s.idle >= AFK_FORFEIT && !s.bot) {
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
        if (!match || match.id !== matchId || match.over) return emitTo(playerId, 'coop:error', { message: 'Match not found.' });
        const seat = seatOf(match, playerId);
        if (!action || typeof action !== 'object' || typeof action.kind !== 'string') {
            return emitTo(playerId, 'coop:error', { message: 'Invalid action.' });
        }
        const ok = match.state.doAction(seat, actionFrom(action, seat));
        if (!ok) {
            emitTo(playerId, 'coop:error', { message: 'That move is not allowed right now.' });
            return sendStart(match, seat, true);
        }
        match.seats[seat].idle = 0;
        broadcast(match, match.state.takeEvents());
    }

    /** A player's result (once): rewards, achievements, clan mastery. */
    async function settle(match, seat) {
        const s = match.seats[seat];
        if (s.settled) return s.settled;
        const st = match.state;
        const won = st.winner !== '' && st.winner !== 'boss';
        const outcome = won ? 'win' : 'loss';
        s.settled = { won, rewards: null, achievements: [], mastery: null };
        try {
            s.settled.rewards = await deps.resolveTurf({ playerId: s.playerId, bossId: match.boss.id, level: match.lv.level, won, turns: st.turn });
        } catch (err) {
            console.error('[Turf] Rewards failed:', err.message);
        }
        if (s.setup?.deckId) deps.recordDeck?.(s.setup.deckId, outcome)?.catch?.(() => {});
        if (s.cardsPlayed > 0) deps.incrementDailyQuest?.(s.playerId, 'daily_play_10', Math.min(40, s.cardsPlayed))?.catch?.(() => {});
        const clan = await deckClan(s.setup);
        s.settled.achievements = await deps.recordMatch?.({
            playerId: s.playerId, outcome, mode: 'cpu_coop', difficulty: null,
            clan, kos: s.kos, promotes: s.promotes, awakens: s.awakens, morale: st.sides[seat].morale,
        })?.catch?.(() => []) || [];
        s.settled.mastery = await deps.masteryProgress?.(s.playerId, clan, outcome)?.catch?.(() => null) ?? null;
        return s.settled;
    }

    async function finish(match) {
        if (match.over) return;
        match.over = true;
        clearTimeout(match.timer);
        for (const s of Object.values(match.seats)) clearTimeout(s.grace);
        matches.delete(match.id);
        for (const seat of ['p1', 'p2']) {
            const s = match.seats[seat];
            await settle(match, seat);
            if (byPlayer.get(s.playerId) === match) byPlayer.delete(s.playerId);
            if (s.watching) {
                emitTo(s.playerId, 'coop:over', { matchId: match.id, won: s.settled.won, boss: match.info,
                    players: playersFor(match, seat), rewards: s.settled.rewards, achievements: s.settled.achievements,
                    mastery: s.settled.mastery, turns: match.state.turn,
                    morale: { player: match.state.sides[seat].morale, ally: match.state.sides[partnerOf(seat)].morale, boss: match.state.sides.boss.morale } });
            }
        }
        console.log(`[Turf] Match ${match.id} over — ${match.state.winner === 'boss' ? match.boss.name : 'the crew'} won (turn ${match.state.turn})`);
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

        socket.on('coop:queue', ({ boss, level } = {}) => queue(me, socket, boss, level));

        socket.on('coop:leave', () => {
            leaveQueue(me);
            socket.emit('coop:left', { reason: '' });
        });

        socket.on('coop:action', ({ matchId, action } = {}) => act(me, matchId, action));

        socket.on('coop:emote', ({ matchId, key } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId || match.over || !EMOTES.includes(key)) return;
            const s = match.seats[seatOf(match, me)];
            const now = Date.now();
            if (now - (s.lastEmote || 0) < EMOTE_GAP_MS || (s.emotes || 0) >= MAX_EMOTES) return;
            s.lastEmote = now;
            s.emotes = (s.emotes || 0) + 1;
            emitTo(match.seats[partnerOf(seatOf(match, me))].playerId, 'coop:emote', { matchId, key });
        });

        socket.on('coop:concede', ({ matchId } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId) return;
            goOut(match, seatOf(match, me), 'concede');
        });

        // Leaving for good (out and done watching, or giving up): no more updates; the result still
        // comes when the match ends (rewards are paid either way)
        socket.on('coop:quit', () => {
            const match = byPlayer.get(me);
            if (!match) return;
            const seat = seatOf(match, me);
            match.seats[seat].watching = false;
            if (!match.over && !match.state.sides[seat].out) goOut(match, seat, 'concede');
            byPlayer.delete(me);
        });

        socket.on('coop:resync', () => {
            const key = queued.get(me);
            if (key) {
                const [boss, level] = key.split(':');
                const e = (queues.get(key) || []).find(x => x.playerId === me);
                return socket.emit('coop:queue', { boss, level: Number(level), since: e?.since || Date.now() });
            }
            const match = byPlayer.get(me);
            if (!match || match.over) return socket.emit('coop:none', {});
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
            leaveQueue(me);
            const match = byPlayer.get(me);
            if (!match || match.over) return;
            const seat = seatOf(match, me);
            const s = match.seats[seat];
            s.connected = false;
            if (match.state.sides[seat].out) return;
            s.grace = setTimeout(() => goOut(match, seat, 'disconnect'), secs('reconnectSecs', RECONNECT_SECS) * 1000);
        });
    }

    return { register, isBusy: busy, leaveQueue, waiting, _matches: matches };
}

/** The clan most of a deck's cards belong to (achievements and clan mastery). */
async function deckClan(setup) {
    const { getCard } = await engine;
    const count = {};
    for (const spec of setup?.deck || []) {
        const clan = getCard(typeof spec === 'object' ? spec.id : spec)?.clan;
        if (clan) count[clan] = (count[clan] || 0) + 1;
    }
    return Object.keys(count).sort((a, b) => count[b] - count[a])[0] || null;
}

module.exports = { createCoopService, namesFor, actionFrom, EMOTES };
