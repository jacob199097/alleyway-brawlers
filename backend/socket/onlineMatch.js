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
 *   client → server  mp:queue, mp:cancel, mp:challenge {targetPlayerId}, mp:accept {fromPlayerId},
 *                    mp:decline {fromPlayerId}, mp:action {matchId, action}, mp:concede {matchId},
 *                    mp:resync
 *   server → client  mp:queued, mp:cancelled, mp:error {message}, mp:challenge {fromPlayerId, fromUsername},
 *                    mp:declined {byUsername}, mp:start {matchId, you, opponent, view, resync},
 *                    mp:update {matchId, events, view}, mp:opponent {status, graceSecs?},
 *                    mp:over {matchId, result, reason, rewards}
 *
 * Every player sees the match from their own side: their seat is always "player".
 * Database access is passed in (createOnlineService), so tests can run it without Postgres.
 */

const { randomUUID } = require('crypto');

const TURN_SECS        = 90;    // a player who doesn't act for this long is auto-played
const RECONNECT_SECS   = 45;    // a disconnected player loses after this long
const CHALLENGE_SECS   = 60;

const engine = import('../../shared/duel/DuelState.js');

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
 */
function createOnlineService(io, deps) {
    const sockets = new Map();       // playerId → socket (latest connection)
    const queue = [];                // [{ playerId, setup, profile }]
    const matches = new Map();       // matchId → match
    const byPlayer = new Map();      // playerId → match
    const challenges = new Map();    // "from:to" → expiry

    const emitTo = (playerId, event, data) => sockets.get(playerId)?.emit(event, data);

    async function prepare(playerId) {
        const [setup, profile] = await Promise.all([deps.loadSetup(playerId), deps.loadProfile(playerId)]);
        if (setup.error) throw new Error(setup.error);
        return { playerId, setup, profile };
    }

    async function startMatch(a, b, mode) {
        const { DuelState } = await engine;
        const first = Math.random() < 0.5 ? 'player' : 'opponent';
        const state = new DuelState(
            { player: a.setup.deck, opponent: b.setup.deck },
            { player: a.setup.hideout, opponent: b.setup.hideout },
            { player: a.setup.leader, opponent: b.setup.leader },
            first,
        );
        const match = {
            id: randomUUID(), mode, state, startedAt: Date.now(), over: false, timer: null,
            seats: {
                player: { ...a, connected: true, grace: null, cardsPlayed: 0 },
                opponent: { ...b, connected: true, grace: null, cardsPlayed: 0 },
            },
        };
        matches.set(match.id, match);
        byPlayer.set(a.playerId, match);
        byPlayer.set(b.playerId, match);
        state.start();
        const events = state.takeEvents();
        for (const seat of ['player', 'opponent']) sendStart(match, seat, false);
        broadcast(match, events);
        console.log(`[Online] ${a.profile.username} vs ${b.profile.username} (${mode}) — ${match.id}`);
    }

    function profileOf(seat) {
        return { username: seat.profile.username, level: seat.profile.level, avatar_url: seat.profile.avatar_url };
    }

    function sendStart(match, seat, resync) {
        const s = match.seats[seat];
        emitTo(s.playerId, 'mp:start', {
            matchId: match.id, mode: match.mode, resync,
            you: profileOf(s), opponent: profileOf(match.seats[other(seat)]),
            view: forSeat(viewFor(match.state, seat), seat),
        });
    }

    function broadcast(match, events) {
        for (const seat of ['player', 'opponent']) {
            const visible = events.map(ev => statsFilter(filterEvent(ev, seat), seat));
            emitTo(match.seats[seat].playerId, 'mp:update', {
                matchId: match.id,
                events: forSeat(visible, seat),
                view: forSeat(viewFor(match.state, seat), seat),
            });
        }
        for (const ev of events) {
            if (['summon', 'set', 'hustle'].includes(ev.type)) match.seats[ev.side].cardsPlayed += 1;
        }
        if (match.state.winner) finish(match, match.state.winner, match.state.endReason || 'morale');
        else armTimer(match);
    }

    /** Whoever has to act next gets TURN_SECS; then the server plays a safe move for them. */
    function armTimer(match) {
        clearTimeout(match.timer);
        match.timer = setTimeout(() => autoPlay(match), TURN_SECS * 1000);
    }

    function autoPlay(match) {
        if (match.over) return;
        const st = match.state;
        const p = st.pending;
        const seat = p && p.side ? p.side : st.active;
        let action = { kind: 'next' };
        if (p && p.kind === 'choose') action = { kind: 'choose', option: p.options[0].id };
        else if (p && p.kind === 'discard') action = { kind: 'discard', uid: st.sides[seat].hand[0].uid };
        if (st.doAction(seat, action)) broadcast(match, st.takeEvents());
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
        try {
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
        console.log(`[Online] Match ${match.id} over (${reason}) — winner ${winner?.profile.username ?? 'none'}`);
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
            if (byPlayer.has(me)) return socket.emit('mp:error', { message: 'You are already in a match.' });
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
                startMatch(rival, entry, 'casual').catch(err => console.error('[Online] Start failed:', err));
            } else {
                queue.push(entry);
                socket.emit('mp:queued', { position: queue.length });
            }
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
            if (byPlayer.has(targetPlayerId)) return socket.emit('mp:error', { message: 'That player is in a match.' });
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
            if (byPlayer.has(me) || byPlayer.has(fromPlayerId)) return socket.emit('mp:error', { message: 'A player is already in a match.' });
            leaveQueue(me);
            leaveQueue(fromPlayerId);
            try {
                const [a, b] = await Promise.all([prepare(fromPlayerId), prepare(me)]);
                await startMatch(a, b, 'friendly');
            } catch (err) {
                socket.emit('mp:error', { message: err.message || 'Could not start the match.' });
                emitTo(fromPlayerId, 'mp:error', { message: err.message || 'Could not start the match.' });
            }
        });

        socket.on('mp:action', ({ matchId, action } = {}) => act(me, matchId, action));

        socket.on('mp:concede', ({ matchId } = {}) => {
            const match = byPlayer.get(me);
            if (!match || match.id !== matchId) return;
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            finish(match, other(seat), 'concede');
        });

        // A client (re)connecting mid-match asks for the board again
        socket.on('mp:resync', () => {
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
            const match = byPlayer.get(me);
            if (!match || match.over) return;
            const seat = match.seats.player.playerId === me ? 'player' : 'opponent';
            const s = match.seats[seat];
            s.connected = false;
            emitTo(match.seats[other(seat)].playerId, 'mp:opponent', { status: 'disconnected', graceSecs: RECONNECT_SECS });
            s.grace = setTimeout(() => finish(match, other(seat), 'disconnect'), RECONNECT_SECS * 1000);
        });
    }

    return { register, isInMatch: (playerId) => byPlayer.has(playerId), _matches: matches };
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

module.exports = { createOnlineService, loadSetupFromDb, loadProfileFromDb, swapSides, viewFor, filterEvent, statsFilter };
