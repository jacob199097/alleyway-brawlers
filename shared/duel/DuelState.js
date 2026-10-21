/**
 * DUEL STATE — the duel rules, run by the server for online matches.
 *
 * A line-by-line port of godot/scripts/duel/duel_state.gd (which runs CPU duels in the Godot
 * client). Keep the two in step: shared/duel/engine.test.mjs replays games recorded from the
 * Godot rules and checks this engine produces exactly the same events.
 *
 * Players act through doAction(side, action) with plain objects, e.g.
 *   { kind: 'summon', uid: 12, slot: 2, position: 'atk' }
 * Every change is recorded as an event (takeEvents()). Effects that say "you may"/"choose"
 * pause with `pending`, answered by { kind: 'choose', option } or { kind: 'discard', uid }.
 *
 * Free-for-all (FFA): pass 3-4 decks (seats in turn order, e.g. p1..p4) instead of player and
 * opponent. Every opponent is an enemy: attacks name the opponent they go at ({kind: 'attack', from,
 * target, foe}), effects on "an enemy" can pick any opponent's card, "enemies" hit them all, and an
 * effect on "your opponent" (discard, mill, Morale damage, face-down cards) hits the one being fought
 * (in a brawl) or the one its player chooses. A player at 0 Morale (or decked out) is out (their place
 * in `places`); their cards leave at the end of the action and the last one standing wins. Durations
 * that run "through the next turn" last a full round. With two players everything is as before.
 */

import { CARD_CATALOG } from '../cards.js';

export const START_MORALE = 6000;
export const MAX_AUTHORITY = 15;
export const HAND_LIMIT = 9;
export const OPENING_HAND = 5;
export const SECOND_PLAYER_AUTHORITY = 1; // going second: extra Authority on your first turn only
export const LEADER_DEFEAT_PENALTY = 0;   // Morale lost when a Dormant leader is defeated (none: it was never on the field)
export const FRONT = [0, 1, 2, 3, 4];
export const BACK = [5, 6, 7, 8, 9];
export const DIRECT = -1;
const NO_SLOT = -10;
const DORMANT_GIFTS = ['pierce', 'immune', 'untargetable'];   // passives a Dormant leader can give your characters   // effects of a card that isn't on the field (a Hustle, a sprung Ambush)
// Ambushes with hand-written rules; any other Ambush with effects is a Card Forge Ambush (_springFx)
const HAND_AMBUSHES = ['no_witnesses_ambush', 'lion_ambush', 'kings_test'];
// What an "immune" passive keeps off a card
const IMMUNE_TO = ['poison', 'burn', 'bleed', 'shock', 'freeze', 'stasis', 'stun', 'suppress'];
export const LEADER = -2;

// ── Card data ──────────────────────────────────────────────────────────────

export function getCard(id) {
    return CARD_CATALOG[id] ? structuredClone(CARD_CATALOG[id]) : {};
}

/** The form a card promotes into: promotesTo, or the next `_lvN` card (Hunter). */
export function nextForm(id) {
    const card = CARD_CATALOG[id];
    if (card && typeof card.promotesTo === 'string') return card.promotesTo;
    const m = /^(.*_lv)(\d)$/.exec(id);
    if (m) {
        const guess = `${m[1]}${Number(m[2]) + 1}`;
        if (CARD_CATALOG[guess]) return guess;
    }
    return '';
}

const clone = (o) => structuredClone(o);
const isEmpty = (o) => !o || Object.keys(o).length === 0;
const toInt = (v) => Math.trunc(Number(v ?? 0)) || 0;
// Keyword statuses (Card Forge effects); same rules as duel_state.gd
const FOREVER = 1000000;
const STATUS_TICKS = 3;
const STATUS_KEYS = ['poison', 'burn', 'bleed', 'freeze_until', 'stasis_until', 'silence_until', 'suppress_until', 'bounty'];

export function other(side) {
    return side === 'player' ? 'opponent' : 'player';
}

export function isLion(c) {
    return c != null && c.clanTag === 'lion';
}

function attackValue(c) {
    return toInt(c.attack) + (c.downed ? 0 : 1);
}

/** Strongest first; ties go to the lower lane (same order as the Godot engine). */
function signed(v) {
    return (v > 0 ? '+' : '') + String(v);
}

function statText(mod) {
    const parts = [];
    if (toInt(mod.atk) !== 0) parts.push(`${signed(toInt(mod.atk))} ATK`);
    if (toInt(mod.def) !== 0) parts.push(`${signed(toInt(mod.def))} DEF`);
    return parts.length ? parts.join(' / ') : 'no change';
}

function strongestFirst(a, b) {
    const va = attackValue(a.card);
    const vb = attackValue(b.card);
    if (va !== vb) return vb - va;
    return a.slot - b.slot;
}

/** Cards of a condition's clan (if_clan; '' = any) */
function ofIfClan(cards, e) {
    const clan = String(e.if_clan ?? '');
    return cards.filter(x => clan === '' || x.clanTag === clan);
}

/** if_done ("If you do, ..."): an effect that follows on from the one before it becomes that
 *  effect's then (see _doFx), so it happens only if the one before did something. */
function foldIfDone(list) {
    if (!list.some(e => e && e.if_done)) return list;
    const out = [];
    for (const e of list) {
        if (e && typeof e === 'object' && e.if_done && out.length && out[out.length - 1] && typeof out[out.length - 1] === 'object') {
            let p = out[out.length - 1] = { ...out[out.length - 1] };
            while (p.then) p = p.then = { ...p.then };
            p.then = e;
        } else {
            out.push(e);
        }
    }
    return out;
}

export class DuelState {
    /**
     * @param {{player: Array, opponent: Array}} decks     card ids or {id, ...server stats}
     * @param {{player?: Array, opponent?: Array}} hideouts
     * @param {{player?: string, opponent?: string}} leaders
     * @param {string} first   'player' | 'opponent'
     * @param {number} seed    -1 keeps the given deck order (tests); otherwise decks are shuffled,
     *                         repeatably when seed > 0 (the server records it for replays)
     */
    // rules: a challenge's twist (shared/challenges.js): start_authority, start_morale,
    // opening_hand, pierce (every attack pierces). Same as duel_state.gd.
    constructor(decks, hideouts = {}, leaders = {}, first = 'player', seed = 0, rules = {}) {
        this.rules = { ...(rules || {}) };
        // Turn order: player, opponent; FFA seats by name (p1, p2, ...), whatever order they come in
        const keys = Object.keys(decks);
        this.seats = keys.length === 2 && keys.includes('player') ? ['player', 'opponent'] : [...keys].sort();
        this.ffa = this.seats.length > 2;
        this.first = first;
        this.places = {};                  // FFA: side -> finishing place (1 = the winner)
        this._rand = seed > 0 ? seededRandom(seed) : Math.random;
        // Luck (coin flips, die rolls) has its own generator, the same in duel_state.gd: from the
        // match's seed (replays repeat), fixed for seed -1 (tests compare engines), else random
        this._luck = seededRandom(seed > 0 ? (seed ^ LUCK_SALT) >>> 0 : seed === -1 ? LUCK_TEST_SEED : Math.floor(Math.random() * 4294967296));
        this._luckLast = null;   // the last flip or roll: {won, value} (if_luck follows it)
        this._luckWait = null;   // a DOUBLE OR NOTHING not yet decided: {uid, ask} (its "If tails" waits for it)
        this._roll = 1;          // the last die's value ("for each pip")
        this.turn = 1;
        this.active = first;
        this.phase = 'upkeep';
        this.winner = '';
        this.endReason = ''; // how the game ended: 'morale' or 'deck_out'
        this.pending = {};
        this._did = 0;
        this._attackCtx = null;
        this.sides = {};
        this._events = [];
        this._uid = 0;
        this._asks = [];
        this._inAnswer = false;
        this._newAsks = [];
        this._fixedOrder = seed === -1; // never shuffle (tests compare engines)
        for (const side of this.seats) {
            const deck = decks[side].map(spec => this.makeCard(spec));
            if (seed !== -1) shuffle(deck, this._rand);
            const hideout = (hideouts[side] || []).map(spec => this.makeCard(spec));
            const field = Array(10).fill(null);
            const leaderId = leaders[side] || '';
            const leader = leaderId !== '' ? this.makeCard(leaderId) : null;
            if (leader) leader.influence = leader.influence != null ? toInt(leader.influence) : leader.base_defense;   // (Forge leaders set it; else DEF)
            if (leader) leader.influence_max = leader.influence;
            this.sides[side] = {
                morale: toInt(this.rules.start_morale) || START_MORALE,
                authority: toInt(this.rules.start_authority) || 1, authority_max: toInt(this.rules.start_authority) || 1,
                deck, hand: [], field, gutter: [], hideout,
                leader, leader_state: leader ? 'dormant' : 'none',
                brutus_bonus: 0, promoted: {}, mentor_used: false, turns: 0,
            };
        }
    }

    makeCard(spec) {
        const id = typeof spec === 'object' && spec ? String(spec.id) : String(spec);
        const c = getCard(id);
        if (typeof spec === 'object' && spec) {
            for (const key of Object.keys(spec)) if (key !== 'id') c[key] = spec[key];
        }
        this._uid += 1;
        c.uid = this._uid;
        c.id = id;
        for (const key of ['authority', 'level', 'rarity']) c[key] = toInt(c[key]);
        c.base_attack = toInt(c.attack);
        c.base_defense = toInt(c.defense);
        c.attack = c.base_attack;
        c.defense = c.base_defense;
        c.position = 'atk';
        c.face_down = false;
        c.downed = false;
        c.has_attacked = false;
        c.deployed_turn = 0;
        if (c.effectKey == null) c.effectKey = ''; // Card Forge cards may have no hand-written effect
        c.mods = [];
        return c;
    }

    takeEvents() {
        const out = this._events;
        this._events = [];
        return out;
    }

    // ── Queries ────────────────────────────────────────────────────────────

    cardAt(side, slot) {
        return this.sides[side].field[slot];
    }

    characters(side) {
        const out = [];
        for (const slot of FRONT) {
            const c = this.sides[side].field[slot];
            if (c != null) out.push({ slot, card: c });
        }
        return out;
    }

    lionCount(side) {
        return this.characters(side).filter(e => isLion(e.card)).length;
    }

    leaderDormant(side) {
        return this.sides[side].leader_state === 'dormant';
    }

    canAct(side) {
        return this.winner === '' && isEmpty(this.pending) && side === this.active && !this.sides[side]?.out;
    }

    // ── Seats (two players, or FFA) ────────────────────────────────────────

    /** The opponents still in, in turn order after side (two players: just the other one). */
    foesOf(side) {
        const i = this.seats.indexOf(side);
        const out = [];
        for (let k = 1; k < this.seats.length; k++) {
            const s = this.seats[(i + k) % this.seats.length];
            if (!this.sides[s].out) out.push(s);
        }
        return out;
    }

    _alive() {
        return this.seats.filter(s => !this.sides[s].out);
    }

    /** The next seat still in after side. */
    _nextSeat(side) {
        const i = this.seats.indexOf(side);
        for (let k = 1; k <= this.seats.length; k++) {
            const s = this.seats[(i + k) % this.seats.length];
            if (!this.sides[s].out) return s;
        }
        return side;
    }

    /** Every seat, starting with this one. */
    _order(start) {
        const i = this.seats.indexOf(start);
        return this.seats.map((_, k) => this.seats[(i + k) % this.seats.length]);
    }

    /** How many more turns until the next turn of everyone else has passed (two players: 1). */
    _roundSpan() {
        return Math.max(1, this._alive().length - 1);
    }

    /** The opponent an effect on "your opponent" hits: in a brawl, the other side of it; otherwise
     *  the only one, or the one its player chooses (lowest Morale first). ok: which can be hit at all. */
    _withFoe(side, c, vs, ok, fn) {
        const foes = this.foesOf(side).filter(ok);
        if (!foes.length) return;
        const ctx = this._attackCtx;
        let fixed = null;
        if (vs && vs.side && vs.side !== side && foes.includes(vs.side)) fixed = vs.side;
        else if (ctx && ctx.side === side && foes.includes(ctx.foe)) fixed = ctx.foe;
        else if (ctx && ctx.foe === side && foes.includes(ctx.side)) fixed = ctx.side;
        else if (foes.length === 1) fixed = foes[0];
        if (fixed != null) {
            fn(fixed);
            return;
        }
        const order = [...foes].sort((a, b) => (this.sides[a].morale - this.sides[b].morale) || (this.seats.indexOf(a) - this.seats.indexOf(b)));
        this._ask(side, 'foe', `${c.name}: choose an opponent`, c, order.map(x => ({ id: x, label: x, side: x })), (x) => {
            if (this.sides[x] && !this.sides[x].out) fn(x);
        });
    }

    canDeployNow(side) {
        return this.canAct(side) && ['deployment', 'regroup'].includes(this.phase);
    }

    // Character classes: only Strivers PROMOTE; Heavies need some of your characters sacrificed
    // (tributeCost of them, 1-3; the Heavy takes one of their lanes). Same rules as duel_state.gd.
    static needsTribute(c) {
        return c != null && c.subtype === 'heavy';
    }

    /** How many characters a Heavy sacrifices (0: not a Heavy). */
    static tributesFor(c) {
        if (!DuelState.needsTribute(c)) return 0;
        return Math.min(3, Math.max(1, toInt(c.tributeCost ?? 1) || 1));
    }

    /** tribute: a slot (-1 none) or a list of slots. */
    static tributeList(tribute) {
        if (Array.isArray(tribute)) return tribute.map(toInt);
        const t = toInt(tribute ?? -1);
        return t >= 0 ? [t] : [];
    }

    /** One of your characters a deploy can send to the Gutter (a Heavy's sacrifice, or one deployed over). */
    canSacrifice(side, slot) {
        const t = FRONT.includes(slot) ? this.cardAt(side, slot) : null;
        return t != null && t.cardType !== 'leader' && !this.inStasis(t);
    }

    // Summon c into slot. A Heavy names the characters it sacrifices (tribute: their slots; it takes
    // one of their lanes). Anything else goes in an empty lane, or over one of your characters
    // (tribute: that slot), which goes to the Gutter.
    canSummon(side, c, slot, tribute = -1) {
        if (!this.canDeployNow(side) || c.cardType !== 'gang_member') return false;
        if (!FRONT.includes(slot) || this.sides[side].authority < this.costOf(side, c)) return false;
        const list = DuelState.tributeList(tribute);
        if (new Set(list).size !== list.length || !list.every(t => this.canSacrifice(side, t))) return false;
        if (DuelState.needsTribute(c)) return list.length === DuelState.tributesFor(c) && list.includes(slot);
        if (!list.length) return this.sides[side].field[slot] == null;
        return list.length === 1 && list[0] === slot;
    }

    canSummonSomewhere(side, c) {
        const n = DuelState.tributesFor(c);
        const fodder = FRONT.filter(t => this.canSacrifice(side, t));
        if (n > 0) return fodder.length >= n && this.canSummon(side, c, fodder[0], fodder.slice(0, n));
        return FRONT.some(slot => this.canSummon(side, c, slot) || this.canSummon(side, c, slot, slot));
    }

    // ── Continuous / Equip (same as duel_state.gd) ─────────────────────────
    static isLasting(c) {
        return !!c && ['hustle', 'ambush'].includes(String(c.cardType ?? '')) && ['continuous', 'equip'].includes(String(c.subtype ?? ''));
    }

    _lasting(side, sub = '') {
        const out = [];
        for (const b of BACK) {
            const c = this.sides[side].field[b];
            if (c != null && !c.face_down && DuelState.isLasting(c) && (sub === '' || String(c.subtype) === sub)) out.push({ slot: b, card: c });
        }
        return out;
    }

    _emptyBack(side) {
        const b = BACK.find(x => this.sides[side].field[x] == null);
        return b == null ? -1 : b;
    }

    _runLasting(side, when, def = null, vs = {}) {
        for (const x of this._lasting(side, 'continuous')) {
            if (this.winner !== '') return;
            if (this.sides[side].field[x.slot] === x.card && x.card !== def) this._runFx(side, x.slot, x.card, when, def, vs);
        }
    }

    _equipsOn(c) {
        const out = [];
        if (!c || c.uid == null) return out;
        for (const side of Object.keys(this.sides)) {
            for (const x of this._lasting(side, 'equip')) {
                if (toInt(x.card.equipped_to ?? -1) === toInt(c.uid)) out.push({ side, slot: x.slot, card: x.card });
            }
        }
        return out;
    }

    _equipTargets(side, c) {
        const out = [];
        for (const on of String(c.equip_to ?? 'ally') === 'enemy' ? this.foesOf(side) : [side]) {
            for (const x of this.characters(on)) {
                if (!this.inStasis(x.card) && (on === side || isEmpty(this._passive(on, x.slot, x.card, 'untargetable')))) out.push({ side: on, slot: x.slot, card: x.card });
            }
        }
        return out;
    }

    _sweepEquips() {
        for (const side of Object.keys(this.sides)) {
            for (const x of this._lasting(side, 'equip')) {
                const to = toInt(x.card.equipped_to ?? -1);
                if (to < 0) continue;
                let on = false;
                for (const s2 of Object.keys(this.sides)) for (const y of this.characters(s2)) if (toInt(y.card.uid) === to) on = true;
                if (!on) {
                    this.sides[side].field[x.slot] = null;
                    delete x.card.equipped_to;
                    this.sides[side].gutter.push(x.card);
                    this._emit('ko', { side, slot: x.slot, card: clone(x.card) });
                }
            }
        }
    }

    // Ambushes and Hustles are set face-down in the back row. An Ambush is paid for when it's set;
    // a Hustle when it's activated, any time on your turn (setHustleSlot, canHustle).
    canSet(side, c, slot) {
        if (!this.canDeployNow(side) || !['ambush', 'hustle'].includes(c.cardType)) return false;
        if (!BACK.includes(slot) || this.sides[side].field[slot] != null) return false;
        return c.cardType === 'hustle' || this.sides[side].authority >= this.costOf(side, c);
    }

    /** The back-row slot of c if it's a Hustle set face-down there (-1: it isn't). */
    setHustleSlot(side, c) {
        if (c == null || c.cardType !== 'hustle' || !c.face_down) return -1;
        const b = BACK.find(x => this.sides[side].field[x] === c);
        return b == null ? -1 : b;
    }

    hustleReady(side, c) {
        switch (c.effectKey || '') {
            case 'lion_rescue': return this._downedLions(side).length > 0;
            case 'blood_scent': return this._promotableStrivers(side).length > 0;
        }
        return true;
    }

    canHustle(side, c) {
        // One set in the back row: in any phase you act in (the turn it was set too)
        const set = this.setHustleSlot(side, c);
        const now = set >= 0 ? this.canAct(side) && ['deployment', 'brawl', 'regroup'].includes(this.phase) : this.canDeployNow(side);
        if (!(now && c.cardType === 'hustle' && this.sides[side].authority >= this.costOf(side, c) && this.hustleReady(side, c))) return false;
        if (DuelState.isLasting(c)) return (set >= 0 || this._emptyBack(side) >= 0) && (String(c.subtype) !== 'equip' || this._equipTargets(side, c).length > 0);
        return this.cardCan(side, NO_SLOT, c, '*');
    }

    /** Whether any of card c's effects for a trigger would do something now (same as card_can). */
    cardCan(side, slot, c, when, vs = {}, def = null) {
        const list = this._fx(c, when);
        if (!list.length) return !(c.effects || []).length;
        return list.some(e => this.fxCan(side, slot, c, e, vs, def));
    }

    /** Whether effect e of card c would do anything now (same as fx_can in duel_state.gd). */
    fxCan(side, slot, c, e, vs = {}, def = null) {
        if (!this._fxCond(side, slot, e, def)) return false;
        if (String(e.per ?? '') !== '' && this._perCount(side, slot, e) <= 0) return false;
        const s = this.sides[side];
        const foes = this.foesOf(side).map(x => this.sides[x]);
        const mine = (x) => x !== c && this._fxKindOk(x, e);
        switch (String(e.do ?? '')) {
            case 'draw': case 'loot': return s.deck.length > 0;
            case 'search': return s.deck.some(mine);
            case 'recover': return s.gutter.some(mine);
            case 'revive': return this._emptyLane(side) >= 0 && s.gutter.some(mine);
            case 'call': return this._emptyLane(side) >= 0 && s.deck.some(mine);
            case 'token': return this._emptyLane(side) >= 0 && !!CARD_CATALOG[String(e.token ?? '')];
            case 'discard': return foes.some(x => x.hand.length > 0);
            case 'mill': return foes.some(x => x.deck.length > 0);
            case 'heal': return s.morale < START_MORALE;
            case 'break_ambush': return foes.some(x => BACK.some(b => x.field[b] != null && x.field[b].face_down));
            case 'shatter': return foes.some(x => BACK.some(b => x.field[b] != null && !x.field[b].face_down));
            case 'wreck': return foes.some(x => BACK.some(b => x.field[b] != null));
            case 'influence': {
                const l = s.leader;
                return s.leader_state === 'dormant' && l != null && toInt(l.influence) < toInt(l.influence_max ?? l.influence);
            }
            case 'ramp': return s.authority_max < MAX_AUTHORITY;
            case 'jam': return foes.some(x => BACK.some(b => x.field[b] != null && x.field[b].cardType === 'ambush'));
            case 'barricade': return true;
            case 'attack_again': return this.cardAt(side, slot) === c && !!c.has_attacked && toInt(c.again_turn ?? 0) !== this.turn;
        }
        if (!('target' in e)) return true;
        const pool = { down: 'standing', stand: 'downed', force_def: 'attackers', force_atk: 'defenders', ready: 'spent', cleanse: 'statused', rewind: 'changed' }[String(e.do ?? '')] ?? 'any';
        let entries = this._fxTargets(side, slot, c, e, vs, pool);
        if (String(e.target ?? '') === 'enemy') entries = entries.filter(x => isEmpty(this._passive(x.side, x.slot, x.card, 'untargetable')));
        return entries.length > 0;
    }

    /** What a card in hand costs to play: its Authority, less any "cost_down" passives on the field. */
    costOf(side, c) {
        let off = 0;
        const s = this.sides[side];
        const add = (slot, src, when = 'passive') => {
            for (const e of this._fx(src, when)) {
                if (String(e.do ?? '') !== 'cost_down' || !this._fxCond(side, slot, e, null)) continue;
                if (String(e.clan ?? '') !== '' && c.clanTag !== String(e.clan)) continue;
                off += Math.max(1, toInt(e.amount ?? 1));
            }
        };
        for (const x of this.characters(side)) if (!x.card.face_down) add(x.slot, x.card);
        for (const x of this._lasting(side, 'continuous')) add(x.slot, x.card);
        if (s.leader_state === 'dormant' && s.leader != null) add(-1, s.leader, 'dormant');
        return Math.max(0, toInt(c.authority) - off);
    }

    /** A Card Forge passive of this kind that's switched on for the card in this slot (or null). */
    _passive(side, slot, c, kind, ok = null) {
        if (c == null || c.face_down) return null;
        for (const e of this._fx(c, 'passive')) {
            if (String(e.do ?? '') === kind && (ok == null || ok(e)) && this._fxCond(side, slot, e, null)) return e;
        }
        // A Dormant leader can give your characters PIERCE, immunity or "can't be targeted"
        const s = this.sides[side];
        if (DORMANT_GIFTS.includes(kind) && s && s.leader_state === 'dormant' && s.leader != null && s.leader !== c) {
            for (const e of this._fx(s.leader, 'dormant')) {
                if (String(e.do ?? '') === kind && (ok == null || ok(e)) && (String(e.clan ?? '') === '' || c.clanTag === String(e.clan))
                    && this._fxCond(side, -1, e, null)) return e;
            }
        }
        // Continuous cards give your characters the same gifts; an Equip gives its character any passive
        if (s && DORMANT_GIFTS.includes(kind)) {
            for (const x of this._lasting(side, 'continuous')) {
                for (const e of this._fx(x.card, 'passive')) {
                    if (String(e.do ?? '') === kind && (ok == null || ok(e)) && (String(e.clan ?? '') === '' || c.clanTag === String(e.clan))
                        && this._fxCond(side, x.slot, e, null)) return e;
                }
            }
        }
        for (const q of this._equipsOn(c)) {
            for (const e of this._fx(q.card, 'passive')) {
                if (String(e.do ?? '') === kind && (ok == null || ok(e)) && this._fxCond(q.side, q.slot, e, null)) return e;
            }
        }
        return null;
    }

    /** A Dormant leader's triggered effects ("While Dormant, at the start of your turn: ..."). */
    _leaderFx(side, when, def = null) {
        const s = this.sides[side];
        if (s.leader_state === 'dormant' && s.leader != null && this.winner === '') this._runFx(side, -1, s.leader, when, def);
    }

    /** "no_down": this card can't be Downed while its owner controls another character. */
    _staysUp(side, slot, c) {
        return this._passive(side, slot, c, 'no_down') != null && this.characters(side).length > 1;
    }

    inStasis(c) { return c != null && toInt(c.stasis_until ?? 0) >= this.turn; }

    frozen(c) { return c != null && toInt(c.freeze_until ?? 0) >= this.turn; }

    statuses(c) {
        const out = ['poison', 'burn', 'bleed'].filter(k => c[k] !== undefined);
        if (this.frozen(c)) out.push('freeze');
        if (this.inStasis(c)) out.push('stasis');
        if (toInt(c.stun_until ?? 0) >= this.turn) out.push('stun');
        if (toInt(c.suppress_until ?? 0) >= this.turn) out.push('suppress');
        if (c.shield) out.push('shield');
        if (toInt(c.silence_until ?? 0) >= this.turn) out.push('silence');
        if (c.bounty) out.push('bounty');
        if (this._equipsOn(c).length) out.push('equipped');
        // Just promoted or Awakened: it can't attack this turn
        if (toInt(c.rest_turn ?? -1) === this.turn && c.has_attacked && !c.downed) out.push('resting');
        return out;
    }

    /** No attacks yet: until everyone has had a turn (turn 1; a free-for-all's whole first round).
     *  Same as no_attacks_yet in duel_state.gd. */
    noAttacksYet() {
        return this.turn <= (this.ffa ? this.seats.length : 1);
    }

    canAttackWith(side, slot) {
        if (!this.canAct(side) || this.phase !== 'brawl' || this.noAttacksYet() || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        return c != null && c.position === 'atk' && !c.downed && !c.has_attacked && !c.face_down
            && toInt(c.stun_until ?? 0) < this.turn && toInt(c.suppress_until ?? 0) < this.turn && !this.frozen(c) && !this.inStasis(c);
    }

    // Any enemy character; DIRECT when none is still standing (empty row or only Downed);
    // the enemy LEADER whenever it is dormant. foe: which opponent (FFA; default: the first one)
    attackTargets(side, foe = null) {
        foe = foe ?? this.foesOf(side)[0];
        if (foe == null || foe === side || !this.sides[foe] || this.sides[foe].out) return [];
        const foes = this.characters(foe).filter(e => !this.inStasis(e.card));
        // Elusive characters can't be attacked while their owner has another character that can be
        const open = foes.filter(e => !this._passive(foe, e.slot, e.card, 'elusive'));
        const pool = open.length ? open : foes;
        // A standing Guard must be attacked first
        const guards = pool.filter(e => !e.card.downed && this._passive(foe, e.slot, e.card, 'guard'));
        if (guards.length) return guards.map(e => e.slot);
        const targets = pool.map(e => e.slot);
        if (!foes.some(e => !e.card.downed)) targets.push(DIRECT);
        if (this.leaderDormant(foe)) targets.push(LEADER);
        return targets;
    }

    canChangePosition(side, slot) {
        if (!this.canDeployNow(side) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        return c != null && !c.downed && !c.has_attacked && !this.frozen(c) && !this.inStasis(c)
            && c.deployed_turn !== this.turn && (c.position_turn ?? 0) !== this.turn;
    }

    canPromote(side, slot) {
        if (!this.canDeployNow(side) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        if (c == null || c.ability !== 'maya_promote' || c.face_down || c.downed || c.subtype !== 'striver' || this.inStasis(c)) return false;
        if (this.sides[side].promoted[slot] || nextForm(c.id) === '') return false;
        return this.characters(side).some(e => e.slot !== slot && isLion(e.card) && e.card.authority >= c.authority);
    }

    canUseAbility(side, slot) {
        if (!this.canAct(side) || !['deployment', 'brawl', 'regroup'].includes(this.phase) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        if (c == null || c.ability !== 'maya_buff' || c.face_down || c.downed || this.inStasis(c)) return false;
        if ((c.ability_turn ?? 0) === this.turn) return false;
        return this.characters(side).some(e => e.slot !== slot && isLion(e.card));
    }

    // Activated abilities (Card Forge "When: Activate"): used from the card during your own turn, once
    // per turn each, paying the cost first. Which ones can be used now: 1 for the first "activate" effect, ...
    //   cost: '' | authority | morale | discard | sacrifice | exhaust; cost_n: how much
    activations(side, slot) {
        const out = [];
        if (!this.canAct(side) || !['deployment', 'brawl', 'regroup'].includes(this.phase) || !FRONT.includes(slot)) return out;
        const c = this.cardAt(side, slot);
        if (c == null || c.face_down) return out;
        if ((c.evolved_turn ?? -1) === this.turn) return out;   // a Striver that evolved this turn waits a turn
        let k = 0;
        for (const e of this._fx(c, 'activate')) {
            k++;
            if (((c.fx_used ?? {})['activate' + k] ?? -1) !== this.turn && this.fxCan(side, slot, c, e)
                && this._canPay(side, slot, c, e)) out.push(k);
        }
        return out;
    }

    _canPay(side, slot, c, e) {
        const s = this.sides[side];
        const n = Math.max(1, toInt(e.cost_n ?? 1));
        switch (String(e.cost ?? '')) {
            case 'authority': return s.authority >= n;
            case 'morale': return s.morale > n;
            case 'discard': return s.hand.length >= n;
            case 'sacrifice': return this.characters(side).some(x => x.slot !== slot);
            case 'exhaust': return !c.has_attacked && !c.downed;
        }
        return true;
    }

    _activate(side, slot, k) {
        if (!this.activations(side, slot).includes(k)) return false;
        const c = this.cardAt(side, slot);
        const e = this._fx(c, 'activate')[k - 1];
        c.fx_used = { ...(c.fx_used ?? {}), ['activate' + k]: this.turn };
        const go = () => this._doFx(side, slot, c, e);
        const n = Math.max(1, toInt(e.cost_n ?? 1));
        switch (String(e.cost ?? '')) {
            case 'authority':
                this._spend(side, n);
                this._effect(side, c, `${c.name}: pays ${n} Authority to activate`, slot);
                go();
                break;
            case 'morale':
                this._effect(side, c, `${c.name}: pays ${n} Morale to activate`, slot);
                this._damage(side, n, true);
                if (this.winner === '') go();
                break;
            case 'discard':
                this._effect(side, c, `${c.name}: discard ${n} to activate`, slot);
                this._askDiscard(side, n, go, `${c.name}: discard to activate`);
                break;
            case 'sacrifice': {
                const allies = this.characters(side).filter(x => x.slot !== slot).map(x => ({ side, slot: x.slot, card: x.card }));
                allies.sort((a, b) => attackValue(a.card) - attackValue(b.card) || a.slot - b.slot);
                this._askTarget(side, 'sacrifice', `${c.name}: choose a character to sacrifice`, c, allies, side, (x) => {
                    const name = x.card.name;
                    this._ko(side, x.slot);
                    this._effect(side, c, `${c.name} sacrifices ${name}`, slot);
                    if (this.winner === '') go();
                });
                break;
            }
            case 'exhaust':
                c.has_attacked = true;
                this._effect(side, c, `${c.name} activates: it can't attack this turn`, slot);
                go();
                break;
            default:
                this._effect(side, c, `${c.name} activates its ability`, slot);
                go();
        }
        return true;
    }

    // Whether effect e of the card in slot has anyone to affect right now (the CPU checks before activating)
    fxHasTargets(side, slot, e) {
        const c = this.cardAt(side, slot);
        return c == null || this.fxCan(side, slot, c, e);
    }

    // ── Actions ────────────────────────────────────────────────────────────

    start() {
        const order = this._order(this.active);
        for (let i = 0; i < (toInt(this.rules.opening_hand) || OPENING_HAND); i++) {
            for (const side of order) this._draw(side, true);
        }
        // Each player may redraw their opening hand once, in turn order; then turn 1 begins
        const chain = (k) => {
            if (k < order.length) this._askMulligan(order[k], () => chain(k + 1));
            else this._beginTurn();
        };
        chain(0);
        this._flushAsks();
    }

    doAction(side, a) {
        if (this.winner !== '' || !a || typeof a !== 'object') return false;
        let ok = false;
        // A new move (not an answer to a prompt): no brawl is going on any more
        if (a.kind !== 'choose' && a.kind !== 'discard') this._attackCtx = null;
        switch (a.kind) {
            case 'summon': ok = this._summon(side, toInt(a.uid), toInt(a.slot), String(a.position ?? 'atk'), Array.isArray(a.tributes) ? a.tributes : toInt(a.tribute ?? -1)); break;
            case 'set': ok = this._setAmbush(side, toInt(a.uid), toInt(a.slot)); break;
            case 'hustle': ok = this._hustle(side, toInt(a.uid)); break;
            case 'attack': ok = this._attack(side, toInt(a.from), toInt(a.target), a.foe == null ? null : String(a.foe)); break;
            case 'position': ok = this._changePosition(side, toInt(a.slot)); break;
            case 'promote':
                if (this.canPromote(side, toInt(a.slot))) {
                    this._promote(side, toInt(a.slot), 'Maya');
                    ok = true;
                }
                break;
            case 'ability': ok = this._useAbility(side, toInt(a.slot)); break;
            case 'activate': ok = this._activate(side, toInt(a.slot), toInt(a.fx ?? 1)); break;
            case 'choose': ok = this._answer(side, String(a.option)); break;
            case 'discard': ok = this._chooseDiscard(side, toInt(a.uid)); break;
            case 'next': ok = this._nextPhase(side); break;
        }
        if (ok) {
            this._flushAsks();
            if (this.ffa) this._sweepOut();
            this._recalc();
        }
        return ok;
    }

    /** A player leaves (conceding, away too long, disconnected). FFA: they're out, in the last place
     *  still open, and the game goes on; two players: the other one wins. Same as concede in duel_state.gd. */
    concede(side, reason = 'concede') {
        if (this.winner !== '' || !this.sides[side] || this.sides[side].out) return false;
        this._lose(side, reason);
        if (this.ffa) this._sweepOut();
        this._recalc();
        return true;
    }

    _summon(side, uid, slot, position, tribute = -1) {
        const i = this._handIndex(side, uid);
        if (i < 0 || !this.canSummon(side, this.sides[side].hand[i], slot, tribute)) return false;
        const c = this.sides[side].hand[i];
        this._spend(side, this.costOf(side, c));
        this.sides[side].hand.splice(i, 1);
        for (const slot_ of DuelState.tributeList(tribute)) {   // sacrificed, or deployed over
            const t = this.cardAt(side, slot_);
            this.sides[side].field[slot_] = null;
            t.downed = false;
            t.mods = [];
            this._clearStatus(t);
            if (!t.token) this.sides[side].gutter.push(t);   // (tokens vanish)
            const ev = { side, slot: slot_, card: clone(t), for: clone(c) };
            if (!DuelState.needsTribute(c)) ev.replace = true;
            this._emit('tribute', ev);
        }
        c.position = position === 'def' ? 'def' : 'atk';
        c.face_down = false;   // characters are always face-up, in ATK or DEF (only Ambushes are set face-down)
        c.has_attacked = false;
        c.deployed_turn = this.turn;
        this.sides[side].field[slot] = c;
        this._emit('summon', { side, slot, card: clone(c) });
        this._onDeploy(side, slot, c);
        return true;
    }

    _setAmbush(side, uid, slot) {
        const i = this._handIndex(side, uid);
        if (i < 0 || !this.canSet(side, this.sides[side].hand[i], slot)) return false;
        const c = this.sides[side].hand[i];
        if (c.cardType !== 'hustle') this._spend(side, this.costOf(side, c));   // (a Hustle is paid for when it's activated)
        this.sides[side].hand.splice(i, 1);
        c.face_down = true;
        this.sides[side].field[slot] = c;
        this._emit('set', { side, slot, card: clone(c) });
        return true;
    }

    _changePosition(side, slot) {
        if (!this.canChangePosition(side, slot)) return false;
        const c = this.cardAt(side, slot);
        c.position = c.position === 'def' ? 'atk' : 'def';
        c.face_down = false;
        c.position_turn = this.turn;
        this._emit('position', { side, slot, card: clone(c) });
        return true;
    }

    // A Hustle from the hand, or one set face-down in the back row (it's played from there)
    _hustle(side, uid) {
        const s = this.sides[side];
        const i = this._handIndex(side, uid);
        const set = i >= 0 ? -1 : (BACK.find(b => s.field[b] != null && s.field[b].uid === uid && this.setHustleSlot(side, s.field[b]) === b) ?? -1);
        const c = i >= 0 ? s.hand[i] : set >= 0 ? s.field[set] : null;
        if (c == null || !this.canHustle(side, c)) return false;
        this._spend(side, this.costOf(side, c));
        if (i >= 0) s.hand.splice(i, 1);
        else s.field[set] = null;
        if (DuelState.isLasting(c)) {
            // Continuous / Equip: into the back row (a set one stays in its slot), face-up; its "when played" effects happen
            const b = set >= 0 ? set : this._emptyBack(side);
            c.face_down = false;
            s.field[b] = c;
            const ev = { side, slot: b, card: clone(c) };
            if (set >= 0) ev.set = true;
            this._emit('lasting', ev);
            if (String(c.subtype) === 'equip') {
                const on = String(c.equip_to ?? 'ally') === 'enemy' ? (this.foesOf(side)[0] ?? side) : side;
                const entries = this._equipTargets(side, c);
                entries.sort(strongestFirst);
                this._askTarget(side, 'equip', `${c.name}: choose a character to equip`, c, entries, on, (x) => {
                    if (s.field[b] !== c) return;
                    c.equipped_to = x.card.uid;
                    this._emit('equip', { side, slot: b, target_side: x.side ?? on, target_slot: x.slot, card: clone(c) });
                    this._effect(side, c, `${c.name} is equipped to ${x.card.name}`, b);
                    this._recalc();
                    this._runFx(side, b, c, 'deploy');   // (an Equip's effects come once it's on its character)
                });
            } else this._runFx(side, b, c, 'deploy');
        } else {
            c.face_down = false;
            s.gutter.push(c);
            this._emit('hustle', set >= 0 ? { side, card: clone(c), slot: set, set: true } : { side, card: clone(c) });
            // A Card Forge Hustle: all of its effects happen when it's played
            if ((c.effects || []).length) this._runFx(side, NO_SLOT, c, '*');
        }
        for (const x of this.characters(side)) this._runFx(side, x.slot, x.card, 'hustle_played', c);
        this._runLasting(side, 'hustle_played', c);
        this._leaderFx(side, 'dormant_hustle', c);
        switch (c.effectKey) {
            case 'corner_deal':
                this._draw(side);
                this._draw(side);
                if (this._hasStriver(side)) {
                    this._effect(side, c, 'You control a Striver: no discard');
                } else {
                    this._effect(side, c, 'Drew 2 — now discard 1');
                    this._askDiscard(side, 1, null, `${c.name}: drew 2`);
                }
                break;
            case 'lion_rescue':
                this._askTarget(side, 'lion_rescue', 'Lion Rescue: choose a Downed LIONS character to stand', c,
                    this._downedLions(side), side, (e) => {
                        e.card.downed = false;
                        this._emit('stand', { side, slot: e.slot, card: clone(e.card) });
                        this._effect(side, c, `${e.card.name} stands back up`, e.slot);
                    });
                break;
            case 'blood_scent':
                this._askTarget(side, 'blood_scent', 'Blood Scent: choose a Striver to promote', c,
                    this._promotableStrivers(side), side, (e) => {
                        this._effect(side, c, `${e.card.name}'s promotion is fulfilled`, e.slot);
                        this._promote(side, e.slot, 'Blood Scent');
                    });
                break;
        }
        return true;
    }

    _useAbility(side, slot) {
        if (!this.canUseAbility(side, slot)) return false;
        const maya = this.cardAt(side, slot);
        maya.ability_turn = this.turn;
        const allies = this.characters(side).filter(e => e.slot !== slot && isLion(e.card));
        allies.sort(strongestFirst);
        this._askTarget(side, 'maya_buff', 'Maya Lv.3: choose a LIONS ally to gain +400 ATK / +400 DEF', maya,
            allies, side, (e) => {
                e.card.mods.push({ atk: 400, def: 400, until_turn: this.turn });
                this._effect(side, maya, `${e.card.name} gains +400 ATK and +400 DEF this turn`, slot);
            });
        return true;
    }

    _nextPhase(side) {
        if (!this.canAct(side)) return false;
        switch (this.phase) {
            case 'deployment':
                if (this.noAttacksYet()) {
                    this._emit('notice', { text: this.ffa ? 'NO ATTACKS UNTIL EVERYONE HAS HAD A TURN' : 'NO ATTACKS ON TURN 1' });
                    this._setPhase('regroup');
                } else {
                    this._setPhase('brawl');
                }
                break;
            case 'brawl':
                this._setPhase('regroup');
                break;
            case 'regroup': {
                this._setPhase('end');
                const extra = this.sides[side].hand.length - HAND_LIMIT;
                if (extra > 0) this._askDiscard(side, extra, () => this._endTurn(), `Hand limit: ${this.sides[side].hand.length} cards, keep ${HAND_LIMIT}`);
                else this._endTurn();
                break;
            }
            default:
                return false;
        }
        return true;
    }

    // ── Attacks ────────────────────────────────────────────────────────────

    _attack(side, from, target, foe = null) {
        foe = foe ?? this.foesOf(side)[0];
        if (foe == null || !this.foesOf(side).includes(foe)) return false;
        if (!this.canAttackWith(side, from) || !this.attackTargets(side, foe).includes(target)) return false;
        const att = this.cardAt(side, from);
        att.has_attacked = true;
        // Attacks twice each turn: the first attack leaves it ready for one more
        if (this._passive(side, from, att, 'double_attack') && att.second_attack !== this.turn) {
            att.has_attacked = false;
            att.second_attack = this.turn;
        }
        this._emit('attack', this.ffa ? { side, from, target, foe, card: clone(att) } : { side, from, target, card: clone(att) });
        const ctx = { side, foe, from, target, att, bonus: 0 };
        this._attackCtx = ctx;   // (an attacker that promotes mid-attack carries on as its new form: _promote)
        if (this._passive(side, from, att, 'pierce') || this.rules.pierce) ctx.pierce = true;
        const defNow = target >= 0 ? this.cardAt(foe, target) : null;
        let k = 0;
        for (const e of this._fx(att, 'attack')) {
            k += 1;
            const selfBuff = String(e.do ?? '') === 'buff' && String(e.target ?? 'self') === 'self';
            if (selfBuff && String(e.if ?? '') !== '') continue;   // settled in the brawl (_brawlBonus)
            if (!this._fxCond(side, from, e, defNow) || !this._fxCountFire(att, `attack${k}`, e) || !this._fxOnce(att, `attack${k}`, e)) continue;
            if (selfBuff) {
                if (!this._luckGate(side, from, att, e)) continue;
                const se = this._scaled(side, from, e);
                if (toInt(se.atk) !== 0) {
                    ctx.bonus += toInt(se.atk);
                    this._effect(side, att, `${att.name}: ${signed(toInt(se.atk))} ATK this brawl`, from);
                }
            } else if (String(e.do ?? '') === 'pierce') {
                ctx.pierce = true;
                this._effect(side, att, `${att.name}: piercing attack`, from);
            } else {
                this._doFx(side, from, att, e);
            }
        }
        if (isLion(att) && this.sides[side].brutus_bonus > 0) {
            ctx.bonus += this.sides[side].brutus_bonus;
            this.sides[side].brutus_bonus = 0;
            this._effect(side, att, "Brutus's momentum: +300 ATK", from);
        }
        this._atkRedirect(ctx);
        return true;
    }

    // An attack whose own trigger removed its target or the attacker ends there
    _atkGone(ctx) {
        if (this.winner !== '') return true;
        if (this.cardAt(ctx.side, ctx.from) !== ctx.att) return true;
        if (ctx.target >= 0 && this.cardAt(ctx.foe, ctx.target) == null) {
            this._effect(ctx.side, ctx.att, `${ctx.att.name}'s target is gone: the attack ends`, ctx.from);
            return true;
        }
        return false;
    }

    _atkRedirect(ctx) {
        const foe = ctx.foe;
        if (this._atkGone(ctx)) return;
        if (ctx.target >= 0) {
            const def = this.cardAt(foe, ctx.target);
            const be = this._readyEnforcer(foe, ctx.target);
            if (isLion(def) && be) {
                const worth = enforcerWorthIt(ctx.att, def, be.card);
                const yes = { id: 'yes', label: 'REDIRECT TO BLOCK ENFORCER', side: foe, slot: be.slot };
                const no = { id: 'no', label: `LET ${String(def.name).toUpperCase()} TAKE IT` };
                this._ask(foe, 'redirect', `Block Enforcer: take the hit for ${def.name}?`, be.card,
                    worth ? [yes, no] : [no, yes], (choice) => {
                        if (choice === 'yes') {
                            be.card.redirect_turn = this.turn;
                            ctx.target = be.slot;
                            this._effect(foe, be.card, 'Block Enforcer steps in and takes the hit', be.slot);
                            this._emit('retarget', this.ffa ? { side: ctx.side, from: ctx.from, target: ctx.target, foe } : { side: ctx.side, from: ctx.from, target: ctx.target });
                        }
                        this._atkAmbush(ctx);
                    });
                return;
            }
        }
        this._atkAmbush(ctx);
    }

    _atkAmbush(ctx) {
        const foe = ctx.foe;
        if (this._atkGone(ctx)) return;
        if (ctx.target < 0) {
            this._atkResolve(ctx);
            return;
        }
        const def = this.cardAt(foe, ctx.target);
        if (def.face_down) {
            def.face_down = false;
            this._emit('flip', { side: foe, slot: ctx.target, card: clone(def) });
        }
        const options = [];
        if (isLion(def)) {
            for (const key of ['no_witnesses_ambush', 'lion_ambush']) {
                for (const slot of BACK) {
                    const a = this.cardAt(foe, slot);
                    if (a != null && a.effectKey === key) {
                        options.push({ id: String(slot), label: `SPRING ${String(a.name).toUpperCase()}`, side: foe, slot });
                    }
                }
            }
        }
        // Card Forge Ambushes can be sprung when any of your characters is attacked
        // (ambushClan: only when the attacked character is of that clan; not while JAMMED)
        const jammed = toInt(this.sides[foe].jam_until ?? -1) >= this.turn;
        for (const slot of BACK) {
            const a = this.cardAt(foe, slot);
            if (a != null && !jammed && a.cardType === 'ambush' && (a.effects || []).length && !HAND_AMBUSHES.includes(String(a.effectKey ?? ''))
                && (String(a.ambushClan ?? '') === '' || def.clanTag === String(a.ambushClan))
                && (DuelState.isLasting(a) || this.cardCan(foe, NO_SLOT, a, '*', { side: ctx.side, slot: ctx.from, card: ctx.att }, ctx.att))) {
                options.push({ id: String(slot), label: `SPRING ${String(a.name).toUpperCase()}`, side: foe, slot });
            }
        }
        if (!options.length) {
            this._atkResolve(ctx);
            return;
        }
        options.push({ id: 'no', label: "DON'T SPRING" });
        this._ask(foe, 'ambush', `${ctx.att.name} is attacking ${def.name}. Spring an Ambush?`, ctx.att, options,
            (choice) => {
                if (choice === 'no') {
                    this._atkResolve(ctx);
                    return;
                }
                const slot = toInt(choice);
                const a = this.cardAt(foe, slot);
                if (a == null) {   // (destroyed while the choice was waiting)
                    this._atkResolve(ctx);
                    return;
                }
                this._spring(foe, slot);
                if (!HAND_AMBUSHES.includes(String(a.effectKey ?? ''))) {
                    this._springFx(ctx, foe, a);
                    return;
                }
                if (a.effectKey === 'no_witnesses_ambush') {
                    if (this._staysUp(ctx.side, ctx.from, ctx.att)) {
                        this._effect(foe, a, 'No Witnesses: the attack is negated', slot);
                        return;
                    }
                    this._effect(foe, a, 'No Witnesses: the attacker is Downed and the attack negated', slot);
                    ctx.att.downed = true;
                    ctx.att.position = 'def';   // a Downed character is in DEF
                    this._emit('downed', { side: ctx.side, slot: ctx.from, card: clone(ctx.att) });
                    return;
                }
                this._effect(foe, a, "Lion's Ambush: the attacker loses 1000 ATK this brawl", slot);
                ctx.bonus -= 1000;
                this._atkResolve(ctx);
            });
    }

    _atkResolve(ctx) {
        const { side, foe, from, target, att } = ctx;
        if (target === DIRECT) {
            const dmg = Math.max(0, att.attack + ctx.bonus);
            this._emit('clash', this._withFoeKey({ side, from, target: DIRECT, att: dmg, def: 0, vs: 'DIRECT' }, foe));
            this._damage(foe, dmg);
            this._lifesteal(side, from, att, dmg);
            if (this.winner === '' && this.cardAt(side, from) === att) this._runFx(side, from, att, 'direct');
            this._bleed(side, att);
            return;
        }
        if (target === LEADER) {
            this._hitLeader(ctx);
            this._bleed(side, att);
            return;
        }
        const def = this.cardAt(foe, target);
        let defAtk = 0, defDef = 0, k = 0;
        const vs = { side, slot: from, card: att };
        // "When another of your characters is attacked" (covering fire)
        for (const x of this.characters(foe)) {
            if (x.slot !== target && this.winner === '' && this.cardAt(side, from) === att) this._runFx(foe, x.slot, x.card, 'ally_attacked', att, vs);
        }
        if (this.cardAt(side, from) === att) this._runLasting(foe, 'ally_attacked', att, vs);
        for (const e of this._fx(def, 'defend')) {
            k += 1;
            if (this.winner !== '' || this.cardAt(foe, target) !== def || !this._fxCond(foe, target, e, att) || !this._fxCountFire(def, `defend${k}`, e) || !this._fxOnce(def, `defend${k}`, e)) continue;
            if (String(e.do ?? '') === 'buff' && String(e.target ?? 'self') === 'self') {
                if (!this._luckGate(foe, target, def, e)) continue;
                const se = this._scaled(foe, target, e);
                defAtk += toInt(se.atk);
                defDef += toInt(se.def);
                this._effect(foe, def, `${def.name}: ${statText(se)} this brawl`, target);
            } else {
                this._doFx(foe, target, def, e, vs);
            }
        }
        // The defender's effects may have removed or stopped the attacker (or itself)
        if (this.winner !== '' || this.cardAt(side, from) !== att || att.downed || this.cardAt(foe, target) !== def) return;
        this._recalc();   // (what they did to either card counts in this brawl, e.g. SUPPRESS on the attacker)
        let bonus = ctx.bonus + this._brawlBonus(side, from, att, def);
        if (def.effectKey === 'bulwark') {
            bonus -= 300;
            this._effect(foe, def, 'Bulwark: the attacker loses 300 ATK', target);
        }
        const defWasDowned = def.downed;
        const defInfo = { downed: def.downed, position: def.position, face_down: false };
        const vsDef = def.downed || def.position === 'def';
        const aVal = Math.max(0, att.attack + bonus);
        const dVal = vsDef ? def.defense + defDef : def.attack + defAtk;
        this._emit('clash', this._withFoeKey({ side, from, target, att: aVal, def: dVal, vs: vsDef ? 'DEF' : 'ATK' }, foe));

        let result = '';
        if (vsDef) {
            if (aVal > dVal) {
                if (ctx.pierce) { this._damage(foe, aVal - dVal); this._lifesteal(side, from, att, aVal - dVal); }
                result = this._defeat(foe, target);
            }
            else {
                this._emit('blocked', { side: foe, slot: target });
                if (aVal < dVal) {   // a failed attack costs the difference, as it does against ATK
                    this._damage(side, dVal - aVal);
                    this._lifesteal(foe, target, def, dVal - aVal);
                }
            }
        } else if (aVal > dVal) {
            this._damage(foe, aVal - dVal);
            this._lifesteal(side, from, att, aVal - dVal);
            result = this._defeat(foe, target);
        } else if (aVal < dVal) {
            this._damage(side, dVal - aVal);
            this._lifesteal(foe, target, def, dVal - aVal);
            this._defeat(side, from);
        } else {
            this._emit('notice', { text: 'TIE — BOTH GO DOWN' });
            result = this._defeat(foe, target);
            this._defeat(side, from);
        }
        if (this.winner === '' && this.cardAt(side, from) === att && !att.downed) {
            if (result === 'ko') {
                this._onKo(side, from, att, defWasDowned, target, foe);
                this._runFx(side, this._slotOf(side, att, from), att, 'ko', defInfo);
            } else if (result === 'downed') {
                this._onDown(side, from, att, foe);
                this._runFx(side, this._slotOf(side, att, from), att, 'down', defInfo);
            }
        }
        this._bleed(side, att);
        this._bleed(foe, def);
    }

    _bleed(side, c) {
        const n = toInt(c.bleed ?? 0);
        if (n <= 0 || this.winner !== '') return;
        const slot = this._slotOf(side, c, -1);
        if (slot < 0) return;
        c.mods.push({ atk: -n, def: -n, until_turn: FOREVER });
        this._emit('status_tick', { side, slot, kind: 'bleed', amount: n, card: clone(c) });
    }

    _hitLeader(ctx) {
        const foe = ctx.foe;
        const leader = this.sides[foe].leader;
        const dmg = Math.max(0, ctx.att.attack + ctx.bonus);
        this._emit('clash', this._withFoeKey({ side: ctx.side, from: ctx.from, target: LEADER, att: dmg, def: leader.influence, vs: 'INFLUENCE' }, foe));
        leader.influence = Math.max(0, leader.influence - dmg);
        this._emit('leader_hit', { side: foe, amount: dmg, influence: leader.influence });
        if (leader.influence <= 0) {
            this.sides[foe].leader_state = 'defeated';
            this.sides[foe].gutter.push(leader);
            this._emit('leader_down', { side: foe, card: clone(leader) });   // (no Morale lost: it never took the field)
        } else {
            this._leaderFx(foe, 'dormant_hit', ctx.att);
        }
    }

    // ── Battle results ─────────────────────────────────────────────────────

    _defeat(side, slot) {
        const c = this.cardAt(side, slot);
        if (c.shield) {
            delete c.shield;
            this._effect(side, c, `${c.name}'s shield takes the blow`, slot);
            return 'saved';
        }
        if (c.downed) {
            if (isLion(c) && c.subtype === 'striver' && this._springKingsTest(side, slot, c)) return 'saved';
            this._ko(side, slot);
            return 'ko';
        }
        if (this._staysUp(side, slot, c)) {
            this._effect(side, c, `${c.name} stays standing`, slot);
            return 'saved';
        }
        c.downed = true;
        c.position = 'def';   // a Downed character is in DEF
        this._emit('downed', { side, slot, card: clone(c) });
        this._runFx(side, slot, c, 'self_downed');
        return 'downed';
    }

    _ko(side, slot) {
        const c = this.cardAt(side, slot);
        if (c == null) return;
        this.sides[side].field[slot] = null;
        const bounty = c.bounty;
        c.downed = false;
        c.mods = [];
        this._clearStatus(c);
        if (!c.token) this.sides[side].gutter.push(c);   // a token vanishes
        this._emit('ko', { side, slot, card: clone(c) });
        this._runFx(side, slot, c, 'self_ko');
        // "When another of your characters is KO'd"
        for (const x of this.characters(side)) this._runFx(side, x.slot, x.card, 'ally_ko', c);
        this._runLasting(side, 'ally_ko', c);
        // "When an enemy character is KO'd" (by anything): every opponent's cards
        for (const foe of this.foesOf(side)) {
            for (const x of this.characters(foe)) this._runFx(foe, x.slot, x.card, 'foe_ko', c);
            this._runLasting(foe, 'foe_ko', c);
        }
        // BOUNTY: whoever put it on draws
        if (bounty && this.winner === '' && this.sides[bounty.by]) {
            this._effect(bounty.by, c, `BOUNTY on ${c.name} collected: draw ${bounty.n}`, -1);
            for (let i = 0; i < toInt(bounty.n) && this.winner === ''; i++) this._draw(bounty.by);
        }
    }

    /** Whether a character has a status CLEANSE would take away. */
    _afflicted(c) {
        return c.poison !== undefined || c.burn !== undefined || c.bleed !== undefined || c.bounty !== undefined
            || this.frozen(c) || this.inStasis(c) || toInt(c.stun_until ?? 0) >= this.turn
            || toInt(c.suppress_until ?? 0) >= this.turn || toInt(c.silence_until ?? 0) >= this.turn;
    }

    /** Put a character back on top of its owner's deck (a token just vanishes). */
    _topdeck(side, slot) {
        const c = this.cardAt(side, slot);
        this.sides[side].field[slot] = null;
        if (c.token) {
            this._emit('ko', { side, slot, card: clone(c) });
            return;
        }
        c.downed = false;
        c.mods = [];
        c.position = 'atk';
        c.face_down = false;
        c.has_attacked = false;
        for (const k of ['shield', 'stun_until', 'down_turns', 'kings_test', 'fx_used', 'fx_count']) delete c[k];
        this._clearStatus(c);
        this.sides[side].deck.push(c);   // (draws take from the end)
        this._emit('topdeck', { side, slot, card: clone(c) });
    }

    /** Remove a character from the game: it doesn't go to the Gutter, and no KO effects happen. */
    _exile(side, slot) {
        const c = this.cardAt(side, slot);
        this.sides[side].field[slot] = null;
        this._clearStatus(c);
        this._emit('ko', { side, slot, card: clone(c), exiled: true });
    }

    /** LIFESTEAL (Card Forge passive): the Morale a character takes from an opponent in a brawl, its owner gains. */
    _lifesteal(side, slot, c, amount) {
        if (amount <= 0 || this.winner !== '' || c == null || isEmpty(this._passive(side, slot, c, 'lifesteal'))) return;
        this._heal(side, c, amount, slot);
    }

    _damage(side, amount, paid = false) {
        if (amount <= 0) return;
        const s = this.sides[side];
        const wall = paid ? 0 : toInt(s.barricade ?? 0);
        if (wall > 0) {
            const held = Math.min(wall, amount);
            s.barricade = wall - held;
            amount -= held;
            this._emit('barricade', { side, amount: s.barricade, held });
            if (amount <= 0) return;
        }
        s.morale = Math.max(0, s.morale - amount);
        this._emit('damage', { side, amount, morale: s.morale });
        if (s.morale <= 0 && this.winner === '') this._lose(side, 'morale');
    }

    /** side is out (no Morale, or decked out). Two players: the other one wins. FFA: they take the
     *  last place still open, their cards leave at the end of the action (_sweepOut), and the last
     *  player standing wins. */
    _lose(side, reason) {
        if (this.winner !== '') return;
        if (!this.ffa) {
            this._end(this.seats.find(x => x !== side), reason);
            return;
        }
        const s = this.sides[side];
        if (s.out) return;
        s.out = this._alive().length;
        this.places[side] = s.out;
        this._emit('eliminated', { side, place: s.out, reason });
        const left = this._alive();
        if (left.length === 1) {
            this.places[left[0]] = 1;
            this._end(left[0], reason);
        }
    }

    /** FFA, after each action: the cards of players who went out leave the game, their prompts are
     *  dropped, and if it was their turn the next player's begins. */
    _sweepOut() {
        let changed = false;
        for (const side of this.seats) {
            const s = this.sides[side];
            if (!s.out || s.cleared) continue;
            s.cleared = true;
            changed = true;
            s.field = Array(10).fill(null);
            s.hand = [];
            if (s.leader_state === 'dormant') s.leader_state = 'defeated';
        }
        if (!changed || this.winner !== '') return;
        this._asks = this._asks.filter(a => !this.sides[a.side].out);
        if (this.pending.side && this.sides[this.pending.side].out) this.pending = {};
        while (this.winner === '' && this.sides[this.active].out) {
            for (const side of this.seats) {
                for (const c of this.sides[side].field) if (c != null) c.mods = c.mods.filter(m => m.until_turn > this.turn);
            }
            this.active = this._nextSeat(this.active);
            this.turn += 1;
            this._beginTurn();
        }
        this._flushAsks();
        if (this.seats.some(x => this.sides[x].out && !this.sides[x].cleared)) this._sweepOut();
    }

    /** FFA events about a brawl say which opponent it's with (two players: unchanged). */
    _withFoeKey(ev, foe) {
        if (this.ffa) ev.foe = foe;
        return ev;
    }

    _end(winSide, reason) {
        this.winner = winSide;
        this.endReason = reason;
        this.pending = {};
        this._asks = [];
        this._newAsks = [];
        this._emit('game_over', { winner: this.winner, reason });
    }

    _brawlBonus(side, from, att, def) {
        let extra = 0;
        let k = 0;
        for (const e of this._fx(att, 'attack')) {
            k += 1;
            if (String(e.do ?? '') === 'buff' && String(e.target ?? 'self') === 'self'
                    && String(e.if ?? '') !== '' && this._fxCond(side, from, e, def) && this._fxOnce(att, `attack${k}`, e)) {
                if (!this._luckGate(side, from, att, e)) continue;
                const se = this._scaled(side, from, e);
                if (toInt(se.atk) !== 0) {
                    extra += toInt(se.atk);
                    this._effect(side, att, `${att.name}: ${signed(toInt(se.atk))} ATK this brawl`, from);
                }
            }
        }
        return extra + this._keyBrawlBonus(side, from, att, def);
    }

    _keyBrawlBonus(side, from, att, def) {
        const key = att.effectKey || '';
        if (key === 'goldfang_attacker' && def.position === 'def' && !def.downed) {
            this._effect(side, att, 'Goldfang hits a defender: +500 ATK', from);
            return 500;
        }
        if (def.downed && ['hunter_lv1', 'hunter_lv2', 'hunter_lv3', 'mauler'].includes(key)) {
            this._effect(side, att, `${att.name} smells blood: +500 ATK vs Downed`, from);
            return 500;
        }
        return 0;
    }

    _onKo(side, slot, att, wasDowned, target, foe = null) {
        const key = att.effectKey || '';
        foe = foe ?? this.foesOf(side)[0];
        if (key === 'brutus_enter') {
            this.sides[side].brutus_bonus = 300;
            this._effect(side, att, 'Brutus: your next LIONS attacker gains +300 ATK', slot);
        }
        switch (key) {
            case 'eric_lv3_draw':
                this._effect(side, att, 'Eric Lv.3 KO: draw 1 card', slot);
                this._draw(side);
                break;
            case 'lion_clan_bonus':
                if (typeof att.promotesTo === 'string' && !att.abilityOnlyPromote) this._promote(side, slot, att.name);
                break;
            case 'mauler':
                if (wasDowned) {
                    this._effect(side, att, 'Mauler: enemies in the next lanes lose 500 DEF this turn', slot);
                    for (const e of this.characters(foe)) {
                        if (Math.abs(e.slot - target) === 1) e.card.mods.push({ def: -500, until_turn: this.turn });
                    }
                }
                break;
        }
        if (['hunter_lv2', 'hunter_lv3'].includes(key)) {
            const standing = this.characters(foe).filter(e => !e.card.downed && !this._staysUp(foe, e.slot, e.card));
            standing.sort(strongestFirst);
            this._askTarget(side, 'hunter_down', `${att.name} KO: choose an enemy character to Down`, att,
                standing, foe, (e) => {
                    e.card.downed = true;
                    e.card.position = 'def';   // a Downed character is in DEF
                    this._effect(side, att, `${att.name} Downs ${e.card.name}`, slot);
                    this._emit('downed', { side: foe, slot: e.slot, card: clone(e.card) });
                });
        }
        if (wasDowned) {
            if (['hunter_lv1', 'hunter_lv2'].includes(key)) {
                this._promote(side, slot, att.name);
            } else if (key === 'hunter_lv3') {
                att.has_attacked = false;
                this._effect(side, att, `${att.name} may attack again this turn`, slot);
            }
        }
    }

    _onDown(side, slot, att, foe = null) {
        switch (att.effectKey || '') {
            case 'brutus_enter':
                this.sides[side].brutus_bonus = 300;
                this._effect(side, att, 'Brutus: your next LIONS attacker gains +300 ATK', slot);
                break;
            case 'debt_collector': {
                foe = foe ?? this.foesOf(side)[0];
                if (foe != null && this.sides[foe].hand.length) {
                    this._effect(side, att, 'Debt Collector: your opponent discards 1 card', slot);
                    this._askDiscard(foe, 1, null, 'Debt Collector makes you discard');
                }
                break;
            }
        }
    }

    _springKingsTest(side, slot, c) {
        for (const s of BACK) {
            const a = this.cardAt(side, s);
            if (a != null && a.effectKey === 'kings_test') {
                this._spring(side, s);
                this._effect(side, a, `King's Test: ${c.name} survives — it may promote next turn`, s);
                c.kings_test = true;
                return true;
            }
        }
        return false;
    }

    _spring(side, slot) {
        const a = this.cardAt(side, slot);
        a.face_down = false;
        if (DuelState.isLasting(a)) {   // a Continuous Ambush stays, face-up
            this._emit('ambush', { side, slot, card: clone(a), stays: true });
            return;
        }
        this.sides[side].field[slot] = null;
        this.sides[side].gutter.push(a);
        this._emit('ambush', { side, slot, card: clone(a) });
    }

    // ── Effects ────────────────────────────────────────────────────────────

    /** evolved: a Striver's new form arriving by promotion. Its own "when deployed" effects run, but
     *  it doesn't count as a deploy for other cards ("when you / your opponent deploy a character"). */
    _onDeploy(side, slot, c, evolved = false) {
        delete c.fx_count;   // "times" counts start fresh each time a card enters the field
        this._runFx(side, slot, c, 'deploy');
        const foes = this.foesOf(side);
        if (!evolved) {
            for (const x of this.characters(side)) {
                if (x.slot !== slot) this._runFx(side, x.slot, x.card, 'ally_deployed', c);
            }
            for (const foe of foes) for (const x of this.characters(foe)) this._runFx(foe, x.slot, x.card, 'foe_deployed', c);
            this._runLasting(side, 'ally_deployed', c);
            for (const foe of foes) this._runLasting(foe, 'foe_deployed', c);
            this._leaderFx(side, 'dormant_ally_deployed', c);
            for (const foe of foes) this._leaderFx(foe, 'dormant_foe_deployed', c);
        }
        switch (c.effectKey || '') {
            case 'pride_lieutenant_deploy': {
                const allies = this.characters(side).filter(e => e.slot !== slot && isLion(e.card));
                allies.sort(strongestFirst);
                this._askTarget(side, 'lieutenant', 'Pride Lieutenant: choose a LIONS ally to gain +500 ATK', c,
                    allies, side, (e) => {
                        e.card.mods.push({ atk: 500, until_turn: this.turn });
                        this._effect(side, c, `${e.card.name} gains +500 ATK this turn`, slot);
                    });
                break;
            }
            case 'brutus_enter': {
                const enemies = foes.flatMap(f => this.characters(f).map(x => ({ side: f, slot: x.slot, card: x.card })));
                enemies.sort(strongestFirst);
                this._askTarget(side, 'brutus', 'Brutus: choose an enemy character to lose 700 ATK', c,
                    enemies, foes[0] ?? side, (e) => {
                        e.card.mods.push({ atk: -700, until_turn: this.turn + this._roundSpan() });
                        this._effect(side, c, `${e.card.name} loses 700 ATK until the end of your opponent's next turn`, slot);
                    });
                break;
            }
            case 'sovereign': {
                let hit = 0;
                for (const foe of foes) {
                    for (const e of this.characters(foe)) {
                        if (!e.card.downed && e.card.defense <= 1500 && !this._staysUp(foe, e.slot, e.card)) {
                            e.card.downed = true;
                            e.card.position = 'def';   // a Downed character is in DEF
                            hit += 1;
                            this._emit('downed', { side: foe, slot: e.slot, card: clone(e.card) });
                        }
                    }
                }
                if (hit > 0) this._effect(side, c, `Sovereign's arrival Downs ${hit} enem${hit === 1 ? 'y' : 'ies'}`, slot);
                break;
            }
        }
    }

    _promote(side, slot, reason) {
        const s = this.sides[side];
        const old = this.cardAt(side, slot);
        if (old == null || s.promoted[slot] || old.subtype !== 'striver') return;   // only Strivers level up
        const toId = nextForm(old.id);
        if (toId === '') return;
        s.promoted[slot] = true;
        const preview = getCard(toId);
        const ask = this._ask(side, 'position', `Promote to ${preview.name ?? toId}: choose its position`, preview, [
            { id: 'atk', label: 'ATK POSITION' }, { id: 'def', label: 'DEF POSITION' },
        ], (pos) => {
            if (this.cardAt(side, slot) !== old || old.downed || this.inStasis(old)) return;
            let promoted = null;
            const i = s.hideout.findIndex(h => h.id === toId);
            if (i >= 0) promoted = s.hideout.splice(i, 1)[0];
            if (promoted == null) promoted = this.makeCard(toId);
            promoted.position = pos;
            promoted.face_down = false;
            promoted.has_attacked = true;
            promoted.rest_turn = this.turn;   // shown as resting: it can't attack this turn
            promoted.evolved_turn = this.turn;   // ...nor use its Activate abilities (see activations)
            promoted.deployed_turn = this.turn;
            s.field[slot] = promoted;
            if (this._attackCtx && this._attackCtx.att === old) this._attackCtx.att = promoted;   // promoted mid-attack: the attack goes on
            // The same fighter, stronger: its ATK/DEF changes (buffs and debuffs) and its Equips carry
            // over; its statuses (STASIS, FREEZE, ...) don't
            promoted.mods = (old.mods ?? []).map(m => ({ ...m }));
            for (const q of this._equipsOn(old)) q.card.equipped_to = promoted.uid;
            old.mods = [];
            old.downed = false;
            this._clearStatus(old);
            s.gutter.push(old);
            this._emit('promote', { side, slot, from: clone(old), card: clone(promoted), reason });
            this._onDeploy(side, slot, promoted, true);
            if (promoted.subtype === 'striver' && isLion(promoted) && !s.mentor_used) {
                for (const e of this.characters(side)) {
                    if (e.card.effectKey === 'pride_mentor_draw') {
                        s.mentor_used = true;
                        this._effect(side, e.card, 'Pride Mentor: a Striver promoted — draw 2', e.slot);
                        this._draw(side);
                        this._draw(side);
                        break;
                    }
                }
            }
        });
        // Downed, KO'd or in STASIS before the player answers (an Ambush mid-attack): it doesn't promote
        ask.still = () => this.cardAt(side, slot) === old && !old.downed && !this.inStasis(old);
    }

    _checkAwaken(side) {
        const s = this.sides[side];
        if (s.leader_state !== 'dormant') return;
        const cond = s.leader.awakenCondition || {};
        if (isEmpty(cond)) return;
        // Any of: N+ standing (clan) characters, Authority N+, Morale N or less
        // (King Roan's older form: lions = LIONS characters, authorityThreshold = Authority)
        const clan = cond.lions != null ? 'lion' : String(cond.clan ?? '');
        const chars = this.characters(side).filter(e => (clan === '' || e.card.clanTag === clan) && !e.card.downed && !e.card.face_down).length;
        const ready = chars >= toInt(cond.lions ?? cond.chars ?? 99)
            || s.authority_max >= toInt(cond.authorityThreshold ?? cond.authority ?? 99)
            || (cond.morale != null && s.morale <= toInt(cond.morale))
            || (cond.gutter != null && s.gutter.length >= toInt(cond.gutter))
            || (cond.foe_morale != null && this.foesOf(side).some(f => this.sides[f].morale <= toInt(cond.foe_morale)))
            || (cond.influence != null && toInt(s.leader.influence) <= toInt(cond.influence))
            || (cond.luck != null && toInt(s.luck_won ?? 0) >= toInt(cond.luck));   // N won coin flips / die rolls
        if (!ready) return;
        const empties = [];
        const taken = [];
        for (const slot of FRONT) {
            const c = s.field[slot];
            if (c == null) {
                empties.push({ id: String(slot), label: `LANE ${slot + 1} (EMPTY)`, side, slot });
            } else {
                taken.push({ id: String(slot), label: `REPLACE ${String(c.name).toUpperCase()}`, side, slot, value: attackValue(c) });
            }
        }
        taken.sort((a, b) => (a.value - b.value) || (a.slot - b.slot));
        const options = [...empties, ...taken, { id: 'wait', label: 'STAY DORMANT FOR NOW' }];
        this._ask(side, 'awaken', `${s.leader.name} AWAKENS! Choose a lane`, s.leader, options, (choice) => {
            if (choice === 'wait') return;
            const slot = toInt(choice);
            const displaced = s.field[slot];
            if (displaced != null) {
                s.field[slot] = null;
                displaced.downed = false;
                displaced.mods = [];
                s.gutter.push(displaced);
                this._emit('ko', { side, slot, card: clone(displaced) });
            }
            const king = s.leader;
            s.leader_state = 'awake';
            king.position = 'atk';
            king.has_attacked = !cond.ready;   // ready: it may attack the turn it Awakens
            if (!cond.ready) king.rest_turn = this.turn;
            king.deployed_turn = this.turn;
            s.field[slot] = king;
            this._emit('awaken', { side, slot, card: clone(king) });
            this._effect(side, king, `${king.name} takes the street`, slot);
            delete king.fx_count;
            this._runFx(side, slot, king, 'awaken');
            this._recalc();
        });
    }

    _recalc() {
        this._sweepEquips();
        const values = {};
        for (const side of Object.keys(this.sides)) {
            const s = this.sides[side];
            const foes = this.foesOf(side);
            const foeHasDowned = foes.some(f => this.characters(f).some(e => e.card.downed));
            const lions = this.lionCount(side);
            const roan = s.leader_state === 'dormant' && s.leader.effectKey === 'king_roan_leader' && lions >= 2;
            const auras = this._auras(side);
            const foeAuras = foes.flatMap(f => this._auras(f)).filter(a => String(a[1].target ?? '') === 'enemies');
            values[side] = {};
            for (const slot of FRONT) {
                const c = s.field[slot];
                if (c == null) continue;
                let atk = c.base_attack;
                let df = c.base_defense;
                for (const m of c.mods) {
                    atk += toInt(m.atk);
                    df += toInt(m.def);
                }
                const otherLions = lions - (isLion(c) ? 1 : 0);
                switch (c.effectKey || '') {
                    case 'lion_grunt_synergy': if (otherLions > 0) atk += 300; break;
                    case 'pride_runner_adjacency': if (this._adjacentLion(side, slot)) atk += 400; break;
                    case 'eric_lv3_draw': atk += 100 * otherLions; break;
                    case 'kingpin': if (foeHasDowned) atk += 400; break;
                    case 'sovereign': if (foeHasDowned) atk += 600; break;
                }
                if (roan && isLion(c)) atk += 300;
                for (const a of auras) {
                    if (this._auraHits(a, slot, c)) {
                        atk += toInt(a[1].atk);
                        df += toInt(a[1].def);
                    }
                }
                for (const a of foeAuras) {
                    const clan = String(a[1].clan ?? '');
                    if (clan === '' || c.clanTag === clan) {
                        atk += toInt(a[1].atk);
                        df += toInt(a[1].def);
                    }
                }
                for (const q of this._equipsOn(c)) {   // an Equip's buffs are its character's
                    for (const e of this._fx(q.card, 'passive')) {
                        if (String(e.do ?? '') === 'buff' && this._fxCond(q.side, q.slot, e, null)) {
                            const se = this._scaled(q.side, q.slot, e);
                            atk += toInt(se.atk);
                            df += toInt(se.def);
                        }
                    }
                }
                for (const adj of [slot - 1, slot + 1]) {
                    if (FRONT.includes(adj) && s.field[adj] != null && s.field[adj].effectKey === 'bulwark') df += 400;
                }
                if (c.mods.filter(m => m.swap).length % 2 === 1) [atk, df] = [df, atk];   // (swapped: ATK and DEF trade places)
                c.attack = Math.max(0, atk);
                c.defense = Math.max(0, df);
                values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense, c.face_down, this.statuses(c)];
            }
        }
        this._emit('stats', { values });
    }

    // ── Card effects from data (Card Forge) ────────────────────────────────
    // Same building blocks and rules as duel_state.gd (see the list there):
    // {when, do, target, atk, def, amount, until, clan, kind, if, n, once, times}
    // Passives (when "passive"): buff (self / allies / enemies), pierce, untargetable, immune,
    // guard, double_attack, cost_down (amount, clan), no_down.

    _fx(c, when) {
        if (c == null || this.inStasis(c)) return [];   // STASIS: frozen in time, no effects
        if (toInt(c.silence_until ?? 0) >= this.turn) return [];   // SILENCED: its effects don't work
        // A Downed character's effects don't work, except as it goes Down or is KO'd, and the ones
        // that stand it back up ("At the end of your turn: if this card is Downed, it stands back up")
        const downed = !!c.downed && !['self_downed', 'self_ko'].includes(when);
        // "*": all of them (Hustles, Ambushes)
        return foldIfDone(c.effects || []).filter(e => e && typeof e === 'object' && (when === '*' || String(e.when ?? '') === when)
            && !(downed && !(String(e.do ?? '') === 'stand' && String(e.target ?? '') === 'self')));
    }

    /** A sprung Card Forge Ambush (same as _spring_fx in duel_state.gd). */
    _springFx(ctx, foe, a) {
        const vs = { side: ctx.side, slot: ctx.from, card: ctx.att };
        for (const e of this._fx(a, DuelState.isLasting(a) ? 'defend' : '*')) {   // (a Continuous one's other effects last)
            if (this.winner !== '') return;
            if (!this._fxCond(foe, NO_SLOT, e, ctx.att)) continue;
            if (String(e.do ?? '') === 'buff' && String(e.target ?? '') === 'attacker') {
                const atk = toInt(this._scaled(foe, NO_SLOT, e).atk ?? 0);
                if (atk !== 0) {
                    ctx.bonus += atk;
                    this._effect(foe, a, `${a.name}: the attacker gets ${signed(atk)} ATK this brawl`, NO_SLOT);
                }
            } else {
                this._doFx(foe, NO_SLOT, a, e, vs);
            }
        }
        if (this.winner !== '') return;
        if (this.cardAt(ctx.side, ctx.from) !== ctx.att || ctx.att.downed || this.inStasis(ctx.att) || this.cardAt(foe, ctx.target) == null) {
            this._effect(foe, a, `${a.name} stops the attack`, NO_SLOT);
            return;
        }
        this._atkResolve(ctx);
    }

    /** times on attack / defend triggers: counts this one; true once it has happened enough (then counts again). */
    _fxCountFire(c, key, e) {
        if (!this._fxCount(c, key, e)) return false;
        if (toInt(e.times ?? 1) > 1) delete c.fx_count[key];
        return true;
    }

    /** times: the effect waits until its trigger has happened that many times (e.g. Downs 2 characters). */
    _fxCount(c, key, e) {
        const need = toInt(e.times ?? 1);
        if (need <= 1) return true;
        const count = c.fx_count || {};
        count[key] = toInt(count[key] ?? 0) + 1;
        c.fx_count = count;
        return count[key] >= need;
    }

    _fxOnce(c, key, e) {
        if (!e.once) return true;
        const used = c.fx_used || {};
        if (toInt(used[key] ?? -1) === this.turn) return false;
        used[key] = this.turn;
        c.fx_used = used;
        return true;
    }

    /** Every opponent's characters, with their side. */
    _enemyChars(side) {
        const out = [];
        for (const f of this.foesOf(side)) for (const x of this.characters(f)) out.push({ side: f, slot: x.slot, card: x.card });
        return out;
    }

    _fxPool(side, e, except, standingOnly = false) {
        const clan = String(e.clan ?? '');
        return this.characters(side).filter(x => x.slot !== except && (clan === '' || x.card.clanTag === clan)
            && !(standingOnly && x.card.downed));
    }

    /** "For each": what effect e counts (same as _per_count in duel_state.gd). */
    _perCount(side, slot, e) {
        const clan = String(e.per_clan ?? '');
        const ofClan = (x) => clan === '' || x.clanTag === clan;
        const s = this.sides[side];
        let n;
        switch (String(e.per ?? '')) {
            case 'allies': n = this.characters(side).filter(x => x.slot !== slot && ofClan(x.card)).length; break;
            case 'enemies': n = this._enemyChars(side).length; break;
            case 'foe_downed': n = this._enemyChars(side).filter(x => x.card.downed).length; break;
            case 'gutter': n = s.gutter.filter(ofClan).length; break;
            case 'hand': n = s.hand.filter(ofClan).length; break;
            case 'roll': n = Math.max(1, toInt(this._roll)); break;   // the die just rolled (_luckGate)
            default: return 1;
        }
        if (e.per_max != null) n = Math.min(n, toInt(e.per_max));
        return n;
    }

    _scaled(side, slot, e) {
        if (String(e.per ?? '') === '') return e;
        const k = this._perCount(side, slot, e);
        const out = { ...e, atk: toInt(e.atk ?? 0) * k, def: toInt(e.def ?? 0) * k, amount: toInt(e.amount ?? 1) * k };
        delete out.per;
        return out;
    }

    _emptyLane(side) {
        const lane = FRONT.find(l => this.sides[side].field[l] == null);
        return lane == null ? -1 : lane;
    }

    /** "Choose one" (same as _choose_fx in duel_state.gd) */
    _chooseFx(side, slot, c, opts, vs) {
        if (opts.length === 1) { this._doFx(side, slot, c, opts[0], vs); return; }
        if (!this._fxUseful(side, slot, c, opts[0], vs) && this._fxUseful(side, slot, c, opts[1], vs)) opts = [opts[1], opts[0]];
        const options = opts.map((o, k) => {
            const label = String(o.label ?? '');
            return { id: String(k), label: label !== '' ? label.toUpperCase() : String(o.do ?? '').toUpperCase() };
        });
        this._ask(side, 'fx_choice', `${c.name}: choose one`, c, options, (choice) => {
            const k = toInt(choice);
            if (k >= 0 && k < opts.length && this.winner === '') this._doFx(side, this._slotOf(side, c, slot), c, opts[k], vs);
        });
    }

    _fxUseful(side, slot, c, e, vs) {
        return this.fxCan(side, slot, c, e, vs);
    }

    _fxCond(side, slot, e, def) {
        const n = toInt(e.n ?? 1);
        const s = this.sides[side];
        switch (String(e.if ?? '')) {
            case 'vs_def': return def != null && (def.position === 'def' || !!def.face_down || !!def.downed);
            case 'vs_downed': return def != null && !!def.downed;
            case 'vs_atk': return def != null && def.position === 'atk' && !def.downed;
            // (if_clan: whose characters count; without it, the effect's clan as before)
            case 'allies': return this._fxPool(side, { ...e, clan: e.if_clan ?? e.clan }, slot).length >= n;
            case 'allies_le': return this._fxPool(side, { ...e, clan: e.if_clan ?? e.clan }, slot).length <= n;
            case 'alone': return this.characters(side).every(x => x.slot === slot);
            case 'adjacent': return this._fxPool(side, { ...e, clan: e.if_clan ?? e.clan }, slot).some(x => Math.abs(x.slot - slot) === 1);
            case 'foe_downed': return this._enemyChars(side).some(x => x.card.downed);
            case 'hand_le': return s.hand.length <= n;
            case 'morale_le': return s.morale <= n;
            case 'foe_morale_le': return this.foesOf(side).some(f => this.sides[f].morale <= n);
            case 'enemies_ge': return this._enemyChars(side).length >= n;
            case 'gutter_ge': return ofIfClan(s.gutter, e).length >= n;
            case 'leader_dormant': return s.leader_state === 'dormant';
            case 'leader_awake': return s.leader_state === 'awake';
            case 'foe_hand_le': return this.foesOf(side).some(f => this.sides[f].hand.length <= n);
            case 'foe_ambush': return this.foesOf(side).some(f => BACK.some(b => this.sides[f].field[b] != null));
            case 'authority_ge': return s.authority_max >= n;
            case 'ally_downed': return this.characters(side).some(x => x.slot !== slot && x.card.downed && ofIfClan([x.card], e).length > 0);
            case 'hand_ge': return ofIfClan(s.hand, e).length >= n;
            case 'self_def': { const me = this.cardAt(side, slot); return me != null && me.position === 'def'; }
            case 'self_atk': { const me = this.cardAt(side, slot); return me != null && me.position === 'atk' && !me.downed; }
            case 'enemies_le': return this._enemyChars(side).length <= n;
            case 'turn_ge': return this.turn >= n;
            case 'deck_le': return s.deck.length <= n;
        }
        return true;
    }

    _runFx(side, slot, c, when, def = null, vs = {}) {
        const list = this._fx(c, when);
        let i = 0;
        while (i < list.length) {
            const e = list[i];
            i += 1;
            const k = i;
            if (this.winner !== '') return;
            // "Choose one" (or): this effect or the next; the player picks one whose condition holds
            let opts = [e];
            if (e.or && i < list.length) { opts.push(list[i]); i += 1; }
            // when_clan: only when an ally of that clan is deployed (without it, the effect's clan as before)
            const wc = String(e.when_clan ?? e.clan ?? '');
            if ((when === 'ally_deployed' || when === 'dormant_ally_deployed') && wc !== '' && (def == null || def.clanTag !== wc)) continue;
            opts = opts.filter(o => this._fxCond(side, slot, o, def));
            if (!opts.length || !this._fxCount(c, `${when}${k}`, e)) continue;
            if (this._fxOnce(c, `${when}${k}`, e)) {
                if (toInt(e.times ?? 1) > 1) delete c.fx_count[`${when}${k}`];   // start counting again
                if (opts.length > 1) this._chooseFx(side, slot, c, opts, vs);
                else this._doFx(side, slot, c, opts[0], vs);
            }
        }
    }

    /** then: a follow-up effect that happens only if this one did something ("If you do, ...").
     *  Effects that wait on a choice (a target, a card to take) run it after the answer, and not on SKIP. */
    _doFx(side, slot, c, e, vs = {}) {
        const w = this._luckWait;
        if (w && w.uid === c.uid && String(e.if_luck ?? '') !== '') {   // ("If tails, ..." waits for the bet it follows)
            const cb = w.ask.cb;
            w.ask.cb = (...answer) => { if (cb) cb(...answer); if (this.winner === '') this._doFx(side, this._slotOf(side, c, slot), c, e, vs); };
            return;
        }
        if (String(e.luck ?? '') === 'double') { this._askDouble(side, slot, c, e, vs); return; }
        if (!this._luckGate(side, slot, c, e)) return;
        this._doFxRun(side, slot, c, e, vs);
    }

    /** DOUBLE OR NOTHING (same as _ask_double in duel_state.gd): the player chooses to bet (a coin;
     *  heads, the effect happens twice; tails, not at all) or to take it once, with no flip. The CPU
     *  bets when it has LOADED DICE to fall back on. */
    _askDouble(side, slot, c, e, vs) {
        const s = this.sides[side];
        const loaded = s && toInt(s.loaded_turn ?? -1) !== this.turn
            && this.characters(side).some(x => !isEmpty(this._passive(side, x.slot, x.card, 'loaded')));
        const bet = { id: 'double', label: 'DOUBLE OR NOTHING' }, once = { id: 'once', label: 'JUST ONCE' };
        const w = { uid: c.uid, ask: null };
        w.ask = this._ask(side, 'double', `${c.name}: double or nothing? Flip a coin: heads, it happens twice; tails, not at all. Or take it once.`,
            c, loaded ? [bet, once] : [once, bet], (choice) => {
                if (this._luckWait === w) this._luckWait = null;
                if (this.winner !== '') return;
                const at = this._slotOf(side, c, slot);
                if (choice !== 'double') {
                    this._luckLast = null;   // (no flip: no "If heads" or "If tails")
                    this._effect(side, c, `${c.name}: no bet, it happens once`, at);
                    this._doFxRun(side, at, c, e, vs);
                    return;
                }
                if (!this._luckGate(side, at, c, e)) return;
                this._doFxRun(side, at, c, e, vs);
                if (this.winner === '') this._doFxRun(side, this._slotOf(side, c, slot), c, e, vs);   // heads: twice
            });
        this._luckWait = w;
    }

    _doFxRun(side, slot, c, e, vs) {
        const then = e.then && typeof e.then === 'object' ? e.then : null;
        if (then == null) { this._doFxOne(side, slot, c, e, vs); return; }
        const did = this._did, asks = this._inAnswer ? this._newAsks : this._asks, queued = asks.length;
        const next = () => { if (this.winner === '') this._doFx(side, this._slotOf(side, c, slot), c, then, vs); };
        this._doFxOne(side, slot, c, e, vs);
        if (this._did > did) next();
        else if (asks.length > queued) {
            const ask = asks[queued], cb = ask.cb;
            ask.cb = (...answer) => { const before = this._did; if (cb) cb(...answer); if (this._did > before) next(); };
        }
    }

    _doFxOne(side, slot, c, e, vs = {}) {
        const s = this.sides[side];
        if (String(e.per ?? '') !== '') {   // "for each ...": nothing to count, nothing happens
            if (this._perCount(side, slot, e) <= 0) return;
            e = this._scaled(side, slot, e);
        }
        const n = Math.max(1, toInt(e.amount ?? 1));
        switch (String(e.do ?? '')) {
            case 'buff': {
                const mod = { atk: toInt(e.atk), def: toInt(e.def), until_turn: this._until(e) };
                const label = statText(mod);
                this._fxApply(side, slot, c, e, vs, 'any', label, (x) => {
                    x.card.mods.push({ ...mod });
                    return `${x.card.name}: ${label}`;
                }, `${c.name}: ${label} to %s`);
                break;
            }
            case 'down':
                this._fxApply(side, slot, c, e, vs, 'standing', 'DOWN', (x) => {
                    x.card.downed = true;
                    x.card.position = 'def';   // a Downed character is in DEF
                    this._emit('downed', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${c.name} Downs ${x.card.name}`;
                }, `${c.name} Downs %s`);
                break;
            case 'ko':
                this._fxApply(side, slot, c, e, vs, 'any', 'KO', (x) => {
                    const name = x.card.name;
                    this._ko(x.side, x.slot);
                    return `${c.name} KOs ${name}`;
                }, `${c.name} KOs %s`);
                break;
            case 'ready':
                // Characters that already attacked this turn may attack again (at most once more each turn)
                this._fxApply(side, slot, c, e, vs, 'spent', 'attack again', (x) => {
                    x.card.has_attacked = false;
                    x.card.again_turn = this.turn;
                    return `${x.card.name} may attack again this turn`;
                }, `${c.name}: %s may attack again this turn`);
                break;
            case 'stand':
                this._fxApply(side, slot, c, e, vs, 'downed', 'stand up', (x) => {
                    x.card.downed = false;
                    delete x.card.down_turns;
                    this._emit('stand', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${x.card.name} stands back up`;
                }, `${c.name}: %s stand back up`);
                break;
            case 'bounce':
                this._fxApply(side, slot, c, e, vs, 'any', 'send back to the hand', (x) => {
                    const name = x.card.name;
                    this._bounce(x.side, x.slot);
                    return `${c.name} sends ${name} back to the hand`;
                }, `${c.name} sends %s back to the hand`);
                break;
            case 'topdeck':   // back on top of its owner's deck: they draw it again
                this._fxApply(side, slot, c, e, vs, 'any', 'put on top of the deck', (x) => {
                    const name = x.card.name;
                    this._topdeck(x.side, x.slot);
                    return `${c.name} puts ${name} on top of its owner's deck`;
                }, `${c.name} puts %s on top of the deck`);
                break;
            case 'exile':   // gone for good: not to the Gutter, so nothing can bring it back
                this._fxApply(side, slot, c, e, vs, 'any', 'remove from the game', (x) => {
                    const name = x.card.name;
                    this._exile(x.side, x.slot);
                    return `${c.name} removes ${name} from the game`;
                }, `${c.name} removes %s from the game`);
                break;
            case 'swap': {   // ATK and DEF trade places (until the end of the turn, the next, or for good)
                const until = this._until(e);
                this._fxApply(side, slot, c, e, vs, 'any', 'swap ATK and DEF', (x) => {
                    x.card.mods.push({ swap: true, until_turn: until });
                    return `${x.card.name}: ATK and DEF swapped`;
                }, `${c.name} swaps the ATK and DEF of %s`);
                break;
            }
            case 'cleanse':   // CLEANSE: its statuses are gone (STASIS, FREEZE, STUN, SUPPRESS, SILENCE, POISON, BURN, BLEED, BOUNTY)
                this._fxApply(side, slot, c, e, vs, 'statused', 'cleanse', (x) => {
                    this._clearStatus(x.card);
                    delete x.card.stun_until;
                    this._emit('cleanse', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${x.card.name} is cleansed`;
                }, `${c.name} cleanses %s`);
                break;
            case 'rewind':   // REWIND: its ATK / DEF changes are undone (back to its printed stats)
                this._fxApply(side, slot, c, e, vs, 'changed', 'rewind', (x) => {
                    x.card.mods = [];
                    this._recalc();
                    this._emit('rewind', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${x.card.name} is rewound to its printed ATK and DEF`;
                }, `${c.name} rewinds %s`);
                break;
            case 'jam':   // JAM: the opponent can't spring Ambushes until the end of their next turn
                for (const foe of this.foesOf(side)) {
                    this.sides[foe].jam_until = this._ownerNextTurn(foe);
                    this._emit('jam', { side: foe, until: this.sides[foe].jam_until });
                }
                this._effect(side, c, `${c.name} JAMS your opponent's Ambushes`, slot);
                break;
            case 'barricade':   // BARRICADE N: the next N Morale damage before your next turn is prevented
                s.barricade = toInt(s.barricade ?? 0) + n;
                this._emit('barricade', { side, amount: s.barricade });
                this._effect(side, c, `${c.name} raises a BARRICADE of ${n}`, slot);
                break;
            case 'bounty':   // BOUNTY X: when it's KO'd, whoever put the bounty on it draws X
                this._fxApply(side, slot, c, e, vs, 'any', 'put a BOUNTY on', (x) => {
                    x.card.bounty = { by: side, n };
                    return `${c.name} puts a BOUNTY of ${n} on ${x.card.name}`;
                }, `${c.name} puts a BOUNTY of ${n} on %s`);
                break;
            case 'force_def':
                this._fxApply(side, slot, c, e, vs, 'attackers', 'force into DEF', (x) => {
                    x.card.position = 'def';
                    x.card.position_turn = this.turn;
                    this._emit('position', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${c.name} forces ${x.card.name} into DEF`;
                }, `${c.name} forces %s into DEF`);
                break;
            case 'stun':
                this._fxApply(side, slot, c, e, vs, 'any', 'stun', (x) => {
                    x.card.stun_until = this._ownerNextTurn(x.side);
                    return `${c.name} stuns ${x.card.name}: it can't attack next turn`;
                }, `${c.name} stuns %s`);
                break;
            case 'shield':
                this._fxApply(side, slot, c, e, vs, 'any', 'shield', (x) => {
                    x.card.shield = true;
                    return `${x.card.name} is shielded from the next defeat`;
                }, `${c.name} shields %s`);
                break;
            case 'influence': {
                // A Dormant leader regains Influence, up to what it started with
                const l = s.leader;
                if (s.leader_state !== 'dormant' || l == null) break;
                const gain = Math.min(n, toInt(l.influence_max ?? l.influence) - toInt(l.influence));
                if (gain <= 0) break;
                l.influence += gain;
                this._effect(side, c, `${c.name}: ${l.name} regains ${gain} Influence`, slot);
                this._emit('leader_heal', { side, amount: gain, influence: l.influence });
                break;
            }
            case 'ramp': {
                // More Authority every turn from now on (and this turn)
                const before = s.authority_max;
                s.authority_max = Math.min(MAX_AUTHORITY, s.authority_max + n);
                const d = s.authority_max - before;
                if (d <= 0) break;
                s.authority += d;
                this._effect(side, c, `${c.name}: +${d} max Authority`, slot);
                this._emit('authority', { side, value: s.authority, max: s.authority_max, delta: d });
                break;
            }
            case 'silence':
                this._fxApply(side, slot, c, e, vs, 'any', 'silence', (x) => {
                    x.card.silence_until = this.turn + (String(e.until ?? 'turn') === 'next_turn' ? this._roundSpan() : 0);
                    this._recalc();
                    return `${c.name} silences ${x.card.name}: its effects stop`;
                }, `${c.name} silences %s`);
                break;
            case 'draw':
                this._effect(side, c, `${c.name}: draw ${n}`, slot);
                for (let i = 0; i < n; i++) this._draw(side);
                break;
            case 'loot': {   // draw N, then discard discard_n (as many as drawn unless set; 0: none)
                const d = Math.max(0, toInt(e.discard_n ?? n));
                this._effect(side, c, `${c.name}: draw ${n}, then discard ${d}`, slot);
                for (let i = 0; i < n && this.winner === ''; i++) this._draw(side);
                const k = Math.min(d, s.hand.length);
                if (k > 0 && this.winner === '') this._askDiscard(side, k, null, `${c.name}: loot`);
                break;
            }
            case 'search': {
                const found = this._fxTake(side, c, e, s.deck, `${c.name}: choose a card to add to your hand`, (card) => {
                    s.hand.push(card);
                    // What it found stays hidden from the other players, unless the card says to reveal it
                    this._effect(side, c, `${c.name}: searches the deck for ${card.name}`, slot,
                        e.reveal === true ? '' : `${c.name}: searches the deck for a card`);
                    this._emit('draw', { side, card: clone(card), opening: false });
                    return true;
                }, () => this._shuffleDeck(side));
                if (!found) this._emit('effect', { side, card: clone(c), text: `${c.name}: nothing to find in the deck`, slot });   // (not something done)
                break;
            }
            case 'revive':
            case 'call': {
                // A character from your Gutter (revive) or deck (call) onto the field, in the first
                // empty lane, in ATK
                if (this._emptyLane(side) < 0) break;
                const fromDeck = String(e.do ?? '') === 'call';
                const pile = fromDeck ? s.deck : s.gutter;
                this._fxTake(side, c, e, pile, `${c.name}: choose a character to ${fromDeck ? 'call in' : 'bring back'}`, (card) => {
                    const lane = this._emptyLane(side);
                    if (lane < 0) { pile.push(card); return false; }
                    card.downed = false;
                    card.mods = [];
                    this._clearStatus(card);
                    delete card.fx_count;
                    if (!fromDeck) this._emit('recover', { side, card: clone(card) });
                    card.position = 'atk';
                    card.face_down = false;
                    card.has_attacked = false;
                    card.deployed_turn = this.turn;
                    s.field[lane] = card;
                    const ev = { side, slot: lane, card: clone(card) };
                    if (fromDeck) ev.from = 'deck';
                    this._emit('summon', ev);
                    this._effect(side, c, fromDeck ? `${c.name}: ${card.name} is called in` : `${c.name}: ${card.name} is back on the street`, slot);
                    this._recalc();
                    return true;
                }, fromDeck ? () => this._shuffleDeck(side) : null);
                break;
            }
            case 'token': {
                // Copies of a token card (Card Forge: marked Token, never in packs or decks) in the
                // first empty lanes, in ATK. They vanish when they leave the field.
                const spec = String(e.token ?? '');
                if (spec === '' || !CARD_CATALOG[spec]) break;
                let made = 0;
                for (let i = 0; i < Math.min(n, FRONT.length); i++) {
                    const lane = this._emptyLane(side);
                    if (lane < 0) break;
                    const t = this.makeCard(spec);
                    t.token = true;
                    t.deployed_turn = this.turn;
                    s.field[lane] = t;
                    this._emit('summon', { side, slot: lane, card: clone(t), from: 'token' });
                    made += 1;
                }
                if (made > 0) {
                    this._effect(side, c, `${c.name}: ${made} ${CARD_CATALOG[spec].name ?? 'token'} token${made === 1 ? '' : 's'} join${made === 1 ? 's' : ''} the fight`, slot);
                    this._recalc();
                }
                break;
            }
            case 'break_ambush':
            case 'shatter':
            case 'wreck': {
                // The opponent's face-down cards in the back row (break_ambush), its face-up Continuous and
                // Equip cards (shatter), or either (wreck), left to right
                const kind = String(e.do);
                const hit = (a) => a != null && (kind === 'wreck' || !!a.face_down === (kind === 'break_ambush'));
                this._withFoe(side, c, vs, (f) => BACK.some(b => hit(this.sides[f].field[b])), (foe) => {
                    let k = n;
                    for (const b of BACK) {
                        const a = this.sides[foe].field[b];
                        if (k <= 0 || !hit(a)) continue;
                        this.sides[foe].field[b] = null;
                        this.sides[foe].gutter.push(a);
                        const up = !a.face_down;
                        if (up) delete a.equipped_to;
                        this._emit('ko', { side: foe, slot: b, card: clone(a) });
                        this._effect(side, c, up ? `${c.name}: destroys ${a.name}` : `${c.name}: destroys a face-down card`, slot);
                        k -= 1;
                    }
                    this._recalc();   // (what a face-up one gave is gone)
                });
                break;
            }
            case 'recover': {
                const back = this._fxTake(side, c, e, s.gutter, `${c.name}: choose a card to return to your hand`, (card) => {
                    card.downed = false;
                    card.mods = [];
                    s.hand.push(card);
                    this._effect(side, c, `${c.name}: ${card.name} returns to the hand`, slot);
                    this._emit('recover', { side, card: clone(card) });
                    return true;
                });
                if (back) return;
                break;
            }
            case 'discard':
                this._withFoe(side, c, vs, (f) => this.sides[f].hand.length > 0, (foe) => {
                    const k = Math.min(n, this.sides[foe].hand.length);
                    this._effect(side, c, `${c.name}: your opponent discards ${k}`, slot);
                    this._askDiscard(foe, k, null, `${c.name} makes you discard`);
                });
                break;
            case 'mill':
                this._withFoe(side, c, vs, (f) => this.sides[f].deck.length > 0, (foe) => {
                    const fd = this.sides[foe].deck;
                    const lost = Math.min(n, fd.length);
                    this._effect(side, c, `${c.name}: your opponent loses ${lost} card${lost === 1 ? '' : 's'} from the deck`, slot);
                    for (let i = 0; i < lost; i++) {
                        const milled = fd.pop();
                        this.sides[foe].gutter.push(milled);
                        this._emit('mill', { side: foe, card: clone(milled) });
                    }
                });
                break;
            case 'damage':
                this._withFoe(side, c, vs, () => true, (foe) => {
                    this._effect(side, c, `${c.name}: ${n} Morale damage`, slot);
                    this._damage(foe, n);
                });
                break;
            case 'heal':
                this._heal(side, c, n, slot);
                break;
            case 'drain':
                this._withFoe(side, c, vs, () => true, (foe) => {
                    this._effect(side, c, `${c.name} drains ${n} Morale`, slot);
                    this._damage(foe, n);
                    if (this.winner === '') this._heal(side, c, n, slot);
                });
                break;
            case 'authority':
                s.authority += n;
                this._effect(side, c, `${c.name}: +${n} Authority this turn`, slot);
                this._emit('authority', { side, value: s.authority, max: s.authority_max, delta: n });
                break;
            case 'promote':
                if (this.cardAt(side, slot) === c) this._promote(side, slot, c.name);
                break;
            case 'attack_again':
                // At most one extra attack per card each turn, so no trigger can attack forever
                if (this.cardAt(side, slot) === c && c.has_attacked && c.again_turn !== this.turn) {
                    c.has_attacked = false;
                    c.again_turn = this.turn;
                    this._effect(side, c, `${c.name} may attack again this turn`, slot);
                }
                break;
            case 'poison': case 'burn': {
                const kind = String(e.do);
                this._fxApply(side, slot, c, e, vs, 'any', kind.toUpperCase(), (x) => {
                    const cur = x.card[kind] || {};
                    x.card[kind] = { amt: Math.max(n, toInt(cur.amt ?? 0)), left: STATUS_TICKS };
                    this._emit('status', { side: x.side, slot: x.slot, kind, card: clone(x.card) });
                    return kind === 'poison' ? `${x.card.name} is POISONED: -${n} ATK each turn`
                        : `${x.card.name} is BURNING: its owner loses ${n} Morale each turn`;
                }, `${c.name} ${kind === 'poison' ? 'poisons' : 'burns'} %s`);
                break;
            }
            case 'bleed':
                this._fxApply(side, slot, c, e, vs, 'any', 'BLEED', (x) => {
                    x.card.bleed = Math.max(n, toInt(x.card.bleed ?? 0));
                    this._emit('status', { side: x.side, slot: x.slot, kind: 'bleed', card: clone(x.card) });
                    return `${x.card.name} is BLEEDING: -${n} ATK / DEF after every brawl`;
                }, `${c.name} makes %s bleed`);
                break;
            case 'shock':
                this._fxApply(side, slot, c, e, vs, 'any', 'SHOCK', (x) => {
                    this._emit('status', { side: x.side, slot: x.slot, kind: 'shock', card: clone(x.card) });
                    if (!x.card.downed && n >= toInt(x.card.defense ?? 0) && !this._staysUp(x.side, x.slot, x.card)) {
                        x.card.downed = true;
                        x.card.position = 'def';   // a Downed character is in DEF
                        this._emit('downed', { side: x.side, slot: x.slot, card: clone(x.card) });
                        return `${c.name} SHOCKS ${x.card.name}: it goes Down`;
                    }
                    x.card.mods.push({ atk: 0, def: -n, until_turn: this.turn });
                    this._recalc();
                    return `${c.name} SHOCKS ${x.card.name}: -${n} DEF this turn`;
                }, `${c.name} shocks %s`);
                break;
            case 'force_atk':
                // Pulled out of cover: a face-up character in DEF switches to ATK
                this._fxApply(side, slot, c, e, vs, 'defenders', 'force into ATK', (x) => {
                    x.card.position = 'atk';
                    x.card.position_turn = this.turn;
                    this._emit('position', { side: x.side, slot: x.slot, card: clone(x.card) });
                    return `${c.name} forces ${x.card.name} into ATK`;
                }, `${c.name} forces %s into ATK`);
                break;
            case 'suppress':
                // SUPPRESS X (Militia): pinned down through its owner's next turn: -X ATK and it can't attack
                this._fxApply(side, slot, c, e, vs, 'any', 'SUPPRESS', (x) => {
                    const untilTurn = this._ownerNextTurn(x.side);
                    x.card.suppress_until = untilTurn;
                    x.card.mods.push({ atk: -n, def: 0, until_turn: untilTurn });
                    this._emit('status', { side: x.side, slot: x.slot, kind: 'suppress', card: clone(x.card) });
                    this._recalc();
                    return `${x.card.name} is SUPPRESSED: -${n} ATK and it can't attack through its owner's next turn`;
                }, `${c.name} suppresses %s`);
                break;
            case 'freeze':
                this._fxApply(side, slot, c, e, vs, 'any', 'FREEZE', (x) => {
                    x.card.freeze_until = this._ownerNextTurn(x.side);
                    this._emit('status', { side: x.side, slot: x.slot, kind: 'freeze', card: clone(x.card) });
                    if (x.card.position !== 'def') {
                        x.card.position = 'def';
                        x.card.position_turn = this.turn;
                        this._emit('position', { side: x.side, slot: x.slot, card: clone(x.card) });
                    }
                    return `${x.card.name} is FROZEN in DEF through its owner's next turn`;
                }, `${c.name} freezes %s`);
                break;
            case 'stasis':
                this._fxApply(side, slot, c, e, vs, 'any', 'STASIS', (x) => {
                    x.card.stasis_until = this._ownerNextTurn(x.side);
                    this._emit('status', { side: x.side, slot: x.slot, kind: 'stasis', card: clone(x.card) });
                    return `${x.card.name} is in STASIS until its owner's next turn ends`;
                }, `${c.name} puts %s in STASIS`);
                break;
        }
    }

    // The last turn a change lasts: this turn, through the next one, or (forever) while the card stays on the field
    _until(e) {
        const u = String(e.until ?? 'turn');
        return u === 'next_turn' ? this.turn + this._roundSpan() : u === 'forever' ? FOREVER : this.turn;
    }

    /** The turn on which side's next turn ends (two players: the active one's is 2 away, the other's 1). */
    _ownerNextTurn(side) {
        if (side === this.active) return this.turn + Math.max(2, this._alive().length);
        let d = 1;
        for (let s = this._nextSeat(this.active); s !== side && d < this.seats.length; s = this._nextSeat(s)) d += 1;
        return this.turn + d;
    }

    _clearStatus(c) { for (const k of STATUS_KEYS) delete c[k]; }

    _statusTicks(side) {
        for (const e of this.characters(side)) {
            const c = e.card;
            for (const kind of ['poison', 'burn']) {
                if (this.winner !== '' || c[kind] === undefined) continue;
                const st = c[kind];
                const amt = toInt(st.amt);
                st.left = toInt(st.left) - 1;
                if (toInt(st.left) <= 0) delete c[kind];
                this._emit('status_tick', { side, slot: e.slot, kind, amount: amt, card: clone(c) });
                if (kind === 'poison') c.mods.push({ atk: -amt, def: 0, until_turn: FOREVER });
                else this._damage(side, amt);
            }
        }
    }

    _fxApply(side, slot, c, e, vs, poolKind, what, fn, allText) {
        const target = String(e.target ?? 'self');
        const entries = this._fxTargets(side, slot, c, e, vs, poolKind);
        if ((target === 'ally' || target === 'enemy') && this._equippedEntry(c)) {   // an Equip: its own character, no choice
            for (const x of entries) this._effect(side, c, fn(x), slot);
        } else if (target === 'ally' || target === 'enemy') {
            entries.sort((a, b) => {
                const va = this._targetValue(side, e, a), vb = this._targetValue(side, e, b);
                return va !== vb ? vb - va : (this.seats.indexOf(a.side) - this.seats.indexOf(b.side)) || a.slot - b.slot;
            });
            const on = target === 'ally' ? side : (this.foesOf(side)[0] ?? side);
            this._askTarget(side, 'fx', `${c.name}: choose ${target === 'ally' ? 'an ally' : 'an enemy'} (${what})`, c,
                entries, on, (x) => this._effect(side, c, fn(x), slot), true);
        } else if (target === 'allies' || target === 'enemies' || target === 'all') {
            let count = 0;
            for (const x of entries) {   // (one a chained trigger already removed is skipped)
                if (this.winner !== '' || this.cardAt(x.side, x.slot) !== x.card) continue;
                fn(x);
                count += 1;
            }
            if (count > 0) {
                const who = target === 'allies' ? `${count} of your characters`
                    : target === 'all' ? `${count} character${count === 1 ? '' : 's'}` : `${count} enem${count === 1 ? 'y' : 'ies'}`;
                this._effect(side, c, allText.replace('%s', who), slot);
            }
        } else {
            for (const x of entries) this._effect(side, c, fn(x), slot);
        }
    }

    // The characters effect e of card c would affect, before choosing one (same as _fx_targets)
    /** An effect's "only ones ..." limit: statused, def, atk, downed, standing */
    _onlyFits(c, only) {
        switch (only) {
            case 'statused': return this._afflicted(c);
            case 'def': return c.position === 'def' && !c.downed;
            case 'atk': return c.position === 'atk' && !c.downed;
            case 'downed': return !!c.downed;
            case 'standing': return !c.downed;
        }
        return true;
    }

    /** The character an Equip is on, as {side, slot, card}; null for anything else. */
    _equippedEntry(c) {
        if (!c || String(c.subtype ?? '') !== 'equip' || c.equipped_to == null) return null;
        for (const s of Object.keys(this.sides)) for (const x of this.characters(s)) {
            if (toInt(x.card.uid) === toInt(c.equipped_to)) return { side: s, slot: x.slot, card: x.card };
        }
        return null;
    }

    _fxTargets(side, slot, c, e, vs, poolKind) {
        const target = String(e.target ?? 'self');
        const only = String(e.only ?? '');
        const pick = (x) => {
            // "only ones with a status / in DEF position / ...": the card's own limit, on top of the action's
            if (only !== '' && !this._onlyFits(x.card, only)) return false;
            switch (poolKind) {
                case 'standing': return !x.card.downed;
                case 'downed': return !!x.card.downed;
                case 'attackers': return x.card.position === 'atk' && !x.card.downed;
                case 'defenders': return x.card.position === 'def' && !x.card.downed && !x.card.face_down && !this.frozen(x.card);
                case 'spent': return !!x.card.has_attacked && !x.card.downed && (x.card.again_turn ?? 0) !== this.turn;
                case 'statused': return this._afflicted(x.card);
                case 'changed': {   // REWIND helps: an enemy's net gains, your character's net losses
                    const net = (x.card.mods || []).reduce((t, m) => t + toInt(m.atk) + toInt(m.def), 0);
                    return x.side === side ? net < 0 : net > 0;
                }
            }
            return true;
        };
        let entries = [];
        const worn = ['self', 'ally', 'enemy'].includes(target) ? this._equippedEntry(c) : null;
        if (worn) entries = [worn];   // an Equip's "this card" / "one ally" / "one enemy" is the character it's on
        else switch (target) {
            case 'self':
                if (this.cardAt(side, slot) === c) entries = [{ side, slot, card: c }];
                break;
            case 'attacker':
                if (vs && vs.card && this.cardAt(vs.side, vs.slot) === vs.card) entries = [{ side: vs.side, slot: vs.slot, card: vs.card }];
                break;
            case 'ally': case 'allies':
                entries = this._fxPool(side, e, slot).map(x => ({ side, slot: x.slot, card: x.card }));
                break;
            case 'enemy': case 'enemies':
                for (const foe of this.foesOf(side)) entries.push(...this._fxPool(foe, e, -99).map(x => ({ side: foe, slot: x.slot, card: x.card })));
                break;
            case 'all':   // every character: yours (not this card) and every opponent's
                entries = this._fxPool(side, e, slot).map(x => ({ side, slot: x.slot, card: x.card }));
                for (const foe of this.foesOf(side)) entries.push(...this._fxPool(foe, e, -99).map(x => ({ side: foe, slot: x.slot, card: x.card })));
                break;
        }
        const what_ = String(e.do ?? '');
        // (a leader on the field can be affected like any character, but has no hand to go back to)
        // (STASIS can't be targeted, except to be cleansed of it)
        entries = entries.filter(x => pick(x) && !(x.card.cardType === 'leader' && ['bounce', 'topdeck', 'exile'].includes(what_))
            && (what_ === 'cleanse' || !this.inStasis(x.card)));
        // immune: to the statuses it lists (none listed: all of them)
        const covers = (im) => !Array.isArray(im.statuses) || !im.statuses.length || im.statuses.includes(what_);
        if (IMMUNE_TO.includes(what_)) entries = entries.filter(x => !this._passive(x.side, x.slot, x.card, 'immune', covers));
        if (what_ === 'down') entries = entries.filter(x => !this._staysUp(x.side, x.slot, x.card));
        if (target === 'attacker') entries = entries.filter(x => x.side === side || !this._passive(x.side, x.slot, x.card, 'untargetable'));
        return entries;
    }

    // Same as _target_value in duel_state.gd
    _targetValue(side, e, x) {
        const c = x.card;
        const value = attackValue(c);
        const standingAtk = !c.downed && c.position === 'atk';
        switch (String(e.do ?? '')) {
            case 'shock':
                if (!c.downed && Math.max(1, toInt(e.amount ?? 1)) >= toInt(c.defense ?? 0)) return 100000 + value;
                break;
            case 'stasis':
                if (x.side === side) return (c.downed ? 100000 : 0) + value;
                return (standingAtk ? 100000 : 0) + value;
            case 'poison': case 'bleed':
                if (c[e.do] !== undefined) return value - 50000;
                if (c.downed) return value - 20000;
                break;
            case 'burn':
                if (c.burn !== undefined) return toInt(c.defense ?? 0) - 50000;
                return (c.downed ? 0 : 10000) + toInt(c.defense ?? 0);
            case 'freeze': case 'stun': {
                const key = e.do === 'freeze' ? 'freeze_until' : 'stun_until';
                if (toInt(c[key] ?? 0) >= this.turn) return value - 50000;
                if (standingAtk) return 100000 + value;
                break;
            }
            case 'shield':
                if (c.shield) return value - 50000;
                break;
        }
        return value;
    }

    _fxKindOk(card, e) {
        const kind = ['revive', 'call'].includes(String(e.do ?? '')) ? 'gang_member' : String(e.kind ?? '');
        const clan = String(e.clan ?? '');
        if (!((kind === '' || card.cardType === kind) && (clan === '' || card.clanTag === clan) && card.cardType !== 'leader')) return false;
        // search / recover / revive filters: Authority N or less, role, level, name
        if (e.max_auth != null && toInt(card.authority) > toInt(e.max_auth)) return false;
        if (String(e.role ?? '') !== '' && (card.cardType !== 'gang_member' || String(card.subtype ?? 'brawler') !== String(e.role))) return false;
        if (e.level != null && (card.cardType !== 'gang_member' || Math.max(1, toInt(card.level)) !== toInt(e.level))) return false;
        if (String(e.name ?? '') !== '' && !String(card.name ?? '').toLowerCase().includes(String(e.name).toLowerCase())) return false;
        return true;
    }

    /** search / recover / revive: take matching cards from a pile (top first), `amount` times;
     *  with `choose` the player picks each one (options best first, so the CPU takes the best).
     *  Same as _fx_take in duel_state.gd. */
    // after: once it's done (every card taken, or skipped), when it looked through the pile (a deck is
    // shuffled then)
    _fxTake(side, c, e, pile, prompt, take, after = null, left = Math.max(1, toInt(e.amount ?? 1))) {
        const matches = [];
        for (let i = pile.length - 1; i >= 0; i--) if (pile[i] !== c && this._fxKindOk(pile[i], e)) matches.push(pile[i]);
        if (!matches.length) {
            if (after && left < Math.max(1, toInt(e.amount ?? 1))) after();   // (found some before)
            return false;
        }
        const done = () => { if (after) after(); };
        const next = (card) => {
            const i = pile.findIndex(x => x.uid === card.uid);
            if (i < 0 || !take(pile.splice(i, 1)[0])) return done();
            if (left > 1) this._fxTake(side, c, e, pile, prompt, take, after, left - 1);
            else done();
        };
        if (!e.choose) {
            next(matches[0]);
            return true;
        }
        const seen = new Set(), opts = [];
        matches.forEach((m, k) => { const key = `${m.id}|${m.name}`; if (!seen.has(key)) { seen.add(key); opts.push({ m, k }); } });
        opts.sort((a, b) => (toInt(b.m.authority) - toInt(a.m.authority)) || (toInt(b.m.base_attack) - toInt(a.m.base_attack)) || (a.k - b.k));
        const shown = opts.slice(0, 8);
        // (each option carries its card: the player sees the cards to choose from)
        this._ask(side, 'fx_pick', prompt, c, [...shown.map((o, k) => ({ id: String(k), label: `${String(o.m.name).toUpperCase()}  (${toInt(o.m.authority)})`, card: clone(o.m) })),
            { id: 'skip', label: 'SKIP' }],
            (choice) => { const o = choice === 'skip' ? null : shown[toInt(choice)]; if (o) next(o.m); else done(); });
        return true;
    }

    /** A deck that was searched is shuffled (not in the engines' comparison games, which keep a fixed order). */
    _shuffleDeck(side) {
        if (!this._fixedOrder) shuffle(this.sides[side].deck, this._rand);
        this._emit('shuffle', { side });
    }

    _heal(side, c, n, slot) {
        const s = this.sides[side];
        const gain = Math.min(n, START_MORALE - s.morale);
        if (gain > 0) {
            s.morale += gain;
            this._effect(side, c, `${c.name}: +${gain} Morale`, slot);
            this._emit('heal', { side, amount: gain, morale: s.morale });
        }
    }

    _bounce(side, slot) {
        const c = this.cardAt(side, slot);
        this.sides[side].field[slot] = null;
        if (c.token) {   // a token has no hand to go back to: it vanishes
            this._emit('ko', { side, slot, card: clone(c) });
            return;
        }
        c.downed = false;
        c.mods = [];
        c.position = 'atk';
        c.face_down = false;
        c.has_attacked = false;
        for (const k of ['shield', 'stun_until', 'down_turns', 'kings_test', 'fx_used', 'fx_count']) delete c[k];
        this._clearStatus(c);
        this.sides[side].hand.push(c);
        this._emit('bounce', { side, slot, card: clone(c) });
    }

    _auras(side) {
        const s = this.sides[side];
        const out = [];
        for (const x of this.characters(side)) {
            if (x.card.face_down) continue;
            for (const e of this._fx(x.card, 'passive')) {
                if (String(e.do ?? '') === 'buff' && this._fxCond(side, x.slot, e, null)) out.push([x.slot, this._scaled(side, x.slot, e)]);
            }
        }
        if (s.leader_state === 'dormant' && s.leader != null) {
            for (const e of this._fx(s.leader, 'dormant')) {   // (its "passive" effects work once it's on the field)
                if (String(e.do ?? '') === 'buff' && this._fxCond(side, -1, e, null)) out.push([-1, this._scaled(side, -1, e)]);
            }
        }
        for (const x of this._lasting(side, 'continuous')) {   // (from the back row: they reach every character)
            for (const e of this._fx(x.card, 'passive')) {
                if (String(e.do ?? '') === 'buff' && this._fxCond(side, x.slot, e, null)) out.push([x.slot, this._scaled(side, x.slot, e)]);
            }
        }
        return out;
    }

    _auraHits(a, slot, c) {
        const e = a[1];
        const clan = String(e.clan ?? '');
        if (clan !== '' && c.clanTag !== clan) return false;
        switch (String(e.target ?? 'self')) {
            case 'self': return a[0] === slot;
            case 'allies': return a[0] !== slot;
        }
        return false;
    }

    _slotOf(side, c, fallback) {
        for (const slot of FRONT) if (this.sides[side].field[slot] === c) return slot;
        return fallback;
    }

    // ── Turn flow ──────────────────────────────────────────────────────────

    _beginTurn() {
        const s = this.sides[this.active];
        s.promoted = {};
        s.mentor_used = false;
        s.turns = toInt(s.turns) + 1;
        if (toInt(s.barricade ?? 0) > 0) {   // (it lasts until your next turn)
            s.barricade = 0;
            this._emit('barricade', { side: this.active, amount: 0 });
        }
        this._setPhase('upkeep');
        this._emit('turn', { side: this.active, turn: this.turn });
        if (s.turns > 1) {   // (every turn but your first)
            s.authority_max = Math.min(MAX_AUTHORITY, s.authority_max + 1);
            s.authority = s.authority_max;
            this._emit('authority', { side: this.active, value: s.authority, max: s.authority_max, delta: 1 });
        }
        // Going second (or later) is a disadvantage; one extra Authority on that player's first turn
        if (s.turns === 1 && this.active !== this.first && SECOND_PLAYER_AUTHORITY > 0) {
            s.authority = s.authority_max + SECOND_PLAYER_AUTHORITY;
            this._emit('authority', { side: this.active, value: s.authority, max: s.authority_max, delta: SECOND_PLAYER_AUTHORITY });
        }
        if (this.turn > 1) this._draw(this.active);
        // A Downed character stays down for a full round, then gets back up in DEF position
        // at the start of its owner's turn (its owner may switch it to ATK straight away)
        for (const e of this.characters(this.active)) {
            if (!e.card.downed) {
                delete e.card.down_turns;
            } else if (toInt(e.card.down_turns) >= 1) {
                e.card.downed = false;
                delete e.card.down_turns;
                e.card.position = 'def';
                this._emit('stand', { side: this.active, slot: e.slot, card: clone(e.card) });
            } else {
                e.card.down_turns = 1;
            }
        }
        this._statusTicks(this.active);
        if (this.winner !== '') return;
        for (const e of this.characters(this.active)) this._runFx(this.active, e.slot, e.card, 'turn_start');
        this._runLasting(this.active, 'turn_start');
        this._leaderFx(this.active, 'dormant_turn_start');
        for (const e of this.characters(this.active)) {
            if (e.card.kings_test) {
                delete e.card.kings_test;
                const side = this.active;
                const slot = e.slot;
                this._ask(side, 'kings_test', `King's Test: promote ${e.card.name} now?`, e.card, [
                    { id: 'yes', label: 'PROMOTE', side, slot }, { id: 'no', label: 'NOT NOW' },
                ], (choice) => {
                    if (choice === 'yes') this._promote(side, slot, "King's Test");
                });
            }
        }
        this._checkAwaken(this.active);
        this._recalc();
        this._setPhase('deployment');
    }

    _endTurn() {
        for (const e of this.characters(this.active)) this._runFx(this.active, e.slot, e.card, 'turn_end');
        this._runLasting(this.active, 'turn_end');
        for (const foe of this.foesOf(this.active)) {
            for (const e of this.characters(foe)) this._runFx(foe, e.slot, e.card, 'foe_turn_end');
            this._runLasting(foe, 'foe_turn_end');
        }
        this._leaderFx(this.active, 'dormant_turn_end');
        if (this.winner !== '') return;
        const s = this.sides[this.active];
        for (const c of s.field) if (c != null) c.has_attacked = false;
        s.brutus_bonus = 0;
        for (const side of Object.keys(this.sides)) {
            for (const c of this.sides[side].field) {
                if (c != null) c.mods = c.mods.filter(m => m.until_turn > this.turn);
            }
        }
        this.active = this._nextSeat(this.active);
        this.turn += 1;
        this._beginTurn();
    }

    _setPhase(p) {
        this.phase = p;
        this._emit('phase', { phase: p, side: this.active });
    }

    // ── Prompts ────────────────────────────────────────────────────────────

    _ask(side, key, prompt, card, options, cb) {
        const ask = { kind: 'choose', side, key, prompt, options, card: clone(card), cb };
        if (this._inAnswer) this._newAsks.push(ask);
        else this._asks.push(ask);
        return ask;
    }

    /** optional: the player always chooses (even from one) and may skip it (a card effect's target). */
    /** Entries may carry their own side (FFA: cards on several opponents' boards; their option ids
     *  are then "side:slot"); otherwise they're on targetSide. */
    _askTarget(side, key, prompt, source, entries, targetSide, cb, optional = false) {
        const sideOf = (e) => e.side ?? targetSide;
        // Your opponent's effects can't choose a card that can't be targeted
        entries = entries.filter(e => sideOf(e) === side || !this._passive(sideOf(e), e.slot, e.card, 'untargetable'));
        if (!entries.length) return;
        if (entries.length === 1 && !optional) {
            cb(entries[0]);
            return;
        }
        const multi = new Set(entries.map(sideOf)).size > 1;
        const idOf = (e) => (multi ? `${sideOf(e)}:${e.slot}` : String(e.slot));
        const options = entries.map(e => ({
            id: idOf(e), label: `${String(e.card.name).toUpperCase()}  (${e.card.attack} / ${e.card.defense})`,
            side: sideOf(e), slot: e.slot,
        }));
        if (optional) options.push({ id: 'skip', label: 'SKIP' });
        this._ask(side, key, prompt, source, options, (choice) => {
            for (const e of entries) {
                if (idOf(e) === choice && this.cardAt(sideOf(e), e.slot) === e.card) cb(e);
            }
        });
    }

    // Opening hand: keep it, or shuffle it back and draw the same number again (once).
    // The suggested choice comes first: redraw when nothing in hand is cheap enough to play early.
    _askMulligan(side, then) {
        const keep = { id: 'keep', label: 'KEEP THIS HAND' };
        const redraw = { id: 'redraw', label: `REDRAW: SHUFFLE BACK AND DRAW ${this.sides[side].hand.length}` };
        const cheap = this.sides[side].hand.some(c => c.cardType === 'gang_member' && toInt(c.authority) <= 2);
        this._ask(side, 'mulligan', 'Your opening hand. Keep it, or shuffle it back and draw a new one?', {},
            cheap ? [keep, redraw] : [redraw, keep], (choice) => {
                if (choice === 'redraw') this._mulligan(side);
                then();
            });
    }

    _mulligan(side) {
        const s = this.sides[side];
        const n = s.hand.length;
        for (const c of s.hand) s.deck.unshift(c); // to the bottom: draws come off the back
        s.hand = [];
        if (!this._fixedOrder) shuffle(s.deck, this._rand);
        this._emit('mulligan', { side, count: n });
        for (let i = 0; i < n; i++) this._draw(side, true);
    }

    /** why: what the prompt says first, so the player knows what's making them discard. */
    _askDiscard(side, count, then, why = '') {
        const choose = `Choose ${count} card${count === 1 ? '' : 's'} to discard`;
        const ask = { kind: 'discard', side, count, cb: then, prompt: why ? `${why}. ${choose}` : choose };
        if (this._inAnswer) this._newAsks.push(ask);
        else this._asks.push(ask);
    }

    _answer(side, option) {
        if (this.pending.kind !== 'choose' || this.pending.side !== side) return false;
        if (!this.pending.options.some(o => o.id === option)) return false;
        const cb = this.pending.cb;
        this._emit('answered', { side, key: this.pending.key, option });
        this.pending = {};
        this._runAnswer(() => cb(option));
        return true;
    }

    _chooseDiscard(side, uid) {
        if (this.pending.kind !== 'discard' || this.pending.side !== side) return false;
        const i = this._handIndex(side, uid);
        if (i < 0) return false;
        this._discardAt(side, i);
        this.pending.count -= 1;
        if (this.pending.count > 0 && this.sides[side].hand.length) {
            this.pending.prompt = `Choose ${this.pending.count} more card${this.pending.count === 1 ? '' : 's'} to discard`;
            this._emit('prompt', promptEvent(this.pending));
            return true;
        }
        const cb = this.pending.cb;
        this.pending = {};
        if (cb) this._runAnswer(cb);
        return true;
    }

    _runAnswer(cb) {
        this._inAnswer = true;
        this._newAsks = [];
        cb();
        this._inAnswer = false;
        this._asks = [...this._newAsks, ...this._asks];
        this._newAsks = [];
    }

    _flushAsks() {
        while (isEmpty(this.pending) && this._asks.length && this.winner === '') {
            const ask = this._asks.shift();
            if (ask.still && !ask.still()) continue;   // no longer applies (e.g. a promotion whose card went Down)
            if (ask.kind === 'discard' && !this.sides[ask.side].hand.length) {
                if (ask.cb) this._runAnswer(ask.cb);
                continue;
            }
            this.pending = ask;
            this._emit('prompt', promptEvent(ask));
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    _draw(side, opening = false) {
        const s = this.sides[side];
        if (!s.deck.length) {
            // Decked out: a player who has to draw from an empty deck loses
            if (this.winner === '') this._lose(side, 'deck_out');
            return;
        }
        const c = s.deck.pop();
        s.hand.push(c);
        this._emit('draw', { side, card: clone(c), opening });
    }

    _discardAt(side, i) {
        const c = this.sides[side].hand.splice(i, 1)[0];
        this.sides[side].gutter.push(c);
        this._emit('discard', { side, card: clone(c) });
    }

    _spend(side, amount) {
        if (amount <= 0) return;
        const s = this.sides[side];
        s.authority = Math.max(0, s.authority - amount);
        this._emit('authority', { side, value: s.authority, max: s.authority_max, delta: -amount });
    }

    /**
     * Luck (Card Forge, same as _luck_gate in duel_state.gd): whether an effect happens.
     *   luck: 'coin' (heads: it happens) | 'die' (it happens on luck_on or more, 1-6; 'for each
     *   pip' (per: 'roll') multiplies it by the die) | 'double' (DOUBLE OR NOTHING: a coin; heads, it
     *   happens twice: see _doFx). if_luck: 'won' | 'lost': no roll of its own, it follows the last
     *   flip or roll ("If tails, ..."). Anything else always happens. LOADED DICE (a passive): once per
     *   turn, a side's lost flip or roll is tried again.
     */
    _luckGate(side, slot, c, e) {
        const follow = String(e.if_luck ?? '');
        if (follow !== '') {
            if (!this._luckLast) return false;
            this._roll = this._luckLast.value;
            return follow === 'lost' ? !this._luckLast.won : this._luckLast.won;
        }
        const kind = String(e.luck ?? '');
        if (kind !== 'coin' && kind !== 'die' && kind !== 'double' && String(e.per ?? '') !== 'roll') return true;
        const coin = kind === 'coin' || kind === 'double';
        const need = coin ? 1 : Math.max(1, Math.min(6, toInt(e.luck_on ?? 1)));
        const toss = (again = false) => {
            const r = this._luck();
            const value = coin ? (r < 0.5 ? 1 : 0) : 1 + Math.floor(r * 6);   // coin: 1 heads, 0 tails
            const won = value >= need;
            if (won && this.sides[side]) this.sides[side].luck_won = toInt(this.sides[side].luck_won ?? 0) + 1;   // (a leader can Awaken on it)
            this._luckLast = { won, value };
            this._roll = value;
            const ev = { side, slot, card: clone(c), kind: coin ? 'coin' : 'die', value, need, won };
            if (kind === 'double') ev.double = true;   // (the game shows the stakes: DOUBLE! or nothing)
            if (again) ev.again = true;                // (a LOADED DICE re-roll)
            this._emit('luck', ev);
            this._effect(side, c, coin ? `${c.name} flips a coin: ${value ? 'HEADS' : 'TAILS'}`
                : `${c.name} rolls a ${value}${need > 1 ? (won ? ` (${need}+ needed)` : ` (needed ${need}+)`) : ''}`, slot);
            return won;
        };
        let won = toss();
        const s = this.sides[side];
        if (!won && s && toInt(s.loaded_turn ?? -1) !== this.turn && this.winner === '') {   // LOADED DICE: once a turn, try again
            const by = this.characters(side).find(x => !isEmpty(this._passive(side, x.slot, x.card, 'loaded')));
            if (by) {
                s.loaded_turn = this.turn;
                this._effect(side, by.card, `${by.card.name}: LOADED DICE, ${coin ? 'flip' : 'roll'} again`, by.slot);
                won = toss(true);
            }
        }
        return won;
    }

    /** publicText: what the other players see instead (text names a card they mustn't know). */
    _effect(side, c, text, slot = -1, publicText = '') {
        this._did += 1;   // effects that did something (see then in _doFx)
        if (publicText !== '') this._emit('effect', { side, card: clone(c), text, slot, public_text: publicText });
        else this._emit('effect', { side, card: clone(c), text, slot });
    }

    _handIndex(side, uid) {
        return this.sides[side].hand.findIndex(c => c.uid === uid);
    }

    _hasStriver(side) {
        return this.characters(side).some(e => e.card.subtype === 'striver');
    }

    _downedLions(side) {
        return this.characters(side).filter(e => e.card.downed && isLion(e.card)).sort(strongestFirst);
    }

    _promotableStrivers(side) {
        return this.characters(side).filter(e => isLion(e.card) && e.card.subtype === 'striver'
            && !e.card.downed && !e.card.face_down && !this.sides[side].promoted[e.slot]
            && nextForm(e.card.id) !== '')
            .sort((a, b) => (toInt(b.card.level) - toInt(a.card.level)) || (a.slot - b.slot));
    }

    _readyEnforcer(side, targetSlot) {
        for (const e of this.characters(side)) {
            const c = e.card;
            if (e.slot !== targetSlot && c.effectKey === 'block_enforcer_redirect'
                && !c.downed && !c.face_down && (c.redirect_turn ?? 0) !== this.turn) return e;
        }
        return null;
    }

    _adjacentLion(side, slot) {
        return [slot - 1, slot + 1].some(adj => FRONT.includes(adj) && isLion(this.cardAt(side, adj)));
    }

    _emit(type, data = {}) {
        data.type = type;
        data.counts = this._counts();
        this._events.push(data);
    }

    _counts() {
        const out = {};
        for (const side of Object.keys(this.sides)) {
            const s = this.sides[side];
            out[side] = {
                deck: s.deck.length, gutter: s.gutter.length, hideout: s.hideout.length,
                hand: s.hand.length, morale: s.morale,
                authority: s.authority, authority_max: s.authority_max,
                gutter_top: s.gutter.length ? s.gutter[s.gutter.length - 1].id : '',
                leader_state: s.leader_state,
                influence: s.leader ? s.leader.influence : 0,
            };
            if (this.ffa) out[side].out = toInt(s.out);
        }
        return out;
    }
}

function enforcerWorthIt(att, target, be) {
    const targetHolds = (target.downed || target.position === 'def' ? target.defense : target.attack) >= att.attack;
    const beHolds = (be.position === 'def' ? be.defense : be.attack) >= att.attack;
    return target.downed || (beHolds && !targetHolds);
}

function promptEvent(ask) {
    const ev = { ...ask };
    delete ev.cb;
    delete ev.still;
    return ev;
}

const LUCK_SALT = 0x5BD1E995;
const LUCK_TEST_SEED = 0x2545F491;

/** mulberry32: a small repeatable random number generator (0 <= x < 1). */
function seededRandom(seed) {
    let t = seed >>> 0;
    return () => {
        t = (t + 0x6D2B79F5) >>> 0;
        let r = Math.imul(t ^ (t >>> 15), 1 | t);
        r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
        return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
}

function shuffle(a, rand = Math.random) {
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(rand() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
}
