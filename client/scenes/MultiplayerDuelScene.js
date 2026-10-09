/**
 * MULTIPLAYER DUEL SCENE
 * Extends DuelScene's board layout and reuses its visual layer entirely.
 * Overrides the phase/action handlers to relay every action through Socket.io
 * rather than resolving locally.
 *
 * The server (duelHandler.js) is the authority — we optimistically update
 * visuals on the acting client, but roll back on 'duel:error'.
 */

import { DuelScene }    from './DuelScene.js';
import { CardObject }   from '../cards/CardObject.js';
import { SocketClient } from '../network/SocketClient.js';
import { Sfx }          from '../utils/Sfx.js';

export class MultiplayerDuelScene extends DuelScene {

    constructor() {
        super();
        this.sys.settings.key = 'MultiplayerDuelScene';
    }

    // ── init: receives match data from MatchmakingScene ──────────────────────

    init(data) {
        this._matchId        = data.matchId;
        this._roomId         = data.roomId;
        this._myPlayerId     = data.yourPlayerId;
        this._roleKey        = data.yourRole || 'p1';   // authoritative role from server
        this._opponentName   = data.opponentName;
        this._opponentAvatar = data.opponentAvatar;
        this._myTurn         = data.yourTurn;
        this._isMultiplayer  = true;

        super.init({ playerDeck: data.playerDeck || [], opponentDeck: [] });
    }

    create() {
        super.create();

        this._registerServerListeners();

        if (!this._myTurn) {
            this._setInteractionEnabled(false);
        }
    }

    // ── Override: intercept card placement → relay to server ─────────────────

    _placeCard(cardObj, slotIndex) {
        SocketClient.emit('duel:playCard', {
            matchId:   this._matchId,
            card:      cardObj.cardData,
            slotIndex,
        });
        super._placeCard(cardObj, slotIndex);
    }

    // ── Override: relay attacks ───────────────────────────────────────────────

    _declareAttack(attackerSlot, defenderSlot) {
        SocketClient.emit('duel:attack', {
            matchId:      this._matchId,
            attackerSlot: attackerSlot.slotIndex,
            defenderSlot: defenderSlot.slotIndex,
        });
        // Visuals applied when server echoes 'duel:attacked'
    }

    _declareDirectAttack(attackerSlot) {
        SocketClient.emit('duel:attack', {
            matchId:      this._matchId,
            attackerSlot: attackerSlot.slotIndex,
            defenderSlot: null,
        });
    }

    // ── Override: relay phase change ──────────────────────────────────────────

    _onPhaseButtonPressed(phaseKey) {
        if (!this._myTurn) return;
        SocketClient.emit('duel:phaseAdvance', { matchId: this._matchId });
    }

    // ── Server event listeners ────────────────────────────────────────────────

    _registerServerListeners() {
        const sc = SocketClient;

        // Opponent played a card
        sc.on('duel:cardPlayed', ({ role, slotIndex, card }) => {
            if (role === this._myRole()) return;   // already applied optimistically
            const isBack  = slotIndex >= 5;
            const rowKey  = isBack ? 'opp_back' : 'opp_front';
            const rowIdx  = isBack ? slotIndex - 5 : slotIndex;
            const slot    = this._slotObjects[rowKey][rowIdx];
            if (!slot) return;
            this._renderOpponentCard(slot, card);

            // Recalc clan bonuses after opponent places a card
            this._recalcClanBonuses();
        });

        // Combat result from server
        sc.on('duel:attacked', (payload) => {
            const { attackerRole, attackerSlot, defenderSlot, result,
                    ambushTriggered, ambushCard, p1Morale, p2Morale,
                    promoted, promotedCard, promotingRole, promotingSlot } = payload;

            // Sync authoritative morale values
            this.state.player.morale   = this._myRole() === 'p1' ? p1Morale : p2Morale;
            this.state.opponent.morale = this._myRole() === 'p1' ? p2Morale : p1Morale;

            const isMyAttack = attackerRole === this._myRole();
            const attSlots   = isMyAttack ? this._slotObjects.pl_front : this._slotObjects.opp_front;
            const defSlots   = isMyAttack ? this._slotObjects.opp_front : this._slotObjects.pl_front;

            const aSlot = attSlots[attackerSlot];
            const dSlot = defenderSlot !== null ? defSlots[defenderSlot] : null;

            if (ambushTriggered && ambushCard) {
                const ambushRow = isMyAttack ? this._slotObjects.opp_back : this._slotObjects.pl_back;
                const ambSlot   = ambushRow[defenderSlot];
                this._playAmbushAnimation(ambSlot, ambushCard);
            }

            if (dSlot) {
                this._playAttackAnimation(aSlot, dSlot, result || {});
            } else {
                this._playDirectAttackAnimation(aSlot, result || {});
            }

            // Server-authoritative promotion
            if (promoted && promotedCard) {
                const ownerKey = (promotingRole === this._myRole()) ? 'player' : 'opponent';
                this.time.delayedCall(650, () => {
                    this._doPromotion(ownerKey, promotingSlot, promotedCard);
                });
            }

            // On gameOver the server follows up with 'duel:matchOver' (winner + rewards)
        });

        // Phase advance from server
        sc.on('duel:phaseChanged', ({ phase, activePlayerId, turn }) => {
            this.state.turn  = turn;
            this._myTurn     = activePlayerId === this._myPlayerId;
            this._setInteractionEnabled(this._myTurn);
            this._startPhase(phase);
        });

        // Server-side error (e.g. invalid move)
        sc.on('duel:error', ({ message }) => {
            this._showFloatingText(W / 2, 200, message, '#e63946');
        });

        // Opponent disconnected
        sc.on('match:opponentDisconnected', ({ message }) => {
            // The server records the forfeit and follows up with 'duel:matchOver'
            this._showFloatingText(W / 2, 200, message, '#4cc9f0');
        });

        // Opponent chose a position for their promoted card
        sc.on('duel:promotionPositionSet', ({ role, slotIndex, position }) => {
            if (role === this._myRole()) return;   // we already applied ours locally
            const slot = this._slotObjects.opp_front.find(s => s.slotIndex === slotIndex);
            if (!slot) return;
            if (position === 'def') slot.cardObject?.container.setAngle(90);
            const card = this.state.opponent.field[slotIndex];
            if (card) card.position = position;
        });

        // Match over with rewards
        sc.on('duel:matchOver', (payload) => {
            this._handleMatchOver(payload);
        });

        // Authoritative stat snapshot — keeps both clients' HUDs in sync after
        // any state-changing event (placement, combat, promotion, buff/debuff).
        sc.on('duel:fieldStats', ({ stats }) => {
            if (!stats) return;
            const myRole = this._myRole();
            const meSnap = myRole === 'p1' ? stats.p1 : stats.p2;
            const opSnap = myRole === 'p1' ? stats.p2 : stats.p1;

            this._applyFieldStatsSnapshot('player',   meSnap);
            this._applyFieldStatsSnapshot('opponent', opSnap);

            this._refreshAllStatBadges();
        });
    }

    _applyFieldStatsSnapshot(owner, snap) {
        if (!Array.isArray(snap)) return;
        const field = this.state[owner].field;
        for (const entry of snap) {
            const card = field[entry.slotIndex];
            if (!card) continue;
            card.attack       = entry.attack;
            card.defense      = entry.defense;
            card._baseAttack  = entry.baseAttack;
            card._baseDefense = entry.baseDefense;
            card.position     = entry.position || card.position || 'atk';
        }
    }

    _handleMatchOver(payload) {
        const iWon     = payload.winnerId === this._myPlayerId;
        const myReward = payload.rewards?.[this._myPlayerId];

        this.bgm?.stop();
        Sfx.play(this, iWon ? 'sfx_victory' : 'sfx_defeat');

        this.time.delayedCall(1500, () => {
            this.scene.start('PostMatchScene', {
                result:  payload.winnerId == null ? 'draw' : (iWon ? 'win' : 'loss'),
                rewards: myReward || { karatEarned: 0, xpEarned: 0 },
            });
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _myRole() { return this._roleKey; }

    _onPromotionPositionChosen(slotIndex, position) {
        SocketClient.emit('duel:setPromotionPosition', {
            matchId:   this._matchId,
            slotIndex,
            position,
        });
    }

    _setInteractionEnabled(enabled) {
        this._phaseBtns?.forEach(btn => {
            if (enabled) btn.setInteractive();
            else         btn.disableInteractive();
        });
        if (!enabled) this._turnText?.setText("OPPONENT'S TURN...");
    }

    _renderOpponentCard(slot, card) {
        const cardObj = new CardObject(this, slot.x, slot.y, card, 'field_opp');
        if (card.faceDown) cardObj.flipFaceDown();
        slot.cardObject = cardObj;
        this.add.existing(cardObj.container);
        this._reattachOppZoom();
    }
}

// W is not exported from DuelScene so re-declare for the error toast
const W = 844;
