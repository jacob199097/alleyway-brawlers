/**
 * BRAWL PHASE
 * Pure combat math, no Phaser dependencies.
 * DuelScene delegates all damage calculation here so the same
 * logic can be shared with MultiplayerDuelScene.
 *
 * Combat rules:
 *   • Defender in ATK position  → compare ATK vs ATK
 *       – higher ATK wins, loser destroyed, excess dealt to loser's morale
 *       – equal ATK: tie, both destroyed, no morale damage
 *   • Defender in DEF position  → compare ATK vs DEF
 *       – ATK > DEF: defender destroyed, no morale damage
 *       – ATK ≤ DEF: defender holds, no damage to either side
 *   • Defender is Downed        → compare ATK vs DEF (regardless of original position)
 *       – ATK > DEF: defender destroyed, no morale damage
 *       – ATK ≤ DEF: attack blocked, defender stays Downed, no damage
 *   • Direct attack             → ATK dealt directly to opponent morale
 */

export class BrawlPhase {

    /**
     * @param {Phaser.Scene} scene    — for access to EffectBus emissions
     * @param {object}       state   — shared game state object from DuelScene
     * @param {object}       effectBus
     */
    constructor(scene, state, effectBus) {
        this.scene     = scene;
        this.state     = state;
        this.effectBus = effectBus;
    }

    // ── Monster vs Monster ────────────────────────────────────────────────────

    /**
     * @param {number} attackerSlot  — 0-4 index on attacker's field
     * @param {number} defenderSlot  — 0-4 index on defender's field
     * @param {string} attackerOwner — 'player' | 'opponent'
     * @returns {CombatResult}
     */
    resolveAttack(attackerSlot, defenderSlot, attackerOwner) {
        const defOwner = attackerOwner === 'player' ? 'opponent' : 'player';
        const attCard  = this.state[attackerOwner].field[attackerSlot];
        const defCard  = this.state[defOwner].field[defenderSlot];

        if (!attCard) throw new Error('No attacker at slot ' + attackerSlot);
        if (!defCard) throw new Error('No defender at slot ' + defenderSlot);

        attCard.hasAttacked = true;
        let result;

        if (defCard.downed) {
            // ── Downed defender: ATK vs DEF ──────────────────────────────────
            // Downed characters brace — only piercing their DEF finishes them off.
            if (attCard.attack > defCard.defense) {
                this.state[defOwner].field[defenderSlot] = null;
                this.state[defOwner].gutter.push(defCard);
                result = { defenderDestroyed: true, defenderDowned: false,
                           attackerDestroyed: false, tie: false, moraleDealt: 0,
                           defenderWasDowned: true };
                this._applyAttackerPromotion(result, attCard, attackerSlot, attackerOwner);
            } else {
                // DEF holds — downed card survives, no damage to either side
                result = { defenderDestroyed: false, defenderDowned: false,
                           attackerDestroyed: false, tie: false, moraleDealt: 0 };
            }

        } else if (defCard.position === 'def') {
            // ── ATK vs DEF position ──────────────────────────────────────────
            if (attCard.attack > defCard.defense) {
                result = this._applyDefeat(defCard, defOwner, defenderSlot,
                    { defenderDestroyed: false, attackerDestroyed: false, tie: false, moraleDealt: 0 },
                    'defender');
                if (result.defenderDestroyed) this._applyAttackerPromotion(result, attCard, attackerSlot, attackerOwner);
            } else {
                // Defender walls the attack — no damage to either side
                result = { defenderDestroyed: false, defenderDowned: false, attackerDestroyed: false, tie: false, moraleDealt: 0 };
            }

        } else {
            // ── ATK vs ATK position ──────────────────────────────────────────
            if (attCard.attack > defCard.attack) {
                const excess = attCard.attack - defCard.attack;
                this.state[defOwner].morale -= excess;
                result = this._applyDefeat(defCard, defOwner, defenderSlot,
                    { defenderDestroyed: false, attackerDestroyed: false, tie: false, moraleDealt: excess },
                    'defender');
                if (result.defenderDestroyed) this._applyAttackerPromotion(result, attCard, attackerSlot, attackerOwner);

            } else if (attCard.attack < defCard.attack) {
                const excess = defCard.attack - attCard.attack;
                this.state[attackerOwner].morale -= excess;
                result = this._applyDefeat(attCard, attackerOwner, attackerSlot,
                    { defenderDestroyed: false, attackerDestroyed: false, tie: false, moraleDealt: -excess },
                    'attacker');

            } else {
                // Tie — both downed (or destroyed if already downed), no morale damage
                result = { defenderDestroyed: false, defenderDowned: false, attackerDestroyed: false, attackerDowned: false, tie: true, moraleDealt: 0 };
                this._applyDefeatInto(result, defCard, defOwner, defenderSlot, 'defender');
                this._applyDefeatInto(result, attCard, attackerOwner, attackerSlot, 'attacker');
            }
        }

        this.effectBus.trigger('on_battle', {
            attacker: attCard, defender: defCard, result, attackerOwner, defOwner,
            attackerSlotIdx: attackerSlot, defenderSlotIdx: defenderSlot,
        });

        return result;
    }

    // ── Downed State helpers ──────────────────────────────────────────────────

    /**
     * Applies defeat to one side's card: first hit = Downed, second hit = Destroyed.
     * Mutates `base` result in-place and returns it.
     */
    _applyDefeat(card, owner, slotIdx, base, side) {
        this._applyDefeatInto(base, card, owner, slotIdx, side);
        return base;
    }

    _applyDefeatInto(result, card, owner, slotIdx, side) {
        const destroyedKey = side === 'defender' ? 'defenderDestroyed' : 'attackerDestroyed';
        const downedKey    = side === 'defender' ? 'defenderDowned'    : 'attackerDowned';

        if (card.downed) {
            // Already Downed — finish it off
            this.state[owner].field[slotIdx] = null;
            this.state[owner].gutter.push(card);
            result[destroyedKey] = true;
            result[downedKey]    = false;
        } else {
            // First loss — go Downed, stay in slot
            card.downed = true;
            result[downedKey]    = true;
            result[destroyedKey] = false;
        }
    }

    // ── Attacker promotion (kill-based) ───────────────────────────────────────

    _applyAttackerPromotion(result, attCard, attackerSlot, attackerOwner) {
        if (!attCard.promotesTo) return;
        // Cards with ability-only promotion (e.g. Maya) never auto-promote on kills
        if (attCard.abilityOnlyPromote) return;
        const needed = attCard.promotionKillsNeeded || 1;
        attCard._promotionKills = (attCard._promotionKills || 0) + 1;
        if (attCard._promotionKills >= needed) {
            result.promoted       = true;
            result.promotedCardId = attCard.promotesTo;
            result.promotingSlot  = attackerSlot;
            result.promotingOwner = attackerOwner;
        }
    }

    // ── Direct attack ─────────────────────────────────────────────────────────

    /**
     * @param {number} attackerSlot
     * @param {string} attackerOwner
     * @returns {CombatResult}
     */
    resolveDirectAttack(attackerSlot, attackerOwner) {
        const defOwner = attackerOwner === 'player' ? 'opponent' : 'player';
        const attCard  = this.state[attackerOwner].field[attackerSlot];

        if (!attCard) throw new Error('No attacker at slot ' + attackerSlot);

        const oppFront = this.state[defOwner].field.slice(0, 5).filter(Boolean);
        if (oppFront.length) throw new Error('Cannot attack directly while opponent has Gang Members.');

        attCard.hasAttacked = true;
        this.state[defOwner].morale -= attCard.attack;

        const result = {
            defenderDestroyed: false,
            attackerDestroyed: false,
            tie:         false,
            moraleDealt: attCard.attack,
            isDirect:    true,
        };

        this.effectBus.trigger('on_direct_attack', { attacker: attCard, result, attackerOwner });

        return result;
    }
}

/**
 * @typedef {object} CombatResult
 * @property {boolean} defenderDestroyed  — true when defender sent to Gutter
 * @property {boolean} [defenderDowned]   — true when defender first becomes Downed
 * @property {boolean} attackerDestroyed  — true when attacker sent to Gutter
 * @property {boolean} [attackerDowned]   — true when attacker first becomes Downed
 * @property {boolean} tie
 * @property {number}  moraleDealt  — positive = opp lost morale, negative = attacker lost morale
 * @property {boolean} [isDirect]
 * @property {boolean} [promoted]
 * @property {string}  [promotedCardId]
 * @property {number}  [promotingSlot]
 * @property {string}  [promotingOwner]
 */
