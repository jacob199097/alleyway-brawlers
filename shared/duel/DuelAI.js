/**
 * CPU player for the server (CPU matches run on the server so their results can be trusted).
 * A line-by-line port of godot/scripts/duel/duel_ai.gd: choose() returns the next action for
 * DuelState.doAction(), one at a time.
 */
import { CARD_CATALOG } from '../cards.js';
import { DuelState, FRONT, BACK, DIRECT, LEADER, other } from './DuelState.js';

const SLOT_ORDER = [2, 1, 3, 0, 4];   // deploy toward the middle first
const NO_TARGET = -99;

/** The CPU's deck: two of every Lv.1 character and every Hustle/Ambush; higher levels in the Hideout. */
export function cpuSetup() {
    const base = [];
    const hideout = [];
    let leader = '';
    for (const [id, c] of Object.entries(CARD_CATALOG)) {
        if (c.cardType === 'leader') {
            if (!leader) leader = id;
        } else if (c.cardType === 'gang_member') {
            if (Math.trunc(Number(c.level) || 1) === 1) base.push(id);
            else hideout.push(id);
        } else {
            base.push(id);
        }
    }
    return { deck: [...base, ...base], hideout, leader };
}

export function choose(d, side) {
    if (d.winner !== '') return {};
    const p = d.pending;
    if (p && Object.keys(p).length) {
        if (p.side !== side) return {};
        if (p.kind === 'discard') return { kind: 'discard', uid: weakest(d.sides[side].hand).uid };
        // Prompts list their options best-first for the deciding side
        return { kind: 'choose', option: p.options[0].id };
    }
    if (d.active !== side) return {};
    let a = {};
    if (d.phase === 'deployment') a = deploy(d, side);
    else if (d.phase === 'brawl') a = brawl(d, side);
    return Object.keys(a).length ? a : { kind: 'next' };
}

function deploy(d, side) {
    const s = d.sides[side];
    for (const slot of FRONT) if (d.canPromote(side, slot)) return { kind: 'promote', slot };
    for (const c of s.hand) if (d.canHustle(side, c)) return { kind: 'hustle', uid: c.uid };
    // Stand up a defender that now out-muscles everything the opponent shows
    const t = threat(d, side);
    for (const e of d.characters(side)) {
        if (e.card.position === 'def' && d.canChangePosition(side, e.slot) && e.card.attack > t) {
            return { kind: 'position', slot: e.slot };
        }
    }
    const free = SLOT_ORDER.filter(i => s.field[i] == null);
    if (free.length) {
        let best = null;
        for (const c of s.hand) {
            if (d.canSummon(side, c, free[0]) && (best == null || c.base_attack > best.base_attack)) best = c;
        }
        if (best != null) {
            return { kind: 'summon', uid: best.uid, slot: free[0], position: best.base_attack >= t ? 'atk' : 'def' };
        }
    }
    for (const slot of BACK) {
        if (s.field[slot] == null) {
            for (const c of s.hand) if (d.canSet(side, c, slot)) return { kind: 'set', uid: c.uid, slot };
            break;
        }
    }
    return {};
}

function brawl(d, side) {
    const foe = other(side);
    // Maya Lv.3 buffs an ally before the punches start
    for (const slot of FRONT) if (d.canUseAbility(side, slot)) return { kind: 'ability', slot };
    for (const slot of FRONT) {
        if (!d.canAttackWith(side, slot)) continue;
        const att = d.cardAt(side, slot);
        let best = NO_TARGET;
        let bestScore = 0;
        for (const t of d.attackTargets(side)) {
            let score;
            if (t === DIRECT) {
                // Finish the game if this hit does it; otherwise chip the opponent's morale
                score = att.attack >= d.sides[foe].morale ? 100 : 2.5 + att.attack / 2000;
            } else if (t === LEADER) {
                // Knock out a dormant leader when one hit does it; chipping its Influence is a last resort
                score = att.attack >= d.sides[foe].leader.influence ? 4 : 0.5;
            } else {
                score = targetScore(att, d.cardAt(foe, t));
            }
            if (score > bestScore) {
                bestScore = score;
                best = t;
            }
        }
        if (best !== NO_TARGET) return { kind: 'attack', from: slot, target: best };
    }
    return {};
}

/** How much the CPU wants to attack this enemy character (0 = not worth it). */
function targetScore(att, df) {
    if (df.face_down) return att.attack >= 1600 ? 1 : 0;   // unknown DEF: only strong attackers try
    if (df.downed) return att.attack > df.defense ? 3 : 0;
    if (df.position === 'def') return att.attack > df.defense ? 2 : 0;
    if (att.attack > df.attack) return 2 + (att.attack - df.attack) / 1000;
    return 0;
}

/** The strongest face-up attacker the opponent shows. */
function threat(d, side) {
    let t = 0;
    for (const e of d.characters(other(side))) {
        if (e.card.position === 'atk' && !e.card.downed && !e.card.face_down) t = Math.max(t, e.card.attack);
    }
    return t;
}

function weakest(hand) {
    let worst = hand[0];
    for (const c of hand) {
        if (c.authority * 1000 + c.base_attack < worst.authority * 1000 + worst.base_attack) worst = c;
    }
    return worst;
}

export { DuelState };
