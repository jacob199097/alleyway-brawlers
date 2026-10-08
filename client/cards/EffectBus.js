/**
 * EFFECT BUS
 * Pub/sub system for card effects.
 * Cards register handlers keyed by their `effectKey` field.
 * The BrawlPhase and DuelScene emit trigger events here.
 *
 * Trigger points (matching server duelHandler.js):
 *   'on_play'          — when the card is placed on the field
 *   'on_battle'        — after combat resolution
 *   'on_direct_attack' — after a direct attack
 *   'on_destroy'       — when the card itself is sent to Gutter
 *   'on_downed'        — when the card first becomes Downed
 *   'on_ambush'        — when a face-down Ambush is flipped
 *   'on_promote'       — when a Striver promotes to next level
 *   'on_upkeep'        — at the start of the active player's turn
 */

export class EffectBus {

    constructor(scene) {
        this.scene    = scene;
        this._handlers = new Map();  // effectKey → handler fn

        this._registerBuiltins();
    }

    /**
     * Register a custom handler for a card effect key.
     * @param {string}   effectKey
     * @param {Function} handler   (payload) => void
     */
    register(effectKey, handler) {
        this._handlers.set(effectKey, handler);
    }

    /**
     * Trigger a named game event. Iterates all field cards and fires
     * handlers whose triggerPoint matches.
     *
     * @param {string} triggerPoint  — e.g. 'on_battle'
     * @param {object} payload
     */
    trigger(triggerPoint, payload) {
        for (const [key, handler] of this._handlers) {
            try {
                handler(triggerPoint, payload, this.scene);
            } catch (err) {
                console.warn(`[EffectBus] Handler "${key}" threw:`, err.message);
            }
        }
    }

    // ── Built-in card effect implementations ─────────────────────────────────

    _registerBuiltins() {

        // Lion Clan Bonus: +300 ATK to all [Lion] tagged cards when 2+ are face-up.
        // Actual math lives in DuelScene._recalcClanBonuses; this just triggers it.
        this.register('lion_clan_bonus', (trigger, payload, scene) => {
            if (!['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) return;
            scene._recalcClanBonuses?.();
        });

        // Eric Lv.3 sweep: on promotion, send all non-Lion Characters with ATK < Eric's ATK to The Gutter
        this.register('eric_lv3_sweep', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'eric_lv3_sweep') return;
            if (!payload.isPromotion) return;

            const owner    = payload.owner;
            const defOwner = owner === 'player' ? 'opponent' : 'player';
            const eric     = payload.card;

            for (const side of [owner, defOwner]) {
                const rows = side === 'player'
                    ? [scene._slotObjects?.pl_front]
                    : [scene._slotObjects?.opp_front];
                for (const row of rows) {
                    if (!row) continue;
                    for (const slot of row) {
                        const card = scene.state[side].field[slot.slotIndex];
                        if (!card || card.clanTag === 'lion' || card === eric) continue;
                        if (card.attack < eric.attack) {
                            scene._sendToGraveyard?.(side, slot);
                        }
                    }
                }
            }

            scene._showFloatingText?.(scene.scale.width / 2, 200, 'ERIC LV.3: SWEEP!', '#ff6b35');
            scene._recalcClanBonuses?.();
        });

        // ── Eric Lv.3 – Draw + per-turn ATK scaling ──────────────────────────
        // On destroy by battle (when Eric himself is the destroyed defender): draw 1 card.
        // on_upkeep: +100 ATK per other LIONS card controlled (recalced each upkeep).
        this.register('eric_lv3_draw', (trigger, payload, scene) => {
            if (trigger === 'on_battle') {
                const { result, defender, attackerOwner } = payload;
                if (!result?.defenderDestroyed) return;
                // Only draw when Eric himself is the one being destroyed
                if (defender?.effectKey !== 'eric_lv3_draw') return;
                const defOwner = attackerOwner === 'player' ? 'opponent' : 'player';
                scene._drawCard?.(defOwner);
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'ERIC LV.3: DRAW!', '#f4d35e');
                return;
            }
            if (trigger === 'on_upkeep') {
                // Eric Lv.3's +100 ATK per other LIONS is now computed inside
                // _recalcClanBonuses; the upkeep just needs to recompute.
                scene._recalcClanBonuses?.();
            }
        });

        // ── Maya Lv.3 – once per turn: chosen LIONS card gains +400/+400 ────
        this.register('maya_lv3_buff', (trigger, payload, scene) => {
            if (trigger !== 'on_upkeep') return;
            const owner = payload.owner;
            if (scene.state.activePlayer !== owner) return;
            const maya = scene.state[owner].field.find(c => c?.effectKey === 'maya_lv3_buff');
            if (!maya || maya.abilityUsedThisTurn || maya.downed) return;
            // Mark for use by player action menu this turn
            maya._mayaBuffAvailable = true;
        });

        // ── Pride Runner – +400 ATK while adjacent to another LIONS ─────────
        this.register('pride_runner_adjacency', (trigger, payload, scene) => {
            if (!['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) return;
            scene._recalcPrideRunnerBonuses?.();
        });

        // ── Lion Grunt – +300 ATK when you control another LIONS ─────────────
        this.register('lion_grunt_synergy', (trigger, payload, scene) => {
            if (!['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) return;
            scene._recalcClanBonuses?.();
        });

        // ── Block Enforcer – redirect attack to itself once per turn ─────────
        // Handled in DuelScene targeting logic; this just shows a toast on deploy.
        this.register('block_enforcer_redirect', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'block_enforcer_redirect') return;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'BLOCK ENFORCER: HOLDING THE LINE!', '#4cc9f0');
        });

        // ── Goldfang – +500 ATK when attacking a DEF-position character ──────
        // Applied temporarily in BrawlPhase via _preAttackBonus. Shown as toast.
        this.register('goldfang_attacker', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, defender, result } = payload;
            if (attacker?.effectKey !== 'goldfang_attacker') return;
            if (defender?.position !== 'def') return;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'GOLDFANG: +500 ATK vs DEFENDER!', '#f4d35e');
        });

        // ── Pride Lieutenant – on deploy: another LIONS gets +500 ATK ────────
        this.register('pride_lieutenant_deploy', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'pride_lieutenant_deploy') return;
            const owner = payload.owner;
            const lt = payload.card;
            if (owner === 'player') {
                scene._promptLieutenantBuff?.(owner, lt);
            } else {
                // AI: auto-buff strongest eligible LIONS
                const field = scene.state[owner].field;
                const target = field.filter(c => c && c !== lt && c.clanTag === 'lion' && !c.downed && !c.faceDown)
                    .sort((a, b) => b.attack - a.attack)[0];
                if (!target) return;
                target._baseAtk = target._baseAtk ?? target.attack;
                target._ltBuff  = (target._ltBuff || 0) + 500;
                scene._showFloatingText?.(scene.scale.width / 2, 200, `LIEUTENANT: ${target.name} +500 ATK!`, '#f4d35e');
                scene._recalcClanBonuses?.();
            }
        });

        // ── Pride Mentor – draw 2 when a LIONS Striver promotes ─────────────
        this.register('pride_mentor_draw', (trigger, payload, scene) => {
            if (trigger !== 'on_promote') return;
            const owner  = payload.owner;
            const mentor = scene.state[owner].field.find(c => c?.effectKey === 'pride_mentor_draw' && !c.downed);
            if (!mentor) return;
            scene._drawCard?.(owner);
            scene._drawCard?.(owner);
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'PRIDE MENTOR: DRAW 2!', '#4cc9f0');
        });

        // ── Brutus – on enter: chosen enemy -700 ATK; on kill: next LIONS +300 ATK
        this.register('brutus_enter', (trigger, payload, scene) => {
            if (trigger === 'on_play') {
                if (payload.card?.effectKey !== 'brutus_enter') return;
                const owner = payload.owner;
                const defOwner = owner === 'player' ? 'opponent' : 'player';
                if (owner === 'player') {
                    scene._promptBrutusTarget?.(defOwner);
                } else {
                    // AI: auto-debuff strongest enemy
                    const target = scene.state[defOwner].field
                        .filter(c => c && !c.downed && c.cardType === 'gang_member')
                        .sort((a, b) => b.attack - a.attack)[0];
                    if (!target) return;
                    target._baseAtk = target._baseAtk ?? target.attack;
                    target._brutusDebuff = (target._brutusDebuff || 0) + 700;
                    scene._showFloatingText?.(scene.scale.width / 2, 200, `BRUTUS: ${target.name} -700 ATK!`, '#e63946');
                    scene._recalcClanBonuses?.();
                }
                return;
            }
            if (trigger === 'on_battle') {
                const { result, attacker, attackerOwner } = payload;
                if (attacker?.effectKey !== 'brutus_enter') return;
                if (!result?.defenderDestroyed) return;
                scene.state[attackerOwner]._brutusChainBonus = 300;
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'BRUTUS: NEXT LION +300 ATK!', '#f4d35e');
            }
        });

        // ── King Roan (Leader) – dormant passive applied via _recalcClanBonuses
        // Awaken check happens in DuelScene at the start of each turn.
        this.register('king_roan_leader', (trigger, payload, scene) => {
            if (trigger === 'on_play' && payload.card?.effectKey === 'king_roan_leader' && payload.isLeaderEntry) {
                scene._showFloatingText?.(scene.scale.width / 2, 140, '👑 LEADER BONUS ACTIVATED!', '#f4d35e');
                scene._recalcClanBonuses?.();
            }
        });

        // ── Ambush: Lion's Ambush – attacker loses 1000 ATK this brawl ─────────
        this.register('lion_ambush', (trigger, payload, scene) => {
            if (trigger !== 'on_ambush') return;
            const { attackerIdx } = payload;
            const attacker = scene.state.opponent.field[attackerIdx];
            if (!attacker) return;
            attacker._baseAtk = attacker._baseAtk ?? attacker.attack;
            attacker._ambushDebuff = (attacker._ambushDebuff || 0) + 1000;
            scene._showFloatingText?.(scene.scale.width / 2, 180, "LION'S AMBUSH: ATTACKER -1000 ATK!", '#f4d35e');
            scene._recalcClanBonuses?.();
        });

        // ── Ambush: No Witnesses – negate attack + down the attacker ─────────
        this.register('no_witnesses_ambush', (trigger, payload, scene) => {
            if (trigger !== 'on_ambush') return;
            const { attackerIdx } = payload;
            const attacker = scene.state.opponent.field[attackerIdx];
            if (!attacker) return;
            attacker.downed = true;
            // Visual downed on the opponent's slot
            const slot = scene._slotObjects?.opp_front?.find(s => s.slotIndex === attackerIdx);
            slot?.cardObject?.setDowned?.();
            scene._showFloatingText?.(scene.scale.width / 2, 180, 'NO WITNESSES: ATTACK NEGATED!', '#e63946');
            scene.effectBus.trigger('on_downed', { card: attacker, owner: 'opponent' });
            scene._recalcDownedBonuses?.();
        });

        // ── Ambush: King's Test – negate destruction of a LIONS Striver ──────
        // Logic handled in DuelScene._resolveVisualAftermath; this shows toast.
        this.register('kings_test', (trigger, payload, scene) => {
            if (trigger !== 'on_ambush') return;
            const { targetIdx } = payload;
            const target = targetIdx != null ? scene.state.player.field[targetIdx] : null;
            if (!target || target.subtype !== 'striver' || target.clanTag !== 'lion') return;
            // Mark the target so the next destruction is negated once
            target._kingsTestShield = true;
            scene._showFloatingText?.(scene.scale.width / 2, 180, "KING'S TEST: DESTRUCTION NEGATED!", '#f4d35e');
        });

        // ── Hustle: Corner Deal – draw 2, discard 1 (free with Striver) ──────
        this.register('corner_deal', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'corner_deal') return;
            const owner = payload.owner;
            scene._drawCard?.(owner);
            scene._drawCard?.(owner);
            const hasStriver = scene.state[owner].field.some(c => c && c.subtype === 'striver' && !c.downed);
            if (!hasStriver) {
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'CORNER DEAL: DRAW 2 – DISCARD 1', '#4cc9f0');
                scene._promptDiscard?.(owner);
            } else {
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'CORNER DEAL: DRAW 2 FREE!', '#4cc9f0');
            }
        });

        // ── Hustle: Blood Scent – player selects which Striver gets promo-ready ──
        this.register('blood_scent', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'blood_scent') return;
            scene._promptBloodScent?.(payload.owner);
        });

        // ── Hustle: Lion Rescue – stand a Downed LIONS character ─────────────
        this.register('lion_rescue', (trigger, payload, scene) => {
            if (trigger !== 'on_play') return;
            if (payload.card?.effectKey !== 'lion_rescue') return;
            const owner = payload.owner;
            if (owner === 'player') {
                scene._promptLionRescue?.(owner);
            } else {
                const target = scene.state[owner].field.find(c => c?.downed && c.clanTag === 'lion');
                if (!target) return;
                const slotIdx = scene.state[owner].field.indexOf(target);
                scene._recoverDownedCard?.(owner, slotIdx);
                scene._showFloatingText?.(scene.scale.width / 2, 200, `LION RESCUE: ${target.name} STANDS UP!`, '#4cc9f0');
            }
        });

        // ── Hunter Lv.1 – +500 vs Downed (handled in _declareAttack); promote on KO downed
        this.register('hunter_lv1', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner } = payload;
            if (attacker?.effectKey !== 'hunter_lv1') return;
            if (!result.defenderWasDowned || !result.defenderDestroyed) return;
            const slotIdx = scene.state[attackerOwner].field.indexOf(attacker);
            if (slotIdx === -1) return;
            result.promoted       = true;
            result.promotedCardId = 'hunter_lv2';
            result.promotingSlot  = slotIdx;
            result.promotingOwner = attackerOwner;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'HUNTER: PROMOTED!', '#f4d35e');
        });

        // ── Hunter Lv.2 – promote on KO downed; down 1 enemy on any KO
        this.register('hunter_lv2', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner, defOwner } = payload;
            if (attacker?.effectKey !== 'hunter_lv2') return;
            if (!result.defenderDestroyed) return;
            // Promote on downed KO
            if (result.defenderWasDowned) {
                const slotIdx = scene.state[attackerOwner].field.indexOf(attacker);
                if (slotIdx !== -1) {
                    result.promoted       = true;
                    result.promotedCardId = 'hunter_lv3';
                    result.promotingSlot  = slotIdx;
                    result.promotingOwner = attackerOwner;
                    scene._showFloatingText?.(scene.scale.width / 2, 200, 'HUNTER LV.2: PROMOTED!', '#f4d35e');
                }
            }
            // Down 1 enemy on any KO
            result.hunterShouldDown = true;
        });

        // ── Hunter Lv.3 – attack again on KO downed; down 1 enemy on any KO
        this.register('hunter_lv3', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner } = payload;
            if (attacker?.effectKey !== 'hunter_lv3') return;
            if (!result.defenderDestroyed) return;
            result.hunterShouldDown = true;
            if (result.defenderWasDowned) {
                result.attackerCanAttackAgain = true;
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'HUNTER LV.3: ATTACK AGAIN!', '#f4d35e');
            }
        });

        // ── Viper Lv.1 – promote on Down (pre-move handled in _selectAttacker)
        this.register('viper_lv1', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner } = payload;
            if (attacker?.effectKey !== 'viper_lv1') return;
            if (!result.defenderDowned) return;
            const slotIdx = scene.state[attackerOwner].field.indexOf(attacker);
            if (slotIdx === -1) return;
            result.promoted       = true;
            result.promotedCardId = 'viper_lv2';
            result.promotingSlot  = slotIdx;
            result.promotingOwner = attackerOwner;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'VIPER: PROMOTED!', '#4cc9f0');
        });

        // ── Viper Lv.2 – promote on Down
        this.register('viper_lv2', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner } = payload;
            if (attacker?.effectKey !== 'viper_lv2') return;
            if (!result.defenderDowned) return;
            const slotIdx = scene.state[attackerOwner].field.indexOf(attacker);
            if (slotIdx === -1) return;
            result.promoted       = true;
            result.promotedCardId = 'viper_lv3';
            result.promotingSlot  = slotIdx;
            result.promotingOwner = attackerOwner;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'VIPER LV.2: PROMOTED!', '#4cc9f0');
        });

        // ── Viper Lv.3 – move after KO; attack again on KO downed
        this.register('viper_lv3', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner } = payload;
            if (attacker?.effectKey !== 'viper_lv3') return;
            if (!result.defenderDestroyed) return;
            result.viperShouldMoveAfterKill = true;
            if (result.defenderWasDowned) {
                result.attackerCanAttackAgain = true;
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'VIPER LV.3: ATTACK AGAIN!', '#4cc9f0');
            }
        });

        // ── Debt Collector – opponent discards 1 on Down by battle
        this.register('debt_collector', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, attackerOwner, defOwner } = payload;
            if (attacker?.effectKey !== 'debt_collector') return;
            if (!result.defenderDowned) return;
            scene._showFloatingText?.(scene.scale.width / 2, 200, 'DEBT COLLECTOR: OPPONENT DISCARDS!', '#e63946');
            scene._debtCollectorDiscard?.(defOwner);
        });

        // ── Bulwark – deploy toast + recompute adjacent DEF on field changes
        this.register('bulwark', (trigger, payload, scene) => {
            if (trigger === 'on_play' && payload.card?.effectKey === 'bulwark') {
                scene._showFloatingText?.(scene.scale.width / 2, 200, 'BULWARK: HOLDING THE LINE!', '#4cc9f0');
            }
            if (['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) {
                scene._recalcBulwarkDefBonuses?.();
            }
        });

        // ── Mauler – +500 vs Downed (handled in _declareAttack); adj DEF debuff on KO downed
        this.register('mauler', (trigger, payload, scene) => {
            if (trigger !== 'on_battle') return;
            const { attacker, result, defenderSlotIdx } = payload;
            if (attacker?.effectKey !== 'mauler') return;
            if (!result.defenderWasDowned || !result.defenderDestroyed) return;
            result.maulerAdjDebuff     = true;
            result.maulerAdjDebuffSlot = defenderSlotIdx ?? -1;
        });

        // ── Kingpin – +400 ATK while opponent has Downed
        this.register('kingpin', (trigger, payload, scene) => {
            if (['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) {
                scene._recalcDownedBonuses?.();
            }
        });

        // ── Sovereign – on enter: sweep enemies ≤ 1500 DEF; +600 ATK while opp has Downed
        this.register('sovereign', (trigger, payload, scene) => {
            if (trigger === 'on_play' && payload.card?.effectKey === 'sovereign') {
                scene._sovereignSweep?.(payload.owner);
            }
            if (['on_play', 'on_battle', 'on_destroy', 'on_downed'].includes(trigger)) {
                scene._recalcDownedBonuses?.();
            }
        });
    }
}
