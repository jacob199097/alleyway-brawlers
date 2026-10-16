/**
 * CPU player for the server (CPU matches run on the server so their results can be trusted).
 * A line-by-line port of godot/scripts/duel/duel_ai.gd: choose() returns the next action for
 * DuelState.doAction(), one at a time.
 */
import { CARD_CATALOG } from '../cards.js';
import { pickableClans, starterRecipe, expand } from '../clans.js';
import { DuelState, FRONT, BACK, DIRECT, LEADER, other } from './DuelState.js';

const SLOT_ORDER = [2, 1, 3, 0, 4];   // deploy toward the middle first
const NO_TARGET = -99;

/**
 * The CPU's deck: a clan's starter deck (shared/clans.js), for `clan` or else the clan with the
 * most cards. Only if no clan has a starter yet: two of every Lv.1 character and every
 * Hustle/Ambush, higher levels in the Hideout.
 */
export function cpuSetup(clan = '') {
    const clans = pickableClans();
    const pick = clans.some(c => c.id === clan) ? clan : [...clans].sort((a, b) => b.cards - a.cards)[0]?.id;
    const recipe = pick ? starterRecipe(pick) : null;
    if (recipe) return { deck: expand(recipe.deck), hideout: expand(recipe.hideout), leader: recipe.leader, clan: pick };
    return everyCardSetup();
}

/** A clan the CPU plays at random (server CPU matches). */
export function randomCpuClan() {
    const clans = pickableClans();
    return clans.length ? clans[Math.floor(Math.random() * clans.length)].id : '';
}

function everyCardSetup() {
    const base = [];
    const hideout = [];
    let leader = '';
    for (const [id, c] of Object.entries(CARD_CATALOG)) {
        if (c.token) continue;   // (made only by effects)
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

// Difficulty: "easy" misses attacks, picks the first target that works and never sacrifices for
// a Heavy; "normal" is the standard CPU; "hard" sacrifices more readily (preferring Downed or
// weakened characters), takes even trades that cost it the weaker card, keeps its Ambushes for
// attacks that would hurt, and pays an Activate ability's sacrifice with a Downed or weak character.
export const LEVELS = ['easy', 'normal', 'hard'];

export function choose(d, side, level = 'normal') {
    if (d.winner !== '') return {};
    const p = d.pending;
    if (p && Object.keys(p).length) {
        if (p.side !== side) return {};
        if (p.kind === 'discard') return { kind: 'discard', uid: weakest(d.sides[side].hand).uid };
        if (level === 'hard' && p.key === 'ambush' && p.options.some(o => o.id === 'no') && !attackHurts(d, side)) {
            return { kind: 'choose', option: 'no' };   // this attack fails anyway: keep the Ambush
        }
        // Prompts list their options best-first for the deciding side
        return { kind: 'choose', option: p.options[0].id };
    }
    if (d.active !== side) return {};
    let a = {};
    if (d.phase === 'deployment') a = deploy(d, side, level);
    else if (d.phase === 'brawl') a = brawl(d, side, level);
    else if (d.phase === 'regroup' && level === 'hard') a = brace(d, side);
    return Object.keys(a).length ? a : { kind: 'next' };
}

/** Same as _hustle_useful in duel_ai.gd: a Card Forge Hustle only when one of its effects would do something. */
function hustleUseful(d, side, c) {
    const effects = c.effects || [];
    if (!effects.length) return true;
    const foe = other(side);
    const allies = d.characters(side).filter(e => !d.inStasis(e.card));
    const enemies = d.characters(foe).filter(e => !d.inStasis(e.card));
    for (const e of effects) {
        const what = String(e.do ?? '');
        switch (String(e.target ?? '')) {
            case 'ally': case 'allies':
                if (what === 'stand') { if (allies.some(x => x.card.downed)) return true; }
                else if (allies.length) return true;
                break;
            case 'enemy': case 'enemies':
                if (enemies.length) return true;
                break;
            default:
                if (what === 'discard') { if (d.sides[foe].hand.length) return true; }
                else return true;
        }
    }
    return false;
}

function deploy(d, side, level) {
    const s = d.sides[side];
    for (const slot of FRONT) if (d.canPromote(side, slot)) return { kind: 'promote', slot };
    const act = activation(d, side, level);
    if (act) return act;
    for (const c of s.hand) if (d.canHustle(side, c) && hustleUseful(d, side, c)) return { kind: 'hustle', uid: c.uid };
    const t = threat(d, side);
    if (level !== 'easy') {
        // Stand up a defender that now out-muscles everything the opponent shows
        for (const e of d.characters(side)) {
            if (e.card.position === 'def' && d.canChangePosition(side, e.slot) && e.card.attack > t) {
                return { kind: 'position', slot: e.slot };
            }
        }
        // A Heavy is worth a sacrifice when it clearly out-muscles the character we'd give up
        let heavy = null;
        for (const c of s.hand) {
            if (DuelState.needsTribute(c) && d.canSummonSomewhere(side, c) && (heavy == null || c.base_attack > heavy.base_attack)) heavy = c;
        }
        if (heavy != null) {
            // Its sacrifices: the characters least worth keeping (ties: the leftmost lane)
            const n = DuelState.tributesFor(heavy);
            const fodder = d.characters(side).filter(e => d.canSacrifice(side, e.slot))
                .map(e => ({ slot: e.slot, v: keepValue(e.card) }))
                .sort((x, y) => x.v - y.v || x.slot - y.slot).slice(0, n);
            const given = fodder.reduce((sum, f) => sum + f.v, 0);
            const margin = level === 'hard' ? 400 : 800;
            if (fodder.length === n && heavy.base_attack >= given + margin) {
                return { kind: 'summon', uid: heavy.uid, slot: fodder[0].slot, tributes: fodder.map(f => f.slot),
                    position: heavy.base_attack >= t ? 'atk' : 'def' };
            }
        }
    }
    const free = SLOT_ORDER.filter(i => s.field[i] == null);
    if (free.length) {
        let best = null;
        for (const c of s.hand) {
            if (!d.canSummon(side, c, free[0])) continue;
            if (level === 'easy') {
                best = c;
                break;
            }
            if (best == null || c.base_attack > best.base_attack) best = c;
        }
        if (best != null) {
            return { kind: 'summon', uid: best.uid, slot: free[0], position: best.base_attack >= t ? 'atk' : 'def' };
        }
    } else if (level !== 'easy') {
        // Front row full: deploy over the character least worth keeping, for a clearly stronger one
        // (a Downed one counts half: it stands back up, if it isn't finished off first)
        const worth = (c) => (c.downed ? Math.trunc(c.attack / 2) : keepValue(c));
        const weakest = d.characters(side).filter(e => d.canSacrifice(side, e.slot))
            .map(e => ({ slot: e.slot, v: worth(e.card) })).sort((x, y) => x.v - y.v || x.slot - y.slot)[0];
        if (weakest != null) {
            let best = null;
            for (const c of s.hand) {
                if (d.canSummon(side, c, weakest.slot, weakest.slot) && (best == null || c.base_attack > best.base_attack)) best = c;
            }
            if (best != null && best.base_attack >= weakest.v + (level === 'hard' ? 400 : 800)) {
                return { kind: 'summon', uid: best.uid, slot: weakest.slot, tributes: [weakest.slot], position: best.base_attack >= t ? 'atk' : 'def' };
            }
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

/** Whether the attack on one of side's characters (an Ambush may answer it) would beat it. */
function attackHurts(d, side) {
    const ctx = d._attackCtx;
    if (!ctx || ctx.foe !== side) return true;
    const df = d.cardAt(side, ctx.target);
    if (!df) return true;
    const guard = df.downed || df.position === 'def' ? df.defense : df.attack;
    return ctx.att.attack + ctx.bonus >= guard;
}

// Activated abilities: same rules as _activation in duel_ai.gd
function activation(d, side, level = 'normal') {
    const s = d.sides[side];
    for (const slot of FRONT) {
        for (const k of d.activations(side, slot)) {
            const e = d._fx(d.cardAt(side, slot), 'activate')[k - 1];
            const n = Math.max(1, Math.trunc(Number(e.cost_n ?? 1)) || 1);
            const cost = String(e.cost ?? '');
            if (!d.fxHasTargets(side, slot, e)) continue;
            if (cost === 'sacrifice') {
                // Hard: when the one it would give up (the weakest, as the prompt offers) is Downed or weak
                if (level !== 'hard') continue;
                const fodder = d.characters(side).filter(x => x.slot !== slot)
                    .sort((a, b) => (toAttackValue(a.card) - toAttackValue(b.card)) || a.slot - b.slot)[0];
                if (!fodder || keepValue(fodder.card) > 600) continue;
            }
            if (cost === 'morale' && s.morale <= n * 3) continue;
            if (cost === 'discard' && s.hand.length < n + 2) continue;
            if (cost === 'exhaust' && (d.phase !== 'brawl' || d.canAttackWith(side, slot))) continue;
            return { kind: 'activate', slot, fx: k };
        }
    }
    return null;
}

function brawl(d, side, level) {
    const foe = other(side);
    // Maya Lv.3 buffs an ally before the punches start
    for (const slot of FRONT) if (d.canUseAbility(side, slot)) return { kind: 'ability', slot };
    const act = activation(d, side, level);
    if (act) return act;
    // Easy and Normal take the first attacker's best hit; Hard picks the best hit of all
    let plan = {}, planScore = 0;
    for (const slot of FRONT) {
        if (!d.canAttackWith(side, slot)) continue;
        if (level === 'easy' && roll(d, side, slot) < 35) continue;   // an easy CPU sometimes forgets to attack
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
                score = targetScore(att, d.cardAt(foe, t), level);
            }
            if (score > bestScore) {
                bestScore = score;
                best = t;
                if (level === 'easy') break;
            }
        }
        if (best !== NO_TARGET && level !== 'hard') return { kind: 'attack', from: slot, target: best };
        if (best !== NO_TARGET && bestScore > planScore) {
            planScore = bestScore;
            plan = { kind: 'attack', from: slot, target: best };
        }
    }
    return plan;
}

/** Hard, before ending its turn: characters in ATK that would lose to an enemy that can attack
 *  next turn switch to DEF, so a lost brawl costs no Morale. Same as _brace in duel_ai.gd. */
function brace(d, side) {
    let danger = 0;
    for (const e of d.characters(other(side))) if (!e.card.downed && !e.card.face_down) danger = Math.max(danger, e.card.attack);
    for (const slot of FRONT) {
        const c = d.cardAt(side, slot);
        if (c && c.position === 'atk' && c.cardType !== 'leader' && danger > c.attack && d.canChangePosition(side, slot)) return { kind: 'position', slot };
    }
    return {};
}

/** How much the CPU wants to attack this enemy character (0 = not worth it). */
function targetScore(att, df, level) {
    let score = 0;
    if (df.face_down) score = att.attack >= 1600 ? 1 : 0;   // unknown DEF: only strong attackers try
    else if (df.downed) score = att.attack > df.defense ? 3 : 0;
    else if (df.position === 'def') score = att.attack > df.defense ? 2 : 0;
    else if (att.attack > df.attack) score = 2 + (att.attack - df.attack) / 1000;
    else if (level === 'hard' && att.attack === df.attack && att.base_attack < df.base_attack) score = 1.5;   // even trade, our weaker card
    if (df.shield) score *= 0.5;   // the hit only pops the shield
    return score;
}

/** The order an Activate's sacrifice prompt offers allies in (DuelState attackValue). */
function toAttackValue(c) {
    return Math.trunc(Number(c.attack) || 0) + (c.downed ? 0 : 1);
}

/** How much a character is worth keeping (lowest = the first to sacrifice for a Heavy). */
function keepValue(c) {
    if (c.downed) return -1;
    let v = c.attack;
    if (c.poison !== undefined || c.bleed !== undefined) v -= 500;
    return v;
}

/** A repeatable 0-99 "dice roll" (must match duel_ai.gd). */
function roll(d, side, slot) {
    return (d.turn * 37 + slot * 53 + d.sides[side].hand.length * 17) % 100;
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
