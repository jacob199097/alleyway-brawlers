/**
 * CARD OBJECT
 * A self-contained Phaser Container wrapping the visual representation
 * of one card. Handles rendering (frame, art, stats text) and all
 * touch input for drag-and-drop.
 *
 * Modes:
 *   'hand'      — shown in the player's hand strip; draggable
 *   'field_pl'  — placed on the player's side; tappable for combat select
 *   'field_opp' — placed on opponent's side; tappable as attack target
 */

import Phaser from 'phaser';
import { showCardZoom, attachHoldZoom } from '../utils/CardZoom.js';

const CARD_W = 64;
const CARD_H = 76;

export class CardObject extends Phaser.Events.EventEmitter {

    /**
     * @param {Phaser.Scene} scene
     * @param {number} x
     * @param {number} y
     * @param {object} cardData  — raw card JSON from the server/deck
     * @param {string} mode      — 'hand' | 'field_pl' | 'field_opp'
     */
    constructor(scene, x, y, cardData, mode = 'hand') {
        super();
        this.scene    = scene;
        this.cardData = cardData;
        this.mode     = mode;
        this._faceDown = cardData.cardType === 'ambush' && mode !== 'hand';
        this._homeX   = x;
        this._homeY   = y;

        this.container = scene.add.container(x, y);
        this._build();
        // Lets desktop right-click zoom / hover find this card (utils/DesktopInput.js)
        this._frame.cardObject = this;

        if (mode === 'hand') {
            this._attachTapListener();
            this._attachHoldZoom();
        }
    }

    // ── Visual construction ───────────────────────────────────────────────────

    // Maps card id → loaded texture key for monster art (fallback — art_url on card data takes priority)
    static ART_MAP = {
        eric_lv1:        'eric_lv1',
        eric_lv2:        'eric_lv2',
        eric_lv3:        'eric_lv3',
        king_roan:       'king_roan',
        maya_lv1:        'maya_lv1',
        maya_lv2:        'maya_lv2',
        maya_lv3:        'maya_lv3',
        pride_runner:    'pride_runner',
        lion_grunt:      'lion_grunt',
        block_enforcer:  'block_enforcer',
        goldfang:        'goldfang',
        pride_lieutenant:'pride_lieutenant',
        pride_mentor:    'pride_mentor',
        brutus:          'brutus',
        lion_ambush:     'lion_ambush',
        no_witnesses:    'no_witnesses',
        kings_test:      'kings_test',
        corner_deal:     'corner_deal',
        blood_scent:     'blood_scent',
        lion_rescue:     'lion_rescue',
    };

    _build() {
        if (this._faceDown) {
            this._art = this._makeBackImage();
            this.container.add(this._art);
            this._frame = this._makeHitTarget();
            this.container.add(this._frame);
            return;
        }

        // The supplied card images are full cards (frame + art + baked stats).
        // Render the whole image at card size — no overlays, no chrome.
        const artKey = CardObject._resolveArtKey(this.scene, this.cardData);
        if (artKey) {
            this._art = this.scene.add.image(0, 0, artKey).setDisplaySize(CARD_W, CARD_H);
            // Force LINEAR filtering so up-/down-scaling stays smooth
            this._art.texture?.setFilter?.(1);
        } else {
            // Fallback: minimal chrome with the card name when no art is loaded
            const bg = this.scene.add.rectangle(0, 0, CARD_W, CARD_H, 0x0d1020)
                .setStrokeStyle(1, 0xb388c9, 0.9);
            this.container.add(bg);
            const label = this.scene.add.text(0, 0, this.cardData?.name || '?', {
                fontSize: '7px', fontFamily: 'Arial Black', color: '#ffffff',
                wordWrap: { width: CARD_W - 4 }, align: 'center',
            }).setOrigin(0.5);
            this.container.add(label);
            this._art = bg;
        }
        if (this._art && this._art !== this.container.list[0]) this.container.add(this._art);

        // Transparent hit target on top — drag/tap input goes here
        this._frame = this._makeHitTarget();
        this.container.add(this._frame);
    }

    _makeBackImage() {
        if (this.scene.textures.exists('card_back')) {
            const img = this.scene.add.image(0, 0, 'card_back').setDisplaySize(CARD_W, CARD_H);
            img.texture?.setFilter?.(1);
            return img;
        }
        return this.scene.add.rectangle(0, 0, CARD_W, CARD_H, 0x2a2a3e)
            .setStrokeStyle(1, 0x6a0572);
    }

    _makeHitTarget() {
        return this.scene.add.rectangle(0, 0, CARD_W, CARD_H, 0x000000, 0);
    }

    // Resolve a loaded texture key for a card, in priority order.
    static _resolveArtKey(scene, cardData) {
        const d = cardData || {};
        if (d.art_url && scene.textures.exists(d.art_url)) return d.art_url;
        if (d.id && scene.textures.exists(d.id))           return d.id;
        const mapped = CardObject.ART_MAP[d.id];
        if (mapped && scene.textures.exists(mapped))       return mapped;
        return null;
    }

    // (Face-up content is the full card image — no programmatic chrome needed.)

    // ── Touch drag listeners (hand mode only) ────────────────────────────────

    // ── Hold-to-zoom (hand mode) ─────────────────────────────────────────────

    _attachHoldZoom() {
        let timer  = null;
        let startX = 0;
        let startY = 0;
        const cancel = () => { if (timer) { timer.remove(false); timer = null; } };

        this._frame.on('pointerdown', (ptr) => {
            cancel();
            startX = ptr.worldX;
            startY = ptr.worldY;
            timer  = this.scene.time.delayedCall(600, () => {
                timer = null;
                showCardZoom(this.scene, this.cardData);
            });
        });
        this._frame.on('pointermove', (ptr) => {
            if (Math.abs(ptr.worldX - startX) > 8 || Math.abs(ptr.worldY - startY) > 8) cancel();
        });
        this._frame.on('pointerup',  cancel);
        this._frame.on('pointerout', cancel);
        this._frame.on('dragstart',  cancel); // drag cancels the hold timer
    }

    // ── Zoom for field-mode cards (called by scene after placement) ──────────

    /**
     * @param {boolean} immediate  true = tap zooms, false = 2s hold zooms
     */
    enableZoom(immediate = false) {
        if (!this._frame) return;
        if (!this._frame.input) this._frame.setInteractive();
        if (immediate) {
            this._frame.on('pointerdown', () => showCardZoom(this.scene, this.cardData));
        } else {
            attachHoldZoom(this.scene, this._frame, this.cardData, 600);
        }
    }

    _attachTapListener() {
        this._frame.setInteractive({ useHandCursor: true });
        let downX = 0, downY = 0;
        this._frame.on('pointerdown', (ptr) => { downX = ptr.worldX; downY = ptr.worldY; });
        this._frame.on('pointerup',  (ptr) => {
            if (Math.abs(ptr.worldX - downX) < 10 && Math.abs(ptr.worldY - downY) < 10) {
                this.emit('tapped');
            }
        });
    }

    // ── State changes ─────────────────────────────────────────────────────────

    /**
     * No-op kept for call-site compatibility — stats are rendered as a separate
     * HUD overlay by DuelScene, not on the card itself.
     */
    updateStats(_cardData) {}

    flipFaceDown() {
        this._faceDown = true;
        this._art?.setVisible(false);
        if (!this._back) {
            this._back = this._makeBackImage();
            // Insert beneath the hit-target frame
            this.container.addAt(this._back, 0);
        }
        this._back.setVisible(true);
    }

    flipFaceUp() {
        this._faceDown = false;
        this._back?.setVisible(false);
        this._art?.setVisible(true);
    }

    /** Set-in-DEF position: face-down AND sideways (YuGiOh style). */
    setFaceDownDef() {
        this.flipFaceDown();
        this.container.setAngle(90);
    }

    /** Reveal a set-in-DEF card face-up (stays sideways). */
    flipFaceUpDef() {
        this.flipFaceUp();
        this.container.setAngle(90);
    }

    /**
     * Switch the card into a field-resident mode: strip the hand-mode drag
     * listeners and disable draggable input. Call this once a card is placed
     * on the board so taps don't accidentally pick it back up.
     */
    setFieldMode(owner = 'player') {
        this.mode = owner === 'player' ? 'field_pl' : 'field_opp';
        this.container.setScale(1);
        if (!this._frame) return;
        if (this._frame.input) this.scene.input.setDraggable(this._frame, false);
        this._frame.removeAllListeners('drag');
        this._frame.removeAllListeners('dragstart');
        this._frame.removeAllListeners('dragend');
        this._frame.removeAllListeners('pointerup');
        // Remove hand-hover listeners so they can't tween a field card back toward y≈0
        this._frame.removeAllListeners('pointerover');
        this._frame.removeAllListeners('pointerout');
    }

    /** Animate the card back to its home position in the hand (fan arc). */
    returnToHand() {
        this.scene.tweens.add({
            targets:  this.container,
            x:        this._homeX,
            y:        this._homeY ?? 0,
            angle:    this._homeAngle ?? 0,
            duration: 180,
            ease:     'Back.Out',
        });
        this.container.setDepth(1);
    }

    /** Mark this card as Downed: rotate sideways + red tint. */
    setDowned() {
        this.container.setAngle(90);
        if (this._art?.setTint) this._art.setTint(0xff4444);
        if (this._back?.setTint) this._back.setTint(0xff4444);
    }

    /** Recover from Downed state: restore angle + clear tint. */
    unsetDowned() {
        const card = this.cardData;
        this.container.setAngle(card?.position === 'def' ? 90 : 0);
        if (this._art?.clearTint) this._art.clearTint();
        if (this._back?.clearTint) this._back.clearTint();
    }

    destroy() {
        this.container.destroy();
        this.removeAllListeners();
    }
}
