/**
 * AI BRAIN — Utility AI for the CPU opponent.
 *
 * Pure decision module. Reads game `state` + `BrawlPhase` and returns
 * action plans. DuelScene drives the animations.
 *
 * Public API:
 *   plan = AiBrain.planDeployment(state, brawlPhase)
 *     → [{ type: 'play_character', cardIdx, slotIdx, position }, …]
 *   plan = AiBrain.planBrawl(state, brawlPhase)
 *     → [{ attackerIdx, targetIdx }] — targetIdx is null for direct attacks
 *
 * Design:
 *   Each candidate action is scored. We commit the best, re-score, repeat.
 *   This gives natural reactivity: once a Striver is queued to promote,
 *   its target stops being a candidate for other attackers.
 */

const SIDE = { SELF: 'opponent', FOE: 'player' };

// ── Tunable weights ──────────────────────────────────────────────────────────
const W = {
    // Deployment
    fillFrontRow:    50,    // empty front-row slot is bad — fill it
    perAttack:        0.05, // 1 ATK ≈ 0.05 utility (per-stat scoring)
    perDefense:       0.04,
    heavyBonus:      30,    // Heavies are board anchors
    striverPotential:18,    // Strivers are valuable when promote target exists
    survivalDefBias: 60,    // when low Morale, bias toward DEF position
    setAmbushBase:   12,    // setting any trap is mild value
    hardwareBoost:    1.2,  // multiplier on stat utility for hardware target
    overcommitPenalty:-8,   // already 3+ characters out — diminishing returns

    // Brawl
    lethal:         9999,   // take it. always.
    promoteKill:     400,   // Striver kills foe → promote — top priority
    killWithoutLoss: 120,   // we kill them, we live
    valueTrade:       60,   // trade up: kill higher-stat target with lower-stat self
    evenTrade:        20,
    suicide:        -100,   // we die, they live — usually bad
    moraleDamage:     0.05, // per point of morale damage dealt
    directAttack:     30,   // direct hit on empty board
};

// ── Card helpers ─────────────────────────────────────────────────────────────

function isCharacter(c)  { return c && c.cardType === 'gang_member'; }
function isHardware(c)   { return c && c.cardType === 'hardware'; }
function isAmbush(c)     { return c && c.cardType === 'ambush'; }
function isHustle(c)     { return c && c.cardType === 'hustle'; }
function isStriver(c)    { return c && c.promotesTo; }
function isHeavy(c)      { return c && (c.authority || 0) >= 5; }

// Effective stats taking attached hardware into account
function effectiveStats(field, slotIdx) {
    const c = field[slotIdx];
    if (!c) return null;
    let atk = c.attack || 0, def = c.defense || 0;
    const hw = field[slotIdx + 5];
    if (hw && hw.cardType === 'hardware' && hw._attachedToFront === slotIdx) {
        atk += hw.atkMod || 0;
        def += hw.defMod || 0;
    }
    return { atk, def, position: c.position || 'atk', card: c };
}

function frontRowStats(field) {
    const out = [];
    for (let i = 0; i < 5; i++) {
        const s = effectiveStats(field, i);
        if (s) out.push({ slotIdx: i, ...s });
    }
    return out;
}

// ── DEPLOYMENT PLANNER ───────────────────────────────────────────────────────

function planDeployment(state) {
    const me  = state[SIDE.SELF];
    const foe = state[SIDE.FOE];
    const plan = [];

    // We mutate a snapshot of authority + hand so we can score successive picks
    let authLeft = me.authority;
    const hand   = me.hand.map((c, i) => ({ ...c, _origIdx: i }));
    const field  = me.field.slice();

    // Repeatedly score every legal action, commit the highest-scoring one,
    // until no positive-utility action remains.
    let safety = 12; // guard against infinite loops
    while (safety-- > 0) {
        const best = pickBestDeploymentAction(hand, field, authLeft, me, foe);
        if (!best || best.score <= 0) break;

        plan.push(best.action);

        // Commit to local snapshot so the next iteration sees the new state
        const card = hand[best.action.cardIdx];
        if (best.action.type === 'play_character') {
            field[best.action.slotIdx] = { ...card, position: best.action.position };
            authLeft -= card.authority || 0;
        } else if (best.action.type === 'set_ambush') {
            field[best.action.slotIdx + 5] = { ...card };
            authLeft -= card.authority || 0;
        } else if (best.action.type === 'attach_hardware') {
            field[best.action.slotIdx + 5] = { ...card, _attachedToFront: best.action.slotIdx };
            authLeft -= card.authority || 0;
        }
        // Mark hand card consumed
        hand[best.action.cardIdx] = null;
    }

    return plan;
}

function pickBestDeploymentAction(hand, field, authLeft, me, foe) {
    let best = null;

    for (let i = 0; i < hand.length; i++) {
        const card = hand[i];
        if (!card) continue;

        // Characters
        if (isCharacter(card) && (card.authority || 0) <= authLeft) {
            for (let s = 0; s < 5; s++) {
                if (field[s]) continue;
                ['atk', 'def'].forEach(pos => {
                    const score = scoreCharacterPlay(card, s, pos, field, me, foe);
                    if (!best || score > best.score) {
                        best = { score, action: { type: 'play_character', cardIdx: i, slotIdx: s, position: pos } };
                    }
                });
            }
        }

        // Hardware — attach to highest-ATK character without one
        if (isHardware(card) && (card.authority || 0) <= authLeft) {
            const targetSlot = pickHardwareTarget(field);
            if (targetSlot != null) {
                const score = scoreHardware(card, targetSlot, field);
                if (!best || score > best.score) {
                    best = { score, action: { type: 'attach_hardware', cardIdx: i, slotIdx: targetSlot } };
                }
            }
        }

        // Ambushes — set in any open back-row slot (costs authority like player)
        if (isAmbush(card) && (card.authority || 0) <= authLeft) {
            const backSlot = field.slice(5, 10).findIndex(v => !v);
            if (backSlot !== -1) {
                const score = W.setAmbushBase;
                if (!best || score > best.score) {
                    best = { score, action: { type: 'set_ambush', cardIdx: i, slotIdx: backSlot } };
                }
            }
        }

        // Hustles — out of scope for this pass; left as a stub
        // if (isHustle(card)) { … }
    }

    return best;
}

function scoreCharacterPlay(card, slotIdx, position, field, me, foe) {
    let score = 0;

    // Filling an empty front row is a strong baseline
    score += W.fillFrontRow;

    // Stat value (raw power)
    score += (card.attack || 0)  * W.perAttack;
    score += (card.defense || 0) * W.perDefense;

    // Heavy boss bonus
    if (isHeavy(card)) score += W.heavyBonus;

    // Strivers worth more if a promote target is sitting on the foe's front row
    if (isStriver(card)) {
        const promoteTarget = foe.field.slice(0, 5).find(c =>
            c && (c.attack || 0) < (card.attack || 0)
        );
        if (promoteTarget) score += W.striverPotential;
    }

    // Survival mode: heavily prefer DEF when our Morale is low
    if (me.morale < 2000) {
        if (position === 'def') score += W.survivalDefBias;
        else                    score -= W.survivalDefBias * 0.5;
    } else {
        // Normal mode: prefer ATK unless the card has way more DEF than ATK
        if (position === 'atk' && (card.attack || 0) >= (card.defense || 0)) score += 6;
        if (position === 'def' && (card.defense || 0) >  (card.attack || 0)) score += 4;
    }

    // Diminishing returns once we have a stacked board
    const onBoard = field.slice(0, 5).filter(Boolean).length;
    if (onBoard >= 3) score += W.overcommitPenalty;

    return score;
}

function pickHardwareTarget(field) {
    let bestSlot = null, bestAtk = -1;
    for (let i = 0; i < 5; i++) {
        const c = field[i];
        if (!c) continue;
        if (field[i + 5]) continue;       // back-row slot occupied
        if ((c.attack || 0) > bestAtk) {
            bestAtk = c.attack || 0;
            bestSlot = i;
        }
    }
    return bestSlot;
}

function scoreHardware(card, targetSlot, field) {
    const tgt = field[targetSlot];
    const stat = ((card.atkMod || 0) + (card.defMod || 0));
    return W.hardwareBoost * (stat + (tgt.attack || 0) * W.perAttack);
}

// ── BRAWL PLANNER ────────────────────────────────────────────────────────────

function planBrawl(state) {
    const me  = state[SIDE.SELF];
    const foe = state[SIDE.FOE];

    // Snapshot front rows; the planner mutates these snapshots as it commits
    const myFront  = frontRowStats(me.field).filter(s => s.card.position !== 'def'
        && !s.card.hasAttacked
        && !s.card.downed);
    let foeFront = frontRowStats(foe.field);

    const foeMorale = foe.morale;

    // 1) LETHAL CHECK — if we can sum-attack to 0, do it.
    const lethalPlan = tryLethal(myFront, foeFront, foeMorale);
    if (lethalPlan) return lethalPlan;

    // 2/3/4) Greedy utility loop: score each (attacker, target|direct) pair,
    // commit the best, remove attacker + (if killed) target, repeat.
    const plan = [];
    const remainingAttackers = [...myFront];
    const remainingTargets   = [...foeFront];

    let safety = 10;
    while (remainingAttackers.length && safety-- > 0) {
        const best = pickBestAttack(remainingAttackers, remainingTargets, foeMorale);
        if (!best || best.score <= W.suicide) break; // refuse pure suicide

        plan.push(best.action);

        // Remove the attacker (it has now attacked)
        remainingAttackers.splice(remainingAttackers.indexOf(best.attacker), 1);
        // If the target died, remove it from remainingTargets
        if (best.targetDies && best.target) {
            const idx = remainingTargets.indexOf(best.target);
            if (idx !== -1) remainingTargets.splice(idx, 1);
        }
        // If the attacker died, it's already gone from remainingAttackers above.
    }

    return plan;
}

function tryLethal(myFront, foeFront, foeMorale) {
    // Direct lethal — only valid if foeFront is empty.
    if (foeFront.length === 0) {
        const totalDmg = myFront.reduce((sum, a) => sum + a.atk, 0);
        if (totalDmg >= foeMorale) {
            return myFront.map(a => ({ attackerIdx: a.slotIdx, targetIdx: null }));
        }
        return null;
    }

    // Combo lethal — kill all foe front then push remaining damage.
    // Sort our attackers descending; greedy-assign smallest sufficient attacker
    // to each foe target so the highest-ATK pieces remain free to swing for face.
    const attackers = [...myFront].sort((a, b) => b.atk - a.atk);
    const targets   = [...foeFront].sort((a, b) => effectiveBlockHp(b) - effectiveBlockHp(a));
    const used      = new Set();
    const tradePlan = [];

    for (const t of targets) {
        // Find smallest attacker that can kill this target
        const tHp = effectiveBlockHp(t);
        const candidate = [...attackers]
            .filter(a => !used.has(a) && a.atk > tHp)
            .sort((a, b) => a.atk - b.atk)[0];
        if (!candidate) return null;        // can't clear board → no lethal
        used.add(candidate);
        tradePlan.push({ attackerIdx: candidate.slotIdx, targetIdx: t.slotIdx });
    }

    // Sum damage from clears + any free attackers swinging direct
    let dmg = 0;
    for (const t of targets) {
        const a = attackers.find(x => used.has(x) && tradePlan.some(p =>
            p.attackerIdx === x.slotIdx && p.targetIdx === t.slotIdx));
        if (a && t.position !== 'def') dmg += (a.atk - t.atk);
    }
    const freeAttackers = attackers.filter(a => !used.has(a));
    // Once front row is cleared, surviving attackers go direct
    dmg += freeAttackers.reduce((s, a) => s + a.atk, 0);

    if (dmg >= foeMorale) {
        return [
            ...tradePlan,
            ...freeAttackers.map(a => ({ attackerIdx: a.slotIdx, targetIdx: null })),
        ];
    }
    return null;
}

// "Effective HP" the attacker has to beat to kill a target
function effectiveBlockHp(target) {
    return target.position === 'def' ? target.def : target.atk;
}

function pickBestAttack(attackers, targets, foeMorale) {
    let best = null;

    for (const a of attackers) {
        // Direct attack option (only legal when targets[] is empty)
        if (targets.length === 0) {
            const score = W.directAttack + a.atk * W.moraleDamage;
            if (!best || score > best.score) {
                best = { score, attacker: a, target: null, targetDies: false,
                         action: { attackerIdx: a.slotIdx, targetIdx: null } };
            }
            continue;
        }

        for (const t of targets) {
            const score = scoreAttack(a, t, foeMorale);
            if (!best || score.score > best.score) {
                best = {
                    score: score.score,
                    attacker: a, target: t, targetDies: score.targetDies,
                    action: { attackerIdx: a.slotIdx, targetIdx: t.slotIdx },
                };
            }
        }
    }

    return best;
}

function scoreAttack(att, def, foeMorale) {
    const tHp = effectiveBlockHp(def);

    // ATK vs DEF — defender face-down/face-up DEF
    if (def.position === 'def') {
        if (att.atk > def.def) {
            // Clean kill, no morale damage
            let s = W.killWithoutLoss + (def.def * W.perDefense);
            if (isStriver(att.card)) s += W.promoteKill;
            return { score: s, targetDies: true };
        }
        // Wall — no damage to either side; mostly useless
        return { score: -10, targetDies: false };
    }

    // ATK vs ATK
    if (att.atk > def.atk) {
        const excess = att.atk - def.atk;
        let s = W.killWithoutLoss
              + (def.atk * W.perAttack * 2)              // value-trade scaling
              + (excess * W.moraleDamage);
        // Bonus when their card was strictly stronger statwise — solid trade up
        if ((def.atk + def.def) > (att.atk + att.def)) s += W.valueTrade;
        if (isStriver(att.card))                       s += W.promoteKill;
        if (excess >= foeMorale)                       s += W.lethal;
        return { score: s, targetDies: true };
    }

    if (att.atk === def.atk) {
        // Mutual destruction — fine if their piece is more valuable
        const myValue   = att.atk + att.def + (isHeavy(att.card)  ? 30 : 0);
        const foeValue  = def.atk + def.def + (isHeavy(def.card) ? 30 : 0);
        const s = W.evenTrade + (foeValue - myValue) * 0.5;
        return { score: s, targetDies: true };
    }

    // Suicide — defender stronger
    const excess = def.atk - att.atk;
    return { score: W.suicide - excess * W.moraleDamage, targetDies: false };
}

export const AiBrain = {
    planDeployment,
    planBrawl,
    // expose internals for tests / tuning
    _internals: { scoreAttack, scoreCharacterPlay, tryLethal, W },
};
