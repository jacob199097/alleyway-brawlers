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
 */

import { CARD_CATALOG } from '../cards.js';

export const START_MORALE = 6000;
export const MAX_AUTHORITY = 15;
export const HAND_LIMIT = 9;
export const OPENING_HAND = 5;
export const SECOND_PLAYER_AUTHORITY = 1; // going second: extra Authority on your first turn only
export const LEADER_DEFEAT_PENALTY = 1000;
export const FRONT = [0, 1, 2, 3, 4];
export const BACK = [5, 6, 7, 8, 9];
export const DIRECT = -1;
export const LEADER = -2;

// ── Card data ──────────────────────────────────────────────────────────────

export function getCard(id) {
    return CARD_CATALOG[id] ? structuredClone(CARD_CATALOG[id]) : {};
}

/** The form a card promotes into: promotesTo, or the next `_lvN` card (Hunter, Viper). */
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

export class DuelState {
    /**
     * @param {{player: Array, opponent: Array}} decks     card ids or {id, ...server stats}
     * @param {{player?: Array, opponent?: Array}} hideouts
     * @param {{player?: string, opponent?: string}} leaders
     * @param {string} first   'player' | 'opponent'
     * @param {number} seed    -1 keeps the given deck order (tests); otherwise decks are shuffled
     */
    constructor(decks, hideouts = {}, leaders = {}, first = 'player', seed = 0) {
        this.turn = 1;
        this.active = first;
        this.phase = 'upkeep';
        this.winner = '';
        this.endReason = ''; // how the game ended: 'morale' or 'deck_out'
        this.pending = {};
        this.sides = {};
        this._events = [];
        this._uid = 0;
        this._asks = [];
        this._inAnswer = false;
        this._newAsks = [];
        this._fixedOrder = seed === -1; // never shuffle (tests compare engines)
        for (const side of ['player', 'opponent']) {
            const deck = decks[side].map(spec => this.makeCard(spec));
            if (seed !== -1) shuffle(deck);
            const hideout = (hideouts[side] || []).map(spec => this.makeCard(spec));
            const field = Array(10).fill(null);
            const leaderId = leaders[side] || '';
            const leader = leaderId !== '' ? this.makeCard(leaderId) : null;
            if (leader) leader.influence = leader.base_defense;
            this.sides[side] = {
                morale: START_MORALE, authority: 1, authority_max: 1,
                deck, hand: [], field, gutter: [], hideout,
                leader, leader_state: leader ? 'dormant' : 'none',
                brutus_bonus: 0, promoted: {}, mentor_used: false,
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
        return this.winner === '' && isEmpty(this.pending) && side === this.active;
    }

    canDeployNow(side) {
        return this.canAct(side) && ['deployment', 'regroup'].includes(this.phase);
    }

    canSummon(side, c, slot) {
        if (!this.canDeployNow(side) || c.cardType !== 'gang_member') return false;
        if (!FRONT.includes(slot) || this.sides[side].field[slot] != null) return false;
        return this.sides[side].authority >= c.authority;
    }

    canSet(side, c, slot) {
        if (!this.canDeployNow(side) || c.cardType !== 'ambush') return false;
        if (!BACK.includes(slot) || this.sides[side].field[slot] != null) return false;
        return this.sides[side].authority >= c.authority;
    }

    hustleReady(side, c) {
        switch (c.effectKey || '') {
            case 'lion_rescue': return this._downedLions(side).length > 0;
            case 'blood_scent': return this._promotableStrivers(side).length > 0;
        }
        return true;
    }

    canHustle(side, c) {
        return this.canDeployNow(side) && c.cardType === 'hustle'
            && this.sides[side].authority >= c.authority && this.hustleReady(side, c);
    }

    canAttackWith(side, slot) {
        if (!this.canAct(side) || this.phase !== 'brawl' || this.turn === 1 || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        return c != null && c.position === 'atk' && !c.downed && !c.has_attacked && !c.face_down;
    }

    // Any enemy character; DIRECT when none is still standing (empty row or only Downed);
    // the enemy LEADER whenever it is dormant.
    attackTargets(side) {
        const foe = other(side);
        const foes = this.characters(foe);
        const targets = foes.map(e => e.slot);
        if (!foes.some(e => !e.card.downed)) targets.push(DIRECT);
        if (this.leaderDormant(foe)) targets.push(LEADER);
        return targets;
    }

    canChangePosition(side, slot) {
        if (!this.canDeployNow(side) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        return c != null && !c.downed && !c.has_attacked
            && c.deployed_turn !== this.turn && (c.position_turn ?? 0) !== this.turn;
    }

    canPromote(side, slot) {
        if (!this.canDeployNow(side) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        if (c == null || c.ability !== 'maya_promote' || c.face_down || c.downed) return false;
        if (this.sides[side].promoted[slot] || nextForm(c.id) === '') return false;
        return this.characters(side).some(e => e.slot !== slot && isLion(e.card) && e.card.authority >= c.authority);
    }

    canUseAbility(side, slot) {
        if (!this.canAct(side) || !['deployment', 'brawl', 'regroup'].includes(this.phase) || !FRONT.includes(slot)) return false;
        const c = this.cardAt(side, slot);
        if (c == null || c.ability !== 'maya_buff' || c.face_down || c.downed) return false;
        if ((c.ability_turn ?? 0) === this.turn) return false;
        return this.characters(side).some(e => e.slot !== slot && isLion(e.card));
    }

    // ── Actions ────────────────────────────────────────────────────────────

    start() {
        for (let i = 0; i < OPENING_HAND; i++) {
            this._draw(this.active, true);
            this._draw(other(this.active), true);
        }
        // Each player may redraw their opening hand once, first player first; then turn 1 begins
        const first = this.active;
        this._askMulligan(first, () => this._askMulligan(other(first), () => this._beginTurn()));
        this._flushAsks();
    }

    doAction(side, a) {
        if (this.winner !== '' || !a || typeof a !== 'object') return false;
        let ok = false;
        switch (a.kind) {
            case 'summon': ok = this._summon(side, toInt(a.uid), toInt(a.slot), String(a.position ?? 'atk')); break;
            case 'set': ok = this._setAmbush(side, toInt(a.uid), toInt(a.slot)); break;
            case 'hustle': ok = this._hustle(side, toInt(a.uid)); break;
            case 'attack': ok = this._attack(side, toInt(a.from), toInt(a.target)); break;
            case 'position': ok = this._changePosition(side, toInt(a.slot)); break;
            case 'promote':
                if (this.canPromote(side, toInt(a.slot))) {
                    this._promote(side, toInt(a.slot), 'Maya');
                    ok = true;
                }
                break;
            case 'ability': ok = this._useAbility(side, toInt(a.slot)); break;
            case 'choose': ok = this._answer(side, String(a.option)); break;
            case 'discard': ok = this._chooseDiscard(side, toInt(a.uid)); break;
            case 'next': ok = this._nextPhase(side); break;
        }
        if (ok) {
            this._flushAsks();
            this._recalc();
        }
        return ok;
    }

    _summon(side, uid, slot, position) {
        const i = this._handIndex(side, uid);
        if (i < 0 || !this.canSummon(side, this.sides[side].hand[i], slot)) return false;
        const c = this.sides[side].hand.splice(i, 1)[0];
        this._spend(side, c.authority);
        c.position = position === 'def' ? 'def' : 'atk';
        c.face_down = c.position === 'def';
        c.has_attacked = false;
        c.deployed_turn = this.turn;
        this.sides[side].field[slot] = c;
        this._emit('summon', { side, slot, card: clone(c) });
        if (!c.face_down) this._onDeploy(side, slot, c);
        return true;
    }

    _setAmbush(side, uid, slot) {
        const i = this._handIndex(side, uid);
        if (i < 0 || !this.canSet(side, this.sides[side].hand[i], slot)) return false;
        const c = this.sides[side].hand.splice(i, 1)[0];
        this._spend(side, c.authority);
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

    _hustle(side, uid) {
        const i = this._handIndex(side, uid);
        if (i < 0 || !this.canHustle(side, this.sides[side].hand[i])) return false;
        const s = this.sides[side];
        const c = s.hand.splice(i, 1)[0];
        this._spend(side, c.authority);
        s.gutter.push(c);
        this._emit('hustle', { side, card: clone(c) });
        switch (c.effectKey) {
            case 'corner_deal':
                this._draw(side);
                this._draw(side);
                if (this._hasStriver(side)) {
                    this._effect(side, c, 'You control a Striver: no discard');
                } else {
                    this._effect(side, c, 'Drew 2 — now discard 1');
                    this._askDiscard(side, 1, null);
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
                if (this.turn === 1) {
                    this._emit('notice', { text: 'NO ATTACKS ON TURN 1' });
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
                if (extra > 0) this._askDiscard(side, extra, () => this._endTurn());
                else this._endTurn();
                break;
            }
            default:
                return false;
        }
        return true;
    }

    // ── Attacks ────────────────────────────────────────────────────────────

    _attack(side, from, target) {
        if (!this.canAttackWith(side, from) || !this.attackTargets(side).includes(target)) return false;
        const att = this.cardAt(side, from);
        att.has_attacked = true;
        this._emit('attack', { side, from, target, card: clone(att) });
        const ctx = { side, foe: other(side), from, target, att, bonus: 0 };
        const defNow = target >= 0 ? this.cardAt(other(side), target) : null;
        for (const e of this._fx(att, 'attack')) {
            if (String(e.do ?? '') === 'buff' && String(e.target ?? 'self') === 'self') {
                if (String(e.if ?? '') === '' && toInt(e.atk) !== 0) {
                    ctx.bonus += toInt(e.atk);
                    this._effect(side, att, `${att.name}: ${signed(toInt(e.atk))} ATK this brawl`, from);
                }
            } else if (this._fxCond(side, from, e, defNow)) {
                this._doFx(side, from, att, e);
            }
        }
        if (isLion(att) && this.sides[side].brutus_bonus > 0) {
            ctx.bonus += this.sides[side].brutus_bonus;
            this.sides[side].brutus_bonus = 0;
            this._effect(side, att, "Brutus's momentum: +300 ATK", from);
        }
        this._atkLaneMove(ctx);
        return true;
    }

    _atkLaneMove(ctx) {
        const att = ctx.att;
        if (['viper_lv2', 'viper_lv3'].includes(att.effectKey)) {
            const lanes = this._freeAdjacent(ctx.side, ctx.from);
            if (lanes.length) {
                this._askLane(ctx.side, att, ctx.from, lanes, `${att.name}: move to an adjacent lane before the brawl?`,
                    (to) => {
                        ctx.from = to;
                        this._atkRedirect(ctx);
                    });
                return;
            }
        }
        this._atkRedirect(ctx);
    }

    _atkRedirect(ctx) {
        const foe = ctx.foe;
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
                            this._emit('retarget', { side: ctx.side, from: ctx.from, target: ctx.target });
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
                this._spring(foe, slot);
                if (a.effectKey === 'no_witnesses_ambush') {
                    this._effect(foe, a, 'No Witnesses: the attacker is Downed and the attack negated', slot);
                    ctx.att.downed = true;
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
            this._emit('clash', { side, from, target: DIRECT, att: dmg, def: 0, vs: 'DIRECT' });
            this._damage(foe, dmg);
            return;
        }
        if (target === LEADER) {
            this._hitLeader(ctx);
            return;
        }
        const def = this.cardAt(foe, target);
        let bonus = ctx.bonus + this._brawlBonus(side, from, att, def);
        if (def.effectKey === 'bulwark') {
            bonus -= 300;
            this._effect(foe, def, 'Bulwark: the attacker loses 300 ATK', target);
        }
        const defWasDowned = def.downed;
        const defInfo = { downed: def.downed, position: def.position, face_down: false };
        const vsDef = def.downed || def.position === 'def';
        const aVal = Math.max(0, att.attack + bonus);
        const dVal = vsDef ? def.defense : def.attack;
        this._emit('clash', { side, from, target, att: aVal, def: dVal, vs: vsDef ? 'DEF' : 'ATK' });

        let result = '';
        if (vsDef) {
            if (aVal > dVal) result = this._defeat(foe, target);
            else this._emit('blocked', { side: foe, slot: target });
        } else if (aVal > dVal) {
            this._damage(foe, aVal - dVal);
            result = this._defeat(foe, target);
        } else if (aVal < dVal) {
            this._damage(side, dVal - aVal);
            this._defeat(side, from);
        } else {
            this._emit('notice', { text: 'TIE — BOTH GO DOWN' });
            result = this._defeat(foe, target);
            this._defeat(side, from);
        }
        if (this.winner === '' && this.cardAt(side, from) === att && !att.downed) {
            if (result === 'ko') {
                this._onKo(side, from, att, defWasDowned, target);
                this._runFx(side, this._slotOf(side, att, from), att, 'ko', defInfo);
            } else if (result === 'downed') {
                this._onDown(side, from, att);
                this._runFx(side, this._slotOf(side, att, from), att, 'down', defInfo);
            }
        }
    }

    _hitLeader(ctx) {
        const foe = ctx.foe;
        const leader = this.sides[foe].leader;
        const dmg = Math.max(0, ctx.att.attack + ctx.bonus);
        this._emit('clash', { side: ctx.side, from: ctx.from, target: LEADER, att: dmg, def: leader.influence, vs: 'INFLUENCE' });
        leader.influence = Math.max(0, leader.influence - dmg);
        this._emit('leader_hit', { side: foe, amount: dmg, influence: leader.influence });
        if (leader.influence <= 0) {
            this.sides[foe].leader_state = 'defeated';
            this.sides[foe].gutter.push(leader);
            this._emit('leader_down', { side: foe, card: clone(leader) });
            this._damage(foe, LEADER_DEFEAT_PENALTY);
        }
    }

    // ── Battle results ─────────────────────────────────────────────────────

    _defeat(side, slot) {
        const c = this.cardAt(side, slot);
        if (c.downed) {
            if (isLion(c) && c.subtype === 'striver' && this._springKingsTest(side, slot, c)) return 'saved';
            this._ko(side, slot);
            return 'ko';
        }
        c.downed = true;
        this._emit('downed', { side, slot, card: clone(c) });
        return 'downed';
    }

    _ko(side, slot) {
        const c = this.cardAt(side, slot);
        this.sides[side].field[slot] = null;
        c.downed = false;
        c.mods = [];
        this.sides[side].gutter.push(c);
        this._emit('ko', { side, slot, card: clone(c) });
    }

    _damage(side, amount) {
        if (amount <= 0) return;
        const s = this.sides[side];
        s.morale = Math.max(0, s.morale - amount);
        this._emit('damage', { side, amount, morale: s.morale });
        if (s.morale <= 0 && this.winner === '') this._end(other(side), 'morale');
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
        for (const e of this._fx(att, 'attack')) {
            if (String(e.do ?? '') === 'buff' && String(e.target ?? 'self') === 'self'
                    && String(e.if ?? '') !== '' && this._fxCond(side, from, e, def)) {
                extra += toInt(e.atk);
                this._effect(side, att, `${att.name}: ${signed(toInt(e.atk))} ATK this brawl`, from);
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

    _onKo(side, slot, att, wasDowned, target) {
        const key = att.effectKey || '';
        const foe = other(side);
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
            const standing = this.characters(foe).filter(e => !e.card.downed);
            standing.sort(strongestFirst);
            this._askTarget(side, 'hunter_down', `${att.name} KO: choose an enemy character to Down`, att,
                standing, foe, (e) => {
                    e.card.downed = true;
                    this._effect(side, att, `${att.name} Downs ${e.card.name}`, slot);
                    this._emit('downed', { side: foe, slot: e.slot, card: clone(e.card) });
                });
        }
        if (wasDowned) {
            if (['hunter_lv1', 'hunter_lv2'].includes(key)) {
                this._promote(side, slot, att.name);
            } else if (['hunter_lv3', 'viper_lv3'].includes(key)) {
                att.has_attacked = false;
                this._effect(side, att, `${att.name} may attack again this turn`, slot);
            }
        }
        if (key === 'viper_lv3') {
            const lanes = this._freeAdjacent(side, slot);
            if (lanes.length) this._askLane(side, att, slot, lanes, 'Viper Lv.3: move to an adjacent lane after the KO?', () => {});
        }
    }

    _onDown(side, slot, att) {
        switch (att.effectKey || '') {
            case 'brutus_enter':
                this.sides[side].brutus_bonus = 300;
                this._effect(side, att, 'Brutus: your next LIONS attacker gains +300 ATK', slot);
                break;
            case 'viper_lv1':
            case 'viper_lv2':
                this._promote(side, slot, att.name);
                break;
            case 'debt_collector': {
                const foe = other(side);
                if (this.sides[foe].hand.length) {
                    this._effect(side, att, 'Debt Collector: your opponent discards 1 card', slot);
                    this._askDiscard(foe, 1, null);
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
        this.sides[side].field[slot] = null;
        this.sides[side].gutter.push(a);
        a.face_down = false;
        this._emit('ambush', { side, slot, card: clone(a) });
    }

    // ── Effects ────────────────────────────────────────────────────────────

    _onDeploy(side, slot, c) {
        this._runFx(side, slot, c, 'deploy');
        const foe = other(side);
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
                const foes = this.characters(foe);
                foes.sort(strongestFirst);
                this._askTarget(side, 'brutus', 'Brutus: choose an enemy character to lose 700 ATK', c,
                    foes, foe, (e) => {
                        e.card.mods.push({ atk: -700, until_turn: this.turn + 1 });
                        this._effect(side, c, `${e.card.name} loses 700 ATK until the end of your opponent's next turn`, slot);
                    });
                break;
            }
            case 'sovereign': {
                let hit = 0;
                for (const e of this.characters(foe)) {
                    if (!e.card.downed && e.card.defense <= 1500) {
                        e.card.downed = true;
                        hit += 1;
                        this._emit('downed', { side: foe, slot: e.slot, card: clone(e.card) });
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
        if (old == null || s.promoted[slot]) return;
        const toId = nextForm(old.id);
        if (toId === '') return;
        s.promoted[slot] = true;
        const preview = getCard(toId);
        this._ask(side, 'position', `Promote to ${preview.name ?? toId}: choose its position`, preview, [
            { id: 'atk', label: 'ATK POSITION' }, { id: 'def', label: 'DEF POSITION' },
        ], (pos) => {
            if (this.cardAt(side, slot) !== old) return;
            let promoted = null;
            const i = s.hideout.findIndex(h => h.id === toId);
            if (i >= 0) promoted = s.hideout.splice(i, 1)[0];
            if (promoted == null) promoted = this.makeCard(toId);
            promoted.position = pos;
            promoted.face_down = false;
            promoted.has_attacked = true;
            promoted.deployed_turn = this.turn;
            s.field[slot] = promoted;
            old.mods = [];
            old.downed = false;
            s.gutter.push(old);
            this._emit('promote', { side, slot, from: clone(old), card: clone(promoted), reason });
            this._onDeploy(side, slot, promoted);
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
    }

    _checkAwaken(side) {
        const s = this.sides[side];
        if (s.leader_state !== 'dormant') return;
        const cond = s.leader.awakenCondition || {};
        if (isEmpty(cond)) return;
        const lions = this.characters(side).filter(e => isLion(e.card) && !e.card.downed && !e.card.face_down).length;
        if (lions < toInt(cond.lions ?? 99) && s.authority_max < toInt(cond.authorityThreshold ?? 99)) return;
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
        this._ask(side, 'awaken', `${s.leader.name} AWAKENS! Choose his lane`, s.leader, options, (choice) => {
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
            king.has_attacked = true;
            king.deployed_turn = this.turn;
            s.field[slot] = king;
            this._emit('awaken', { side, slot, card: clone(king) });
            this._effect(side, king, `${king.name} takes the street himself`, slot);
        });
    }

    _recalc() {
        const values = {};
        for (const side of Object.keys(this.sides)) {
            const s = this.sides[side];
            const foeHasDowned = this.characters(other(side)).some(e => e.card.downed);
            const lions = this.lionCount(side);
            const roan = s.leader_state === 'dormant' && s.leader.effectKey === 'king_roan_leader' && lions >= 2;
            const auras = this._auras(side);
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
                for (const adj of [slot - 1, slot + 1]) {
                    if (FRONT.includes(adj) && s.field[adj] != null && s.field[adj].effectKey === 'bulwark') df += 400;
                }
                c.attack = Math.max(0, atk);
                c.defense = Math.max(0, df);
                values[side][slot] = [c.attack, c.defense, c.base_attack, c.base_defense, c.face_down];
            }
        }
        this._emit('stats', { values });
    }

    // ── Card effects from data (Card Forge) ────────────────────────────────
    // Same building blocks as duel_state.gd: {when, do, target, atk, def, amount, until, clan, if, n}

    _fx(c, when) {
        if (c == null) return [];
        return (c.effects || []).filter(e => e && typeof e === 'object' && String(e.when ?? '') === when);
    }

    _fxPool(side, e, except, standingOnly = false) {
        const clan = String(e.clan ?? '');
        return this.characters(side).filter(x => x.slot !== except && (clan === '' || x.card.clanTag === clan)
            && !(standingOnly && x.card.downed));
    }

    _fxCond(side, slot, e, def) {
        switch (String(e.if ?? '')) {
            case 'vs_def': return def != null && (def.position === 'def' || !!def.face_down);
            case 'vs_downed': return def != null && !!def.downed;
            case 'allies': return this._fxPool(side, e, slot).length >= toInt(e.n ?? 1);
            case 'adjacent': return this._fxPool(side, e, slot).some(x => Math.abs(x.slot - slot) === 1);
            case 'foe_downed': return this.characters(other(side)).some(x => x.card.downed);
        }
        return true;
    }

    _runFx(side, slot, c, when, def = null) {
        for (const e of this._fx(c, when)) {
            if (this.winner === '' && this._fxCond(side, slot, e, def)) this._doFx(side, slot, c, e);
        }
    }

    _doFx(side, slot, c, e) {
        const foe = other(side);
        const n = Math.max(1, toInt(e.amount ?? 1));
        const target = String(e.target ?? 'self');
        switch (String(e.do ?? '')) {
            case 'buff': {
                const mod = { atk: toInt(e.atk), def: toInt(e.def),
                    until_turn: this.turn + (String(e.until ?? 'turn') === 'next_turn' ? 1 : 0) };
                const label = statText(mod);
                if (target === 'self') {
                    if (this.cardAt(side, slot) === c) {
                        c.mods.push({ ...mod });
                        this._effect(side, c, `${c.name}: ${label}`, slot);
                    }
                } else if (target === 'ally' || target === 'enemy') {
                    const on = target === 'ally' ? side : foe;
                    const pool = this._fxPool(on, e, on === side ? slot : -99);
                    pool.sort(strongestFirst);
                    this._askTarget(side, 'fx', `${c.name}: choose ${on === side ? 'an ally' : 'an enemy'} for ${label}`, c,
                        pool, on, (x) => {
                            x.card.mods.push({ ...mod });
                            this._effect(side, c, `${x.card.name}: ${label}`, slot);
                        });
                } else if (target === 'allies' || target === 'enemies') {
                    const on = target === 'allies' ? side : foe;
                    const pool = this._fxPool(on, e, on === side ? slot : -99);
                    for (const x of pool) x.card.mods.push({ ...mod });
                    if (pool.length) this._effect(side, c, `${c.name}: ${label} to ${on === side ? 'your characters' : 'enemy characters'}`, slot);
                }
                break;
            }
            case 'down': {
                const pool = this._fxPool(foe, e, -99, true);
                if (target === 'enemies') {
                    for (const x of pool) {
                        x.card.downed = true;
                        this._emit('downed', { side: foe, slot: x.slot, card: clone(x.card) });
                    }
                    if (pool.length) this._effect(side, c, `${c.name} Downs ${pool.length} enem${pool.length === 1 ? 'y' : 'ies'}`, slot);
                } else {
                    pool.sort(strongestFirst);
                    this._askTarget(side, 'fx', `${c.name}: choose an enemy character to Down`, c, pool, foe, (x) => {
                        x.card.downed = true;
                        this._emit('downed', { side: foe, slot: x.slot, card: clone(x.card) });
                        this._effect(side, c, `${c.name} Downs ${x.card.name}`, slot);
                    });
                }
                break;
            }
            case 'draw':
                this._effect(side, c, `${c.name}: draw ${n}`, slot);
                for (let i = 0; i < n; i++) this._draw(side);
                break;
            case 'discard': {
                const k = Math.min(n, this.sides[foe].hand.length);
                if (k > 0) {
                    this._effect(side, c, `${c.name}: your opponent discards ${k}`, slot);
                    this._askDiscard(foe, k, null);
                }
                break;
            }
            case 'damage':
                this._effect(side, c, `${c.name}: ${n} Morale damage`, slot);
                this._damage(foe, n);
                break;
            case 'heal': {
                const s = this.sides[side];
                const gain = Math.min(n, START_MORALE - s.morale);
                if (gain > 0) {
                    s.morale += gain;
                    this._effect(side, c, `${c.name}: +${gain} Morale`, slot);
                    this._emit('heal', { side, amount: gain, morale: s.morale });
                }
                break;
            }
            case 'promote':
                if (this.cardAt(side, slot) === c) this._promote(side, slot, c.name);
                break;
            case 'attack_again':
                if (this.cardAt(side, slot) === c && c.has_attacked) {
                    c.has_attacked = false;
                    this._effect(side, c, `${c.name} may attack again this turn`, slot);
                }
                break;
        }
    }

    _auras(side) {
        const s = this.sides[side];
        const out = [];
        for (const x of this.characters(side)) {
            if (x.card.face_down) continue;
            for (const e of this._fx(x.card, 'passive')) {
                if (String(e.do ?? '') === 'buff' && this._fxCond(side, x.slot, e, null)) out.push([x.slot, e]);
            }
        }
        if (s.leader_state === 'dormant' && s.leader != null) {
            for (const e of this._fx(s.leader, 'passive')) {
                if (String(e.do ?? '') === 'buff' && this._fxCond(side, -1, e, null)) out.push([-1, e]);
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
        this._setPhase('upkeep');
        this._emit('turn', { side: this.active, turn: this.turn });
        if (this.turn > 2) {
            s.authority_max = Math.min(MAX_AUTHORITY, s.authority_max + 1);
            s.authority = s.authority_max;
            this._emit('authority', { side: this.active, value: s.authority, max: s.authority_max, delta: 1 });
        }
        // Going second is a disadvantage; one extra Authority on that player's first turn
        if (this.turn === 2 && SECOND_PLAYER_AUTHORITY > 0) {
            s.authority = s.authority_max + SECOND_PLAYER_AUTHORITY;
            this._emit('authority', { side: this.active, value: s.authority, max: s.authority_max, delta: SECOND_PLAYER_AUTHORITY });
        }
        if (this.turn > 1) this._draw(this.active);
        // A Downed character stays down for a full round, then gets back up in DEF position
        // at the start of its owner's turn (no switching to ATK until the turn after)
        for (const e of this.characters(this.active)) {
            if (!e.card.downed) {
                delete e.card.down_turns;
            } else if (toInt(e.card.down_turns) >= 1) {
                e.card.downed = false;
                delete e.card.down_turns;
                e.card.position = 'def';
                e.card.position_turn = this.turn;
                this._emit('stand', { side: this.active, slot: e.slot, card: clone(e.card) });
            } else {
                e.card.down_turns = 1;
            }
        }
        for (const e of this.characters(this.active)) this._runFx(this.active, e.slot, e.card, 'turn_start');
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
        const s = this.sides[this.active];
        for (const c of s.field) if (c != null) c.has_attacked = false;
        s.brutus_bonus = 0;
        for (const side of Object.keys(this.sides)) {
            for (const c of this.sides[side].field) {
                if (c != null) c.mods = c.mods.filter(m => m.until_turn > this.turn);
            }
        }
        this.active = other(this.active);
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
    }

    _askTarget(side, key, prompt, source, entries, targetSide, cb) {
        if (!entries.length) return;
        if (entries.length === 1) {
            cb(entries[0]);
            return;
        }
        const options = entries.map(e => ({
            id: String(e.slot), label: `${String(e.card.name).toUpperCase()}  (${e.card.attack} / ${e.card.defense})`,
            side: targetSide, slot: e.slot,
        }));
        this._ask(side, key, prompt, source, options, (choice) => {
            for (const e of entries) {
                if (String(e.slot) === choice && this.cardAt(targetSide, e.slot) === e.card) cb(e);
            }
        });
    }

    _askLane(side, c, from, lanes, prompt, then) {
        const options = [{ id: 'stay', label: 'STAY' }];
        for (const to of lanes) {
            options.push({ id: String(to), label: `MOVE ${(to < from) === (side === 'player') ? 'LEFT' : 'RIGHT'}`, side, slot: to });
        }
        if (this._laneValue(side, c, lanes[0]) > this._laneValue(side, c, from)) {
            options.unshift(options.splice(1, 1)[0]);
        }
        this._ask(side, 'lane', prompt, c, options, (choice) => {
            let at = from;
            if (choice !== 'stay' && this.cardAt(side, from) === c && this.cardAt(side, toInt(choice)) == null) {
                at = toInt(choice);
                this.sides[side].field[from] = null;
                this.sides[side].field[at] = c;
                this._emit('move', { side, from, to: at, card: clone(c) });
            }
            then(at);
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
        if (!this._fixedOrder) shuffle(s.deck);
        this._emit('mulligan', { side, count: n });
        for (let i = 0; i < n; i++) this._draw(side, true);
    }

    _askDiscard(side, count, then) {
        const ask = { kind: 'discard', side, count, cb: then, prompt: `Choose ${count} card${count === 1 ? '' : 's'} to discard` };
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
            if (this.winner === '') this._end(other(side), 'deck_out');
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

    _effect(side, c, text, slot = -1) {
        this._emit('effect', { side, card: clone(c), text, slot });
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

    _freeAdjacent(side, slot) {
        return [slot - 1, slot + 1].filter(adj => FRONT.includes(adj) && this.cardAt(side, adj) == null);
    }

    _laneValue(side, c, slot) {
        let v = 0;
        for (const adj of [slot - 1, slot + 1]) {
            if (!FRONT.includes(adj)) continue;
            const n = this.cardAt(side, adj);
            if (n != null && n !== c) {
                v += isLion(n) ? 1 : 0;
                v += n.effectKey === 'bulwark' ? 2 : 0;
            }
        }
        return v;
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
    return ev;
}

function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
}
