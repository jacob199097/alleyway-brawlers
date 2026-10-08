/**
 * DUEL SCENE (single-player / local AI duel)
 * ─────────────────────────────────────────────────────────────────────────────
 * Board layout (landscape 844 × 390):
 *
 *   ┌────────────────────────────────────────────────────────────────┐
 *   │  Opponent Morale bar                                [844 wide] │ y≈13
 *   │  Opp hand card-backs (top edge)                    + Zones    │ y≈7
 *   │  Opponent back row  (5 slots)      [Deck / Hideout / Gutter] │ y≈56
 *   │  Opponent front row (5 slots)                                 │ y≈142
 *   │  ──────────────────── DIVIDER ──────────────────────────────  │ y≈186
 *   │  Player front row   (5 slots)                                 │ y≈228
 *   │  Player back row    (5 slots)      [Deck / Hideout / Gutter]  │ y≈314
 *   │  Player Morale bar                                            │ y≈316
 *   │  Turn indicator + Phase buttons                               │ y≈340
 *   │  Hand (scrollable)                                            │ y≈374
 *   └────────────────────────────────────────────────────────────────┘
 */

import { CardObject }      from '../cards/CardObject.js';
import { BrawlPhase }      from '../cards/BrawlPhase.js';
import { EffectBus }       from '../cards/EffectBus.js';
import { AiBrain }         from '../cards/AiBrain.js';
import { SettingsManager } from '../utils/SettingsManager.js';
import { Graphics } from '../utils/Graphics.js';
import { showCardZoom }   from '../utils/CardZoom.js';
import { getPlayerTitle } from '../utils/PlayerTitle.js';
import { apiFetch } from '../utils/Platform.js';

const W = 844;
const H = 390;

// Slot geometry (portrait-ish cards; roughly matches Yu-Gi-Oh aspect)
const SLOT_W   = 64;
const SLOT_H   = 76;   // slightly reduced to give the hand strip more room
const SLOT_GAP = 7;

// Hand cards render at the same size as field cards (no scale offset)
const HAND_SCALE = 1.0;

// Row y-centres (absolute) — 78px spacing (SLOT_H=76 + 2px gap) leaves 68px for hand strip
const ROW_Y = {
    opp_back:  48,
    opp_front: 126,
    pl_front:  204,
    pl_back:   282,
};

// Turn timer
const TURN_TIME_SECONDS = 180;
// KO text (configurable — change main/sub to test different wording)
const KO_TEXT = { main: 'DROPPED!', sub: 'is taken down' };

export class DuelScene extends Phaser.Scene {

    constructor() { super('DuelScene'); }

    // ── Phaser lifecycle ──────────────────────────────────────────────────────

    init(data) {
        // Separate leader cards out of the hideout before storing
        const rawPlHideout  = data.playerHideout   || _buildTestHideout();
        const rawOppHideout = data.opponentHideout || _buildTestHideout();

        this._playerLeaderCard   = rawPlHideout.find(c => c.cardType === 'leader') || null;
        this._opponentLeaderCard = rawOppHideout.find(c => c.cardType === 'leader') || null;

        this._playerDeck      = data.playerDeck    || _buildTestDeck('player');
        this._opponentDeck    = data.opponentDeck  || _buildTestDeck('opponent');
        this._playerHideout   = rawPlHideout.filter(c => c.cardType !== 'leader');
        this._opponentHideout = rawOppHideout.filter(c => c.cardType !== 'leader');
        this._isMultiplayer   = false;
        this._firstPlayer     = data.firstPlayer   || 'player';
        this._ranked          = !!data.ranked;
    }

    create() {
        this._zoneTooltip = null;   // reset in case scene restarts over stale refs
        this._initState();
        this._buildBoard();
        this._buildProfileBoxes();
        this._buildPhaseControls();
        this._buildHandArea();
        this._buildTurnIndicator();

        this.effectBus = new EffectBus(this);
        this._mvpLog = {};
        this._playerCardsPlayed = 0;
        this._startSoloSession();
        this.brawlPhase = new BrawlPhase(this, this.state, this.effectBus);

        // Opponent card-back strip (shows card count at top edge)
        this._buildOppHandDisplay();

        // Draw opening hands — 6 each per spec
        for (let i = 0; i < 5; i++) this._drawCard('player');
        for (let i = 0; i < 5; i++) this._drawCard('opponent');

        // Stop any menu music that may still be playing
        ['bgm_main_menu', 'bgm_menu'].forEach(key => {
            const snd = this.sound.get(key);
            if (snd?.isPlaying) snd.stop();
        });

        // Start duel music — stop any stale instances first to prevent stacking
        const duelBgmKey = this.cache.audio.exists('bgm_duel_theme') ? 'bgm_duel_theme'
            : this.cache.audio.exists('bgm_duel') ? 'bgm_duel' : null;
        if (duelBgmKey) {
            this.sound.sounds?.filter(s => s.key === duelBgmKey && s.isPlaying).forEach(s => s.stop());
            this.bgm = this.sound.add(duelBgmKey, { loop: true, volume: SettingsManager.bgmVolume });
            this.bgm.play();
        }

        // Refresh authority UI (displays 1/15 for both sides at start)
        this._refreshAuthorityDisplay();

        // Combat log panel (top-left overlay)
        this._buildCombatLog();

        // Offer mulligan before the first turn starts
        this._showMulliganModal(() => this._startPhase('upkeep'));
    }

    // ── State initialisation ──────────────────────────────────────────────────

    _initState() {
        this.state = {
            turn:         1,
            activePlayer: this._firstPlayer || 'player',
            phase:        'upkeep',
            player: {
                morale:              6000,
                authority:           1,
                authorityMax:        1,
                deck:                [...this._playerDeck],
                hand:                [],
                field:               Array(10).fill(null),
                gutter:              [],
                hideout:             [...this._playerHideout],
                deployedThisTurn:    0,
                leader:              this._playerLeaderCard   ? { ...this._playerLeaderCard,   downed: false, influence: this._playerLeaderCard.defense ?? 3000 } : null,
                leaderAwakened:      false,
                _brutusChainBonus:   0,
            },
            opponent: {
                morale:              6000,
                authority:           1,
                authorityMax:        1,
                deck:                [...this._opponentDeck],
                hand:                [],
                field:               Array(10).fill(null),
                gutter:              [],
                hideout:             [...this._opponentHideout],
                deployedThisTurn:    0,
                leader:              this._opponentLeaderCard ? { ...this._opponentLeaderCard, downed: false, influence: this._opponentLeaderCard.defense ?? 3000 } : null,
                leaderAwakened:      false,
                _brutusChainBonus:   0,
            },
        };

        // Legacy alias — some older code paths (effects) still reference .graveyard
        Object.defineProperty(this.state.player,   'graveyard', { get() { return this.gutter; } });
        Object.defineProperty(this.state.opponent, 'graveyard', { get() { return this.gutter; } });
    }

    // ── Authority helpers ─────────────────────────────────────────────────────

    _gainAuthority(owner) {
        const s = this.state[owner];
        s.authorityMax = Math.min(15, (s.authorityMax ?? 1) + 1);
        s.authority    = s.authorityMax;
        this._refreshAuthorityDisplay();
        this._pulseAuthorityPill(owner, '+1', '#4cc9f0');
    }

    /** Briefly scale the authority pill and float a "+1 / -N" badge above it. */
    _pulseAuthorityPill(owner, label, color = '#f4d35e') {
        const txt = owner === 'player' ? this._plAuthText : this._oppAuthText;
        if (!txt) return;
        // Scale pulse on the number
        this.tweens.add({
            targets:  txt,
            scaleX:   1.4,
            scaleY:   1.4,
            duration: 180,
            yoyo:     true,
            ease:     'Back.Out',
        });
        // Float-up label above the pill
        const float = this.add.text(txt.x, txt.y - 12, label, {
            fontSize: '10px', fontFamily: 'Arial Black', color,
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5).setDepth(60);
        this.tweens.add({
            targets:  float,
            y:        float.y - 16,
            alpha:    0,
            duration: 600,
            ease:     'Power2',
            onComplete: () => float.destroy(),
        });
    }

    _refreshAuthorityDisplay() {
        const p = this.state.player;
        const o = this.state.opponent;
        this._plAuthText?.setText(`${p.authority}/${p.authorityMax}`);
        this._oppAuthText?.setText(`${o.authority}/${o.authorityMax}`);
    }

    // ── Profile boxes (left margin) ───────────────────────────────────────────

    _buildProfileBoxes() {
        const player   = this.registry.get('player');
        const myName   = player?.username   || 'YOU';
        const myLevel  = player?.level      || 1;
        const myAvatar = player?.avatar_url || 'profile_001';
        const myTitle  = getPlayerTitle(myLevel);
        const myWins   = player?.wins   ?? 0;
        const myLosses = player?.losses ?? 0;

        // Opponent data — overridden by MultiplayerDuelScene before super.create()
        const oppName   = this._opponentName   || 'CPU';
        const oppAvatar = this._opponentAvatar || 'profile_001';
        const oppLevel  = this._opponentLevel  || null;
        const oppTitle  = oppLevel ? getPlayerTitle(oppLevel) : 'Opponent';
        const oppWins   = this._opponentWins   ?? null;
        const oppLosses = this._opponentLosses ?? null;

        this._oppProfileBox = this._makeProfileBox(4, 22,  oppName, oppLevel, oppAvatar, 'opponent', oppTitle, oppWins, oppLosses);
        this._plProfileBox  = this._makeProfileBox(4, 168, myName,  myLevel,  myAvatar,  'player',   myTitle,  myWins, myLosses);
    }

    _makeProfileBox(x, y, name, level, avatarKey, owner, title, wins, losses) {
        const BOX_W = 108, BOX_H = 150;
        const accent = owner === 'player' ? 0x4cc9f0 : 0xe63946;

        // Background panel
        this.add.rectangle(x + BOX_W / 2, y + BOX_H / 2, BOX_W, BOX_H, 0x0a0a1a, 0.88)
            .setStrokeStyle(1, accent, 0.8).setDepth(12);

        // Avatar (square)
        const avKey = (avatarKey && this.textures.exists(avatarKey)) ? avatarKey : null;
        if (avKey) {
            this.add.image(x + 24, y + 26, avKey).setDisplaySize(44, 44).setDepth(13);
        } else {
            this.add.rectangle(x + 24, y + 26, 44, 44, 0x222233).setDepth(13);
        }

        // Name
        this.add.text(x + 52, y + 10, name.toUpperCase().slice(0, 9), {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0, 0.5).setDepth(13);

        // Level
        if (level != null) {
            this.add.text(x + 52, y + 22, `LVL ${level}`, {
                fontSize: '7px', color: '#aaaacc',
            }).setOrigin(0, 0.5).setDepth(13);
        }

        // Title
        this.add.text(x + 52, y + 34, title || '', {
            fontSize: '6px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0, 0.5).setDepth(13);

        // W/L
        const wlStr = (wins != null && losses != null) ? `W:${wins}  L:${losses}` : '';
        this.add.text(x + 52, y + 46, wlStr, {
            fontSize: '6px', color: '#888888',
        }).setOrigin(0, 0.5).setDepth(13);

        // Divider
        this.add.rectangle(x + BOX_W / 2, y + 60, BOX_W - 8, 1, accent, 0.4).setDepth(13);

        // Morale label
        this.add.text(x + 8, y + 68, 'MORALE', {
            fontSize: '6px', fontFamily: 'Arial Black', color: '#888888',
        }).setDepth(13);

        // Morale value
        const moraleText = this.add.text(x + BOX_W / 2, y + 90, '6000', {
            fontSize: '20px', fontFamily: 'Arial Black',
            color: owner === 'player' ? '#4cc9f0' : '#e63946',
        }).setOrigin(0.5, 0.5).setDepth(13);

        // Mini morale bar
        const barX = x + 6, barY = y + 112, barW = BOX_W - 12;
        this.add.rectangle(barX, barY, barW, 7, 0x333333).setOrigin(0, 0.5).setDepth(13);
        const barFill = this.add.rectangle(barX, barY, barW, 7, accent).setOrigin(0, 0.5).setDepth(13);

        // Authority row (below the morale bar)
        this.add.text(x + 8, y + 124, 'AUTH', {
            fontSize: '6px', fontFamily: 'Arial Black', color: '#888888',
        }).setDepth(13);
        const authText = this.add.text(x + BOX_W - 8, y + 124, '1/1', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(1, 0).setDepth(13);
        if (owner === 'player')   this._plAuthText  = authText;
        if (owner === 'opponent') this._oppAuthText = authText;

        return {
            update: (val) => {
                const pct = Math.max(0, val) / 6000;
                moraleText.setText(Math.max(0, val).toString());
                this.tweens.add({ targets: barFill, width: barW * pct, duration: 400, ease: 'Power2' });
            },
        };
    }

    // ── Board construction ────────────────────────────────────────────────────

    _buildBoard() {
        // Background
        this.add.image(W / 2, H / 2, 'duel_background').setDisplaySize(W, H);

        // A subtle dark overlay tones the board down for readability
        this.add.rectangle(W / 2, H / 2, W, H, 0x04060c, 0.25).setDepth(0);

        // Glowing center divider with fade-out edges
        this._buildCenterDivider();

        // Subtle ambient glow beneath each row so the grid feels layered
        this._buildRowAmbience();

        // Slot grids
        this._slotObjects = {
            opp_back:  this._buildSlotRow('opp_back',  'opponent', true),
            opp_front: this._buildSlotRow('opp_front', 'opponent', false),
            pl_front:  this._buildSlotRow('pl_front',  'player',   false),
            pl_back:   this._buildSlotRow('pl_back',   'player',   true),
        };

        this._buildSideZones();
    }

    _buildCenterDivider() {
        // Triple-stacked lines for a glowing look
        const y = 165;
        this.add.rectangle(W / 2, y,     W,        8, 0xe63946, 0.08).setDepth(1);
        this.add.rectangle(W / 2, y,     W,        4, 0xe63946, 0.28).setDepth(1);
        this.add.rectangle(W / 2, y,     W - 40,   1, 0xff6b7a, 0.95).setDepth(1);

        // Side tick marks
        this.add.rectangle(24,     y, 2, 14, 0xe63946, 0.6).setDepth(1);
        this.add.rectangle(W - 24, y, 2, 14, 0xe63946, 0.6).setDepth(1);
    }

    _buildRowAmbience() {
        // Translucent bands behind each row to anchor the slots
        const bandWidth = 5 * SLOT_W + 4 * SLOT_GAP + 16;
        const bandX     = W / 2;
        [
            { y: ROW_Y.opp_back,  color: 0x3d1d54, alpha: 0.22 },
            { y: ROW_Y.opp_front, color: 0x521a24, alpha: 0.22 },
            { y: ROW_Y.pl_front,  color: 0x1c2f4f, alpha: 0.22 },
            { y: ROW_Y.pl_back,   color: 0x1c3d54, alpha: 0.22 },
        ].forEach(b => {
            this.add.rectangle(bandX, b.y, bandWidth, SLOT_H + 10, b.color, b.alpha)
                .setDepth(0);
        });
    }

    // ── Side zones: Deck + Leader in back-row end slots, Hideout + Gutter pills beside them ──
    _buildSideZones() {
        const plBack  = this._slotObjects.pl_back;
        const oppBack = this._slotObjects.opp_back;

        // One slot-step beyond the 3-slot back row
        const STEP    = SLOT_W + SLOT_GAP;   // 71px
        const plLeadX  = plBack[0].x - STEP;                       // left end of pl_back row
        const plDeckX  = plBack[plBack.length - 1].x + STEP;       // right end of pl_back row
        const oppDeckX = oppBack[0].x - STEP;                      // left end of opp_back row
        const oppLeadX = oppBack[oppBack.length - 1].x + STEP;     // right end of opp_back row
        const plY      = ROW_Y.pl_back;
        const oppY     = ROW_Y.opp_back;

        const ZONE_W = SLOT_W;
        const ZONE_H = SLOT_H;   // match field slot height — no overlap with hand area

        // ── Tooltip layer ────────────────────────────────────────────────────
        // One reusable tooltip — moves to whichever zone is hovered.
        if (!this._zoneTooltip) {
            const ttContainer = this.add.container(0, 0).setDepth(80).setVisible(false);
            const ttBg = this.add.rectangle(0, 0, 96, 18, 0x000000, 0.9)
                .setStrokeStyle(1, 0xf4d35e, 0.85);
            const ttTxt = this.add.text(0, 0, '', {
                fontSize: '8px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
                fontStyle: 'bold', color: '#ffd86b',
            }).setOrigin(0.5);
            ttContainer.add([ttBg, ttTxt]);
            this._zoneTooltip = { container: ttContainer, bg: ttBg, txt: ttTxt };
        }

        const showTip = (x, y, text) => {
            const t  = this._zoneTooltip;
            t.txt.setText(text);
            // Auto-fit the plate to the text
            t.bg.setSize(Math.max(80, t.txt.width + 16), 18);
            t.container.setPosition(x, y).setVisible(true);
        };
        const hideTip = () => this._zoneTooltip?.container.setVisible(false);

        // Build a deck/hideout/gutter pile: framed slot + (optional) card-back stack.
        // `getTopCard()` is optional; supplied for the gutter so its top card shows face-up.
        const makePile = (x, y, label, colour, opts = {}) => {
            const { onClick, getTopCard, hideoutLike = false, labelBelow = false, hideLabel = false } = opts;

            const stack = this.add.container(x, y).setDepth(4);

            // Frame: drop-shadow + base panel + bordered slot + inner highlight,
            // matching the field zones so empty piles still read as a zone.
            stack.add(this.add.rectangle(1, 2, ZONE_W, ZONE_H, 0x000000, 0.35));
            stack.add(this.add.rectangle(0, 0, ZONE_W, ZONE_H, 0x0f1226, 0.55));
            stack.add(this.add.rectangle(0, 0, ZONE_W, ZONE_H, 0x1a1a2e, 0.0)
                .setStrokeStyle(1, colour, 0.85));
            stack.add(this.add.rectangle(0, -ZONE_H / 2 + 2, ZONE_W - 4, 1, 0xffffff, 0.12));

            // Card-back stack (3 offset layers) — built on demand once the pile
            // has at least one card. Stored on the pile so we can toggle it.
            const hasBack    = this.textures.exists('card_back');
            const backLayers = [];
            for (let i = 2; i >= 0; i--) {
                const layer = hasBack
                    ? this.add.image(i, i, 'card_back').setDisplaySize(ZONE_W - i * 2, ZONE_H - i * 2)
                    : this.add.rectangle(i, i, ZONE_W - i * 2, ZONE_H - i * 2, 0x12122a, 0.9)
                          .setStrokeStyle(1, colour, 0.7);
                if (hasBack) layer.texture?.setFilter?.(1);
                layer.setOrigin(0.5).setVisible(false);
                stack.add(layer);
                backLayers.push(layer);
            }

            // Optional top-card overlay (used for the Gutter so the most-recent
            // discard shows face-up at a glance — YGO style)
            let topImg = null;
            if (getTopCard) {
                topImg = this.add.rectangle(0, 0, ZONE_W, ZONE_H, 0x000000, 0).setVisible(false);
                stack.add(topImg);
            }

            // Faint label (above for player zones, below for opponent zones near top edge)
            const lblY = labelBelow ? ZONE_H / 2 + 8 : -ZONE_H / 2 - 8;
            const lbl = hideLabel ? null : (() => {
                const t = this.add.text(0, lblY, label, {
                    fontSize: '7px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
                    fontStyle: 'bold', color: '#ffd86b', stroke: '#000', strokeThickness: 2,
                }).setOrigin(0.5);
                stack.add(t);
                return t;
            })();

            // Tap target covering the whole pile
            const hit = this.add.rectangle(0, 0, ZONE_W + 6, ZONE_H + 12, 0x000000, 0)
                .setInteractive({ useHandCursor: true });
            stack.add(hit);

            // Hover tooltip — shows count + label
            const tipDy = opts.labelBelow ? ZONE_H / 2 + 22 : -(ZONE_H / 2 + 22);
            hit.on('pointerover', () => showTip(x, y + tipDy, '— hover —'));
            hit.on('pointerout',  () => hideTip());
            hit.on('pointerup',   () => onClick?.());

            return { stack, lbl, hit, x, y, label, getTopCard, topImg, hideoutLike, backLayers };
        };

        // ── Deck piles — right end of player back row, left end of opp back row ──
        const plDeck  = makePile(plDeckX,  plY,  'DECK', 0x6a0572, { hideLabel: true });
        const oppDeck = makePile(oppDeckX, oppY, 'DECK', 0x6a0572, { hideLabel: true });

        const setHover = (pile, kind, owner) => {
            pile.hit.removeAllListeners('pointerover');
            pile.hit.removeAllListeners('pointerout');
            pile.hit.on('pointerover', () => {
                const count  = this._zoneCount(kind, owner);
                const word   = owner === 'player' ? 'YOUR' : "OPPONENT'S";
                const tipDy  = owner === 'opponent' ? ZONE_H / 2 + 18 : -(ZONE_H / 2 + 18);
                showTip(pile.x, pile.y + tipDy, `${word} ${kind.toUpperCase()} — ${count}`);
            });
            pile.hit.on('pointerout', () => hideTip());
        };
        setHover(plDeck,  'deck', 'player');
        setHover(oppDeck, 'deck', 'opponent');

        // ── Collapsed pill buttons for Hideout + Gutter ───────────────────────
        // Sit just outside the leader/deck zones at the same back-row y
        const PW_PILL   = 58;
        const pillX_pl    = Math.round(plLeadX  - SLOT_W / 2 - PW_PILL / 2 - 4);  // ~215
        const pillX_pl_r  = Math.round(plDeckX  + SLOT_W / 2 + PW_PILL / 2 + 4);  // ~629
        const pillX_opp_l = Math.round(oppDeckX - SLOT_W / 2 - PW_PILL / 2 - 4);  // ~215
        const pillX_opp   = Math.round(oppLeadX + SLOT_W / 2 + PW_PILL / 2 + 4);  // ~629

        const makePill = (x, y, label, color, onClick) => {
            const PW = 58, PH = 20;
            const c = this.add.container(x, y).setDepth(5);

            const bg = this.add.rectangle(0, 0, PW, PH, 0x0a0a1a, 0.92)
                .setStrokeStyle(1, color, 0.85);
            const lbl = this.add.text(-PW / 2 + 5, 0, label, {
                fontSize: '7px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
                fontStyle: 'bold', color: '#' + color.toString(16).padStart(6, '0'),
                stroke: '#000', strokeThickness: 2,
            }).setOrigin(0, 0.5);
            const cnt = this.add.text(PW / 2 - 5, 0, '0', {
                fontSize: '8px', fontFamily: 'Arial Black', color: '#ffffff',
            }).setOrigin(1, 0.5);
            const hit = this.add.rectangle(0, 0, PW + 4, PH + 4, 0, 0)
                .setInteractive({ useHandCursor: true });
            hit.on('pointerdown', onClick);
            hit.on('pointerover', () => bg.setStrokeStyle(1, color, 1));
            hit.on('pointerout',  () => bg.setStrokeStyle(1, color, 0.85));
            c.add([bg, lbl, cnt, hit]);
            return { container: c, countText: cnt };
        };

        // Player: hideout LEFT, gutter RIGHT — inline with deck/leader at back-row y
        const plHid = makePill(pillX_pl,   plY, 'HIDEOUT', 0xf4d35e, () => this._openHideoutSearch('player'));
        const plGut = makePill(pillX_pl_r, plY, 'GUTTER',  0x888888, () => this._openGutterSearch('player'));

        // Opponent: hideout LEFT, gutter RIGHT — inline with their back-row zones
        const oppHid = makePill(pillX_opp_l, oppY, 'HIDEOUT', 0xf4d35e,
            () => this._showFloatingText(pillX_opp_l, oppY + 60, "OPP HIDEOUT (PRIVATE)", '#aaaacc'));
        const oppGut = makePill(pillX_opp, oppY, 'GUTTER', 0x888888, () => this._openGutterSearch('opponent'));

        this._piles = { plDeck, oppDeck, plHid, oppHid, plGut, oppGut };

        // ── Leader Zones — end slots of the back row ──────────────────────────
        this._buildLeaderZone('player',   plLeadX,  plY);
        this._buildLeaderZone('opponent', oppLeadX, oppY);

        this._refreshZoneCounts();
    }

    _buildLeaderZone(owner, x, y) {
        const accent  = owner === 'player' ? 0xf4d35e : 0xe63946;
        const depth   = 4;
        const LW = SLOT_W;
        const LH = SLOT_H;

        // Slot frame (same visual language as field slots)
        this.add.rectangle(x + 1, y + 2, LW, LH, 0x000000, 0.35).setDepth(depth);
        this.add.rectangle(x, y, LW, LH, 0x100d20, 0.9).setDepth(depth);
        const frame = this.add.rectangle(x, y, LW, LH, 0x1a1a2e, 0)
            .setStrokeStyle(2, accent, 0.9).setDepth(depth);
        this.add.rectangle(x, y - LH / 2 + 2, LW - 4, 1, 0xffffff, 0.15).setDepth(depth);

        // State badge — below for player, above for opponent
        const badgeY = owner === 'player' ? y + LH / 2 + 8 : y - LH / 2 - 8;
        const stateBadge = this.add.text(x, badgeY, '', {
            fontSize: '6px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            color: '#888888',
        }).setOrigin(0.5).setDepth(depth + 1);

        // Influence tracker — below state badge for player, above it for opponent
        const infY = owner === 'player' ? badgeY + 9 : badgeY - 9;
        const influenceBadge = this.add.text(x, infY, '', {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#ffd166',
            stroke: '#000', strokeThickness: 2,
        }).setOrigin(0.5).setDepth(depth + 1);

        // Leader card image (if leader exists)
        const leader = this.state[owner]?.leader;
        let cardImg = null;
        if (leader) {
            const artKey = (leader.art_url && this.textures.exists(leader.art_url)) ? leader.art_url
                         : (this.textures.exists(leader.id) ? leader.id : null);
            if (artKey) {
                cardImg = this.add.image(x, y, artKey)
                    .setDisplaySize(LW - 4, LH - 4).setDepth(depth + 1);
                cardImg.texture?.setFilter?.(1);
            } else {
                // Text fallback
                this.add.text(x, y, leader.name || '?', {
                    fontSize: '7px', fontFamily: 'Arial Black', color: '#ffffff',
                    wordWrap: { width: LW - 8 }, align: 'center',
                }).setOrigin(0.5).setDepth(depth + 1);
            }
            stateBadge.setText('DORMANT').setColor('#888888');
            influenceBadge.setText(`♛ ${leader.influence ?? leader.defense ?? 0}`);

            // Tap to zoom the leader card
            frame.setInteractive({ useHandCursor: true });
            frame.on('pointerdown', () => showCardZoom(this, leader));
        }

        // Store refs so _checkLeaderAwaken can update the badge + glow
        if (owner === 'player') {
            this._plLeaderBadge     = stateBadge;
            this._plLeaderInfluence = influenceBadge;
            this._plLeaderFrame     = frame;
            this._plLeaderImg       = cardImg;
        } else {
            this._oppLeaderBadge     = stateBadge;
            this._oppLeaderInfluence = influenceBadge;
            this._oppLeaderFrame     = frame;
            this._oppLeaderImg       = cardImg;
        }
    }

    _zoneCount(kind, owner) {
        const side = this.state[owner];
        if (kind === 'deck')    return side.deck.length;
        if (kind === 'hideout') return side.hideout.length;
        if (kind === 'gutter')  return side.gutter.length;
        return 0;
    }

    _refreshZoneCounts() {
        if (!this._piles) return;

        // Deck piles: full makePile() objects — toggle card-back layers by count
        const syncDeck = (pile, count) => {
            pile.backLayers?.forEach(l => l.setVisible(count > 0));
        };
        syncDeck(this._piles.plDeck,  this.state.player.deck.length);
        syncDeck(this._piles.oppDeck, this.state.opponent.deck.length);

        // Pill buttons: { container, countText } — just update the number
        const syncPill = (pill, count) => {
            pill.countText?.setText(String(count));
        };
        syncPill(this._piles.plHid,  this.state.player.hideout.length);
        syncPill(this._piles.oppHid, this.state.opponent.hideout.length);
        syncPill(this._piles.plGut,  this.state.player.gutter.length);
        syncPill(this._piles.oppGut, this.state.opponent.gutter.length);
    }

    // ── Zone search modals ───────────────────────────────────────────────────

    _openHideoutSearch(owner) {
        const cards = this.state[owner].hideout;
        this._openCardListModal(
            owner === 'player' ? 'YOUR HIDEOUT' : "OPPONENT'S HIDEOUT",
            cards,
            owner === 'player',
        );
    }

    _openGutterSearch(owner) {
        const cards = this.state[owner].gutter;
        this._openCardListModal(
            owner === 'player' ? 'YOUR GUTTER' : "OPPONENT'S GUTTER",
            cards,
            true,      // Gutter is always public
        );
    }

    _openCardListModal(title, cards, allowInspect) {
        const els = [];
        const reg = (o) => { els.push(o); return o; };
        const cleanup = () => els.forEach(e => e.destroy());

        reg(this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.82).setDepth(80));
        reg(this.add.rectangle(W / 2, H / 2, 420, 260, 0x0d0d2a)
            .setStrokeStyle(2, 0xf4d35e).setDepth(81));
        reg(this.add.text(W / 2, H / 2 - 112, title, {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(82));
        reg(this.add.text(W / 2, H / 2 - 96, `${cards.length} card(s)`, {
            fontSize: '7px', color: '#aaaacc',
        }).setOrigin(0.5).setDepth(82));

        // Grid of cards (6 per row)
        const cw = 48, ch = 60, gap = 6;
        const perRow = 6;
        cards.slice(0, 18).forEach((c, i) => {
            const col = i % perRow;
            const row = Math.floor(i / perRow);
            const x = W / 2 - (perRow * cw + (perRow - 1) * gap) / 2 + cw / 2 + col * (cw + gap);
            const y = H / 2 - 60 + row * (ch + gap);
            const bg = reg(this.add.rectangle(x, y, cw, ch, 0x1a1a2e)
                .setStrokeStyle(1, 0x4cc9f0).setDepth(82));

            const artKey = c.art_url && this.textures.exists(c.art_url) ? c.art_url : null;
            if (artKey) {
                reg(this.add.image(x, y, artKey).setDisplaySize(cw, ch).setDepth(83));
            } else {
                reg(this.add.text(x, y, c.name || '?', {
                    fontSize: '6px', fontFamily: 'Arial Black', color: '#ffffff',
                    wordWrap: { width: cw - 4 }, align: 'center',
                }).setOrigin(0.5).setDepth(83));
            }

            if (allowInspect) {
                bg.setInteractive({ useHandCursor: true });
                bg.on('pointerup', () => { cleanup(); showCardZoom(this, c); });
            }
        });

        // Close button
        const close = reg(this.add.rectangle(W / 2, H / 2 + 110, 100, 26, 0x333355)
            .setStrokeStyle(1, 0xffffff).setDepth(82).setInteractive({ useHandCursor: true }));
        reg(this.add.text(W / 2, H / 2 + 110, 'CLOSE', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(83));
        close.on('pointerup', () => cleanup());
    }

    /**
     * Builds a row of 5 slot zones.
     * @param {string} rowKey      - key into ROW_Y
     * @param {string} owner       - 'player' | 'opponent'
     * @param {boolean} isBackRow
     * @returns {Phaser.GameObjects.Rectangle[]}
     */
    _buildSlotRow(rowKey, owner, isBackRow) {
        const slots = [];
        // 5 zones in the front row, 3 zones in the back row (Yu-Gi-Oh-style)
        const count  = isBackRow ? 3 : 5;
        const totalW = count * SLOT_W + (count - 1) * SLOT_GAP;
        const startX = (W - totalW) / 2 + SLOT_W / 2;
        const y      = ROW_Y[rowKey];

        for (let i = 0; i < count; i++) {
            const x = startX + i * (SLOT_W + SLOT_GAP);

            // Drop-shadow + inner highlight stack for a glassy, inset look
            const borderColor = isBackRow ? 0x7a8fb8 : 0xb388c9;
            this.add.rectangle(x + 1, y + 2, SLOT_W, SLOT_H, 0x000000, 0.35).setDepth(1);
            this.add.rectangle(x, y, SLOT_W, SLOT_H, 0x0f1226, 0.55).setDepth(1);
            const slot = this.add.rectangle(x, y, SLOT_W, SLOT_H, 0x1a1a2e, 0.0)
                .setStrokeStyle(1, borderColor, 0.75)
                .setInteractive()
                .setDepth(2);
            // Inner highlight line (top) for an embossed-glass feel
            this.add.rectangle(x, y - SLOT_H / 2 + 2, SLOT_W - 4, 1, 0xffffff, 0.12).setDepth(2);

            slot.slotIndex   = isBackRow ? i + 5 : i;
            slot.slotOwner   = owner;
            slot.isBackRow   = isBackRow;
            slot.rowKey      = rowKey;
            slot.cardObject  = null;

            // Accept card drops from the player's hand
            if (owner === 'player') {
                slot.input.dropZone = true;
            }

            // Opponent slots: tap to zoom (guard disables during brawl targeting)
            if (owner === 'opponent') {
                slot.on('pointerdown', () => {
                    if (this._selectedAttacker) return;
                    if (!slot.cardObject || slot.cardObject._faceDown) return;
                    showCardZoom(this, slot.cardObject.cardData);
                });
            }

            slots.push(slot);
        }
        return slots;
    }

    // ── Phase controls ────────────────────────────────────────────────────────

    _buildPhaseControls() {
        const phases = ['Upkeep', 'Deploy', 'Brawl', 'Regroup', 'End'];
        const btnW   = 50;
        const btnH   = 12;
        const gap    = 3;
        const totalW = phases.length * btnW + (phases.length - 1) * gap;
        const startX = (W - totalW) / 2;
        const btnY   = 165;   // sit centred on the divider line

        // Hotbar track (slim dark pill behind the buttons)
        this.add.rectangle(W / 2, btnY, totalW + 14, btnH + 6, 0x04060c, 0.92)
            .setStrokeStyle(1, 0x2d3450, 0.9).setDepth(9);

        this._phaseBtns = phases.map((label, i) => {
            const x   = startX + i * (btnW + gap) + btnW / 2;
            const btn = this.add.rectangle(x, btnY, btnW, btnH, 0x1c2040, 0.95)
                .setStrokeStyle(1, 0x4cc9f0, 0.55)
                .setInteractive({ useHandCursor: true })
                .setDepth(10);

            const txt = this.add.text(x, btnY, label.toUpperCase(), {
                fontSize: '7px',
                fontFamily: 'Impact, "Arial Narrow", sans-serif',
                fontStyle: 'bold',
                color: '#8ea1c4',
                letterSpacing: 1,
            }).setOrigin(0.5).setDepth(11);

            btn.phaseKey = label.toLowerCase().replace('deploy', 'deployment');
            btn.txt      = txt;

            btn.on('pointerdown', () => this._onPhaseButtonPressed(btn.phaseKey));
            return btn;
        });
    }

    _highlightPhaseBtn(phaseKey) {
        this._phaseBtns.forEach(btn => {
            const active = btn.phaseKey === phaseKey;
            btn.setFillStyle(active ? 0xf4d35e : 0x1c2040, active ? 1 : 0.95);
            btn.setStrokeStyle(1, active ? 0xffe28a : 0x4cc9f0, active ? 1 : 0.55);
            btn.txt.setColor(active ? '#1a1a2e' : '#8ea1c4');
        });
    }

    // ── Hand area (scrollable horizontal strip) ───────────────────────────────

    _buildHandArea() {
        // Fan-arc hand: cards centred at handY; maskTop sits 2px below back-row bottom (282+38=320).
        // 68px strip (322–390) gives comfortable room to see and tap cards.
        const handY   = 354;
        const maskTop = 322;

        // Visual hand-area background to clearly separate the hand from the field
        this.add.rectangle(W / 2, maskTop + (H - maskTop) / 2, W, H - maskTop, 0x020408, 0.72)
            .setDepth(5);
        this.add.rectangle(W / 2, maskTop, W, 2, 0x4cc9f0, 0.35).setDepth(5);

        this._handContainer = this.add.container(0, handY).setDepth(6);
        const maskShape = this.add.graphics();
        maskShape.fillRect(0, maskTop, W, H - maskTop);
        this._handContainer.setMask(maskShape.createGeometryMask());
        maskShape.setVisible(false);
        this._handMaskShape = maskShape;
        this._handMaskTop   = maskTop;

        this._handCards = [];
        // No scroll drag needed — fan layout always fits all cards within screen width
    }

    // MD-mobile-style fan: tight overlap, pronounced arc, outer cards rotated & dipped.
    _handCardTransform(index, total) {
        if (total === 0) return { x: W / 2 - 40, y: 0, angle: 0 };

        // Gap shrinks as hand fills — heavy overlap at large counts (like Master Duel mobile)
        const NAT_GAP = SLOT_W + 6;  // 70px — no overlap, comfortable
        const MIN_GAP = 34;           // heavy overlap for 9 cards
        const gap = total <= 4
            ? NAT_GAP
            : Math.max(MIN_GAP, NAT_GAP - (total - 4) * 9);

        const HAND_X_OFFSET = -40;
        const stripW = (total - 1) * gap;
        const startX = (W - stripW) / 2 + HAND_X_OFFSET;
        const x = startX + index * gap;

        // Rotation: ±20° max, linear from center
        const MAX_ANGLE = 20;
        const center    = (total - 1) / 2;
        const norm      = total > 1 ? (index - center) / center : 0; // −1 … +1
        const angle     = norm * MAX_ANGLE;

        // Quadratic arc dip: edges drop down more steeply (MD-style)
        const y = norm * norm * 22;

        return { x, y, angle };
    }

    // Kept for compat — some legacy call-sites use this directly
    _handCardX(index, total) {
        return this._handCardTransform(index, total).x;
    }

    // ── Turn indicator text ───────────────────────────────────────────────────

    _buildTurnIndicator() {
        // Positioned at right side of screen, above the combat log panel
        // Combat log panel top is at H/2 - 63 = 132; place banner just above it
        const BTN_W = 22, LW = 152, LH = 126;
        const panelCX = W - BTN_W - LW / 2;   // ≈ 746
        const panelTopY = H / 2 - LH / 2;     // ≈ 132
        this._turnBanner = this.add.container(panelCX, panelTopY - 14).setDepth(12);
        const chip = this.add.rectangle(0, 0, LW - 8, 18, 0x04060c, 0.9)
            .setStrokeStyle(1, 0xf4d35e, 0.8);
        this._turnText = this.add.text(0, 0, '', {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);
        this._turnBanner.add([chip, this._turnText]);

        this._buildTurnTimer();
        this._buildActionButtons();
        this._buildCancelButton();
        this._installTapToDeselect();

        this._resolvingDepth = 0;
    }

    // ── Turn Timer ───────────────────────────────────────────────────────────

    _buildTurnTimer() {
        const TW = 64, TH = 22;
        this._timerContainer = this.add.container(42, 300).setDepth(13).setVisible(false);

        this._timerBg = this.add.rectangle(0, 0, TW, TH, 0x04060c, 0.95)
            .setStrokeStyle(1, 0x4cc9f0, 0.85);
        const lbl = this.add.text(-TW / 2 + 5, -4, 'TIME', {
            fontSize: '5px', fontFamily: 'Arial Black', color: '#4cc9f0', alpha: 0.7,
        }).setOrigin(0, 0.5);
        this._timerNum = this.add.text(TW / 2 - 5, 2, String(TURN_TIME_SECONDS), {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(1, 0.5);

        this._timerContainer.add([this._timerBg, lbl, this._timerNum]);
        this._timerSecs    = TURN_TIME_SECONDS;
        this._timerEvent   = null;
        this._timerPaused  = false;
        this._timerPulsing = false;
    }

    _startTurnTimer() {
        this._stopTurnTimer();
        this._timerSecs    = TURN_TIME_SECONDS;
        this._timerPaused  = false;
        this._timerPulsing = false;
        this._timerContainer?.setVisible(true).setScale(1).setAlpha(1);
        this._updateTimerDisplay();
        this._timerEvent = this.time.addEvent({
            delay: 1000, loop: true, callback: this._onTimerTick, callbackScope: this,
        });
    }

    _stopTurnTimer() {
        this._timerEvent?.remove(false);
        this._timerEvent   = null;
        this._timerPulsing = false;
        this.tweens.killTweensOf(this._timerContainer);
        this._timerContainer?.setVisible(false);
    }

    _pauseTurnTimer() {
        if (this._timerEvent) this._timerEvent.paused = true;
    }

    _resumeTurnTimer() {
        if (this.state?.activePlayer !== 'player') return;
        if (this._timerEvent) this._timerEvent.paused = false;
    }

    _onTimerTick() {
        if (this._timerPaused) return;
        this._timerSecs = Math.max(0, this._timerSecs - 1);
        this._updateTimerDisplay();
        if (this._timerSecs <= 0) {
            this._stopTurnTimer();
            if (this.state?.activePlayer === 'player') {
                this._timeoutDefeat();
            }
        }
    }

    _updateTimerDisplay() {
        if (!this._timerNum) return;
        const s = this._timerSecs;
        this._timerNum.setText(String(s));

        if (s <= 5) {
            this._timerNum.setColor('#ff3b4e');
            this._timerBg?.setStrokeStyle(1, 0xff3b4e, 0.9);
            if (!this._timerPulsing) {
                this._timerPulsing = true;
                this.tweens.add({
                    targets: this._timerContainer,
                    scaleX: 1.14, scaleY: 1.14,
                    duration: 240, yoyo: true, repeat: -1, ease: 'Sine.InOut',
                });
            }
        } else if (s <= 10) {
            this._timerNum.setColor('#f4a335');
            this._timerBg?.setStrokeStyle(1, 0xf4a335, 0.9);
            if (this._timerPulsing) {
                this._timerPulsing = false;
                this.tweens.killTweensOf(this._timerContainer);
                this._timerContainer.setScale(1);
            }
        } else {
            this._timerNum.setColor('#ffffff');
            this._timerBg?.setStrokeStyle(1, 0x4cc9f0, 0.85);
        }
    }

    // ── Resolving-state counter: pauses timer + tracks nested async sequences ──

    _enterResolving() {
        this._resolvingDepth = (this._resolvingDepth || 0) + 1;
        if (this._resolvingDepth === 1) this._pauseTurnTimer();
    }

    _exitResolving() {
        this._resolvingDepth = Math.max(0, (this._resolvingDepth || 0) - 1);
        if (this._resolvingDepth === 0) this._resumeTurnTimer();
    }

    // ── Mobile action buttons ────────────────────────────────────────────────

    _buildActionButtons() {
        // NEXT PHASE pill — sits on the right side of the phase hotbar
        this._nextBtn = this._makePillButton({
            x: W - 76, y: 312, w: 80, h: 22,
            label: 'NEXT ▶',
            fill: 0x1c2040, stroke: 0x4cc9f0, textColor: '#4cc9f0',
            onTap: () => this._advancePhase(),
        });

        // END TURN pill — above the NEXT button, more prominent red tone
        this._endTurnBtn = this._makePillButton({
            x: W - 76, y: 284, w: 80, h: 20,
            label: 'END TURN',
            fill: 0x3b1020, stroke: 0xe63946, textColor: '#ffa7b0',
            onTap: () => this._onEndTurnTap(),
        });

        this._refreshActionButtons();
    }

    _buildCancelButton() {
        // Cancel floating pill shown only while an attacker is selected
        this._cancelBtn = this._makePillButton({
            x: 60, y: 165, w: 86, h: 22,
            label: '✕ CANCEL',
            fill: 0x2a0a12, stroke: 0xff6b7a, textColor: '#ff6b7a',
            onTap: () => this._deselectAll(),
        });
        this._cancelBtn.setVisible(false);
    }

    _makePillButton({ x, y, w, h, label, fill, stroke, textColor, onTap }) {
        const container = this.add.container(x, y).setDepth(14);
        const bg = this.add.rectangle(0, 0, w, h, fill, 0.95)
            .setStrokeStyle(1, stroke, 0.9)
            .setInteractive({ useHandCursor: true });
        const txt = this.add.text(0, 0, label, {
            fontSize: '9px', fontFamily: 'Arial Black', color: textColor,
            letterSpacing: 1,
        }).setOrigin(0.5);
        container.add([bg, txt]);

        // Touch feedback
        bg.on('pointerdown', () => container.setScale(0.94));
        bg.on('pointerout',  () => container.setScale(1));
        bg.on('pointerup',   () => { container.setScale(1); onTap?.(); });
        return container;
    }

    // Advance to the next phase in order (mobile-friendly single-tap progression).
    _advancePhase() {
        if (this.state.activePlayer !== 'player') return;
        const order = ['upkeep', 'deployment', 'brawl', 'regroup', 'end'];
        const i = order.indexOf(this.state.phase);
        if (i < 0 || i >= order.length - 1) return;
        this._startPhase(order[i + 1]);
    }

    _onEndTurnTap() {
        if (this.state.activePlayer !== 'player') return;
        // Jumping to 'end' immediately wraps up the turn via _endTurn
        this._startPhase('end');
    }

    // Show/hide action buttons based on whose turn / phase it is
    _refreshActionButtons() {
        const isYourTurn = this.state.activePlayer === 'player';
        this._nextBtn?.setVisible(isYourTurn && this.state.phase !== 'end');
        this._endTurnBtn?.setVisible(isYourTurn);
    }

    // Global tap-outside handler: clears attacker selection when you tap an empty area
    _installTapToDeselect() {
        this.input.on('pointerdown', (ptr) => {
            if (!this._selectedAttacker) return;

            // If the tap hit any interactive object, let that handler run instead
            const hits = this.input.hitTestPointer(ptr);
            if (hits && hits.length > 0) return;

            this._deselectAll();
        });
    }

    // ── Card draw ─────────────────────────────────────────────────────────────

    _drawCard(owner) {
        const s = this.state[owner];
        if (!s.deck.length) return;   // deck out
        const cardData = s.deck.shift();
        s.hand.push(cardData);

        if (owner === 'player') {
            this._addCardToHandDisplay(cardData);
        } else {
            this._refreshOppHandDisplay();
        }
        this._refreshDeckCountDisplay(owner);
        this._refreshZoneCounts();
    }

    // Opponent hand = a row of card-backs at the top edge so the player sees count
    _buildOppHandDisplay() {
        this._oppHandContainer = this.add.container(0, 4).setDepth(11);
        this._oppHandSprites   = [];
        this._refreshOppHandDisplay();
    }

    _refreshOppHandDisplay() {
        if (!this._oppHandContainer) return;

        this._oppHandSprites.forEach(s => s.destroy());
        this._oppHandSprites = [];

        const count = this.state.opponent.hand.length;
        const cw    = 22;
        const ch    = 28;
        const gap   = 3;
        const totalW = count * cw + (count - 1) * gap;
        const startX = (W - totalW) / 2 + cw / 2;

        for (let i = 0; i < count; i++) {
            const x = startX + i * (cw + gap);
            let spr;
            if (this.textures.exists('card_back')) {
                spr = this.add.image(x, 0, 'card_back').setDisplaySize(cw, ch);
            } else {
                spr = this.add.rectangle(x, 0, cw, ch, 0x2a2a3e)
                    .setStrokeStyle(1, 0x6a0572, 0.7);
            }
            this._oppHandContainer.add(spr);
            this._oppHandSprites.push(spr);
        }
    }

    _refreshDeckCountDisplay(_owner) {
        // Pile visuals + tooltip pull from state directly; just trigger a sync
        this._refreshZoneCounts();
    }

    _addCardToHandDisplay(cardData) {
        // Start the card off-screen below (draw-from-deck feel), then reflow
        // to its proper fan position with a bounce.
        const total  = this._handCards.length + 1;
        const { x, y, angle } = this._handCardTransform(this._handCards.length, total);
        const cardObj = new CardObject(this, x, 80, cardData, 'hand');
        // Start fully opaque — never depend on a tween for visibility so that
        // killTweensOf in _reflowHand can't leave a card stuck at alpha=0.
        cardObj.container.setAngle(angle);

        cardObj.on('tapped', () => this._onHandCardTapped(cardObj));

        // Hover pop-up (pointer enters card → rise and straighten)
        cardObj._frame?.on('pointerover', () => this._hoverHandCard(cardObj));
        cardObj._frame?.on('pointerout',  () => this._unhoverHandCard(cardObj));

        this._handContainer.add(cardObj.container);
        this._handCards.push(cardObj);

        // _reflowHand will set the final x/y/angle. Do a quick bounce from
        // the entry y=80 so the card visually "slides in" from below.
        this._reflowHand();

        // Bounce draw-in: card starts slightly below its home position
        cardObj.container.y = 80;
        this.tweens.add({
            targets:  cardObj.container,
            y,
            duration: 260,
            ease:     'Back.Out',
        });
    }

    _hoverHandCard(cardObj) {
        if (cardObj === this._pendingHandCard) return;
        if (!this._handCards.includes(cardObj)) return;
        this._hoveredHandCard = cardObj;
        // Expand mask so the lifted card clears the back-row zone boundary
        this._handMaskShape?.clear();
        this._handMaskShape?.fillRect(0, 0, W, H);
        cardObj.container.setDepth(45);
        this.tweens.killTweensOf(cardObj.container);
        this.tweens.add({
            targets:  cardObj.container,
            y:        (cardObj._homeY ?? 0) - 32,
            angle:    0,
            scaleX:   1.12,
            scaleY:   1.12,
            duration: 110,
            ease:     'Power2.Out',
        });
    }

    _unhoverHandCard(cardObj) {
        if (cardObj === this._pendingHandCard) return;
        // Card may have already been deployed — bail out if it's no longer in the hand.
        // Without this guard, a pointerout fired after deployment would tween the card
        // back to y≈0 in scene coordinates (top of canvas = opponent's side).
        if (!this._handCards.includes(cardObj)) return;
        if (this._hoveredHandCard === cardObj) this._hoveredHandCard = null;
        // Restore mask once card settles back into the strip
        this._handMaskShape?.clear();
        this._handMaskShape?.fillRect(0, this._handMaskTop, W, H - this._handMaskTop);
        cardObj.container.setDepth(1);
        this.tweens.killTweensOf(cardObj.container);
        this.tweens.add({
            targets:  cardObj.container,
            y:        cardObj._homeY ?? 0,
            angle:    cardObj._homeAngle ?? 0,
            scaleX:   1,
            scaleY:   1,
            duration: 140,
            ease:     'Power2.Out',
        });
    }

    // ── Tap-to-deploy (hand → field) ─────────────────────────────────────────

    _onHandCardTapped(cardObj) {
        // Discard mode: tapping a hand card discards it
        if (this._discardMode) {
            this._discardMode = false;
            const cb = this._discardCallback;
            this._discardCallback = null;
            const cardData = cardObj.cardData;
            const handIdx  = this.state.player.hand.indexOf(cardData);
            if (handIdx !== -1) this.state.player.hand.splice(handIdx, 1);
            this.state.player.gutter.push(cardData);
            this._handCards = this._handCards.filter(c => c !== cardObj);
            cardObj.destroy();
            this._reflowHand();
            this._refreshZoneCounts();
            cb?.();
            return;
        }

        // Deselect if tapping the already-selected card
        if (this._pendingHandCard === cardObj) {
            this._cancelHandCardPending();
            return;
        }
        this._cancelHandCardPending();

        if (this.state.activePlayer !== 'player') return;
        if (!['deployment', 'regroup'].includes(this.state.phase)) return;

        this._pendingHandCard = cardObj;
        cardObj.container.setDepth(50);
        // Kill any in-flight hover/reflow tween before starting the pop-up so
        // multiple tweens don't fight over y/angle at the same time.
        this.tweens.killTweensOf(cardObj.container);
        // Pop up: lift card out of the fan arc and straighten it
        this.tweens.add({
            targets:  cardObj.container,
            y:        -28,
            angle:    0,
            scaleX:   1,
            scaleY:   1,
            duration: 180,
            ease:     'Back.Out',
        });
        this._showHandCardMenu(cardObj);
    }

    _showHandCardMenu(cardObj) {
        const card = cardObj.cardData;
        const els  = [];
        const reg  = (o) => { els.push(o); return o; };
        this._handMenuEls = els;

        const cx = Phaser.Math.Clamp(
            this._handContainer.x + cardObj.container.x,
            80, W - 80
        );
        const cy = 290;   // above the hand strip

        reg(this.add.rectangle(cx, cy, 168, 70, 0x0d0d2a, 0.97)
            .setStrokeStyle(1, 0xf4d35e, 0.9).setDepth(60));

        const btnDefs = this._handMenuButtons(card);
        const btnW = 148, btnH = 16, gap = 4;
        const startY = cy - ((btnDefs.length - 1) * (btnH + gap)) / 2;

        btnDefs.forEach(({ label, action, enabled = true, disabledAction }, i) => {
            const by  = startY + i * (btnH + gap);
            const bg  = reg(this.add.rectangle(cx, by, btnW, btnH,
                enabled ? 0x1c2040 : 0x0a0a14)
                .setStrokeStyle(1, enabled ? 0x4cc9f0 : 0x33334a, 0.6).setDepth(61));
            reg(this.add.text(cx, by, label, {
                fontSize: '8px', fontFamily: 'Arial Black',
                color: enabled ? '#ffffff' : '#555577',
            }).setOrigin(0.5).setDepth(62));
            if (enabled) {
                bg.setInteractive({ useHandCursor: true });
                bg.on('pointerup', () => { this._closeHandCardMenu(); action(); });
            } else if (disabledAction) {
                bg.setInteractive({ useHandCursor: false });
                bg.on('pointerup', () => { this._closeHandCardMenu(); disabledAction(); });
            }
        });
    }

    _handMenuButtons(card) {
        const type = card.cardType;
        const btns = [];

        if (type === 'gang_member') {
            const canPlay = this.state.player.authority >= (card.authority || 0)
                ;
            if (canPlay) {
                btns.push({ label: 'PLACE — ATK POSITION', action: () => this._beginSlotSelect('atk') });
                btns.push({ label: 'PLACE — DEF POSITION', action: () => this._beginSlotSelect('def') });
            }
        } else if (type === 'hustle') {
            const hasAuth  = this.state.player.authority >= (card.authority || 0);
            const reqMet   = this._hustleReqMet(card);
            const canPlay  = hasAuth && reqMet;
            const disMsg   = !reqMet ? 'Requirements not fulfilled!'
                           : !hasAuth ? 'Not enough authority!'
                           : null;
            btns.push({
                label:          'ACTIVATE',
                enabled:        canPlay,
                action:         () => {
                    const cardObj = this._pendingHandCard;
                    this._cancelHandCardPending(false);
                    this._playHustle('player', cardObj);
                },
                disabledAction: disMsg
                    ? () => this._showFloatingText(W / 2, 290, disMsg, '#ff3b4e')
                    : null,
            });
        } else if (type === 'ambush') {
            const canPlay = this.state.player.authority >= (card.authority || 0);
            btns.push({
                label:          'SET (BACK ROW)',
                enabled:        canPlay,
                action:         () => this._beginSlotSelect('set'),
                disabledAction: canPlay ? null
                    : () => this._showFloatingText(W / 2, 290, 'Not enough authority!', '#ff3b4e'),
            });
        }

        btns.push({ label: 'CANCEL', action: () => this._cancelHandCardPending() });
        return btns;
    }

    _beginSlotSelect(position) {
        this._pendingPosition = position;
        this._highlightValidSlots(this._pendingHandCard.cardData);

        const validSlots = [...this._slotObjects.pl_front, ...this._slotObjects.pl_back]
            .filter(s => !s.cardObject && (
                position === 'activate'
                    ? !s.isBackRow
                    : (this._pendingHandCard.cardData.cardType === 'gang_member' ? !s.isBackRow : s.isBackRow)
            ));

        validSlots.forEach(slot => {
            slot.removeAllListeners('pointerup');
            slot.on('pointerup', () => {
                if (this._canPlayCard(this._pendingHandCard.cardData, slot.slotIndex)) {
                    const cardObj = this._pendingHandCard;
                    const pos     = this._pendingPosition;
                    this._cancelHandCardPending(false);
                    this._placeCardWithPosition(cardObj, slot.slotIndex, pos);
                }
            });
        });
    }

    _closeHandCardMenu() {
        this._handMenuEls?.forEach(e => e.destroy());
        this._handMenuEls = null;
    }

    // restoreDepth=true  → player cancelled: animate card back to fan position.
    // restoreDepth=false → card is being placed: kill tweens only, no return
    //                      animation. _finalizePlaceCard takes over immediately.
    _cancelHandCardPending(restoreDepth = true) {
        this._closeHandCardMenu();
        this._clearSlotHighlights();
        [...this._slotObjects.pl_front, ...this._slotObjects.pl_back]
            .forEach(s => s.removeAllListeners('pointerup'));
        if (this._pendingHandCard) {
            const c = this._pendingHandCard;
            this.tweens.killTweensOf(c.container);
            if (restoreDepth) {
                // Genuine cancel — animate card back to its resting fan position
                c.container.setDepth(1);
                this.tweens.add({
                    targets:  c.container,
                    y:        c._homeY ?? 0,
                    angle:    c._homeAngle ?? 0,
                    scaleX:   1,
                    scaleY:   1,
                    duration: 180,
                    ease:     'Back.Out',
                });
            }
            // When restoreDepth=false the card is being deployed — leave position
            // alone so _finalizePlaceCard can setPosition cleanly with no tween fighting.
        }
        this._pendingHandCard  = null;
        this._pendingPosition  = null;
    }

    _highlightValidSlots(cardData) {
        const type = cardData.cardType;

        // Hardware: highlight front-row slots that already have a character
        if (type === 'hardware') {
            this._slotObjects.pl_front.forEach(slot => {
                if (!slot.cardObject) return;
                slot.setFillStyle(0x28a745).setAlpha(1);
            });
            return;
        }

        // Characters → front row (empty). Ambush → back row (empty). Hustle → back row (empty).
        const wantsFront = type === 'gang_member';
        [...this._slotObjects.pl_front, ...this._slotObjects.pl_back].forEach(slot => {
            if (slot.cardObject) return;
            const valid = wantsFront ? !slot.isBackRow : slot.isBackRow;
            if (valid) slot.setFillStyle(0x28a745).setAlpha(1);
        });
    }

    _clearSlotHighlights() {
        [...this._slotObjects.pl_front, ...this._slotObjects.pl_back].forEach(slot => {
            slot.setFillStyle(0x1a1a2e, 0).setAlpha(1);
            this._resetSlotStroke(slot);
        });
    }

    _resetSlotStroke(slot) {
        const color = slot.isBackRow ? 0x7a8fb8 : 0xb388c9;
        slot.setStrokeStyle(1, color, 0.75);
    }

    _canPlayCard(cardData, slotIndex) {
        if (this.state.activePlayer !== 'player') return false;
        if (!['deployment', 'regroup'].includes(this.state.phase)) return false;

        const slot = this._findSlotByIndex('player', slotIndex);
        if (!slot) return false;

        const type = cardData.cardType;

        // Hardware attaches TO a front-row character (slot must already be occupied by one)
        if (type === 'hardware') {
            if (slot.isBackRow || !slot.cardObject) return false;
            const tgt = this.state.player.field[slot.slotIndex];
            return !!(tgt && tgt.cardType === 'gang_member');
        }

        // Everything else goes into an EMPTY slot
        if (slot.cardObject) return false;

        if (type === 'gang_member') {
            if (slot.isBackRow) return false;
            const cost = cardData.authority || 0;
            if (this.state.player.authority < cost) return false;
            return true;
        }

        // Hustle (spell) and Ambush (trap) go to the back row
        if (type === 'ambush') {
            if (!slot.isBackRow) return false;
            if (this.state.player.authority < (cardData.authority || 0)) return false;
            return true;
        }
        if (type === 'hustle') {
            return slot.isBackRow;
        }

        return false;
    }

    _placeCardWithPosition(cardObj, slotIndex, position) {
        const slot = this._findSlotByIndex('player', slotIndex);
        if (!slot) return;
        const type = cardObj.cardData.cardType;

        if (type === 'hustle') { this._playHustle('player', cardObj); return; }
        if (type === 'hardware') { this._attachHardware('player', slotIndex, cardObj); return; }

        if (type === 'gang_member' && !slot.isBackRow) {
            const cost = cardObj.cardData.authority || 0;
            this.state.player.authority = Math.max(0, this.state.player.authority - cost);
            this._refreshAuthorityDisplay();
            if (cost > 0) this._pulseAuthorityPill('player', `-${cost}`, '#e63946');
        }

        // Map menu choice to internal position token
        const pos = position === 'def' ? 'def_set' : (position === 'atk' ? 'atk' : null);
        this._finalizePlaceCard(cardObj, slot, slotIndex, pos);
    }

    _placeCard(cardObj, slotIndex) {
        const slot = this._findSlotByIndex('player', slotIndex);
        if (!slot) return;

        const type = cardObj.cardData.cardType;

        // ── Hustle: resolve immediately, send to the Gutter, no field presence ──
        if (type === 'hustle') {
            this._playHustle('player', cardObj);
            return;
        }

        // ── Hardware: attach to the character in the matching front-row slot ──
        if (type === 'hardware') {
            this._attachHardware('player', slotIndex, cardObj);
            return;
        }

        // Spend authority to deploy a character
        const isCharacter = type === 'gang_member';
        if (isCharacter && !slot.isBackRow) {
            const cost = cardObj.cardData.authority || 0;
            this.state.player.authority = Math.max(0, this.state.player.authority - cost);
            this._refreshAuthorityDisplay();
        }

        this._finalizePlaceCard(cardObj, slot, slotIndex, isCharacter ? 'atk' : null);
    }

    _finalizePlaceCard(cardObj, slot, slotIndex, position) {
        this._playerCardsPlayed++;
        const type = cardObj.cardData.cardType;
        const isCharacter = type === 'gang_member';

        // Kill any in-flight fan/hover/popup tweens before reparenting —
        // otherwise the tween continues running in scene coordinates after
        // the container leaves handContainer, sending the card to the wrong position.
        this.tweens.killTweensOf(cardObj.container);

        // Reparent the card out of the hand container (which has its own y
        // offset + mask) and back into the scene root, then snap to the slot
        // — otherwise the card renders off-screen and gets mask-clipped.
        if (this._handContainer?.list?.includes(cardObj.container)) {
            this._handContainer.remove(cardObj.container, false);
            this.add.existing(cardObj.container);
            cardObj.container.clearMask?.();
            // Kill again: removing from the container fires pointerout on the frame,
            // which triggers _unhoverHandCard and starts a new tween (y→0 in scene
            // coords = top of canvas). Killing here ensures that tween never runs.
            this.tweens.killTweensOf(cardObj.container);
        }

        // Snap card to slot centre — reset fan rotation and hover scale
        cardObj.container.setPosition(slot.x, slot.y);
        cardObj.container.setAngle(0);
        cardObj.container.setScale(1);
        cardObj.container.setDepth(2);

        // Update state
        this.state.player.field[slotIndex] = {
            ...cardObj.cardData,
            faceDown:    type === 'ambush' || position === 'def_set',
            hasAttacked: false,
            positionChangedThisTurn: isCharacter, // can't re-position on the same turn deployed
            position:    isCharacter ? (position === 'def_set' ? 'def' : position || 'atk') : undefined,
        };
        slot.cardObject = cardObj;
        cardObj.setFieldMode('player');
        cardObj.enableZoom(false);
        this._attachFieldTap(cardObj, slot);

        // Remove from hand array + reflow
        this._handCards = this._handCards.filter(c => c !== cardObj);
        this._reflowHand();

        if (isCharacter && !slot.isBackRow) this.state.player.deployedThisTurn++;

        // Ambush SET costs authority upfront (activation is free — cost already paid)
        if (type === 'ambush') {
            const cost = cardObj.cardData.authority || 0;
            this.state.player.authority = Math.max(0, this.state.player.authority - cost);
            this._refreshAuthorityDisplay();
        }

        this._sfx('sfx_card_play');

        // Visuals by position
        if (type === 'ambush') {
            cardObj.flipFaceDown();   // face-down upright (like YuGiOh trap cards)
        } else if (position === 'def_set') {
            cardObj.setFaceDownDef();  // set-in-DEF: face-down sideways
        } else if (position === 'def') {
            cardObj.container.setAngle(90);  // face-up DEF (rare from hand)
        }

        this._recalcClanBonuses();
        this._refreshZoneCounts();

        // Rarity-based drop-in + impact effect
        this._playCardPlacementEffect(cardObj, slot);
    }

    // ATK vs set-in-DEF prompt shown on character deploy
    _showDeployPositionModal(cardData, callback) {
        const els = [];
        const reg = (o) => { els.push(o); return o; };
        const cleanup = () => els.forEach(e => e.destroy());

        reg(this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.7).setDepth(60));
        reg(this.add.rectangle(W / 2, H / 2, 260, 120, 0x0d0d2a)
            .setStrokeStyle(2, 0x4cc9f0).setDepth(61));
        reg(this.add.text(W / 2, H / 2 - 40, `DEPLOY ${cardData.name?.toUpperCase() || ''}`, {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5).setDepth(62));

        const atkBtn = reg(this.add.rectangle(W / 2 - 60, H / 2 + 10, 100, 32, 0xe63946)
            .setInteractive({ useHandCursor: true }).setDepth(62));
        reg(this.add.text(W / 2 - 60, H / 2 + 10, 'ATK (face-up)', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(63));

        const defBtn = reg(this.add.rectangle(W / 2 + 60, H / 2 + 10, 100, 32, 0x4cc9f0)
            .setInteractive({ useHandCursor: true }).setDepth(62));
        reg(this.add.text(W / 2 + 60, H / 2 + 10, 'SET DEF', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#000000',
        }).setOrigin(0.5).setDepth(63));

        atkBtn.on('pointerup', () => { cleanup(); callback('atk'); });
        defBtn.on('pointerup', () => { cleanup(); callback('def_set'); });
    }

    // ── Hustle: immediate spell ──────────────────────────────────────────────

    _hustleReqMet(cardData) {
        if (cardData.effectKey === 'blood_scent') {
            return this.state.player.field.some(
                c => c && c.subtype === 'striver' && c.promotesTo && !c.downed
            );
        }
        if (cardData.effectKey === 'lion_rescue') {
            return this.state.player.field.some(
                c => c && c.downed && c.clanTag === 'lion'
            );
        }
        return true;
    }

    _playHustle(owner, cardObj) {
        const cardData = cardObj.cardData;

        if (owner === 'player') this._playerCardsPlayed++;

        // Deduct authority on play (the cost is paid when activated from hand)
        if (owner === 'player') {
            const cost = cardData.authority || 0;
            this.state.player.authority = Math.max(0, this.state.player.authority - cost);
            this._refreshAuthorityDisplay();
            if (cost > 0) this._pulseAuthorityPill('player', `-${cost}`, '#e63946');
        }

        // Remove from hand visually + state immediately so it can't be re-played
        const handIdx = this.state[owner].hand.indexOf(cardData);
        if (handIdx !== -1) this.state[owner].hand.splice(handIdx, 1);

        if (owner === 'player') {
            this._handCards = this._handCards.filter(c => c !== cardObj);
            this._reflowHand();
        } else {
            this._refreshOppHandDisplay();
        }

        this._sfx('sfx_card_play');

        // Animate then resolve
        this._playHustleReveal(cardData, cardObj, owner, () => {
            cardObj.destroy();
            this.state[owner].gutter.push(cardData);
            this.effectBus.trigger('on_play', { card: cardData, owner });
            this._refreshZoneCounts();
        });
    }

    _playHustleReveal(cardData, cardObj, owner, onComplete) {
        if (!SettingsManager.animationsEnabled) {
            onComplete?.();
            return;
        }

        this._enterResolving();

        const cx = W / 2;
        const cy = H / 2;
        const layer = this.add.container(0, 0).setDepth(55);

        // Dim the board
        const curtain = this.add.rectangle(cx, cy, W, H, 0x000011, 0).setDepth(54);
        this.tweens.add({ targets: curtain, alpha: 0.65, duration: 200 });

        // Cyan glow ring in center
        const ring = this.add.ellipse(cx, cy, 90, 120, 0x4cc9f0, 0)
            .setDepth(56).setStrokeStyle(3, 0x4cc9f0, 1);
        layer.add(ring);
        this.tweens.add({ targets: ring, alpha: 0.9, scaleX: 1.1, scaleY: 1.1, duration: 180 });

        // Comic burst rays (cyan)
        const burstColors = [0x4cc9f0, 0xffffff, 0x00e5ff];
        const rayCount = 10;
        for (let i = 0; i < rayCount; i++) {
            const angle  = (i / rayCount) * Math.PI * 2;
            const length = 32 + Math.random() * 20;
            const width  = 5 + Math.random() * 5;
            const ray = this.add.rectangle(
                cx + Math.cos(angle) * length * 0.5,
                cy + Math.sin(angle) * length * 0.5,
                length, width,
                burstColors[i % burstColors.length], 0.85,
            ).setDepth(56).setRotation(angle);
            layer.add(ray);
            this.tweens.add({ targets: ray, scaleX: 1.5, alpha: 0, duration: 450, ease: 'Power2' });
        }

        // Enlarged card art centered
        const artKey = cardData.art_url || cardData.id || null;
        let cardImg = null;
        if (artKey && this.textures.exists(artKey)) {
            cardImg = this.add.image(cx, cy, artKey).setDisplaySize(110, 154).setDepth(57);
            // Capture the display-size scale before zeroing so tween restores it correctly
            const tScaleX = cardImg.scaleX;
            const tScaleY = cardImg.scaleY;
            cardImg.setScale(0).setAlpha(0);
            layer.add(cardImg);
            this.tweens.add({ targets: cardImg, scaleX: tScaleX, scaleY: tScaleY, alpha: 1, duration: 200, ease: 'Back.Out' });
        }

        this.time.delayedCall(180, () => {
            // "HUSTLE!" banner
            const banner = this.add.text(cx, cy - 80, 'HUSTLE!', {
                fontSize: '20px', fontFamily: 'Arial Black',
                color: '#4cc9f0',
                stroke: '#000000', strokeThickness: 5,
            }).setOrigin(0.5).setDepth(58).setScale(0).setAlpha(0);
            layer.add(banner);
            this.tweens.add({ targets: banner, scaleX: 1, scaleY: 1, alpha: 1, duration: 220, ease: 'Back.Out' });

            // Card name subtitle
            const nameTxt = this.add.text(cx, cy + 70, cardData.name?.toUpperCase() ?? '', {
                fontSize: '8px', fontFamily: 'Arial Black',
                color: '#ffffff', stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5).setDepth(58).setAlpha(0);
            layer.add(nameTxt);
            this.tweens.add({ targets: nameTxt, alpha: 1, duration: 200, delay: 100 });

            // Effect text snippet (first 60 chars)
            if (cardData.effectText) {
                const snippet = cardData.effectText.length > 60
                    ? cardData.effectText.slice(0, 57) + '…'
                    : cardData.effectText;
                const fx = this.add.text(cx, cy + 86, snippet, {
                    fontSize: '6px', fontFamily: 'Verdana, sans-serif',
                    color: '#aaddff', align: 'center',
                    wordWrap: { width: 180 },
                }).setOrigin(0.5).setDepth(58).setAlpha(0);
                layer.add(fx);
                this.tweens.add({ targets: fx, alpha: 1, duration: 200, delay: 200 });
            }

            this.cameras.main.shake(200, 0.008);

            // Hold then fade out
            this.time.delayedCall(900, () => {
                this.tweens.add({
                    targets: [curtain, ring, banner, nameTxt],
                    alpha: 0, duration: 280, ease: 'Power2',
                    onComplete: () => {
                        layer.destroy(true);
                        curtain.destroy();
                        this._exitResolving();
                        onComplete?.();
                    },
                });
            });
        });
    }

    // ── Hardware: equip onto a front-row character ───────────────────────────

    _attachHardware(owner, slotIndex, cardObj) {
        const tgt = this.state[owner].field[slotIndex];
        if (!tgt || tgt.cardType !== 'gang_member') {
            cardObj.returnToHand();
            return;
        }

        // Apply stat modifiers — track them as cumulative buffs so multiple
        // hardware stack and clan/bulwark recalcs preserve the bonus.
        const atkMod = cardObj.cardData.atkMod || 0;
        const defMod = cardObj.cardData.defMod || 0;
        tgt._baseAtk  = tgt._baseAtk ?? tgt.attack;
        tgt._baseDef  = tgt._baseDef ?? tgt.defense;
        tgt._hwAtkMod = (tgt._hwAtkMod || 0) + atkMod;
        tgt._hwDefMod = (tgt._hwDefMod || 0) + defMod;

        // Track the equipped hardware on the character
        tgt._hardware = tgt._hardware || [];
        tgt._hardware.push({ ...cardObj.cardData, _attachedToFront: slotIndex });

        // Place the hardware visibly in the first open back-row slot.
        // Back row only has 3 zones, so it isn't paired 1:1 with the front row.
        const hwSlot = this._findFirstOpenBackRowSlot(owner);
        if (hwSlot) {
            this.state[owner].field[hwSlot.slotIndex] = {
                ...cardObj.cardData,
                _attachedToFront: slotIndex,
            };
            // Reparent out of the hand strip before snapping into place
            if (this._handContainer?.list?.includes(cardObj.container)) {
                this._handContainer.remove(cardObj.container, false);
                this.add.existing(cardObj.container);
                cardObj.container.clearMask?.();
            }
            cardObj.container.setPosition(hwSlot.x, hwSlot.y);
            cardObj.container.setDepth(2);
            hwSlot.cardObject = cardObj;
            cardObj.setFieldMode('player');
        }

        // Refresh the front-row character visual
        const frontSlot = this._findSlotByIndex(owner, slotIndex);
        if (frontSlot?.cardObject) frontSlot.cardObject.updateStats(tgt);

        this._handCards = this._handCards.filter(c => c !== cardObj);
        this._reflowHand();

        this._sfx('sfx_card_play');
        if (atkMod) this._showStatMod(frontSlot.x - 14, frontSlot.y - 30, atkMod, { label: 'ATK' });
        if (defMod) this._showStatMod(frontSlot.x + 14, frontSlot.y - 30, defMod, { label: 'DEF', accent: '#4cc9f0' });
        this._recalcClanBonuses();
        this._recalcBulwarkDefBonuses();
    }

    _sendToGraveyard(owner, slot) {
        const card = this.state[owner].field[slot.slotIndex];
        if (card) this.state[owner].gutter.push(card);
        this.state[owner].field[slot.slotIndex] = null;

        if (slot.cardObject) {
            slot.cardObject.destroy();
            slot.cardObject = null;
        }
        this._clearSlotGlow(slot);
        // Reset hit area in case card was downed (rotated, expanded slot)
        slot.setSize(SLOT_W, SLOT_H);

        // Hardware attached to a front-row character goes to the Gutter with it
        const hwSlotIdx = slot.slotIndex >= 0 && slot.slotIndex < 5 ? slot.slotIndex + 5 : null;
        if (hwSlotIdx !== null) {
            const attachedHw = this.state[owner].field[hwSlotIdx];
            if (attachedHw && attachedHw.cardType === 'hardware' && attachedHw._attachedToFront === slot.slotIndex) {
                this.state[owner].gutter.push(attachedHw);
                this.state[owner].field[hwSlotIdx] = null;
                const hwRow = owner === 'player' ? this._slotObjects.pl_back : this._slotObjects.opp_back;
                const hwSlot = hwRow.find(s => s.slotIndex === hwSlotIdx);
                if (hwSlot?.cardObject) { hwSlot.cardObject.destroy(); hwSlot.cardObject = null; }
                this._clearSlotGlow(hwSlot);
            }
        }

        this._refreshZoneCounts();
        this._recalcClanBonuses();
    }

    _reflowHand() {
        const total = this._handCards.length;
        this._handCards.forEach((cardObj, i) => {
            const { x, y, angle } = this._handCardTransform(i, total);
            cardObj._homeX     = x;
            cardObj._homeY     = y;
            cardObj._homeAngle = angle;

            // Never tween a card that has its own active animation — the pending
            // card is popped up, the hovered card is rising; both must be left alone.
            if (cardObj === this._pendingHandCard) return;
            if (cardObj === this._hoveredHandCard)  return;

            this.tweens.killTweensOf(cardObj.container);
            this.tweens.add({
                targets:  cardObj.container,
                x, y, angle,
                duration: 150,
                ease:     'Power1',
            });
        });
        this._handContainer.x = 0;
    }

    // ── Phase management ──────────────────────────────────────────────────────

    _startPhase(phase) {
        // Clear any brawl-phase slot highlights whenever the phase changes
        if (this._slotObjects) {
            [...this._slotObjects.pl_front, ...this._slotObjects.opp_front,
             ...this._slotObjects.pl_back,  ...this._slotObjects.opp_back].forEach(slot => {
                slot.setFillStyle(0x1a1a2e, 0).setAlpha(1);
                this._resetSlotStroke(slot);
            });
        }
        this.state.phase = phase;
        this._highlightPhaseBtn(phase);
        this._refreshActionButtons?.();

        const isPlayerTurn = this.state.activePlayer === 'player';
        this._turnText.setText(
            isPlayerTurn
                ? `YOUR TURN  ·  ${phase.toUpperCase()}`
                : `OPPONENT TURN  ·  ${phase.toUpperCase()}`
        );
        this._turnText.setColor(isPlayerTurn ? '#4cc9f0' : '#e63946');
        if (this._turnBanner?.list?.[0]) {
            this._turnBanner.list[0].setStrokeStyle(1, isPlayerTurn ? 0x4cc9f0 : 0xe63946, 0.8);
        }

        switch (phase) {
            case 'upkeep':
                // Reset deployment limit for the active player's new turn
                this.state[this.state.activePlayer].deployedThisTurn = 0;

                // Reset per-turn promotion tracking
                this.state[this.state.activePlayer].promotedSlotsThisTurn = new Set();

                // Authority increases only once both players have completed their first turn
                // (turn counter: 1=P1 first, 2=P2 first, 3+=both have gone once)
                if (this.state.turn > 2) this._gainAuthority(this.state.activePlayer);

                // No draw on the very first turn (first player's draw is the opening hand)
                if (this.state.turn > 1) this._drawCard(this.state.activePlayer);

                // Fire per-turn effects (Eric Lv.3 ATK scaling, Maya Lv.3 buff flag, etc.)
                this.effectBus.trigger('on_upkeep', { owner: this.state.activePlayer });
                // Recalc passive bonuses that depend on board state
                this._recalcDownedBonuses?.();
                this._recalcBulwarkDefBonuses?.();

                // Check King Roan awaken condition
                this._checkLeaderAwaken(this.state.activePlayer);

                if (!isPlayerTurn) { this._stopTurnTimer(); this._runOpponentAI_withDelay(); }
                // YuGiOh-style: draw phase ends automatically once the draw lands
                else this.time.delayedCall(600, () => {
                    if (this.state.phase === 'upkeep' && this.state.activePlayer === 'player') {
                        this._startPhase('deployment');
                    }
                });
                break;
            case 'deployment':
                // Start the countdown the moment the player can act
                if (isPlayerTurn) this._startTurnTimer();
                break;
            case 'brawl':
                // No attacking on turn 1 (YuGiOh rule)
                if (this.state.turn === 1) {
                    this._showFloatingText(W / 2, 155, 'NO ATTACKS ON TURN 1', '#aaaacc');
                    this.time.delayedCall(700, () => this._startPhase('regroup'));
                    return;
                }
                if (isPlayerTurn) this._enterBrawlPhase();
                if (!isPlayerTurn) this._aiAttack();
                break;
            case 'regroup':
                // AI auto-advances through regroup — no player action required here
                if (!isPlayerTurn) this.time.delayedCall(400, () => this._startPhase('end'));
                break;
            case 'end':
                // Hand limit: player must discard down to 9 before ending turn
                if (isPlayerTurn && this.state.player.hand.length > 9) {
                    this._enforceHandLimit(() => this._endTurn());
                } else {
                    this._endTurn();
                }
                break;
        }
    }

    _onPhaseButtonPressed(phaseKey) {
        if (this.state.activePlayer !== 'player') return;

        const order = ['upkeep', 'deployment', 'brawl', 'regroup', 'end'];
        const curr  = order.indexOf(this.state.phase);
        const next  = order.indexOf(phaseKey);

        // Only advance forward
        if (next <= curr) return;
        this._startPhase(phaseKey);
    }

    _endTurn() {
        this._stopTurnTimer();

        // Always clear discard mode on turn end — prevents stale prompt from
        // persisting into the next turn if somehow not consumed.
        this._discardMode     = false;
        this._discardCallback = null;

        const active = this.state.activePlayer;
        const s      = this.state[active];

        // Clear per-turn flags. Promotion sickness clears here too.
        s.field.forEach(card => {
            if (card) {
                card.hasAttacked              = false;
                card.positionChangedThisTurn  = false;
                card.abilityUsedThisTurn      = false;
                card._mayaBuffAvailable       = false;
                card._bloodScentPromo         = false;
                card._blockEnforcerRedirectUsed = false;
                // Temporary buffs/debuffs that expire at end of turn —
                // just clear the flags; recalc below sets the final stats.
                card._ltBuff       = 0;
                card._maulerDebuff = 0;
            }
        });
        // Recompute final ATK/DEF from the cleared modifier fields
        this._recalcClanBonuses?.();
        this._recalcBulwarkDefBonuses?.();

        // Also clear leader per-turn flags
        if (s.leader) {
            s.leader.hasAttacked           = false;
            s.leader.abilityUsedThisTurn   = false;
        }

        s._brutusChainBonus  = 0;

        this.state.activePlayer = active === 'player' ? 'opponent' : 'player';
        this.state.turn++;
        // Apply venom ticks on the player whose turn is starting
        this._tickPoison(this.state.activePlayer);
        this._startPhase('upkeep');
    }

    // ── Brawl Phase: player attack declarations ───────────────────────────────

    _enterBrawlPhase() {
        // Highlight which player monsters can attack — selection happens via
        // the card-tap action menu (see _showCardActionMenu).
        this._slotObjects.pl_front.forEach(slot => {
            if (!slot.cardObject) return;
            const card = this.state.player.field[slot.slotIndex];
            if (!card || card.hasAttacked || card.position === 'def' || card.downed) return;
            slot.setStrokeStyle(2, 0xf4d35e);
        });
    }

    // ── Card action menu (tap own field card → Brawl/Position/Ability) ───────

    _attachFieldTap(cardObj, slot) {
        const frame = cardObj._frame;
        if (!frame) return;
        if (!frame.input) frame.setInteractive();

        let downAt = 0, downX = 0, downY = 0;
        frame.on('pointerdown', (ptr) => {
            downAt = this.time.now;
            downX  = ptr.worldX;
            downY  = ptr.worldY;
        });
        frame.on('pointerup', (ptr) => {
            const dt = this.time.now - downAt;
            const dx = Math.abs(ptr.worldX - downX);
            const dy = Math.abs(ptr.worldY - downY);
            // Quick tap (not a hold-zoom, not a drag)
            if (dt < 350 && dx < 8 && dy < 8) {
                this._showCardActionMenu(slot);
            }
        });
    }

    _showCardActionMenu(slot) {
        if (this.state.activePlayer !== 'player') return;
        const card = this.state.player.field[slot.slotIndex];
        if (!card) return;

        this._closeCardActionMenu();

        const phase   = this.state.phase;
        const isFront = !slot.isBackRow;
        const items   = [];

        if (slot.isBackRow) {
            // Back-row cards (ambush / hustle): only option is Activate
            const condsMet = ['deployment', 'brawl', 'regroup'].includes(phase)
                && card.faceDown
                && !card.abilityUsedThisTurn;
            const hasAuthority = this.state.player.authority >= (card.authority || 0);
            const cardCondMet  = this._checkCardCondition(card);
            items.push({
                label:          'Activate',
                enabled:        condsMet && hasAuthority && cardCondMet,
                action:         () => this._activateBackRowCard(slot),
                disabledAction: condsMet && !hasAuthority
                    ? () => this._showFloatingText(slot.x, slot.y - 40, 'Not enough authority!', '#ff3b4e')
                    : condsMet && !cardCondMet
                    ? () => this._showFloatingText(slot.x, slot.y - 40, 'Conditions not met!', '#ff3b4e')
                    : null,
            });
        } else {
            // Front-row cards: Brawl, Change Position, optional Ability
            const canBrawl = phase === 'brawl'
                && card.cardType === 'gang_member'
                && card.position !== 'def'
                && !card.hasAttacked
                && !card.downed;
            items.push({
                label: 'Brawl', enabled: canBrawl,
                action: () => this._selectAttacker(slot),
            });

            const canChange = ['deployment', 'regroup'].includes(phase)
                && card.cardType === 'gang_member'
                && !card.hasAttacked
                && !card.downed
                && !card.positionChangedThisTurn;
            const newPos = card.position === 'def' ? 'ATK' : 'DEF';
            items.push({
                label: `Change to ${newPos}`, enabled: canChange,
                action: () => this._togglePosition(slot, card),
            });

            if (card.ability) {
                items.push({
                    label: 'Activate Ability',
                    enabled: !card.abilityUsedThisTurn,
                    action: () => this._activateCardAbility(slot, card),
                });
            }
        }

        items.push({ label: 'Cancel', enabled: true, action: () => {} });

        // Layout
        const ITEM_W = 80, ITEM_H = 14, GAP = 2;
        const totalH = items.length * ITEM_H + (items.length - 1) * GAP;
        const above  = slot.y - SLOT_H / 2 - totalH / 2 - 6;
        const below  = slot.y + SLOT_H / 2 + totalH / 2 + 6;
        const py     = above < 14 ? below : above;

        // Tap-shield to dismiss when tapping outside
        const shield = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.001)
            .setDepth(69).setInteractive();
        shield.on('pointerdown', () => this._closeCardActionMenu());

        const c = this.add.container(slot.x, py).setDepth(70);

        items.forEach((it, i) => {
            const yy = -totalH / 2 + ITEM_H / 2 + i * (ITEM_H + GAP);
            const bg = this.add.rectangle(0, yy, ITEM_W, ITEM_H,
                it.enabled ? 0x1c2040 : 0x0a0a14, 0.97)
                .setStrokeStyle(1, it.enabled ? 0xf4d35e : 0x33334a, 0.85);
            const isClickable = it.enabled || !!it.disabledAction;
            if (isClickable) bg.setInteractive({ useHandCursor: it.enabled });
            const txt = this.add.text(0, yy, it.label, {
                fontSize: '8px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
                fontStyle: 'bold',
                color: it.enabled ? '#ffd86b' : '#555577',
            }).setOrigin(0.5);
            if (it.enabled) {
                bg.on('pointerup', (ptr) => {
                    ptr.event?.stopPropagation?.();
                    this._closeCardActionMenu();
                    it.action();
                });
            } else if (it.disabledAction) {
                bg.on('pointerup', (ptr) => {
                    ptr.event?.stopPropagation?.();
                    this._closeCardActionMenu();
                    it.disabledAction();
                });
            }
            c.add([bg, txt]);
        });

        this._cardActionMenu = { container: c, shield };
    }

    _closeCardActionMenu() {
        this._cardActionMenu?.container.destroy();
        this._cardActionMenu?.shield.destroy();
        this._cardActionMenu = null;
    }

    _togglePosition(slot, card) {
        const cardObj = slot.cardObject;
        if (card.position === 'def') {
            card.position = 'atk';
            cardObj?.container.setAngle(0);
            if (card.faceDown) {
                card.faceDown = false;
                cardObj?.flipFaceUp();
            }
        } else {
            card.position = 'def';
            cardObj?.container.setAngle(90);
        }
        card.positionChangedThisTurn = true;
        this._showFloatingText(slot.x, slot.y - 20,
            `→ ${card.position.toUpperCase()}`, '#ffd86b');
        this._sfx?.('sfx_card_play');
    }

    _activateCardAbility(slot, card) {
        if (!card.ability) {
            this._showFloatingText(slot.x, slot.y - 20, 'No effect', '#aaaacc');
            return;
        }
        this._showDecidingBanner('player');
        card.abilityUsedThisTurn = true;
        this.effectBus.trigger('on_ability', { card, owner: 'player', slot });

        // Maya Lv.3: let the player pick a LIONS target for the ATK buff
        if (card.effectKey === 'maya_lv3_buff') {
            this._promptMayaBuff('player');
        }

        // Maya Lv.1/2: promote if condition met
        if (card.ability === 'maya_promote' && card.promotesTo) {
            const field = this.state.player.field;
            const conditionMet = field.some(c =>
                c && c !== card && c.clanTag === 'lion' && !c.downed
                && (c.authority || 0) >= (card.authority || 0)
            );
            if (!conditionMet) {
                card.abilityUsedThisTurn = false; // refund — conditions not met
                this._showFloatingText(slot.x, slot.y - 30, 'Condition not met!', '#aaaacc');
                return;
            }
            const promotedData = CARD_CATALOG[card.promotesTo];
            if (promotedData) {
                const slotIdx = slot.slotIndex;
                this._doPromotion('player', slotIdx, promotedData);
            }
        }
    }

    // ── Targeting helper ──────────────────────────────────────────────────────
    /**
     * Lock the player into a target-selection mode.
     * Creates a full-screen input shield, pulsing overlays on each valid slot,
     * a prompt label, and a Cancel button.  Calls _enterResolving / _exitResolving.
     *
     * @param {Phaser.GameObjects.Rectangle[]} slots  - valid slot objects
     * @param {number}   color       - 0x hex colour for highlights (blue=friendly, red=enemy)
     * @param {string}   promptText  - instruction shown to the player
     * @param {Function} onPick      - called with the chosen slot object
     * @param {Function} [onCancel]  - called when Cancel pressed (default: no-op)
     * @param {string}   [cancelLabel='✕ CANCEL']
     */
    _beginTargeting(slots, color, promptText, onPick, onCancel, cancelLabel = '✕ CANCEL') {
        this._closeCardActionMenu?.();
        this._enterResolving();

        const objs = [];

        // Full-screen shield — absorbs all input so only our overlays are tappable
        const shield = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.001)
            .setDepth(47).setInteractive();
        objs.push(shield);

        // Per-slot pulsing highlight overlays (depth 48 — above shield)
        const overlayTweens = [];
        const slotOverlays = slots.map(s => {
            const hl = this.add.rectangle(s.x, s.y, SLOT_W + 8, SLOT_H + 8, color, 0.3)
                .setStrokeStyle(3, color, 1).setDepth(48).setInteractive({ useHandCursor: true });
            objs.push(hl);
            overlayTweens.push(this.tweens.add({
                targets: hl, alpha: 0.7, yoyo: true, repeat: -1, duration: 430, ease: 'Sine.easeInOut',
            }));
            return { slot: s, hl };
        });

        // Prompt label
        const label = this.add.text(W / 2, H / 2 - 44, promptText, {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
            stroke: '#000000', strokeThickness: 4,
            backgroundColor: '#000000bb',
            padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(49);
        objs.push(label);

        // Cancel / Skip button at the bottom
        const btnW = 130, btnH = 28, btnY = H - 26;
        const cancelBg = this.add.rectangle(W / 2, btnY, btnW, btnH, 0x140820)
            .setStrokeStyle(2, 0x8888aa, 0.9).setDepth(49).setInteractive({ useHandCursor: true });
        const cancelTxt = this.add.text(W / 2, btnY, cancelLabel, {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#aaaacc',
        }).setOrigin(0.5).setDepth(50);
        objs.push(cancelBg, cancelTxt);

        const cleanup = () => {
            overlayTweens.forEach(t => t.remove());
            objs.forEach(o => o?.destroy());
            this._exitResolving();
        };

        cancelBg.on('pointerover',  () => cancelBg.setAlpha(0.75));
        cancelBg.on('pointerout',   () => cancelBg.setAlpha(1));
        cancelBg.on('pointerdown',  () => cancelBg.setAlpha(0.55));
        cancelBg.on('pointerup',    () => { cleanup(); onCancel?.(); });

        slotOverlays.forEach(({ slot, hl }) => {
            hl.on('pointerup', () => { cleanup(); onPick(slot); });
        });
    }

    /** Prompt the player to pick a LIONS card on their field to receive Maya Lv.3's +400/+400 buff. */
    _promptMayaBuff(owner) {
        const validSlots = this._slotObjects.pl_front.filter(s => {
            const c = this.state[owner].field[s.slotIndex];
            return c && c.clanTag === 'lion' && !c.downed;
        });
        if (!validSlots.length) {
            this._showFloatingText(W / 2, 200, 'MAYA LV.3: No valid target!', '#aaaacc');
            return;
        }
        this._beginTargeting(validSlots, 0x4cc9f0, 'MAYA: Pick a LIONS target  (+400 ATK / +400 DEF)', (slot) => {
            const target = this.state[owner].field[slot.slotIndex];
            if (!target) return;
            target._baseAtk  = target._baseAtk ?? target.attack;
            target._baseDef  = target._baseDef ?? target.defense;
            target._mayaBuff = (target._mayaBuff || 0) + 400;
            this._showStatMod(slot.x, slot.y - 30, 400, { label: 'MAYA ATK/DEF' });
            this._recalcClanBonuses();
            this._recalcBulwarkDefBonuses();
        });
    }

    /** Prompt the player to pick a Striver on their field to apply Blood Scent's promo-ready effect. */
    _promptBloodScent(owner) {
        const validSlots = this._slotObjects.pl_front.filter(s => {
            const c = this.state[owner].field[s.slotIndex];
            return c && c.subtype === 'striver' && c.promotesTo && !c.downed;
        });
        if (!validSlots.length) {
            this._showFloatingText(W / 2, 200, 'BLOOD SCENT: No valid Striver!', '#aaaacc');
            return;
        }
        this._beginTargeting(validSlots, 0xe63946, 'BLOOD SCENT: Pick a Striver to grant promo-ready', (slot) => {
            const target = this.state[owner].field[slot.slotIndex];
            if (!target) return;
            // Mark for next-attack auto-promote (consumed by _checkBloodScentPromote).
            // Cleared at end of turn if unused.
            target._bloodScentPromo = true;
            this._showFloatingText(slot.x, slot.y - 30, `${target.name}: NEXT ATTACK PROMOTES!`, '#e63946');
        });
    }

    /** Prompt the player to pick which LIONS card gets Pride Lieutenant's +500 ATK buff. */
    _promptLieutenantBuff(owner, lt) {
        const validSlots = this._slotObjects.pl_front.filter(s => {
            const c = this.state[owner].field[s.slotIndex];
            return c && c !== lt && c.clanTag === 'lion' && !c.downed;
        });
        if (!validSlots.length) {
            this._showFloatingText(W / 2, 200, 'LIEUTENANT: No valid target!', '#aaaacc');
            return;
        }
        this._beginTargeting(validSlots, 0x4cc9f0, 'LIEUTENANT: Pick a LIONS ally (+500 ATK)', (slot) => {
            const target = this.state[owner].field[slot.slotIndex];
            if (!target) return;
            target._baseAtk = target._baseAtk ?? target.attack;
            target._ltBuff  = (target._ltBuff || 0) + 500;
            this._showStatMod(slot.x, slot.y - 30, 500, { label: 'LIEUTENANT ATK' });
            this._recalcClanBonuses();
        });
    }

    /** Prompt the player to pick an enemy character for Brutus's -700 ATK debuff. */
    _promptBrutusTarget(defOwner) {
        const targetSlots = (defOwner === 'opponent' ? this._slotObjects.opp_front : this._slotObjects.pl_front)
            .filter(s => {
                const c = this.state[defOwner].field[s.slotIndex];
                return c && !c.downed && c.cardType === 'gang_member';
            });
        if (!targetSlots.length) {
            this._showFloatingText(W / 2, 200, 'BRUTUS: No valid target!', '#aaaacc');
            return;
        }
        this._beginTargeting(targetSlots, 0xe63946, 'BRUTUS: Pick an enemy to debuff (-700 ATK)', (slot) => {
            const target = this.state[defOwner].field[slot.slotIndex];
            if (!target) return;
            target._baseAtk      = target._baseAtk ?? target.attack;
            target._brutusDebuff = (target._brutusDebuff || 0) + 700;
            this._showStatMod(slot.x, slot.y - 30, -700, { label: 'BRUTUS ATK' });
            this._recalcClanBonuses();
        });
    }

    /** Prompt the player to pick a downed LIONS character to revive with Lion Rescue. */
    _promptLionRescue(owner) {
        const validSlots = this._slotObjects.pl_front.filter(s => {
            const c = this.state[owner].field[s.slotIndex];
            return c && c.downed && c.clanTag === 'lion';
        });
        if (!validSlots.length) {
            this._showFloatingText(W / 2, 200, 'LION RESCUE: No downed LIONS!', '#aaaacc');
            return;
        }
        this._beginTargeting(validSlots, 0x4cc9f0, 'LION RESCUE: Pick a downed LIONS to revive', (slot) => {
            const target = this.state[owner].field[slot.slotIndex];
            if (!target) return;
            this._recoverDownedCard(owner, slot.slotIndex);
            this._showFloatingText(slot.x, slot.y - 30, `${target.name} STANDS UP!`, '#4cc9f0');
        });
    }

    // ── Viper: prompt pre-attack lane move ────────────────────────────────────
    _promptViperMove(attackerSlot, callback) {
        const slotIdx  = attackerSlot.slotIndex;
        const frontRow = this._slotObjects.pl_front;
        const adjSlots = frontRow.filter(s => Math.abs(s.slotIndex - slotIdx) === 1 && !s.cardObject);

        if (!adjSlots.length) { callback(attackerSlot); return; }

        this._beginTargeting(
            adjSlots, 0x4cc9f0, 'VIPER: Move to an adjacent lane before striking',
            (slot) => {
                const card = this.state.player.field[slotIdx];
                if (!card) { callback(attackerSlot); return; }
                this.state.player.field[slot.slotIndex] = card;
                this.state.player.field[slotIdx]        = null;
                const co = attackerSlot.cardObject;
                if (co) {
                    attackerSlot.cardObject = null;
                    slot.cardObject         = co;
                    co.container?.setPosition(slot.x, slot.y);
                    co._slotRef = slot;
                }
                this._showFloatingText(slot.x, slot.y - 30, 'VIPER: REPOSITIONED!', '#4cc9f0');
                this._refreshAllStatBadges?.();
                callback(slot);
            },
            () => callback(attackerSlot),  // SKIP
            '↷ SKIP',
        );
    }

    // ── Viper Lv.3: prompt post-kill lane move ────────────────────────────────
    _promptViperMoveAfterKill(attackerSlot) {
        const slotIdx  = attackerSlot.slotIndex;
        const frontRow = this._slotObjects.pl_front;
        const adjSlots = frontRow.filter(s => Math.abs(s.slotIndex - slotIdx) === 1 && !s.cardObject);

        if (!adjSlots.length) return;

        this._beginTargeting(
            adjSlots, 0x4cc9f0, 'VIPER LV.3: Move to an adjacent lane after the kill',
            (slot) => {
                const card = this.state.player.field[slotIdx];
                if (!card) return;
                this.state.player.field[slot.slotIndex] = card;
                this.state.player.field[slotIdx]        = null;
                const co = attackerSlot.cardObject;
                if (co) {
                    attackerSlot.cardObject = null;
                    slot.cardObject         = co;
                    co.container?.setPosition(slot.x, slot.y);
                }
                this._showFloatingText(slot.x, slot.y - 30, 'VIPER: REPOSITIONED!', '#4cc9f0');
                this._refreshAllStatBadges?.();
            },
            null, // SKIP = do nothing
            '↷ SKIP',
        );
    }

    // ── Hunter Lv.2/3: prompt enemy Down after any KO ────────────────────────
    _promptHunterDown(defOwner) {
        const rows       = defOwner === 'opponent' ? this._slotObjects.opp_front : this._slotObjects.pl_front;
        const validSlots = rows.filter(s => {
            const c = this.state[defOwner].field[s.slotIndex];
            return c && !c.downed && c.cardType === 'gang_member';
        });
        if (!validSlots.length) return;

        this._beginTargeting(
            validSlots, 0xe63946, 'HUNTER: Pick an enemy to Down',
            (slot) => {
                const target = this.state[defOwner].field[slot.slotIndex];
                if (!target || target.downed) return;
                target.downed = true;
                slot.cardObject?.setDowned?.();
                slot.setSize(SLOT_H + 8, SLOT_H + 8);
                this._showFloatingText(slot.x, slot.y - 30, 'DOWNED!', '#ff4444');
                this._sfx('sfx_destroy');
                this.effectBus.trigger('on_downed', { card: target, owner: defOwner });
                this._recalcDownedBonuses();
            },
            null, // SKIP = no effect
            '↷ SKIP',
        );
    }

    // ── Sovereign: sweep enemies with DEF ≤ 1500 on entry ────────────────────
    _sovereignSweep(owner) {
        const defOwner = owner === 'player' ? 'opponent' : 'player';
        const rows     = defOwner === 'opponent' ? this._slotObjects.opp_front : this._slotObjects.pl_front;
        let swept = 0;
        rows.forEach(s => {
            const c = this.state[defOwner].field[s.slotIndex];
            if (!c || c.downed || c.defense > 1500) return;
            c.downed = true;
            s.cardObject?.setDowned?.();
            s.setSize(SLOT_H + 8, SLOT_H + 8);
            swept++;
            this.effectBus.trigger('on_downed', { card: c, owner: defOwner });
        });
        if (swept > 0) {
            this._showFloatingText(W / 2, 180, `SOVEREIGN: ${swept} ENEMY${swept > 1 ? 'S' : ''} DOWNED!`, '#f4d35e');
            this._sfx('sfx_destroy');
            this._recalcDownedBonuses();
        }
    }

    // ── Kingpin / Sovereign: recalc passive ATK bonus while opp has Downed ───
    _recalcDownedBonuses() {
        // Kingpin/Sovereign bonuses are computed inside _recalcClanBonuses now;
        // this just triggers a recompute when the downed state changes.
        this._recalcClanBonuses();
    }

    // ── DEF recalculation: single source of truth for card.defense ───────────
    _recalcBulwarkDefBonuses() {
        for (const owner of ['player', 'opponent']) {
            const field = this.state[owner].field;
            field.forEach((card, idx) => {
                if (!card) return;
                card._baseDef = card._baseDef ?? card.defense;
                let defBonus = 0;

                // Bulwark adjacency
                const left  = field[idx - 1];
                const right = field[idx + 1];
                if (left?.effectKey  === 'bulwark' && !left.downed)  defBonus += 400;
                if (right?.effectKey === 'bulwark' && !right.downed) defBonus += 400;

                // Per-card DEF buffs/debuffs
                defBonus += (card._mayaBuff     || 0);   // Maya Lv.3 also buffs DEF
                defBonus += (card._hwDefMod     || 0);   // Hardware DEF mod
                defBonus -= (card._maulerDebuff || 0);   // Mauler

                card.defense = Math.max(0, card._baseDef + defBonus);
            });
        }
        this._refreshAllStatBadges?.();
    }

    // ── Debt Collector: opponent discards 1 card ──────────────────────────────
    _debtCollectorDiscard(defOwner) {
        const hand = this.state[defOwner].hand;
        if (!hand?.length) {
            this._showFloatingText(W / 2, 200, 'DEBT COLLECTOR: No cards to discard!', '#aaaacc');
            return;
        }
        if (defOwner === 'opponent') {
            // AI: discard random card
            const idx    = Math.floor(Math.random() * hand.length);
            const card   = hand.splice(idx, 1)[0];
            this.state[defOwner].gutter.push(card);
            this._showFloatingText(W / 2, 200, `DEBT COLLECTOR: Opp discards ${card.name}!`, '#e63946');
            this._updateHandDisplay?.('opponent');
        } else {
            this._showFloatingText(W / 2, 190, 'DEBT COLLECTOR: You must discard 1 card!', '#e63946');
            this._promptDiscard?.(defOwner);
        }
    }

    // ── Post-battle result flags handler ─────────────────────────────────────
    _applyPostBattleFlags(result, attackerSlot, attackerOwner, defOwner, anim) {
        if (result.attackerCanAttackAgain) {
            const attCard = this.state[attackerOwner]?.field[attackerSlot.slotIndex];
            if (attCard) {
                attCard.hasAttacked = false;
                this._showFloatingText(attackerSlot.x, attackerSlot.y - 30, 'ATTACK AGAIN!', '#f4d35e');
            }
        }
        if (result.viperShouldMoveAfterKill && attackerOwner === 'player') {
            this.time.delayedCall(anim ? 300 : 0, () => this._promptViperMoveAfterKill(attackerSlot));
        }
        if (result.hunterShouldDown) {
            if (attackerOwner === 'player') {
                this.time.delayedCall(anim ? 300 : 0, () => this._promptHunterDown(defOwner));
            } else {
                // AI: auto-down the strongest eligible enemy
                const rows = defOwner === 'opponent' ? this._slotObjects.opp_front : this._slotObjects.pl_front;
                const tgt  = this.state[defOwner].field
                    .map((c, i) => ({ c, i }))
                    .filter(({ c }) => c && !c.downed && c.cardType === 'gang_member')
                    .sort((a, b) => b.c.attack - a.c.attack)[0];
                if (tgt) {
                    tgt.c.downed = true;
                    const slot = rows.find(s => s.slotIndex === tgt.i);
                    slot?.cardObject?.setDowned?.();
                    if (slot) slot.setSize(SLOT_H + 8, SLOT_H + 8);
                    this._showFloatingText(W / 2, 200, `HUNTER: ${tgt.c.name} DOWNED!`, '#ff6b35');
                    this.effectBus.trigger('on_downed', { card: tgt.c, owner: defOwner });
                    this._recalcDownedBonuses();
                }
            }
        }
        if (result.maulerAdjDebuff) {
            this._applyMaulerAdjDebuff(result.maulerAdjDebuffSlot, defOwner, anim);
        }
    }

    // ── Mauler: adjacent enemy DEF debuff after KO downed ────────────────────
    _applyMaulerAdjDebuff(defSlotIdx, defOwner, anim) {
        const rows = defOwner === 'opponent' ? this._slotObjects.opp_front : this._slotObjects.pl_front;
        [defSlotIdx - 1, defSlotIdx + 1].forEach(adjIdx => {
            const card = this.state[defOwner].field[adjIdx];
            if (!card) return;
            card._baseDef = card._baseDef ?? card.defense;
            card._maulerDebuff = (card._maulerDebuff || 0) + 500;
            const slot = rows.find(s => s.slotIndex === adjIdx);
            if (slot) this._showStatMod(slot.x, slot.y - 30, -500, { label: 'DEF', accent: '#ff6b35' });
        });
        this._recalcBulwarkDefBonuses();
    }

    /** Returns false when a card's activation conditions are not met (prevent grayed-out junk). */
    _checkCardCondition(card) {
        if (!card) return false;
        const field = this.state.player.field;
        switch (card.effectKey) {
            case 'kings_test':
                // Requires a LIONS striver on the field to protect
                return field.some(c => c && c.subtype === 'striver' && c.clanTag === 'lion' && !c.downed);
            case 'lion_rescue':
                // Requires a downed LIONS card on the field (leader in leader zone doesn't count)
                return field.some(c => c && c.clanTag === 'lion' && c.downed);
            case 'blood_scent':
                // Requires a striver on the field
                return field.some(c => c && c.subtype === 'striver' && !c.downed);
            case 'lion_ambush':
            case 'no_witnesses_ambush':
                // Requires at least one non-downed Lion on the front row (leader in his zone doesn't count)
                return field.some(c => c && c.clanTag === 'lion' && !c.downed && !c.faceDown);
            default:
                return true;
        }
    }

    /** Manually activate a face-down back-row card (hustle or ambush) on your own turn. */
    _activateBackRowCard(slot) {
        const card = this.state.player.field[slot.slotIndex];
        if (!card || !card.faceDown) return;

        this._showDecidingBanner('player');
        this._enterResolving();

        const afterReveal = () => {
            card.faceDown = false;
            card.abilityUsedThisTurn = true;

            if (card.cardType === 'hustle' || card.cardType === 'ambush') {
                this.effectBus.trigger('on_play', { card, owner: 'player', isPromotion: false });
            }

            this.time.delayedCall(200, () => {
                this.state.player.gutter.push(card);
                this.state.player.field[slot.slotIndex] = null;
                slot.cardObject?.destroy();
                slot.cardObject = null;
                this._clearSlotGlow(slot);
                this._refreshZoneCounts();
                this._recalcClanBonuses();
                this._exitResolving();
            });
        };

        if (card.cardType === 'hustle') {
            this._playHustleReveal(card, slot.cardObject, 'player', afterReveal);
        } else {
            this._playAmbushReveal(slot, card, afterReveal);
        }
    }

    _selectAttacker(attackerSlot) {
        this._deselectAll();

        const card = this.state.player.field[attackerSlot.slotIndex];
        const needsPreMove = card && ['viper_lv2', 'viper_lv3'].includes(card.effectKey);

        if (needsPreMove) {
            this._promptViperMove(attackerSlot, (resolvedSlot) => {
                this._activateAttackTargets(resolvedSlot || attackerSlot);
            });
        } else {
            this._activateAttackTargets(attackerSlot);
        }
    }

    _activateAttackTargets(attackerSlot) {
        this._selectedAttacker = attackerSlot;
        attackerSlot.setFillStyle(0xf4d35e).setAlpha(1);
        this._cancelBtn?.setVisible(true);

        // Highlight valid attack targets (opponent front row, then direct)
        const oppFront = this._slotObjects.opp_front.filter(s => s.cardObject);
        const targets  = oppFront.length ? oppFront : [];

        targets.forEach(slot => {
            slot.setFillStyle(0xe63946).setAlpha(1);
            slot.on('pointerdown', () => this._declareAttack(attackerSlot, slot));
            // Also route clicks on the card visual itself to the attack (card frame sits above the slot)
            if (slot.cardObject?._frame?.input) {
                slot.cardObject._frame.removeAllListeners('pointerdown');
                slot.cardObject._frame.on('pointerdown', () => this._declareAttack(attackerSlot, slot));
            }
        });

        // When front row is empty: show direct attack + leader attack buttons
        if (!oppFront.length) {
            const leaderAlive = this.state.opponent.leader && !this.state.opponent.leaderDead;
            this._showDirectAttackButton(attackerSlot, false);
            if (leaderAlive) {
                this._highlightLeaderTarget(attackerSlot);
            }
        }
    }

    _declareAttack(attackerSlot, defenderSlot) {
        this._deselectAll();

        const attCard = this.state.player.field[attackerSlot.slotIndex];
        const defCard = this.state.opponent.field[defenderSlot.slotIndex];

        // Pre-battle ATK adjustments (temporary, restored after resolveAttack)
        let preAttackBonus = 0;
        if (attCard?.effectKey === 'goldfang_attacker' && defCard?.position === 'def') preAttackBonus += 500;
        if (['hunter_lv1', 'hunter_lv2', 'hunter_lv3', 'mauler'].includes(attCard?.effectKey) && defCard?.downed) preAttackBonus += 500;
        if (defCard?.effectKey === 'bulwark' && !defCard?.downed) preAttackBonus -= 300;
        // Brutus chain bonus: next LIONS card to attack gets +300 ATK (one-time)
        const brutusBonus = (attCard?.clanTag === 'lion' && this.state.player._brutusChainBonus) ? this.state.player._brutusChainBonus : 0;
        if (brutusBonus) { this.state.player._brutusChainBonus = 0; preAttackBonus += brutusBonus; this._showFloatingText(attackerSlot.x, attackerSlot.y - 30, `BRUTUS: +${brutusBonus} ATK!`, '#f4d35e'); }
        if (preAttackBonus) attCard.attack += preAttackBonus;

        const result = this.brawlPhase.resolveAttack(
            attackerSlot.slotIndex,
            defenderSlot.slotIndex,
            'player'
        );

        if (preAttackBonus) attCard.attack -= preAttackBonus;

        // Blood Scent: any attack triggers promotion (consumes the flag)
        this._checkBloodScentPromote(attCard, attackerSlot.slotIndex, 'player', result);

        if (result.moraleDealt > 0 && attCard) this._trackMvp(attCard, result.moraleDealt, 'player');

        this._playAttackAnimation(attackerSlot, defenderSlot, result);
    }

    /** Blood Scent: if an attacker has _bloodScentPromo set, force a promotion result. */
    _checkBloodScentPromote(attCard, attackerSlotIdx, attackerOwner, result) {
        if (!attCard?._bloodScentPromo) return;
        if (!attCard.promotesTo) return;
        if (result.promoted) { attCard._bloodScentPromo = false; return; }
        attCard._bloodScentPromo = false;
        result.promoted        = true;
        result.promotedCardId  = attCard.promotesTo;
        result.promotingSlot   = attackerSlotIdx;
        result.promotingOwner  = attackerOwner;
        this._showFloatingText(W / 2, 200, 'BLOOD SCENT: PROMOTED!', '#e63946');
    }

    _declareDirectAttack(attackerSlot) {
        this._deselectAll();

        const attCard = this.state.player.field[attackerSlot.slotIndex];
        const result = this.brawlPhase.resolveDirectAttack(
            attackerSlot.slotIndex,
            'player'
        );
        // Blood Scent: direct attack also promotes
        this._checkBloodScentPromote(attCard, attackerSlot.slotIndex, 'player', result);
        if (result.moraleDealt > 0 && attCard) this._trackMvp(attCard, result.moraleDealt, 'player');

        this._playDirectAttackAnimation(attackerSlot, result);
    }

    _deselectAll() {
        this._selectedAttacker = null;
        this._cancelBtn?.setVisible(false);
        [...this._slotObjects.pl_front, ...this._slotObjects.opp_front].forEach(slot => {
            slot.setFillStyle(0x1a1a2e, 0).setAlpha(1);
            this._resetSlotStroke(slot);
            slot.removeAllListeners('pointerdown');
        });
        // Restore leader frame to zoom-only if it was highlighted as a target
        if (this._leaderTargetActive) {
            this._leaderTargetActive = false;
            this._leaderPulseTween?.stop();
            this._leaderPulseTween = null;
            const frame  = this._oppLeaderFrame;
            const leader = this.state.opponent.leader;
            if (frame && leader && !this.state.opponent.leaderDead) {
                frame.setScale(1);
                const isAwakened = this.state.opponent.leaderAwakened;
                frame.setStrokeStyle(2, isAwakened ? 0xf4d35e : 0xe63946, isAwakened ? 1 : 0.9);
                frame.removeAllListeners('pointerdown');
                frame.on('pointerdown', () => showCardZoom(this, leader));
            }
        }
        // Restore card-frame zoom listeners that were overridden during target selection
        this._slotObjects.opp_front.forEach(slot => {
            const frame = slot.cardObject?._frame;
            if (!frame?.input) return;
            frame.removeAllListeners('pointerdown');
            frame.on('pointerdown', () => showCardZoom(this, slot.cardObject.cardData));
        });
        // Re-attach drop-zone listener
        this._slotObjects.pl_front.forEach(slot => {
            if (!slot.cardObject) slot.input.dropZone = true;
        });
        this._reattachOppZoom();
    }

    // Re-adds tap-to-zoom on opp_front slots after pointerdown listeners are cleared
    _reattachOppZoom() {
        this._slotObjects.opp_front.forEach(slot => {
            slot.on('pointerdown', () => {
                if (this._selectedAttacker) return;
                if (!slot.cardObject || slot.cardObject._faceDown) return;
                showCardZoom(this, slot.cardObject.cardData);
            });
        });
    }

    _showDirectAttackButton(attackerSlot, leaderAlive = false) {
        const by = 162;
        const bx = leaderAlive ? W / 2 - 70 : W / 2;
        const bg = this.add.rectangle(bx, by, 130, 22, 0x1a0008, 0.95)
            .setStrokeStyle(1, 0xe63946, 1).setDepth(20);
        const lbl = this.add.text(bx, by, '⚡ DIRECT', {
            fontSize: '11px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            fontStyle: 'bold', color: '#e63946',
            stroke: '#000', strokeThickness: 2,
        }).setOrigin(0.5).setDepth(21);

        const hit = this.add.rectangle(bx, by, 134, 26, 0x000000, 0)
            .setDepth(22).setInteractive({ useHandCursor: true });

        const destroy = () => { bg.destroy(); lbl.destroy(); hit.destroy(); };
        hit.on('pointerover', () => { bg.setFillStyle(0x3a0010, 0.98); lbl.setColor('#ff6b6b'); });
        hit.on('pointerout',  () => { bg.setFillStyle(0x1a0008, 0.95); lbl.setColor('#e63946'); });
        hit.on('pointerdown', () => { destroy(); this._declareDirectAttack(attackerSlot); });

        this.time.delayedCall(5000, destroy);
    }

    // ── Leader targeting ──────────────────────────────────────────────────────

    _highlightLeaderTarget(attackerSlot) {
        const frame = this._oppLeaderFrame;
        if (!frame) return;

        // Glow the leader zone red and pulse to signal it's clickable
        frame.setStrokeStyle(3, 0xe63946, 1);
        this._leaderPulseTween?.stop();
        frame.setScale(1);
        this._leaderPulseTween = this.tweens.add({
            targets: frame,
            scale: { from: 1, to: 1.06 },
            duration: 450,
            yoyo: true,
            repeat: -1,
            ease: 'Sine.easeInOut',
        });

        // Track so _deselectAll can clean it up
        this._leaderTargetActive = true;

        frame.setInteractive({ useHandCursor: true });
        frame.removeAllListeners('pointerdown');
        frame.on('pointerdown', () => {
            this._deselectAll();
            this._declareLeaderAttack(attackerSlot);
        });
    }

    _declareLeaderAttack(attackerSlot) {
        const attCard  = attackerSlot.cardObject?.cardData
            ?? this.state.player.field[attackerSlot.slotIndex];
        const leader   = this.state.opponent.leader;
        if (!attCard || !leader) return;

        attCard.hasAttacked = true;
        this._enterResolving();
        this._sfx('sfx_attack');

        // Leader influence-based combat:
        //   • Attacker's ATK is subtracted from leader.influence
        //   • At 0 influence the leader is destroyed
        //   • The attacker takes no morale damage and is not downed
        if (leader.influence == null) leader.influence = leader.defense ?? 0;
        const dmg = Math.max(0, attCard.attack | 0);
        leader.influence = Math.max(0, leader.influence - dmg);
        const leaderDestroyed = leader.influence === 0;
        const attackerDestroyed = false;

        this._refreshLeaderInfluenceBadge('opponent');

        // Floating damage indicator on the leader frame — oversized comic style
        const lx = this._oppLeaderFrame?.x ?? W / 2;
        const ly = this._oppLeaderFrame?.y ?? 46;
        const attackerCard = attackerSlot?.cardObject?.cardData;
        const isCrit = dmg >= 1500 || leaderDestroyed;
        const accent = (attackerCard?.clan === 'viper_clan' || attackerCard?.clan === 'viper')
            ? '#66ff99' : '#ffd700';
        this._showDamageNumber(lx, ly - 14, dmg, { crit: isCrit, accent });

        this._playLeaderAttackVisuals(attackerSlot, leaderDestroyed, attackerDestroyed, () => {
            if (leaderDestroyed) this._destroyLeader('opponent');
            this._plProfileBox?.update(this.state.player.morale);
            this._oppProfileBox?.update(this.state.opponent.morale);
            this._checkWinCondition();
            this._exitResolving();
        });
    }

    _refreshLeaderInfluenceBadge(owner) {
        const leader = this.state[owner]?.leader;
        const badge  = owner === 'player' ? this._plLeaderInfluence : this._oppLeaderInfluence;
        if (!badge) return;
        if (!leader || this.state[owner].leaderAwakened || this.state[owner].leaderDead) {
            badge.setVisible(false);
            return;
        }
        badge.setText(`♛ ${leader.influence ?? leader.defense ?? 0}`);
        badge.setVisible(true);
    }

    _playLeaderAttackVisuals(attackerSlot, leaderDestroyed, attackerDestroyed, onComplete) {
        if (!SettingsManager.animationsEnabled) { onComplete(); return; }

        this._sfx(leaderDestroyed ? 'sfx_destroy' : 'sfx_attack');
        const lx = this._oppLeaderFrame?.x ?? W / 2;
        const ly = this._oppLeaderFrame?.y ?? ROW_Y.opp_back;

        // Flash on the leader zone
        const flash = this.add.rectangle(lx, ly, SLOT_W + 4, SLOT_H + 4, 0xffffff)
            .setDepth(32).setAlpha(0);
        this.tweens.add({ targets: flash, alpha: 0.85, duration: 60, yoyo: true,
            onComplete: () => flash.destroy() });

        if (leaderDestroyed) {
            this._playProceduralDestroy(lx, ly, onComplete);
        } else {
            this.cameras.main.shake(160, 0.008);
            this.time.delayedCall(300, onComplete);
        }
    }

    _destroyLeader(owner) {
        this.state[owner].leaderDead = true;
        // Morale penalty
        this.state[owner].morale = Math.max(0, this.state[owner].morale - 1000);
        this.state[owner].leader = null;

        const badge = owner === 'player' ? this._plLeaderBadge  : this._oppLeaderBadge;
        const frame = owner === 'player' ? this._plLeaderFrame  : this._oppLeaderFrame;
        const img   = owner === 'player' ? this._plLeaderImg    : this._oppLeaderImg;
        badge?.setText('DEFEATED').setColor('#e63946');
        frame?.setStrokeStyle(2, 0xe63946, 0.4);
        img?.setVisible(false);

        const who = owner === 'player' ? 'YOUR' : "OPPONENT'S";
        this._showFloatingText(W / 2, H / 2 - 20, `${who} LEADER FELL! -1000 INFLUENCE`, '#e63946');
        this._sfx('sfx_destroy');
        this._recalcClanBonuses();

        this._plProfileBox?.update(this.state.player.morale);
        this._oppProfileBox?.update(this.state.opponent.morale);
    }

    // ── Animation helpers ─────────────────────────────────────────────────────

    /**
     * Plays the attack animation between two slots, then resolves visual aftermath.
     * Monster attack: slash FX flies from attacker to defender.
     * On destroy: defend card explodes with anim_destroy.
     */
    _playAttackAnimation(attackerSlot, defenderSlot, result, onComplete) {
        this._enterResolving();
        this._sfx('sfx_attack');

        const attackerOwner = attackerSlot.slotOwner;
        const defenderOwner = attackerOwner === 'player' ? 'opponent' : 'player';

        // BrawlPhase.resolveAttack already nulled destroyed cards in state, so
        // read card data from the cardObject (still on the slot) first.
        const attCard = attackerSlot.cardObject?.cardData
            ?? this.state[attackerOwner]?.field[attackerSlot.slotIndex];
        const defCard = defenderSlot.cardObject?.cardData
            ?? this.state[defenderOwner]?.field[defenderSlot.slotIndex];

        // Flip a face-down DEF defender up (stays sideways)
        if (defenderSlot?.cardObject?._faceDown) {
            defenderSlot.cardObject.flipFaceUpDef();
        }

        const finish = () => {
            this._resolveVisualAftermath(attackerSlot, defenderSlot, result, attackerOwner, () => {
                this._exitResolving();
                onComplete?.();
            });
        };

        if (!SettingsManager.animationsEnabled) {
            finish();
            return;
        }

        this._playBattleCinematic(attCard, defCard, result, attackerOwner, finish);
    }

    // ── Battle cinematic ─────────────────────────────────────────────────────
    //
    // Gritty street-fight cutaway: faction-tinted curtain, attacker rushes
    // forward, freeze-frame on impact, faction FX on the defender, dramatic KO.
    // Total runtime: ~1.4s (no kill) / ~1.8s (kill) — mobile-friendly.
    _playBattleCinematic(attCard, defCard, result, attackerOwner, onComplete) {
        const layer = this.add.container(0, 0).setDepth(60);

        // ── Faction detection ─────────────────────────────────────────────────
        const attClan  = attCard?.clanTag || '';
        const isLion   = attClan === 'lion';
        const isViper  = attClan === 'viper';
        const hasFx    = isLion || isViper;

        // ── Faction-tinted curtain ────────────────────────────────────────────
        const bgColor  = isLion  ? 0x08060 : isViper ? 0x010806 : 0x000000;
        const vigColor = isLion  ? 0x1a0e00 : isViper ? 0x011a06 : 0x0d000d;
        const curtain  = this.add.rectangle(W/2, H/2, W, H, bgColor,  0).setDepth(60);
        const vignette = this.add.rectangle(W/2, H/2, W, H, vigColor, 0).setDepth(60);
        layer.add([curtain, vignette]);
        this.tweens.add({ targets: curtain,  alpha: 0.84, duration: 160 });
        this.tweens.add({ targets: vignette, alpha: 0.40, duration: 160 });

        // ── Card renders ──────────────────────────────────────────────────────
        const leftIsAttacker = attackerOwner === 'player';
        const homeAttX = W / 2 - 115;
        const homeDefX = W / 2 + 115;
        const attX     = leftIsAttacker ? -160 : W + 160;
        const defX     = leftIsAttacker ? W + 160 : -160;

        const attAccent = isLion ? '#ffd700' : isViper ? '#39ff14' : '#4cc9f0';
        const attVisual = this._makeCinematicCard(attCard, attX, H/2, attAccent);
        const defVisual = this._makeCinematicCard(defCard, defX, H/2, '#e63946');
        layer.add([attVisual.container, defVisual.container]);

        // Hard slam-in from both sides
        this.tweens.add({ targets: attVisual.container, x: homeAttX, duration: 260, ease: 'Back.Out', delay: 50 });
        this.tweens.add({ targets: defVisual.container, x: homeDefX, duration: 260, ease: 'Back.Out', delay: 50 });

        // Speed lines during entry
        this._playSpeedLines(layer, leftIsAttacker);

        // ── Rush + impact at t=400ms ──────────────────────────────────────────
        this.time.delayedCall(400, () => {
            this._sfx('sfx_attack');

            // Attacker lunges toward defender
            const rushDir = leftIsAttacker ? 1 : -1;
            this.tweens.add({
                targets: attVisual.container,
                x: homeAttX + rushDir * 58,
                duration: 75, ease: 'Power3.In',
                onComplete: () => {
                    // ── Freeze-frame 70ms ──
                    this.tweens.timeScale = 0.01;
                    this.time.delayedCall(70, () => { this.tweens.timeScale = 1; });

                    this.tweens.add({ targets: attVisual.container, x: homeAttX, duration: 130, ease: 'Back.Out' });
                },
            });

            // Defender recoils
            this.tweens.add({ targets: defVisual.container, x: homeDefX + rushDir * 20, duration: 75, delay: 70, ease: 'Power2', yoyo: true });

            // Impact burst at contact point
            const impX = W / 2 + rushDir * 30;
            const burst = this.add.circle(impX, H/2, 6, 0xffffff, 1).setDepth(63);
            layer.add(burst);
            this.tweens.add({
                targets: burst, radius: 72, alpha: 0, duration: 260, ease: 'Cubic.Out',
                onUpdate: () => burst.setRadius(burst.radius),
                onComplete: () => burst.destroy(),
            });

            this.cameras.main.shake(130, 0.009);

            // Comic-book hit word
            const hitWord = result.defenderDestroyed ? (isLion ? 'SMASHED!' : isViper ? 'INFECTED!' : 'WRECKED!')
                          : result.attackerDestroyed  ? 'COUNTERED!'
                          : result.tie                ? 'CLASH!'
                          : 'HIT!';
            const wordColor = isLion ? '#ffd700' : isViper ? '#39ff14' : '#ff3b4e';
            this._playComicHitText(impX, H/2 - 36, hitWord, layer, wordColor);
        });

        // ── Faction FX on defender card ───────────────────────────────────────
        if (isLion)  this.time.delayedCall(580, () => this._playLionClawCinematic(defVisual.container, H/2, layer));
        if (isViper) this.time.delayedCall(580, () => this._playViperCinematic(defVisual.container, H/2, layer));

        // ── Resolve ───────────────────────────────────────────────────────────
        const obliterateAt = hasFx ? 1060 : 740;
        this.time.delayedCall(obliterateAt, () => {
            const loserVisual = result.attackerDestroyed ? attVisual
                              : result.defenderDestroyed ? defVisual : null;
            const loserDamage = result.attackerDestroyed ? Math.abs(result.moraleDealt)
                              : result.defenderDestroyed ? result.moraleDealt : 0;

            if (result.tie) {
                this._obliterateCinematicCard(attVisual, 0, layer);
                this._obliterateCinematicCard(defVisual, 0, layer);
            } else if (loserVisual) {
                const winner = loserVisual === attVisual ? defVisual : attVisual;
                this._obliterateCinematicCard(loserVisual, loserDamage, layer);
                this.tweens.add({ targets: winner.container, scale: 1.10, duration: 150, yoyo: true, ease: 'Power2' });
            } else {
                this.tweens.add({ targets: [attVisual.container, defVisual.container], alpha: 0, duration: 260, delay: 300 });
            }

            // Close cinematic
            this.time.delayedCall(720, () => {
                this.tweens.add({
                    targets: [curtain, vignette], alpha: 0, duration: 220,
                    onComplete: () => { layer.destroy(); onComplete?.(); },
                });
                this.tweens.add({ targets: [attVisual.container, defVisual.container], alpha: 0, duration: 180 });
            });
        });
    }

    // Radial speed lines that streak inward during card entry
    _playSpeedLines(layer, leftIsAttacker) {
        const cx = leftIsAttacker ? W * 0.28 : W * 0.72;
        for (let i = 0; i < 10; i++) {
            const angle = -Math.PI / 2 + (i - 5) * 0.22;
            const len   = Phaser.Math.Between(35, 90);
            const sx    = cx + Math.cos(angle + Math.PI) * 60;
            const sy    = H / 2 + Math.sin(angle + Math.PI) * 60 + Phaser.Math.Between(-60, 60);
            const line  = this.add.rectangle(sx, sy, len, 1, 0xffffff, 0.25 + Math.random() * 0.2)
                .setAngle(Phaser.Math.RadToDeg(angle)).setDepth(61);
            layer.add(line);
            this.tweens.add({
                targets: line,
                x: sx + Math.cos(angle) * 70,
                y: sy + Math.sin(angle) * 70,
                alpha: 0, duration: 200 + i * 12, ease: 'Power1',
                onComplete: () => line.destroy(),
            });
        }
    }

    // Comic-book impact word: slams in with scale punch, then fades
    _playComicHitText(x, y, word, layer, color = '#ff3b4e') {
        const txt = this.add.text(x, y, word, {
            fontSize: '26px', fontFamily: 'Arial Black',
            color, stroke: '#000000', strokeThickness: 5,
        }).setOrigin(0.5).setDepth(64).setAlpha(0).setScale(0.3)
          .setAngle(Phaser.Math.Between(-6, -3));
        layer.add(txt);
        this.tweens.add({
            targets: txt, scale: 1.05, alpha: 1, duration: 110, ease: 'Back.Out',
            onComplete: () => {
                this.tweens.add({ targets: txt, alpha: 0, scale: 1.25, duration: 240, delay: 300, ease: 'Power2', onComplete: () => txt.destroy() });
            },
        });
    }

    // Large cinematic card render — not the same as the board CardObject.
    _makeCinematicCard(cardData, x, y, accent = '#ffffff') {
        const CW = 140, CH = 196;
        const c  = this.add.container(x, y);

        // Drop shadow
        c.add(this.add.rectangle(6, 10, CW, CH, 0x000000, 0.65));

        // Border panel
        c.add(this.add.rectangle(0, 0, CW, CH, 0x0d1020, 0.98)
            .setStrokeStyle(3, Phaser.Display.Color.HexStringToColor(accent).color, 0.9));

        // Full card art filling the frame
        const artKey = CardObject._resolveArtKey(this, cardData);
        if (artKey) {
            c.add(this.add.image(0, 0, artKey).setDisplaySize(CW - 6, CH - 6));
        } else {
            c.add(this.add.rectangle(0, 0, CW - 6, CH - 6, 0x1a1a2e));
            c.add(this.add.text(0, 0, (cardData?.name || '').toUpperCase(), {
                fontSize: '11px', fontFamily: 'Arial Black', color: '#ffffff',
                wordWrap: { width: CW - 20 }, align: 'center',
            }).setOrigin(0.5));
        }

        c.setDepth(61);
        return { container: c, width: CW, height: CH };
    }

    // Loser obliteration: destroy FX + damage number floats on the card, then fade.
    _obliterateCinematicCard(visual, damage, layer) {
        const { container } = visual;
        this._sfx('sfx_destroy');
        this.cameras.main.shake(200, 0.011);

        // Knockback: card flies backward from impact
        const knockDir = container.x > W / 2 ? 1 : -1;
        this.tweens.add({
            targets: container,
            x: container.x + knockDir * 36,
            angle: knockDir * Phaser.Math.Between(10, 18),
            duration: 70, ease: 'Power3.Out',
        });

        // Glitch: rapid position stutter before death
        let gc = 0;
        const ox = container.x, oy = container.y;
        const glitch = this.time.addEvent({ delay: 38, repeat: 5, callback: () => {
            if (gc++ < 5) { container.x = ox + Phaser.Math.Between(-5, 5); container.y = oy + Phaser.Math.Between(-3, 3); }
            else { container.x = ox; container.y = oy; glitch.remove(); }
        }});

        // Debris shards burst
        const SHARD_COLORS = [0xe63946, 0xff8c00, 0xffd700, 0xffffff];
        const shardCount = SettingsManager.particles(8);
        for (let i = 0; i < shardCount; i++) {
            const angle = (i / shardCount) * Math.PI * 2;
            const shard = this.add.rectangle(
                container.x, container.y,
                Phaser.Math.Between(8, 18), Phaser.Math.Between(3, 6),
                SHARD_COLORS[i % SHARD_COLORS.length], 0.9
            ).setDepth(63).setAngle(angle * 57.3);
            layer.add(shard);
            this.tweens.add({
                targets: shard,
                x: container.x + Math.cos(angle) * Phaser.Math.Between(38, 85),
                y: container.y + Math.sin(angle) * Phaser.Math.Between(28, 65),
                alpha: 0, scaleX: 0.1, scaleY: 0.1, angle: angle * 57.3 + 180,
                duration: 380 + Math.random() * 180, ease: 'Power2',
                onComplete: () => shard.destroy(),
            });
        }

        // Red burst ring
        const burst = this.add.circle(container.x, container.y, 8, 0xe63946, 0.9).setDepth(63);
        layer.add(burst);
        this.tweens.add({
            targets: burst, radius: 95, alpha: 0, duration: 440, ease: 'Cubic.Out',
            onUpdate: () => burst.setRadius(burst.radius + 3),
            onComplete: () => burst.destroy(),
        });

        // Damage number
        if (damage > 0) {
            const dmgText = this.add.text(container.x, container.y - 18, `-${damage} MORALE`, {
                fontSize: '22px', fontFamily: 'Arial Black', color: '#ff3b4e',
                stroke: '#000000', strokeThickness: 5,
            }).setOrigin(0.5).setDepth(64).setScale(0.45).setAlpha(0);
            layer.add(dmgText);
            this.tweens.add({
                targets: dmgText, scale: 1.15, alpha: 1, duration: 190, ease: 'Back.Out',
                onComplete: () => {
                    this.tweens.add({ targets: dmgText, y: container.y - 58, alpha: 0, duration: 560, delay: 360, ease: 'Power2', onComplete: () => dmgText.destroy() });
                },
            });
        }

        // Card fades + shrinks out
        this.tweens.add({ targets: container, alpha: 0, scale: 0.78, angle: container.angle + knockDir * 14, delay: 160, duration: 440, ease: 'Cubic.In' });
    }

    /**
     * Lion-clan claw slash played inside the battle cinematic.
     * All FX are parented to defContainer and positioned in local card
     * coordinates (0,0 = card centre) so they stay strictly on the card face.
     *
     * @param {Phaser.GameObjects.Container} defContainer — cinematic defender card
     * @param {number} _cy  — unused (kept for call-site compat)
     * @param {Phaser.GameObjects.Container} layer — cinematic layer (for sparks only)
     */
    _playLionClawCinematic(defContainer, _cy, layer) {
        this._sfx('sfx_lion_claw');

        // Card face dimensions (must match _makeCinematicCard: CW=140, CH=196)
        const CW = 140, CH = 196;

        // Slash geometry — sized to cross the card, not the screen
        const ANGLE   = -40;            // degrees: top-left → bottom-right
        const SWEEP   = 210;            // px — roughly the card diagonal (≈241), slightly short for a sharp feel
        const SPACING = 16;             // px between parallel marks
        const CLAWS   = 3;

        // White flash on the card face
        const flash = this.add.rectangle(0, 0, CW, CH, 0xffffff, 0.75).setDepth(67);
        defContainer.add(flash);
        this.tweens.add({
            targets: flash, alpha: 0, duration: 160, ease: 'Cubic.Out',
            onComplete: () => flash.destroy(),
        });

        this.cameras.main.shake(200, 0.012);

        // Perpendicular-to-slash direction (for spacing the marks across the card)
        const perpRad = Phaser.Math.DegToRad(ANGLE + 90);

        for (let idx = 0; idx < CLAWS; idx++) {
            this.time.delayedCall(idx * 65, () => {
                // Space marks perpendicular to the slash direction
                const perpOff = (idx - 1) * SPACING;
                const ox = Math.cos(perpRad) * perpOff;
                const oy = Math.sin(perpRad) * perpOff;

                // Start at the card's left edge in local space (origin = card centre)
                const startX = -CW / 2 - 4 + ox;
                const startY = oy;

                // Glow streak — parented to card container → stays on the card
                const glow = this.add.rectangle(startX, startY, SWEEP, 14, 0xffd700, 0.5)
                    .setAngle(ANGLE).setOrigin(0, 0.5).setAlpha(0).setDepth(67);
                defContainer.add(glow);

                // Sharp core line
                const line = this.add.rectangle(startX, startY, SWEEP, 2, 0xfffbe6, 1)
                    .setAngle(ANGLE).setOrigin(0, 0.5).setAlpha(0).setDepth(68);
                defContainer.add(line);

                // Sweep: scaleX 0→1 so slash grows left-to-right across the card
                glow.scaleX = 0;
                line.scaleX = 0;
                this.tweens.add({
                    targets: [glow, line], scaleX: 1, alpha: 1,
                    duration: 130, ease: 'Cubic.Out',
                    onComplete: () => {
                        this.tweens.add({
                            targets: [glow, line], alpha: 0,
                            duration: 340, delay: 180, ease: 'Power2',
                            onComplete: () => { glow.destroy(); line.destroy(); },
                        });
                    },
                });

                // A few sparks fly off in scene space from the card face
                const angleRad = Phaser.Math.DegToRad(ANGLE);
                for (let k = 0; k < 5; k++) {
                    const t  = (k + 1) / 6;
                    const lx = startX + Math.cos(angleRad) * SWEEP * t;
                    const ly = startY + Math.sin(angleRad) * SWEEP * t;
                    // Convert local → scene
                    const sx = defContainer.x + lx;
                    const sy = defContainer.y + ly;
                    const spark = this.add.circle(sx, sy, Phaser.Math.Between(2, 3), 0xfff3a0, 1)
                        .setDepth(69);
                    layer.add(spark);
                    this.tweens.add({
                        targets: spark,
                        x: sx + Phaser.Math.Between(-22, 22),
                        y: sy + Phaser.Math.Between(-20, 4),
                        alpha: 0, scale: 0.1,
                        duration: Phaser.Math.Between(260, 420), delay: 50 + k * 18,
                        ease: 'Cubic.Out',
                        onComplete: () => spark.destroy(),
                    });
                }
            });
        }
    }

    /**
     * Viper faction cinematic FX: toxic green streaks across the defender card,
     * dripping venom particles, and a skull flash — surgical and infected.
     */
    _playViperCinematic(defContainer, _cy, layer) {
        this._sfx('sfx_lion_claw');   // reuse until dedicated viper SFX

        const CW = 140, CH = 196;
        const VENOM = 0x39ff14;

        // Sickly green tint washes over the card
        const toxicWash = this.add.rectangle(0, 0, CW, CH, VENOM, 0.22).setDepth(67);
        defContainer.add(toxicWash);
        this.tweens.add({ targets: toxicWash, alpha: 0, duration: 560, delay: 180, ease: 'Sine', onComplete: () => toxicWash.destroy() });

        this.cameras.main.shake(150, 0.008);

        // Three venom streaks across card face (thinner + more jagged than claw)
        const ANGLE   = -38;
        const SWEEP   = 195;
        const perpRad = Phaser.Math.DegToRad(ANGLE + 90);
        const angleRad = Phaser.Math.DegToRad(ANGLE);

        for (let idx = 0; idx < 3; idx++) {
            this.time.delayedCall(idx * 75, () => {
                const perp  = (idx - 1) * 15;
                const ox    = Math.cos(perpRad) * perp;
                const oy    = Math.sin(perpRad) * perp;
                const sx    = -CW / 2 - 4 + ox;
                const sy    = oy;

                const glow = this.add.rectangle(sx, sy, SWEEP, 11, VENOM, 0.55)
                    .setAngle(ANGLE).setOrigin(0, 0.5).setAlpha(0).setDepth(67);
                const line = this.add.rectangle(sx, sy, SWEEP, 2, 0xaaffaa, 0.9)
                    .setAngle(ANGLE).setOrigin(0, 0.5).setAlpha(0).setDepth(68);
                defContainer.add(glow);
                defContainer.add(line);

                glow.scaleX = 0; line.scaleX = 0;
                this.tweens.add({
                    targets: [glow, line], scaleX: 1, alpha: 1, duration: 140, ease: 'Cubic.Out',
                    onComplete: () => {
                        this.tweens.add({ targets: [glow, line], alpha: 0, duration: 380, delay: 140, ease: 'Power2', onComplete: () => { glow.destroy(); line.destroy(); } });
                    },
                });

                // Venom drips fall downward from each streak
                for (let k = 0; k < 4; k++) {
                    const t  = (k + 1) / 5;
                    const lx = sx + Math.cos(angleRad) * SWEEP * t;
                    const ly = sy + Math.sin(angleRad) * SWEEP * t;
                    const drip = this.add.circle(defContainer.x + lx, defContainer.y + ly, Phaser.Math.Between(2, 4), VENOM, 0.9).setDepth(69);
                    layer.add(drip);
                    this.tweens.add({
                        targets: drip,
                        y: drip.y + Phaser.Math.Between(18, 38),
                        x: drip.x + Phaser.Math.Between(-6, 6),
                        alpha: 0, scale: 0.2,
                        duration: Phaser.Math.Between(300, 500), delay: 90 + k * 18,
                        ease: 'Cubic.In',
                        onComplete: () => drip.destroy(),
                    });
                }
            });
        }

        // Skull icon flashes at card centre
        const skull = this.add.text(0, 0, '☠', {
            fontSize: '44px', color: '#39ff14', stroke: '#002200', strokeThickness: 3,
        }).setOrigin(0.5).setAlpha(0).setDepth(69).setScale(0.4);
        defContainer.add(skull);
        this.tweens.add({
            targets: skull, alpha: 0.95, scale: 1.1, duration: 110, ease: 'Back.Out',
            onComplete: () => {
                this.tweens.add({ targets: skull, alpha: 0, scale: 1.5, duration: 260, delay: 110, ease: 'Power2', onComplete: () => skull.destroy() });
            },
        });
    }

    /**
     * Legacy small-slot claw animation (kept for compatibility with any
     * older call site). The main cinematic uses _playLionClawCinematic.
     */
    _playLionClawAnimation(defSlot, onComplete) {
        if (this.textures.exists('fx_lion_claw')) {
            const spr = this.add.sprite(defSlot.x, defSlot.y, 'fx_lion_claw')
                .setDepth(35).setScale(0.9);
            spr.play('anim_lion_claw');
            spr.on('animationcomplete', () => { spr.destroy(); onComplete(); });
            return;
        }

        // Fallback: three diagonal gold claw-mark lines
        const g = this.add.graphics().setDepth(35);
        g.lineStyle(3, 0xffd700, 1);
        [
            [defSlot.x - 16, defSlot.y - 20, defSlot.x + 4,  defSlot.y + 20],
            [defSlot.x - 6,  defSlot.y - 20, defSlot.x + 14, defSlot.y + 20],
            [defSlot.x + 4,  defSlot.y - 20, defSlot.x + 24, defSlot.y + 20],
        ].forEach(([x1, y1, x2, y2]) => {
            g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.strokePath();
        });

        this.tweens.add({
            targets: g, alpha: 0, duration: 380, delay: 120, ease: 'Power2',
            onComplete: () => { g.destroy(); onComplete(); },
        });
    }

    /**
     * Direct attack animation: a wide slash sweeps across the opponent's half.
     */
    _playDirectAttackAnimation(attackerSlot, result) {
        this._enterResolving();
        this._sfx('sfx_attack');

        const defOwner    = attackerSlot.slotOwner === 'player' ? 'opponent' : 'player';
        const targetY     = defOwner === 'opponent' ? ROW_Y.opp_front : ROW_Y.pl_front;
        const attCard2 = attackerSlot.cardObject?.cardData;
        if (result.moraleDealt > 0) {
            const profileY = defOwner === 'opponent' ? ROW_Y.opp_front - 60 : ROW_Y.pl_front + 60;
            const accent = this._factionAccent(attCard2);
            const isCrit = result.moraleDealt >= 1500;
            this._showDamageNumber(W / 2, profileY, result.moraleDealt, { crit: isCrit, accent, label: 'DIRECT HIT' });
            this._logCombat(`DIRECT HIT! ${result.moraleDealt} morale dmg`, '#ff4444');
        }

        const finish      = () => {
            this._oppProfileBox?.update(this.state.opponent.morale);
            this._plProfileBox?.update(this.state.player.morale);
            this._checkWinCondition();
            this._exitResolving();
        };

        if (!SettingsManager.animationsEnabled) {
            finish();
            return;
        }

        if (this.anims.exists('anim_direct')) {
            const fx = this.add.sprite(W / 2, targetY, 'fx_direct').setDepth(30).setScale(1.2);
            fx.play('anim_direct');
            fx.on('animationcomplete', () => { fx.destroy(); finish(); });
            return;
        }

        // Procedural fallback: lunge attacker, slash on target row, screen flash
        this._playProceduralDirect(attackerSlot, targetY, finish);
    }

    // ── Procedural FX (used when sprite-sheet assets are missing) ─────────────

    _playProceduralDirect(attackerSlot, targetY, onComplete) {
        const card  = attackerSlot.cardObject?.container;
        const homeX = attackerSlot.x, homeY = attackerSlot.y;

        const fireImpact = () => {
            // Bright slash across the target row
            const slash = this.add.rectangle(W / 2, targetY, 8, 18, 0xffe066, 1).setDepth(31);
            this.tweens.add({
                targets: slash, scaleX: W / 6, alpha: 0,
                duration: 340, ease: 'Cubic.Out',
                onComplete: () => slash.destroy(),
            });

            // Red half-screen flash on the target side
            const halfH  = H / 2;
            const flashY = targetY < H / 2 ? halfH / 2 : H - halfH / 2;
            const flash  = this.add.rectangle(W / 2, flashY, W, halfH, 0xe63946, 0.35).setDepth(29);
            this.tweens.add({
                targets: flash, alpha: 0, duration: 280, ease: 'Cubic.Out',
                onComplete: () => flash.destroy(),
            });

            this.cameras.main.shake(180, 0.008);
        };

        if (card) {
            // Lunge ~25% toward the target row, then snap back home (yoyo)
            const lungeY = homeY + (targetY - homeY) * 0.25;
            const orig   = card.depth;
            card.setDepth(20);
            this.tweens.add({
                targets: card, y: lungeY,
                duration: 160, ease: 'Cubic.In',
                yoyo: true, hold: 40,
                onYoyo: () => fireImpact(),
                onComplete: () => {
                    // Force-restore exact home position in case anything nudged it
                    card.setPosition(homeX, homeY);
                    card.setDepth(orig);
                    onComplete?.();
                },
            });
        } else {
            fireImpact();
            this.time.delayedCall(360, () => onComplete?.());
        }
    }

    _playProceduralDestroy(x, y, onComplete) {
        // Central white-hot core
        const core = this.add.circle(x, y, 6, 0xffffff, 1).setDepth(31);
        this.tweens.add({
            targets: core, radius: 28, alpha: 0,
            duration: 260, ease: 'Cubic.Out',
            onUpdate: () => core.setRadius(core.radius),
            onComplete: () => core.destroy(),
        });

        // Red burst ring
        const ring = this.add.circle(x, y, 8, 0xe63946, 0.85).setDepth(30);
        this.tweens.add({
            targets: ring, radius: 46, alpha: 0,
            duration: 420, ease: 'Cubic.Out',
            onUpdate: () => ring.setRadius(ring.radius),
            onComplete: () => ring.destroy(),
        });

        // Shrapnel particles (8 streaks fanning outward)
        const shrapnelCount = SettingsManager.particles(8);
        for (let i = 0; i < shrapnelCount; i++) {
            const ang  = (i / shrapnelCount) * Math.PI * 2 + Math.random() * 0.3;
            const dist = 28 + Math.random() * 14;
            const p    = this.add.rectangle(x, y, 5, 2, 0xffaa33, 1)
                .setDepth(31).setAngle(Phaser.Math.RadToDeg(ang));
            this.tweens.add({
                targets: p,
                x: x + Math.cos(ang) * dist,
                y: y + Math.sin(ang) * dist,
                alpha: 0, duration: 380 + Math.random() * 120, ease: 'Cubic.Out',
                onComplete: () => p.destroy(),
            });
        }

        this.cameras.main.shake(120, 0.005);
        this.time.delayedCall(380, () => onComplete?.());
    }

    /**
     * Resolves all visuals after combat, covering outcomes:
     *   - Attacker wins:   defender Downed or Destroyed
     *   - Defender wins:   attacker Downed or Destroyed
     *   - Tie:             both Downed or Destroyed
     */
    _resolveVisualAftermath(attackerSlot, defSlot, result, attackerOwner, onComplete) {
        const defOwner  = attackerOwner === 'player' ? 'opponent' : 'player';
        const anim      = SettingsManager.animationsEnabled;
        const attCard   = attackerSlot.cardObject?.cardData
            ?? this.state[attackerOwner]?.field[attackerSlot.slotIndex];

        const downVisual = (slot, owner) => {
            const cd = slot.cardObject?.cardData;
            slot.cardObject?.setDowned?.();
            slot.setSize(SLOT_H + 8, SLOT_H + 8);
            this._showFloatingText(slot.x, slot.y - 30, 'DOWNED!', '#ff4444');
            this._pulseSlot(slot, 0xff4444, 400);
            this._sfx('sfx_destroy');
            if (cd?.name) this._logCombat(`${cd.name} DOWNED`, '#ff6666');
        };

        // Defender outcome — check King's Test shield before applying
        const defCard = this.state[defOwner]?.field[defSlot.slotIndex]
            ?? defSlot.cardObject?.cardData;
        if ((result.defenderDestroyed || result.defenderDowned) && defCard?._kingsTestShield) {
            delete defCard._kingsTestShield;
            defCard._kingsTestSurvivor = true;
            result.defenderDestroyed = false;
            result.defenderDowned    = false;
            if (!this.state[defOwner].field[defSlot.slotIndex]) {
                this.state[defOwner].field[defSlot.slotIndex] = defCard;
            }
            this._showFloatingText(defSlot.x, defSlot.y - 30, "KING'S TEST!", '#f4d35e');
        }

        // Track pending KO animations to know when all finish
        let pending = 0;
        const done = () => {
            pending--;
            if (pending <= 0) {
                this._plProfileBox?.update(this.state.player.morale);
                this._oppProfileBox?.update(this.state.opponent.morale);
                if (result.promoted) {
                    const owner = result.promotingOwner;
                    let promotedData = this.state[owner]?.hideout?.find(c => c.id === result.promotedCardId);
                    if (!promotedData) promotedData = CARD_CATALOG[result.promotedCardId];
                    if (promotedData) {
                        this.time.delayedCall(anim ? 650 : 0, () => {
                            this._doPromotion(owner, result.promotingSlot, promotedData);
                        });
                    }
                }
                this._applyPostBattleFlags(result, attackerSlot, attackerOwner, defOwner, anim);
                this._checkWinCondition();
                onComplete?.();
            }
        };

        // Damage numbers + combat log
        if (result.moraleDealt > 0) {
            const accent = this._factionAccent(attCard);
            const isCrit = result.moraleDealt >= 1200 || result.defenderDestroyed;
            this._showDamageNumber(defSlot.x, defSlot.y - 20, result.moraleDealt,
                { crit: isCrit, accent });
            this._logCombat(`${attCard?.name ?? '?'} deals ${result.moraleDealt} morale dmg`, '#ff6666');
        }
        if (result.defenderDEFBlock > 0) {
            this._showDamageNumber(defSlot.x + 20, defSlot.y, result.defenderDEFBlock,
                { type: 'def' });
        }

        // Viper venom: a successful Viper attack stamps 1 poison stack on the
        // surviving target. Stacks deal 200 morale dmg each at the start of the
        // poisoned owner's next turn.
        const isViperAttacker = ['viper_clan', 'viper', 'vipers']
            .includes(attCard?.clan || attCard?.clan_tag);
        if (isViperAttacker && !result.defenderDestroyed && !result.defenderDowned && defCard) {
            defCard._poisonStacks = Math.min(3, (defCard._poisonStacks || 0) + 1);
            this._showStatMod(defSlot.x, defSlot.y - 6,
                defCard._poisonStacks, { label: 'VENOM', accent: '#66ff99' });
        }

        if (result.defenderDestroyed) {
            pending++;
            const defName = defSlot.cardObject?.cardData?.name ?? '?';
            this._logCombat(`${defName} DESTROYED`, '#e63946');
            this._playKOAnimation(defSlot, defOwner, done);
        } else if (result.defenderDowned) {
            downVisual(defSlot, defOwner);
            this.effectBus.trigger('on_downed', { card: defSlot.cardObject?.cardData, owner: defOwner });
            this._recalcDownedBonuses();
        }

        if (result.attackerDestroyed) {
            pending++;
            const attName = attackerSlot.cardObject?.cardData?.name ?? '?';
            this._logCombat(`${attName} DESTROYED`, '#e63946');
            this._playKOAnimation(attackerSlot, attackerOwner, done);
        } else if (result.attackerDowned) {
            downVisual(attackerSlot, attackerOwner);
            this.effectBus.trigger('on_downed', { card: attackerSlot.cardObject?.cardData, owner: attackerOwner });
            this._recalcDownedBonuses();
        }

        // Downed defender blocked the attack — show feedback
        if (!result.defenderDestroyed && !result.defenderDowned && !result.attackerDestroyed && !result.attackerDowned
                && defSlot.cardObject?.cardData?.downed) {
            this._showFloatingText(defSlot.x, defSlot.y - 30, 'BLOCKED!', '#4cc9f0');
            this._logCombat(`Attack BLOCKED by downed unit`, '#4cc9f0');
        }

        // No KO animations — resolve immediately
        if (pending === 0) {
            this._plProfileBox?.update(this.state.player.morale);
            this._oppProfileBox?.update(this.state.opponent.morale);
            if (result.promoted) {
                const owner = result.promotingOwner;
                let promotedData = this.state[owner]?.hideout?.find(c => c.id === result.promotedCardId);
                if (!promotedData) promotedData = CARD_CATALOG[result.promotedCardId];
                if (promotedData) {
                    this.time.delayedCall(anim ? 650 : 0, () => {
                        this._doPromotion(owner, result.promotingSlot, promotedData);
                    });
                }
            }
            this._applyPostBattleFlags(result, attackerSlot, attackerOwner, defOwner, anim);
            this._checkWinCondition();
            onComplete?.();
        }
    }

    // ── KO Animation ─────────────────────────────────────────────────────────

    _playKOAnimation(slot, owner, onComplete) {
        this._sfx('sfx_ko');

        if (!SettingsManager.animationsEnabled) {
            this._sendToGraveyard(owner, slot);
            onComplete?.();
            return;
        }

        // White flash over the card
        const flash = this.add.rectangle(slot.x, slot.y, SLOT_W + 4, SLOT_H + 4, 0xffffff)
            .setDepth(32).setAlpha(0);
        this.tweens.add({ targets: flash, alpha: 0.9, duration: 60, yoyo: true,
            onComplete: () => flash.destroy() });

        // Block input during animation
        const blocker = this.add.rectangle(slot.x, slot.y, SLOT_W + 8, SLOT_H + 8, 0x000000, 0)
            .setDepth(31).setInteractive();

        // Slam "DROPPED!" text
        const cardName = slot.cardObject?.cardData?.name ?? '';
        const mainTxt = this.add.text(slot.x, slot.y - 20, KO_TEXT.main, {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#ff3b4e',
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5).setDepth(33).setScale(2);
        this.tweens.add({ targets: mainTxt, scaleX: 1, scaleY: 1, duration: 180, ease: 'Back.Out' });

        const subTxt = this.add.text(slot.x, slot.y + 6, `${cardName} ${KO_TEXT.sub}`, {
            fontSize: '5px', fontFamily: 'Arial', color: '#ffffff',
            stroke: '#000000', strokeThickness: 2,
        }).setOrigin(0.5).setDepth(33).setAlpha(0);
        this.tweens.add({ targets: subTxt, alpha: 1, duration: 200, delay: 100 });

        // Card shake
        if (slot.cardObject) {
            this.tweens.add({
                targets: slot.cardObject,
                x: slot.x + 4, duration: 40, yoyo: true, repeat: 4,
                onComplete: () => { if (slot.cardObject) slot.cardObject.x = slot.x; },
            });
        }

        // After short hold — fade card out then clean up
        this.time.delayedCall(600, () => {
            const targets = [mainTxt, subTxt];
            if (slot.cardObject) targets.push(slot.cardObject);
            this.tweens.add({
                targets, alpha: 0, duration: 280, ease: 'Power2',
                onComplete: () => {
                    mainTxt.destroy();
                    subTxt.destroy();
                    blocker.destroy();
                    this._sendToGraveyard(owner, slot);
                    onComplete?.();
                },
            });
        });
    }

    // ── Promotion (evolve a brawler after a kill) ─────────────────────────────

    _doPromotion(owner, slotIndex, promotedData) {
        const rows = owner === 'player'
            ? this._slotObjects.pl_front
            : this._slotObjects.opp_front;
        const slot = rows.find(s => s.slotIndex === slotIndex);
        if (!slot) return;

        // Hard lock: each slot can only promote once per turn
        const promotedSet = this.state[owner].promotedSlotsThisTurn ?? (this.state[owner].promotedSlotsThisTurn = new Set());
        if (promotedSet.has(slotIndex)) {
            this._showFloatingText(slot.x, slot.y - 30, 'Already promoted this turn!', '#aaaacc');
            return;
        }
        promotedSet.add(slotIndex);

        // Glow flash + toast play immediately
        const flash = this.add.rectangle(slot.x, slot.y, SLOT_W + 6, SLOT_H + 6, 0xf4d35e)
            .setDepth(5).setAlpha(0.9);
        this.tweens.add({ targets: flash, alpha: 0, duration: 600, ease: 'Power2',
            onComplete: () => flash.destroy() });
        this._showFloatingText(slot.x, slot.y - 40, '★ PROMOTED!', '#f4d35e');
        this._pulseSlot(slot, 0xf4d35e, 700);
        this._logCombat(`★ PROMOTE: ${promotedData?.name ?? '?'}`, '#ffd86b');
        this._sfx('sfx_card_play');

        if (owner === 'player') {
            // Short delay so the player can see the flash before the modal appears
            this.time.delayedCall(300, () => {
                this._showPositionModal(promotedData, (position) => {
                    this._applyPromotion(owner, slotIndex, slot, promotedData, position);
                    this._onPromotionPositionChosen(slotIndex, position);  // hook for multiplayer
                });
            });
        } else {
            // AI / remote opponent: default to ATK, no modal
            this._applyPromotion(owner, slotIndex, slot, promotedData, 'atk');
        }
    }

    _applyPromotion(owner, slotIndex, slot, promotedData, position) {
        // Capture any equipped hardware on the old form so it carries over
        const old = this.state[owner].field[slotIndex];
        const carriedHw = old?._hardware?.slice() || [];
        const carriedAtkMod = carriedHw.reduce((a, h) => a + (h.atkMod || 0), 0);
        const carriedDefMod = carriedHw.reduce((a, h) => a + (h.defMod || 0), 0);

        // Send lv1 to The Gutter (without hardware — hardware survives)
        if (old) {
            const dropped = { ...old };
            delete dropped._hardware;
            this.state[owner].gutter.push(dropped);
        }

        // Build the promoted form with hardware mods reapplied
        const baseAtk = promotedData.attack;
        const baseDef = promotedData.defense;
        this.state[owner].field[slotIndex] = {
            ...promotedData,
            faceDown:    false,
            hasAttacked: true,    // promotion sickness — sits out the rest of this turn
            position,             // 'atk' | 'def'
            _baseAtk:    baseAtk,
            _baseDef:    baseDef,
            attack:      baseAtk + carriedAtkMod,
            defense:     baseDef + carriedDefMod,
            _hardware:   carriedHw,
        };

        // Swap visual card object
        slot.cardObject?.destroy();
        this._clearSlotGlow(slot);
        const mode    = owner === 'player' ? 'field_pl' : 'field_opp';
        const newCard = new CardObject(this, slot.x, slot.y, promotedData, mode);
        slot.cardObject = newCard;
        this.add.existing(newCard.container);
        // Render above the slot panel (depth 1) so the dark base panel doesn't
        // tint the card art — without this the promoted card sits at default
        // depth 0 and looks dimmed until something else nudges its depth.
        newCard.container.setDepth(2);
        newCard.setFieldMode(owner);
        if (owner === 'player') {
            newCard.enableZoom(false);
            this._attachFieldTap(newCard, slot);
        } else {
            newCard.enableZoom(true);
        }

        // DEF position: rotate card 90° — set-in-DEF is also face-down (YuGiOh style)
        if (position === 'def') {
            newCard.container.setAngle(90);
            // Promoted-into-DEF is visible face-up sideways (player chose this form);
            // a newly set-in-DEF (from hand) uses setFaceDownDef() via the deploy flow.
        }

        this._recalcClanBonuses();

        // Fire on_play for the promoted card so promotion-triggered effects run
        const promotedCard = this.state[owner].field[slotIndex];
        this.effectBus.trigger('on_play',    { card: promotedCard, owner, isPromotion: true });
        // Fire on_promote so Pride Mentor and other listeners know a promotion happened
        this.effectBus.trigger('on_promote', { card: promotedCard, owner });
    }

    /**
     * Shows the ATK/DEF position choice modal after a promotion.
     * Blocks all interaction until the player picks.
     */
    _showPositionModal(promotedData, callback) {
        const els = [];
        const reg = (obj) => { els.push(obj); return obj; };
        const cleanup = () => els.forEach(e => e.destroy());

        reg(this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.72).setDepth(60));
        reg(this.add.rectangle(W / 2, H / 2, 270, 135, 0x0d0d2a)
            .setStrokeStyle(2, 0xf4d35e).setDepth(61));

        reg(this.add.text(W / 2, H / 2 - 46, '★  PROMOTION', {
            fontSize: '15px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(62));

        reg(this.add.text(W / 2, H / 2 - 20, `${promotedData.name} — choose a position`, {
            fontSize: '8px', color: '#aaaacc',
        }).setOrigin(0.5).setDepth(62));

        // ATK button
        const atkBtn = reg(this.add.rectangle(W / 2 - 62, H / 2 + 24, 106, 36, 0xe63946)
            .setInteractive({ useHandCursor: true }).setDepth(62));
        reg(this.add.text(W / 2 - 62, H / 2 + 24, 'ATK POSITION', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(63));

        // DEF button
        const defBtn = reg(this.add.rectangle(W / 2 + 62, H / 2 + 24, 106, 36, 0x4cc9f0)
            .setInteractive({ useHandCursor: true }).setDepth(62));
        reg(this.add.text(W / 2 + 62, H / 2 + 24, 'DEF POSITION', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#000000',
        }).setOrigin(0.5).setDepth(63));

        atkBtn.on('pointerup', () => { cleanup(); callback('atk'); });
        defBtn.on('pointerup', () => { cleanup(); callback('def'); });
    }

    /** Override in MultiplayerDuelScene to relay the position choice to the server. */
    _onPromotionPositionChosen(_slotIndex, _position) {}

    // ── Mulligan (pre-turn-1 hand redraw) ────────────────────────────────────

    /**
     * Player may toss any subset of their opening 6 hand; they redraw to 5 new cards
     * (one fewer than original, per spec). AI never mulligans in single-player.
     */
    _showMulliganModal(onDone) {
        if (this._isMultiplayer) { onDone?.(); return; }  // server drives mulligan in MP

        const els = [];
        const reg = (o) => { els.push(o); return o; };
        const tossed = new Set();

        reg(this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.78).setDepth(70));
        reg(this.add.rectangle(W / 2, H / 2, 320, 200, 0x0d0d2a)
            .setStrokeStyle(2, 0xf4d35e).setDepth(71));
        reg(this.add.text(W / 2, H / 2 - 82, 'MULLIGAN', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(72));
        reg(this.add.text(W / 2, H / 2 - 62, 'Tap cards to toss — redraw up to 4', {
            fontSize: '8px', color: '#aaaacc',
        }).setOrigin(0.5).setDepth(72));

        const cw = 40, ch = 56, gap = 6;
        const totalW = 6 * cw + 5 * gap;
        const startX = W / 2 - totalW / 2 + cw / 2;

        const miniCards = [];
        this.state.player.hand.forEach((card, i) => {
            const x = startX + i * (cw + gap);
            const y = H / 2 - 18;

            const bg = reg(this.add.rectangle(x, y, cw, ch, 0x1a1a2e)
                .setStrokeStyle(1, 0x4cc9f0).setDepth(72).setInteractive({ useHandCursor: true }));

            // Card art (uses art_url if loaded, otherwise falls back to name label)
            const artKey = card.art_url && this.textures.exists(card.art_url) ? card.art_url : null;
            let artEl;
            if (artKey) {
                artEl = reg(this.add.image(x, y, artKey).setDisplaySize(cw, ch).setDepth(73));
            } else {
                artEl = reg(this.add.text(x, y, card.name || '?', {
                    fontSize: '6px', fontFamily: 'Arial Black', color: '#ffffff',
                    wordWrap: { width: cw - 4 }, align: 'center',
                }).setOrigin(0.5).setDepth(73));
            }

            // Toss-overlay tint (semi-transparent red rectangle)
            const tossOverlay = reg(this.add.rectangle(x, y, cw, ch, 0xe63946, 0)
                .setDepth(74).setInteractive({ useHandCursor: true }));

            const setTossed = (on) => {
                bg.setStrokeStyle(on ? 2 : 1, on ? 0xe63946 : 0x4cc9f0);
                tossOverlay.setAlpha(on ? 0.45 : 0);
                if (!artKey) artEl.setColor(on ? '#e63946' : '#ffffff');
            };

            tossOverlay.on('pointerup', () => {
                if (tossed.has(i)) { tossed.delete(i); setTossed(false); }
                else               { tossed.add(i);    setTossed(true);  }
            });
            bg.on('pointerup', () => {
                if (tossed.has(i)) { tossed.delete(i); setTossed(false); }
                else               { tossed.add(i);    setTossed(true);  }
            });

            miniCards.push({ bg, artEl, tossOverlay });
        });

        // Keep-all button
        const keepBtn = reg(this.add.rectangle(W / 2 - 72, H / 2 + 60, 120, 28, 0x333355)
            .setStrokeStyle(1, 0xaaaacc).setDepth(72).setInteractive({ useHandCursor: true }));
        reg(this.add.text(W / 2 - 72, H / 2 + 60, 'KEEP HAND', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(73));

        // Confirm-toss button
        const tossBtn = reg(this.add.rectangle(W / 2 + 72, H / 2 + 60, 120, 28, 0xe63946)
            .setStrokeStyle(1, 0xffffff).setDepth(72).setInteractive({ useHandCursor: true }));
        reg(this.add.text(W / 2 + 72, H / 2 + 60, 'REDRAW', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(73));

        const cleanup = () => els.forEach(e => e.destroy());

        keepBtn.on('pointerup', () => { cleanup(); onDone?.(); });

        tossBtn.on('pointerup', () => {
            if (tossed.size === 0) { cleanup(); onDone?.(); return; }

            // Put tossed cards back onto the bottom of the deck, clear visuals
            const hand = this.state.player.hand;
            const keepers = [];
            hand.forEach((c, i) => {
                if (tossed.has(i)) this.state.player.deck.push(c);
                else keepers.push(c);
            });
            this.state.player.hand = keepers;

            // Clear the current hand visuals and rebuild
            this._handCards.forEach(c => c.destroy());
            this._handCards = [];
            keepers.forEach(c => this._addCardToHandDisplay(c));

            // Shuffle deck, then redraw to 4 total (one fewer than the original 5)
            this.state.player.deck = Phaser.Utils.Array.Shuffle(this.state.player.deck);
            const target = 4;
            while (this.state.player.hand.length < target && this.state.player.deck.length) {
                this._drawCard('player');
            }

            cleanup();
            onDone?.();
        });
    }

    // ── Clan Bonus: continuous ATK buff for tagged card groups ────────────────

    _recalcClanBonuses() {
        // Single source of truth for card.attack on the field.
        // Computes from _baseAtk + ALL active buffs/debuffs/passives.
        for (const owner of ['player', 'opponent']) {
            const field = this.state[owner].field;
            const defOwner = owner === 'player' ? 'opponent' : 'player';
            const myLions = field.filter(c => c && c.clanTag === 'lion' && !c.faceDown && !c.downed).length;
            const lionClanBonus = myLions >= 2 ? 300 : 0;
            const oppHasDowned = this.state[defOwner].field.some(c => c && c.downed);

            field.forEach((card, idx) => {
                if (!card) return;
                card._baseAtk = card._baseAtk ?? card.attack;

                let bonus = 0;

                // ── Clan/passive bonuses (Lions only) ──────────────────────
                if (card.clanTag === 'lion' && !card.downed && !card.faceDown) {
                    bonus += lionClanBonus;

                    // Pride Runner: +400 ATK when adjacent to another Lion
                    if (card.effectKey === 'pride_runner_adjacency') {
                        const left  = field[idx - 1];
                        const right = field[idx + 1];
                        const adj   = [left, right].some(c => c && c.clanTag === 'lion' && !c.downed && !c.faceDown);
                        if (adj) bonus += 400;
                    }

                    // Lion Grunt: +300 ATK when controlling another Lion
                    if (card.effectKey === 'lion_grunt_synergy') {
                        const others = field.filter((c, i) => i !== idx && c?.clanTag === 'lion' && !c.downed && !c.faceDown).length;
                        if (others > 0) bonus += 300;
                    }

                    // Eric Lv.3: +100 ATK per other LIONS card on the field
                    if (card.effectKey === 'eric_lv3_draw') {
                        const otherLions = field.filter((c, i) => i !== idx && c?.clanTag === 'lion' && !c.downed && !c.faceDown).length;
                        bonus += otherLions * 100;
                    }

                    // Kingpin: +400 ATK while opponent has a Downed character
                    if (card.effectKey === 'kingpin' && oppHasDowned) bonus += 400;

                    // Sovereign: +600 ATK while opponent has a Downed character
                    if (card.effectKey === 'sovereign' && oppHasDowned) bonus += 600;
                }

                // ── Per-card additive buffs (apply regardless of clan) ─────
                bonus += (card._ltBuff       || 0);   // Pride Lieutenant
                bonus += (card._mayaBuff     || 0);   // Maya Lv.3
                bonus += (card._hwAtkMod     || 0);   // Hardware ATK mod
                bonus -= (card._brutusDebuff || 0);   // Brutus
                bonus -= (card._ambushDebuff || 0);   // Lion's Ambush (one-shot)

                const target = Math.max(0, card._baseAtk + bonus);
                if (card.attack !== target) card.attack = target;
            });
        }

        this._refreshAllStatBadges();
    }

    // ── Stat HUD overlays (under each face-up character on the field) ────────
    //
    // The card images are full bakes (frame + art + baked stats). For the
    // *current* effective ATK/DEF — which can drift via Hardware, clan
    // bonuses, or future buffs/debuffs — we render a small banner under the
    // slot that recolours: yellow = base, blue = buffed, red = debuffed.

    _refreshAllStatBadges() {
        if (!this._statBadges) this._statBadges = new Map();
        if (!this._slotObjects) return;

        const visit = (owner) => {
            const rows = owner === 'player'
                ? [this._slotObjects.pl_front, this._slotObjects.pl_back]
                : [this._slotObjects.opp_front, this._slotObjects.opp_back];
            for (const row of rows) {
                for (const slot of row) {
                    const card = this.state[owner].field[slot.slotIndex];
                    const key  = `${owner}_${slot.slotIndex}`;
                    if (this._shouldShowStatBadge(card)) {
                        this._setStatBadge(key, slot, card);
                    } else {
                        this._removeStatBadge(key);
                    }
                }
            }
        };
        visit('player');
        visit('opponent');
    }

    _shouldShowStatBadge(card) {
        if (!card)        return false;
        if (card.faceDown) return false;
        return card.cardType === 'gang_member' || card.cardType === 'leader';
    }

    _setStatBadge(key, slot, card) {
        const STAT_FONT = {
            fontSize:       '11px',
            fontFamily:     'Impact, "Oswald", "Arial Narrow", sans-serif',
            fontStyle:      'bold',
            stroke:         '#000000',
            strokeThickness: 3,
        };

        let badge = this._statBadges.get(key);
        if (!badge) {
            const c = this.add.container(slot.x, slot.y + SLOT_H / 2 - 10).setDepth(15);

            // Slim dark plate with a thin gold underline — feels like a card stat bar
            const bg = this.add.rectangle(0, 0, SLOT_W + 8, 16, 0x080812, 0.92)
                .setStrokeStyle(1, 0xf4d35e, 0.85);
            const underline = this.add.rectangle(0, 7, SLOT_W + 4, 1, 0xf4d35e, 0.55);

            const atk   = this.add.text(-2, 0, '0',   STAT_FONT).setOrigin(1, 0.5);
            const slash = this.add.text( 0, 0, '/',   { ...STAT_FONT, color: '#aaaacc', strokeThickness: 2 })
                .setOrigin(0.5, 0.5);
            const def   = this.add.text( 2, 0, '0',   STAT_FONT).setOrigin(0, 0.5);

            c.add([bg, underline, atk, slash, def]);
            badge = { container: c, bg, atk, slash, def };
            this._statBadges.set(key, badge);
        }
        badge.container.setPosition(slot.x, slot.y + SLOT_H / 2 - 10);

        const baseAtk = card._baseAttack  ?? card.baseAttack  ?? card._baseAtk ?? card.attack;
        const baseDef = card._baseDefense ?? card.baseDefense ?? card._baseDef ?? card.defense;
        const colorFor = (cur, base) =>
              cur > base ? '#4cc9f0'   // buffed
            : cur < base ? '#e63946'   // debuffed
            :              '#ffd86b';  // base

        badge.atk.setText(`${card.attack}`).setColor(colorFor(card.attack, baseAtk));
        badge.def.setText(`${card.defense}`).setColor(colorFor(card.defense, baseDef));

        // Re-center the slash between the two values so layout stays tight as
        // numbers grow/shrink (e.g. 950 vs 1900).
        const aw = badge.atk.width, dw = badge.def.width;
        const slashGap = 4;
        badge.atk.setX(-slashGap / 2);
        badge.slash.setX(0);
        badge.def.setX(slashGap / 2);
        // Shift the pair so the whole "atk / def" group sits visually centered
        const groupW = aw + 6 + dw;
        const offset = (dw - aw) / 2;   // counter the asymmetric origins
        badge.atk.setX(-3 + offset);
        badge.def.setX( 3 + offset);
        badge.slash.setX(offset);

        // Resize the plate to wrap snugly around the numbers
        const plateW = Math.max(SLOT_W + 6, groupW + 12);
        badge.bg.setSize(plateW, 16);
    }

    _removeStatBadge(key) {
        const badge = this._statBadges?.get(key);
        if (!badge) return;
        badge.container.destroy();
        this._statBadges.delete(key);
    }

    // ── Downed State: recovery ────────────────────────────────────────────────

    /** Recover all Downed units for `owner` at the start of their turn. */
    _recoverDownedUnits(owner) {
        const front = owner === 'player' ? this._slotObjects?.pl_front : this._slotObjects?.opp_front;
        this.state[owner].field.forEach((card, idx) => {
            if (!card?.downed) return;
            this._recoverDownedCard(owner, idx);
        });
    }

    /** Stand one specific Downed card (by field index). */
    _recoverDownedCard(owner, slotIdx) {
        const card = this.state[owner].field[slotIdx];
        if (!card?.downed) return;
        card.downed = false;

        const rows = owner === 'player'
            ? this._slotObjects?.pl_front
            : this._slotObjects?.opp_front;
        const slot = rows?.find(s => s.slotIndex === slotIdx);
        if (slot?.cardObject) {
            slot.cardObject.unsetDowned?.();
            const angle = card.position === 'def' ? 90 : 0;
            slot.cardObject.container.setAngle(angle);
        }
        // Restore normal slot hit area
        slot?.setSize(SLOT_W, SLOT_H);

        this._recalcClanBonuses();
    }

    // ── Leader / Kingpin System ───────────────────────────────────────────────

    /** Check if the active player's leader has met its awaken condition. */
    _checkLeaderAwaken(owner) {
        const s = this.state[owner];
        if (!s.leader || s.leaderAwakened) return;

        const cond = s.leader.awakenCondition;
        if (!cond) return;

        const lions = s.field.filter(c => c && c.clanTag === 'lion' && !c.downed && !c.faceDown).length;
        const authorityMet = s.authorityMax >= (cond.authorityThreshold ?? Infinity);
        const lionsMet     = lions >= (cond.lions ?? Infinity);

        if (!(lionsMet || authorityMet)) return;

        // All front-row slots are valid — leader can displace an existing card
        const frontSlots = owner === 'player' ? this._slotObjects.pl_front : this._slotObjects.opp_front;
        if (!frontSlots.length) return;

        if (owner === 'player') {
            this._promptLeaderPlacement(s.leader);
        } else {
            // AI: prefer empty slot, otherwise take first slot
            const aiSlot = frontSlots.find(sl => !sl.cardObject) ?? frontSlots[0];
            this._placeLeaderOnField(owner, aiSlot);
        }
    }

    /** Highlight ALL front-row slots — leader can displace an existing card. */
    _promptLeaderPlacement(leaderData) {
        this._showDecidingBanner('player');
        this._sfx('sfx_card_play');

        const frontSlots = this._slotObjects.pl_front;

        this._beginTargeting(
            frontSlots,
            0xf4d35e,
            `👑 ${leaderData.name} AWAKENS! Choose a slot (existing card goes to gutter)`,
            (slot) => this._placeLeaderOnField('player', slot),
            null,
            '✕ CANCEL',
        );
    }

    /** Actually place the leader card object on a front-row slot. */
    _placeLeaderOnField(owner, slot) {
        const s          = this.state[owner];
        const leaderData = s.leader;

        // If a card already occupies the slot, send it to the gutter first
        if (slot.cardObject) {
            const displaced = this.state[owner].field[slot.slotIndex];
            if (displaced) {
                this.state[owner].field[slot.slotIndex] = null;
                this.state[owner].gutter.push(displaced);
            }
            slot.cardObject.container?.destroy();
            slot.cardObject = null;
            this._statBadges.get(`${owner}_${slot.slotIndex}`)?.container?.destroy();
            this._statBadges.delete(`${owner}_${slot.slotIndex}`);
        }

        s.leaderAwakened = true;
        s.field[slot.slotIndex] = {
            ...leaderData,
            position:    'atk',
            hasAttacked: true,   // promotion sickness — can't attack the turn it enters
            faceDown:    false,
            downed:      false,
        };

        // ── Leader zone: hide the dormant image and update badge ──────────────
        const img   = owner === 'player' ? this._plLeaderImg   : this._oppLeaderImg;
        const badge = owner === 'player' ? this._plLeaderBadge : this._oppLeaderBadge;
        const frame = owner === 'player' ? this._plLeaderFrame : this._oppLeaderFrame;
        const zoneX = img?.x ?? (owner === 'player' ? 32 : W - 32);
        const zoneY = img?.y ?? 195;

        badge?.setText('AWAKENED').setColor('#f4d35e');
        frame?.setStrokeStyle(2, 0xf4d35e, 1);
        const infBadge = owner === 'player' ? this._plLeaderInfluence : this._oppLeaderInfluence;
        infBadge?.setVisible(false);

        this._enterResolving();

        // ── Ghost image flies from leader zone to target slot ─────────────────
        const artKey = (leaderData.art_url && this.textures.exists(leaderData.art_url))
            ? leaderData.art_url
            : (this.textures.exists(leaderData.id) ? leaderData.id : null);

        const ghost = artKey
            ? this.add.image(zoneX, zoneY, artKey)
                .setDisplaySize(SLOT_W - 4, SLOT_H - 4)
                .setDepth(60)
                .setAlpha(0.9)
            : this.add.rectangle(zoneX, zoneY, SLOT_W - 4, SLOT_H - 4, 0x1a1a2e)
                .setStrokeStyle(2, 0xf4d35e, 1).setDepth(60);

        if (img) img.setVisible(false);

        this.tweens.add({
            targets:  ghost,
            x:        slot.x,
            y:        slot.y,
            scaleX:   1.15,
            scaleY:   1.15,
            duration: 480,
            ease:     'Power2.Out',
            onComplete: () => {
                ghost.destroy();

                // Place the real CardObject
                const mode    = owner === 'player' ? 'field_pl' : 'field_opp';
                const cardObj = new CardObject(this, slot.x, slot.y, leaderData, mode);
                slot.cardObject = cardObj;
                this.add.existing(cardObj.container);
                cardObj.container.setDepth(2).setScale(1.15);
                cardObj.setFieldMode(owner);
                if (owner === 'player') this._attachFieldTap(cardObj, slot);
                else cardObj.enableZoom(true);

                // Bounce settle
                this.tweens.add({
                    targets:  cardObj.container,
                    scaleX:   1,
                    scaleY:   1,
                    duration: 220,
                    ease:     'Back.Out',
                    onComplete: () => {
                        this._showFloatingText(slot.x, slot.y - 40, '👑 ENTERS THE BATTLE!', '#f4d35e');
                        this._sfx('sfx_card_play');
                        this.cameras.main.shake(200, 0.01);
                        this._logCombat(`👑 ${leaderData.name} enters the battle!`, '#ffd86b');
                        this.effectBus.trigger('on_play', { card: leaderData, owner, isPromotion: false, isLeaderEntry: true });
                        this._recalcClanBonuses();
                        this._refreshZoneCounts();
                        this._refreshAllStatBadges();
                        this._exitResolving();
                    },
                });
            },
        });
    }

    // ── Pride Runner adjacency bonus ──────────────────────────────────────────

    _recalcPrideRunnerBonuses() {
        // Pride Runner bonus is now computed inside _recalcClanBonuses so both
        // bonuses stack correctly from _baseAtk in a single pass.
        this._recalcClanBonuses();
    }

    // ── Hand limit enforcement (max 9 cards) ─────────────────────────────────

    _enforceHandLimit(onDone) {
        const excess = this.state.player.hand.length - 9;
        if (excess <= 0) { onDone?.(); return; }

        this._enterResolving();

        // Lift hand above the input shield so taps reach the cards.
        const SHIELD_DEPTH = 60;
        const HAND_DEPTH   = 70;
        const prevHandDepth  = this._handContainer.depth;
        const prevCardDepths = this._handCards.map(c => c.container.depth);
        this._handContainer.setDepth(HAND_DEPTH);
        this._handCards.forEach(c => c.container.setDepth(HAND_DEPTH));

        const objs = [];
        const cleanup = () => {
            objs.forEach(o => o?.destroy());
            this._handContainer.setDepth(prevHandDepth);
            this._handCards.forEach((c, i) => c.container.setDepth(prevCardDepths[i] ?? 1));
            this._exitResolving();
        };

        const shield = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.001)
            .setDepth(SHIELD_DEPTH).setInteractive();
        objs.push(shield);

        const msg = excess === 1
            ? 'HAND LIMIT: Tap a card to discard (1 remaining)'
            : `HAND LIMIT: Tap ${excess} cards to discard (${excess} remaining)`;
        const banner = this.add.text(W / 2, H / 2 - 44, msg, {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 4,
            backgroundColor: '#000000bb',
            padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(49);
        objs.push(banner);

        this._discardMode    = true;
        this._discardCallback = () => {
            cleanup();
            // After one discard, check if still over limit
            if (this.state.player.hand.length > 9) {
                this._enforceHandLimit(onDone);
            } else {
                onDone?.();
            }
        };
    }

    // ── Discard prompt for Corner Deal ───────────────────────────────────────

    _promptDiscard(owner) {
        if (owner !== 'player') {
            // AI discards the weakest card in hand
            const hand = this.state.opponent.hand;
            if (hand.length) {
                const weakest = hand.reduce((a, b) => (a.attack || 0) < (b.attack || 0) ? a : b);
                const idx = hand.indexOf(weakest);
                this.state.opponent.gutter.push(hand.splice(idx, 1)[0]);
            }
            return;
        }

        if (!this.state.player.hand.length) return;

        // Lock the board until the player discards
        this._enterResolving();

        // Lift the hand and its child cards above the input shield so taps land.
        const SHIELD_DEPTH = 60;
        const HAND_DEPTH   = 70;
        const prevHandDepth   = this._handContainer.depth;
        const prevCardDepths  = this._handCards.map(c => c.container.depth);
        this._handContainer.setDepth(HAND_DEPTH);
        this._handCards.forEach(c => c.container.setDepth(HAND_DEPTH));

        const objs = [];
        const cleanup = () => {
            objs.forEach(o => o?.destroy());
            this._handContainer.setDepth(prevHandDepth);
            this._handCards.forEach((c, i) => c.container.setDepth(prevCardDepths[i] ?? 1));
            this._exitResolving();
        };

        // Full-screen shield blocks board input. Sits below the elevated hand.
        const shield = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.001)
            .setDepth(SHIELD_DEPTH).setInteractive();
        objs.push(shield);

        // Persistent banner
        const banner = this.add.text(W / 2, H / 2 - 44, 'CORNER DEAL: TAP A CARD TO DISCARD', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#ff4444',
            stroke: '#000000', strokeThickness: 4,
            backgroundColor: '#000000bb',
            padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(49);
        objs.push(banner);

        this._discardMode = true;
        this._discardCallback = () => {
            cleanup();
        };
    }

    // ── Combat log ───────────────────────────────────────────────────────────

    _buildCombatLog() {
        const LW = 152, LH = 126, MAX_LINES = 6;
        // Anchored to the right edge — toggle button sits at far right
        const BTN_W = 22, BTN_H = 72;
        const BTN_X = W - BTN_W / 2 - 1;
        const BTN_Y = H / 2;
        const PANEL_X = W - BTN_W - LW;   // panel left edge
        const PANEL_Y = BTN_Y - LH / 2;

        this._logLines     = [];
        this._logMaxLines  = MAX_LINES;
        this._logX         = PANEL_X + 5;
        this._logY         = PANEL_Y + 5;
        this._logLH        = 18;
        this._logW         = LW - 10;
        this._logVisible   = false;

        // Panel background (hidden by default)
        this._logBg = this.add.rectangle(PANEL_X + LW / 2, BTN_Y, LW, LH, 0x000511, 0.82)
            .setStrokeStyle(1, 0x334466, 0.8).setDepth(38).setVisible(false);

        // Header label inside panel
        this._logHeader = this.add.text(PANEL_X + LW / 2, PANEL_Y + 8, 'COMBAT LOG', {
            fontSize: '6px', fontFamily: 'Arial Black', color: '#6688aa', letterSpacing: 1,
        }).setOrigin(0.5, 0).setDepth(39).setVisible(false);

        // Toggle button tab on the right edge
        const tab = this.add.rectangle(BTN_X, BTN_Y, BTN_W, BTN_H, 0x111a2a, 0.9)
            .setStrokeStyle(1, 0x334466, 0.8).setDepth(40).setInteractive({ useHandCursor: true });
        this._logTabTxt = this.add.text(BTN_X, BTN_Y, '📋', {
            fontSize: '10px',
        }).setOrigin(0.5).setDepth(41);

        tab.on('pointerup', () => {
            this._logVisible = !this._logVisible;
            this._logBg.setVisible(this._logVisible);
            this._logHeader.setVisible(this._logVisible);
            this._logLines.forEach(ln => ln.setVisible(this._logVisible));
        });
    }

    _logCombat(text, color = '#aaaacc') {
        // Buffer the entry even while panel is hidden
        const lineY = this._logY + this._logLines.length * this._logLH;
        const t = this.add.text(this._logX, lineY, text, {
            fontSize: '6px', fontFamily: 'Arial Black', color,
            wordWrap: { width: this._logW },
        }).setDepth(39).setAlpha(this._logVisible ? 0 : 1).setVisible(this._logVisible);

        if (this._logVisible) {
            this.tweens.add({ targets: t, alpha: 1, duration: 180 });
        }
        this._logLines.push(t);

        // Scroll up when full
        if (this._logLines.length > this._logMaxLines) {
            const removed = this._logLines.shift();
            this.tweens.add({ targets: removed, alpha: 0, duration: 200,
                onComplete: () => removed.destroy() });
            this._logLines.forEach((ln, i) => {
                this.tweens.add({ targets: ln, y: this._logY + i * this._logLH, duration: 150 });
            });
        }
    }

    // ── Damage numbers ────────────────────────────────────────────────────────

    // ── Slot pulse (ability / effect trigger visual) ──────────────────────────

    _pulseSlot(slot, color = 0xf4d35e, duration = 500) {
        if (!slot) return;
        const glow = this.add.rectangle(slot.x, slot.y, SLOT_W + 10, SLOT_H + 10, color, 0)
            .setStrokeStyle(3, color, 0.9).setDepth(5);
        this.tweens.add({
            targets: glow, alpha: 0.8, duration: duration / 3, ease: 'Power2',
            yoyo: true, repeat: 1,
            onComplete: () => glow.destroy(),
        });
    }

    // ── Card placement feel system ────────────────────────────────────────────

    /**
     * Drop-in animation + rarity impact effects + idle glow.
     * Called right after a card is snapped to its slot position.
     */
    _playCardPlacementEffect(cardObj, slot) {
        if (!SettingsManager.animationsEnabled) return;
        const cardData  = cardObj?.cardData;
        const container = cardObj?.container;
        if (!container || !cardData) return;

        const rarity    = cardData.rarity    || 1;
        const authority = cardData.authority || 1;

        // ── 1. Drop-in ──────────────────────────────────────────────────────
        const dropH      = 12 + Math.min(authority, 10) * 1.5;
        const scaleStart = 1.08 + rarity * 0.025;          // 1.10 → 1.21
        const dropMs     = 195 + rarity * 12;              // 207 → 255 ms

        container.y -= dropH;
        container.setScale(scaleStart);

        this.tweens.add({
            targets:  container,
            y:        slot.y,
            scaleX:   1,
            scaleY:   1,
            duration: dropMs,
            ease:     'Back.Out',
            onComplete: () => {
                this._playPlacementImpact(slot, rarity, authority);
                this._playFactionSlam(slot, cardData);
                this._addCardIdleGlow(slot, rarity);
            },
        });
    }

    /**
     * Faction-themed extra layer fired on summon.
     *   Lions  → gold sparks + bass-heavy thump (low pitch)
     *   Vipers → green venom mist + hiss (high pitch)
     */
    _playFactionSlam(slot, cardData) {
        if (!SettingsManager.animationsEnabled) return;
        const clan = cardData?.clan || cardData?.clan_tag || cardData?.faction;
        const cx = slot.x, cy = slot.y;

        if (clan === 'lion_pride' || clan === 'lion' || clan === 'lions') {
            // Gold radial wash
            const wash = this.add.ellipse(cx, cy, SLOT_W * 1.4, SLOT_H * 1.4, 0xffd700, 0.55).setDepth(5);
            this.tweens.add({ targets: wash, scaleX: 2.6, scaleY: 2.6, alpha: 0,
                duration: 420, ease: 'Power2', onComplete: () => wash.destroy() });
            this._spawnSparks(cx, cy, 18, 0xffd700, 50);
            this._spawnSparks(cx, cy,  8, 0xffae00, 30);
            this._spawnEmbers(cx, cy,  6, 0xffa500);
            this.cameras.main.shake(140, 0.012);   // bass thump
            try { this.sound.play('sfx_card_play', { volume: SettingsManager.sfxVolume * 1.1, detune: -350, rate: 0.85 }); } catch {}

        } else if (clan === 'viper_clan' || clan === 'viper' || clan === 'vipers') {
            // Green venom mist — drifting up, hiss SFX
            const wash = this.add.ellipse(cx, cy, SLOT_W * 1.3, SLOT_H * 1.3, 0x44ee88, 0.50).setDepth(5);
            this.tweens.add({ targets: wash, scaleX: 2.4, scaleY: 2.0, alpha: 0,
                duration: 460, ease: 'Power2', onComplete: () => wash.destroy() });
            // Mist droplets drifting up & sideways
            for (let i = 0; i < SettingsManager.particles(12); i++) {
                const ox = Phaser.Math.Between(-SLOT_W / 2, SLOT_W / 2);
                const drop = this.add.circle(cx + ox, cy + 6, 3 + Math.random() * 3, 0x66ff99, 0.65).setDepth(7);
                this.tweens.add({ targets: drop,
                    y: cy - 26 - Math.random() * 24,
                    x: cx + ox + Phaser.Math.Between(-18, 18),
                    alpha: 0, scaleX: 1.6, scaleY: 1.6,
                    duration: 700 + Math.random() * 250, ease: 'Sine.easeOut',
                    onComplete: () => drop.destroy() });
            }
            this._spawnSparks(cx, cy, 8, 0x66ff99, 32);
            this.cameras.main.shake(70, 0.006);    // sharper, lighter
            try { this.sound.play('sfx_card_play', { volume: SettingsManager.sfxVolume * 0.9, detune: 300, rate: 1.18 }); } catch {}
        }
    }

    /** Rarity-tiered impact burst fired after the drop tween completes. */
    _playPlacementImpact(slot, rarity, authority) {
        const cx = slot.x;
        const cy = slot.y;
        const shakeAmt = 0.002 + rarity * 0.0018 + authority * 0.0003;

        // Screen shake — scales with rarity + authority
        this.cameras.main.shake(80 + rarity * 20, shakeAmt);

        if (rarity === 1) {
            // ── COMMON: subtle white dust ring ──────────────────────────────
            const ring = this.add.ellipse(cx, cy, SLOT_W + 8, SLOT_H + 8, 0xffffff, 0)
                .setStrokeStyle(2, 0xdddddd, 0.8).setDepth(6);
            this.tweens.add({
                targets: ring, scaleX: 1.5, scaleY: 1.5, alpha: 0,
                duration: 280, ease: 'Power2',
                onComplete: () => ring.destroy(),
            });

        } else if (rarity === 2) {
            // ── RARE: blue sparks ────────────────────────────────────────────
            const ring = this.add.ellipse(cx, cy, SLOT_W + 10, SLOT_H + 10, 0x4cc9f0, 0)
                .setStrokeStyle(2, 0x4cc9f0, 0.9).setDepth(6);
            this.tweens.add({ targets: ring, scaleX: 1.8, scaleY: 1.8, alpha: 0, duration: 320, ease: 'Power2', onComplete: () => ring.destroy() });
            this._spawnSparks(cx, cy, 6, 0x4cc9f0, 28);

        } else if (rarity === 3) {
            // ── SUPER RARE: purple streaks + glow sweep ──────────────────────
            const ring = this.add.ellipse(cx, cy, SLOT_W + 14, SLOT_H + 14, 0x9b59b6, 0)
                .setStrokeStyle(3, 0xc77dff, 1).setDepth(6);
            this.tweens.add({ targets: ring, scaleX: 2.0, scaleY: 2.0, alpha: 0, duration: 380, ease: 'Power2', onComplete: () => ring.destroy() });
            this._spawnSparks(cx, cy, 10, 0xc77dff, 36);
            this._playGlowSweep(cx, cy, 0xc77dff);

        } else if (rarity === 4) {
            // ── ULTRA RARE: gold sparks + flash frame + micro-zoom ───────────
            const flash = this.add.rectangle(cx, cy, SLOT_W + 4, SLOT_H + 4, 0xffd700)
                .setDepth(7).setAlpha(0.9);
            this.tweens.add({ targets: flash, alpha: 0, duration: 90, ease: 'Power3', onComplete: () => flash.destroy() });

            const ring = this.add.ellipse(cx, cy, SLOT_W + 18, SLOT_H + 18, 0xffd700, 0)
                .setStrokeStyle(3, 0xffd700, 1).setDepth(6);
            this.tweens.add({ targets: ring, scaleX: 2.3, scaleY: 2.3, alpha: 0, duration: 440, ease: 'Power2', onComplete: () => ring.destroy() });

            this._spawnSparks(cx, cy, 14, 0xffd700, 44);
            this._spawnEmbers(cx, cy, 8, 0xffa500);
            this._playGlowSweep(cx, cy, 0xffd700);

            // Micro camera zoom
            this.cameras.main.zoomTo(Graphics.zoom * 1.06, 90, 'Linear', false, (cam, prog) => {
                if (prog === 1) this.cameras.main.zoomTo(Graphics.zoom, 160, 'Power2');
            });

        } else {
            // ── LEGENDARY: slow-mo + energy ripple + intense burst ───────────
            // Brief time-scale effect via tween timeScale
            this.tweens.timeScale = 0.35;
            this.time.delayedCall(120, () => { this.tweens.timeScale = 1; });

            const flash = this.add.rectangle(cx, cy, W, H, 0xffffff).setDepth(8).setAlpha(0.18);
            this.tweens.add({ targets: flash, alpha: 0, duration: 220, ease: 'Power3', onComplete: () => flash.destroy() });

            // Ripple wave across board
            for (let r = 1; r <= 3; r++) {
                const ripple = this.add.ellipse(cx, cy, 10, 10, 0xff6b35, 0)
                    .setStrokeStyle(2, 0xff6b35, 0.9).setDepth(6);
                this.time.delayedCall(r * 60, () => {
                    this.tweens.add({ targets: ripple, scaleX: (SLOT_W * 5) / 10 * r, scaleY: (H * 0.8) / 10 * r, alpha: 0, duration: 500, ease: 'Power2', onComplete: () => ripple.destroy() });
                });
            }

            this._spawnSparks(cx, cy, 20, 0xff6b35, 56);
            this._spawnEmbers(cx, cy, 14, 0xffd700);
            this._playGlowSweep(cx, cy, 0xff6b35);
            this.cameras.main.shake(180, 0.018);
            this.cameras.main.zoomTo(Graphics.zoom * 1.10, 110, 'Linear', false, (cam, prog) => {
                if (prog === 1) this.cameras.main.zoomTo(Graphics.zoom, 220, 'Power2');
            });
        }
    }

    /** Scatter small colored rectangles outward from a point. */
    _spawnSparks(cx, cy, count, color, radius) {
        count = SettingsManager.particles(count);
        for (let i = 0; i < count; i++) {
            const angle  = (i / count) * Math.PI * 2 + Math.random() * 0.5;
            const dist   = radius * (0.5 + Math.random() * 0.8);
            const w      = 3 + Math.random() * 4;
            const h      = 2 + Math.random() * 2;
            const spark  = this.add.rectangle(cx, cy, w, h, color, 0.9).setDepth(7).setRotation(angle);
            this.tweens.add({
                targets: spark,
                x:       cx + Math.cos(angle) * dist,
                y:       cy + Math.sin(angle) * dist,
                alpha:   0,
                scaleX:  0.2,
                duration: 280 + Math.random() * 140,
                ease:    'Power2',
                onComplete: () => spark.destroy(),
            });
        }
    }

    /** Drift small particles upward (fire embers effect). */
    _spawnEmbers(cx, cy, count, color) {
        count = SettingsManager.particles(count);
        for (let i = 0; i < count; i++) {
            const ox    = Phaser.Math.Between(-SLOT_W / 2, SLOT_W / 2);
            const ember = this.add.circle(cx + ox, cy, 2 + Math.random() * 2, color, 0.85).setDepth(7);
            this.tweens.add({
                targets:  ember,
                y:        cy - 30 - Math.random() * 30,
                x:        cx + ox + Phaser.Math.Between(-12, 12),
                alpha:    0,
                duration: 500 + Math.random() * 300,
                delay:    Math.random() * 120,
                ease:     'Power1',
                onComplete: () => ember.destroy(),
            });
        }
    }

    /** Bright highlight sweep across the card face (left → right). */
    _playGlowSweep(cx, cy, color) {
        const sweep = this.add.rectangle(cx - SLOT_W / 2 - 8, cy, 14, SLOT_H - 4, color, 0.55)
            .setDepth(8);
        this.tweens.add({
            targets:  sweep,
            x:        cx + SLOT_W / 2 + 8,
            alpha:    0,
            duration: 220,
            ease:     'Power1',
            onComplete: () => sweep.destroy(),
        });
    }

    /** Soft ambient glow ring that pulses behind the card — tied to rarity. */
    _addCardIdleGlow(slot, rarity) {
        // Remove any existing glow on this slot
        slot._idleGlow?.destroy();
        slot._idleGlowTween?.stop();

        if (rarity < 2) return;   // Common: no idle glow

        const colors = [0, 0, 0x4cc9f0, 0xc77dff, 0xffd700, 0xff6b35];
        const color  = colors[rarity] || 0xffd700;
        const alphaMin = rarity >= 5 ? 0.20 : rarity >= 4 ? 0.14 : rarity >= 3 ? 0.10 : 0.07;
        const alphaMax = alphaMin * 2.8;

        const glow = this.add.ellipse(slot.x, slot.y, SLOT_W + 18, SLOT_H + 18, color, alphaMin)
            .setDepth(1);   // behind the card (card is depth 2)
        slot._idleGlow = glow;
        slot._idleGlowTween = this.tweens.add({
            targets:  glow,
            alpha:    { from: alphaMin, to: alphaMax },
            scaleX:   { from: 1.0, to: 1.08 },
            scaleY:   { from: 1.0, to: 1.08 },
            duration: 1200 - rarity * 80,
            yoyo:     true,
            repeat:   -1,
            ease:     'Sine.easeInOut',
        });
    }

    /** Remove idle glow from a slot (call when a card leaves). */
    _clearSlotGlow(slot) {
        if (!slot) return;
        slot._idleGlowTween?.stop();
        slot._idleGlow?.destroy();
        slot._idleGlow     = null;
        slot._idleGlowTween = null;
    }

    // ── Floating status text ──────────────────────────────────────────────────

    /**
     * Apply venom-tick damage to every poisoned card on the given owner's field.
     * Each stack = 200 morale damage. Damage numbers drip downward in green.
     */
    _tickPoison(owner) {
        const s = this.state[owner];
        if (!s) return;
        const slots = owner === 'player'
            ? [...this._slotObjects.pl_front, ...this._slotObjects.pl_back]
            : [...this._slotObjects.opp_front, ...this._slotObjects.opp_back];

        s.field.forEach((card, idx) => {
            if (!card || !card._poisonStacks) return;
            const stacks = card._poisonStacks;
            const dmg = stacks * 200;
            s.morale = Math.max(0, s.morale - dmg);

            const slot = slots.find(sl => sl.slotIndex === idx);
            const x = slot?.x ?? W / 2;
            const y = slot?.y ?? (owner === 'player' ? ROW_Y.pl_front : ROW_Y.opp_front);

            this._showDamageNumber(x, y - 8, dmg, {
                drip: true, accent: '#66ff99',
                label: stacks > 1 ? `VENOM x${stacks}` : 'VENOM',
            });

            // Decay one stack per tick
            card._poisonStacks = stacks - 1;
            if (card._poisonStacks <= 0) delete card._poisonStacks;
        });

        this._plProfileBox?.update(this.state.player.morale);
        this._oppProfileBox?.update(this.state.opponent.morale);
        this._checkWinCondition?.();
    }

    /** Map a card's clan to an accent hex used by the comic-style number style. */
    _factionAccent(cardData) {
        const c = cardData?.clan || cardData?.clan_tag || cardData?.faction;
        if (c === 'lion_pride' || c === 'lion'  || c === 'lions')  return '#ffd700';
        if (c === 'viper_clan' || c === 'viper' || c === 'vipers') return '#66ff99';
        return '#ffd700';
    }

    /**
     * Stat modification popup: ATK/DEF buffs and debuffs, oversized comic style.
     *  amount > 0  → buff   (gold)
     *  amount < 0  → debuff (red)
     *  opts.label optional ("ATK", "DEF", "ATK/DEF", or freeform)
     */
    _showStatMod(x, y, amount, opts = {}) {
        const isBuff = amount > 0;
        const accent = opts.accent || (isBuff ? '#f4d35e' : '#ff5555');
        const sign   = isBuff ? '+' : '−';
        const fontSize = '20px';

        const txt = this.add.text(x, y, `${sign}${Math.abs(amount)}`, {
            fontSize, fontFamily: 'Impact, "Arial Black", sans-serif',
            color: '#ffffff', stroke: accent, strokeThickness: 4,
        }).setOrigin(0.5).setDepth(45).setScale(0).setAlpha(0);

        let label = null;
        if (opts.label) {
            label = this.add.text(x, y + 14, opts.label, {
                fontSize: '8px', fontFamily: 'Arial Black', color: accent,
                stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5).setDepth(45).setAlpha(0);
        }

        this.tweens.add({ targets: txt, scale: 1.05, alpha: 1, duration: 180, ease: 'Back.Out',
            onComplete: () => this.tweens.add({ targets: txt, scale: 1.0, duration: 120 }),
        });
        if (label) this.tweens.add({ targets: label, alpha: 1, duration: 200, delay: 80 });

        this.time.delayedCall(380, () => {
            this.tweens.add({
                targets: [txt, label].filter(Boolean), y: y - 50, alpha: 0,
                duration: 1200, ease: 'Power2',
                onComplete: () => { txt.destroy(); label?.destroy(); },
            });
        });
    }

    /**
     * Comic-book damage number. Pops up oversized, optional crit shake,
     * optional drip for poison/venom (number falls instead of rises).
     * opts: { crit?: bool, accent?: '#hex', drip?: bool, label?: 'POISON',
     *         type?: 'damage'|'heal'|'def' (legacy shorthand) }
     * For backward-compat, opts may also be a bare string of type.
     */
    _showDamageNumber(x, y, amount, opts = {}) {
        if (typeof opts === 'string') opts = { type: opts };
        // Legacy `type` shorthand → translate to opts
        if (opts.type === 'heal') {
            opts.accent = opts.accent || '#44ff88';
            opts.heal   = true;
        } else if (opts.type === 'def') {
            opts.accent = opts.accent || '#4cc9f0';
            opts.label  = opts.label  || 'BLOCK';
        }

        const accent = opts.accent || '#ffd700';
        const isCrit = !!opts.crit;
        const isDrip = !!opts.drip;
        const isHeal = !!opts.heal;
        const fontSize = isCrit ? '28px' : '22px';
        const prefix = isHeal ? '+' : '-';

        const txt = this.add.text(x, y, `${prefix}${Math.abs(amount)}`, {
            fontSize, fontFamily: 'Impact, "Arial Black", sans-serif', color: '#ffffff',
            stroke: accent, strokeThickness: 5,
        }).setOrigin(0.5).setDepth(45).setScale(0).setAlpha(0);

        // Side label (e.g., POISON)
        let label = null;
        if (opts.label) {
            label = this.add.text(x, y + (isCrit ? 18 : 14), opts.label, {
                fontSize: '9px', fontFamily: 'Arial Black', color: accent,
                stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5).setDepth(45).setAlpha(0);
        }

        this.tweens.add({
            targets: txt, scale: isCrit ? 1.35 : 1.1, alpha: 1,
            duration: 180, ease: 'Back.Out',
            onComplete: () => {
                if (isCrit) this.cameras.main.shake(120, 0.014);
                this.tweens.add({ targets: txt, scale: 1.0, duration: 130, ease: 'Power2' });
            },
        });
        if (label) this.tweens.add({ targets: label, alpha: 1, duration: 220, delay: 80 });

        const dy = isDrip ? y + 50 : y - 60;
        const ease = isDrip ? 'Cubic.easeIn' : 'Power2';
        const dur  = isDrip ? 1400 : 1500;
        this.time.delayedCall(280, () => {
            this.tweens.add({
                targets: [txt, label].filter(Boolean), y: dy, alpha: 0,
                duration: dur, ease,
                onComplete: () => { txt.destroy(); label?.destroy(); },
            });
        });
    }

    _showFloatingText(x, y, text, color = '#ffffff') {
        const t = this.add.text(x, y, text, {
            fontSize: '14px', fontFamily: 'Arial Black', color,
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5).setDepth(40).setScale(0).setAlpha(0);

        // Scale in
        this.tweens.add({
            targets: t, scaleX: 1, scaleY: 1, alpha: 1,
            duration: 220, ease: 'Back.Out',
            onComplete: () => {
                // Hold then float up and fade
                this.time.delayedCall(420, () => {
                    this.tweens.add({
                        targets: t, y: y - 70, alpha: 0,
                        duration: 1600, ease: 'Power2',
                        onComplete: () => t.destroy(),
                    });
                });
            },
        });
    }

    // ── Deciding banner — shown when a player is making an interactive choice ──

    _showDecidingBanner(side = 'player') {
        this._hideDecidingBanner();

        const rawName = side === 'player'
            ? (this.registry.get('player')?.username || 'YOU')
            : (this._opponentName || 'OPPONENT');
        const name = rawName.toUpperCase();

        const bg = this.add.rectangle(W / 2, H / 2, W, 46, 0x000000).setAlpha(0).setDepth(78);
        const txt = this.add.text(W / 2, H / 2, `⚡ ${name} IS DECIDING...`, {
            fontSize: '15px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 4,
        }).setOrigin(0.5).setAlpha(0).setDepth(79);

        this.tweens.add({ targets: bg,  alpha: 0.78, duration: 180 });
        this.tweens.add({ targets: txt, alpha: 1,    duration: 180,
            onComplete: () => {
                this.time.delayedCall(1400, () => this._hideDecidingBanner());
            },
        });

        this._decidingBanner = { bg, txt };
    }

    _hideDecidingBanner() {
        if (!this._decidingBanner) return;
        const { bg, txt } = this._decidingBanner;
        this._decidingBanner = null;
        this.tweens.add({
            targets: [bg, txt], alpha: 0, duration: 220, ease: 'Linear',
            onComplete: () => { bg.destroy(); txt.destroy(); },
        });
    }

    /**
     * Plays the Ambush flip + effect animation when a trap is triggered.
     * @param {Phaser.GameObjects.Rectangle} ambushSlot
     * @param {object} ambushCard
     */
    _playAmbushReveal(ambushSlot, ambushCard, onComplete) {
        if (!SettingsManager.animationsEnabled) {
            ambushSlot.cardObject?.flipFaceUp?.();
            onComplete?.();
            return;
        }

        this._sfx('sfx_trap_reveal');

        const cx = ambushSlot.x;
        const cy = ambushSlot.y;
        const layer = this.add.container(0, 0).setDepth(55);

        // Dim the board
        const curtain = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0).setDepth(54);
        this.tweens.add({ targets: curtain, alpha: 0.6, duration: 200 });

        // Glow ring around card
        const ring = this.add.ellipse(cx, cy, SLOT_W + 20, SLOT_H + 20, 0xff9800, 0)
            .setDepth(56).setStrokeStyle(3, 0xff9800, 1);
        layer.add(ring);
        this.tweens.add({ targets: ring, alpha: 0.85, duration: 180 });

        // Comic burst shapes
        this._spawnComicBurst(cx, cy, layer);

        // Card flip after short delay
        this.time.delayedCall(220, () => {
            if (ambushSlot.cardObject) {
                this.tweens.add({
                    targets: ambushSlot.cardObject.container, scaleX: 0,
                    duration: 100, ease: 'Linear',
                    onComplete: () => {
                        ambushSlot.cardObject.flipFaceUp();
                        this.tweens.add({
                            targets: ambushSlot.cardObject.container, scaleX: 1,
                            duration: 120, ease: 'Back.Out',
                        });
                    },
                });
            }

            // "AMBUSH REVEALED!" banner
            const banner = this.add.text(W / 2, cy - 60, 'AMBUSH REVEALED!', {
                fontSize: '16px', fontFamily: 'Arial Black', color: '#ff9800',
                stroke: '#000000', strokeThickness: 4,
            }).setOrigin(0.5).setDepth(57).setScale(0).setAlpha(0);
            layer.add(banner);
            this.tweens.add({ targets: banner, scaleX: 1, scaleY: 1, alpha: 1,
                duration: 200, ease: 'Back.Out' });

            const nameTxt = this.add.text(W / 2, cy - 42, ambushCard?.name ?? '', {
                fontSize: '7px', fontFamily: 'Arial', color: '#ffffff',
                stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5).setDepth(57).setAlpha(0);
            layer.add(nameTxt);
            this.tweens.add({ targets: nameTxt, alpha: 1, duration: 180, delay: 100 });

            // Screen shake
            this.cameras.main.shake(280, 0.01);

            // Hold then fade out the whole overlay
            this.time.delayedCall(700, () => {
                this.tweens.add({
                    targets: [curtain, ring, banner, nameTxt], alpha: 0,
                    duration: 250, ease: 'Power2',
                    onComplete: () => {
                        layer.destroy(true);
                        curtain.destroy();
                        onComplete?.();
                    },
                });
            });
        });
    }

    _spawnComicBurst(cx, cy, layer) {
        const colors = [0xff9800, 0xffe066, 0xff3b4e];
        const count  = 8;
        for (let i = 0; i < count; i++) {
            const angle  = (i / count) * Math.PI * 2;
            const length = 28 + Math.random() * 18;
            const width  = 6 + Math.random() * 6;
            const tx = cx + Math.cos(angle) * length;
            const ty = cy + Math.sin(angle) * length;
            const ray = this.add.rectangle(
                cx + Math.cos(angle) * length * 0.5,
                cy + Math.sin(angle) * length * 0.5,
                length, width,
                colors[i % colors.length], 0.85,
            ).setDepth(56).setRotation(angle);
            layer.add(ray);
            this.tweens.add({
                targets: ray, scaleX: 1.4, alpha: 0,
                duration: 400, ease: 'Power2',
            });
        }
    }

    // ── Win condition check ───────────────────────────────────────────────────

    _checkWinCondition() {
        const { player, opponent } = this.state;

        if (player.morale <= 0 || opponent.morale <= 0) {
            const playerWon = opponent.morale <= 0;

            this.bgm?.stop();
            this._sfx(playerWon ? 'sfx_victory' : 'sfx_defeat');

            this.time.delayedCall(1200, () => {
                this._launchPostMatch({
                    result:        playerWon ? 'win' : 'loss',
                    playerMorale:  Math.max(0, player.morale),
                    opponentMorale:Math.max(0, opponent.morale),
                    turns:         this.state.turn,
                    reason:        'morale',
                    mvpCard:       this._getMvpCard(),
                });
            });
        }
    }

    _trackMvp(cardData, damage, owner) {
        if (!cardData || !damage || damage <= 0) return;
        const key = (cardData.id || cardData.name || 'unknown') + '_' + owner;
        if (!this._mvpLog[key]) {
            this._mvpLog[key] = {
                name:        cardData.name || 'Unknown',
                artKey:      cardData.art_url || cardData.id || null,
                totalDamage: 0,
                owner,
                cardData,
            };
        }
        this._mvpLog[key].totalDamage += damage;
    }

    _getMvpCard() {
        const entries = Object.values(this._mvpLog || {});
        if (!entries.length) return null;
        return entries.reduce((best, cur) =>
            cur.totalDamage > best.totalDamage ? cur : best
        );
    }

    // Solo (AI) matches get a server-issued session id; rewards can only be
    // claimed against it once, from PostMatchScene.
    _startSoloSession() {
        this._soloMatchId = null;
        const token = this.registry.get('token');
        if (!token || this.scene.key !== 'DuelScene') return;   // multiplayer is server-driven
        apiFetch('/api/match/start', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ ranked: this._ranked }),
        })
        .then(r => r.ok ? r.json() : null)
        .then(d => { if (d?.matchId) this._soloMatchId = d.matchId; })
        .catch(() => {});
    }

    _launchPostMatch(data) {
        data = { ...data, soloMatchId: this._soloMatchId, cardsPlayed: this._playerCardsPlayed };

        // Dim overlay — keep DuelScene partially visible as background behind the result screen
        const overlay = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0).setDepth(998);

        // Apply blur to the duel camera if postFX is supported (Phaser 3.60+)
        if (SettingsManager.postFx) {
            try { this.cameras.main.postFX?.addBlur?.(0, 2, 2, 0.5); } catch (_) {}
        }

        this.tweens.add({
            targets:  overlay,
            alpha:    0.38,
            duration: 900,
            ease:     'Power2',
            onComplete: () => {
                // Snapshot the (already-blurred) duel scene so PostMatchScene can use
                // it as a background — relying on the paused scene to keep rendering
                // beneath the post-match camera doesn't work consistently.
                this.game.renderer.snapshot((image) => {
                    const key = 'duel_snapshot_' + Date.now();
                    if (this.textures.exists(key)) this.textures.remove(key);
                    this.textures.addImage(key, image);
                    this.scene.launch('PostMatchScene', { ...data, snapshotKey: key });
                    this.scene.pause();
                });
            },
        });
    }

    _timeoutDefeat() {
        this.bgm?.stop();
        this._sfx('sfx_defeat');
        this._showFloatingText(W / 2, H / 2 - 30, 'TIMEOUT — YOU LOSE!', '#ff3b4e');
        this.time.delayedCall(1800, () => {
            this._launchPostMatch({
                result:        'loss',
                playerMorale:  Math.max(0, this.state.player.morale),
                opponentMorale:Math.max(0, this.state.opponent.morale),
                turns:         this.state.turn,
                reason:        'timeout',
                mvpCard:       this._getMvpCard(),
            });
        });
    }

    // ── Opponent AI (simple greedy) ───────────────────────────────────────────

    _runOpponentAI_withDelay() {
        this.time.delayedCall(800, () => {
            this._aiDeploy();
            this.time.delayedCall(600, () => this._startPhase('brawl'));
        });
    }

    _aiDeploy() {
        // Utility AI returns a full deployment plan; execute each step.
        const plan = AiBrain.planDeployment(this.state, this.brawlPhase);
        // Execute in original-hand-index descending order so splices don't break refs
        plan.sort((a, b) => b.cardIdx - a.cardIdx);

        for (const step of plan) {
            const hand  = this.state.opponent.hand;
            const field = this.state.opponent.field;
            const cardData = hand[step.cardIdx];
            if (!cardData) continue;

            if (step.type === 'play_character') {
                hand.splice(step.cardIdx, 1);
                field[step.slotIdx] = {
                    ...cardData,
                    position:    step.position,
                    faceDown:    false,
                    hasAttacked: false,
                };
                this.state.opponent.authority = Math.max(
                    0, this.state.opponent.authority - (cardData.authority || 0)
                );

                const slot    = this._slotObjects.opp_front[step.slotIdx];
                const cardObj = new CardObject(this, slot.x, slot.y, cardData, 'field_opp');
                slot.cardObject = cardObj;
                this.add.existing(cardObj.container);
                cardObj.container.setDepth(2);
                cardObj.enableZoom(true);
                if (step.position === 'def') cardObj.container.setAngle(90);
                this._sfx('sfx_card_play');
                this._playCardPlacementEffect(cardObj, slot);
            }

            else if (step.type === 'set_ambush') {
                const cost = cardData.authority || 0;
                if (this.state.opponent.authority < cost) continue;
                const slot = this._findFirstOpenBackRowSlot('opponent');
                if (!slot) continue;
                hand.splice(step.cardIdx, 1);
                field[slot.slotIndex] = { ...cardData, faceDown: true };
                this.state.opponent.authority = Math.max(0, this.state.opponent.authority - cost);
                const cardObj = new CardObject(this, slot.x, slot.y, cardData, 'field_opp');
                cardObj.flipFaceDown?.();
                slot.cardObject = cardObj;
                this.add.existing(cardObj.container);
                cardObj.container.setDepth(2);
                this._sfx('sfx_card_play');
                this._playCardPlacementEffect(cardObj, slot);
            }

            else if (step.type === 'attach_hardware') {
                const cost = cardData.authority || 0;
                if (this.state.opponent.authority < cost) continue;
                const slot = this._findFirstOpenBackRowSlot('opponent');
                if (!slot) continue;
                hand.splice(step.cardIdx, 1);
                this.state.opponent.authority = Math.max(0, this.state.opponent.authority - cost);
                const tgt = field[step.slotIdx];
                if (tgt) {
                    tgt.attack  = (tgt.attack  || 0) + (cardData.atkMod || 0);
                    tgt.defense = (tgt.defense || 0) + (cardData.defMod || 0);
                    field[slot.slotIndex] = { ...cardData, _attachedToFront: step.slotIdx };
                    const cardObj = new CardObject(this, slot.x, slot.y, cardData, 'field_opp');
                    slot.cardObject = cardObj;
                    this.add.existing(cardObj.container);
                    cardObj.container.setDepth(2);
                    const front = this._slotObjects.opp_front[step.slotIdx];
                    front?.cardObject?.updateStats?.(tgt);
                }
            }
        }

        this._refreshAuthorityDisplay();
        this._reattachOppZoom();
        this._refreshOppHandDisplay();
        this._recalcClanBonuses();
    }

    _aiAttack() {
        // Utility AI plans the whole brawl phase up front; execute one at a time,
        // each waiting for the previous cinematic to finish before the next starts.
        const plan = AiBrain.planBrawl(this.state, this.brawlPhase);

        const endTurn = () => {
            this.time.delayedCall(400, () => this._startPhase('regroup'));
        };

        const runStep = (i) => {
            if (i >= plan.length) { endTurn(); return; }

            const step = plan[i];
            const next = () => this.time.delayedCall(300, () => runStep(i + 1));

            // Re-validate — an earlier attack may have cleared this card.
            const attackerCard = this.state.opponent.field[step.attackerIdx];
            if (!attackerCard || attackerCard.hasAttacked) { next(); return; }

            const attackerSlot = this._slotObjects.opp_front[step.attackerIdx];
            let targetIdx = step.targetIdx;
            if (targetIdx != null && !this.state.player.field[targetIdx]) {
                targetIdx = null;
            }
            const playerFrontEmpty = this.state.player.field.slice(0, 5).every(c => !c);

            // Before resolving, give the player a chance to activate ambushes
            // and to redirect to Block Enforcer if applicable.
            const doAttack = (negated) => {
                if (negated) { next(); return; }

                // Refresh the attackerSlot reference in case the target was redirected
                const attCardAI = this.state.opponent.field[step.attackerIdx];
                if (targetIdx != null) {
                    // Apply temporary pre-battle ATK adjustments for AI (mirrors player logic)
                    const defCardAI = this.state.player.field[targetIdx];
                    let preAtkAI = 0;
                    if (attCardAI?.effectKey === 'goldfang_attacker' && defCardAI?.position === 'def') preAtkAI += 500;
                    if (['hunter_lv1', 'hunter_lv2', 'hunter_lv3', 'mauler'].includes(attCardAI?.effectKey) && defCardAI?.downed) preAtkAI += 500;
                    if (defCardAI?.effectKey === 'bulwark' && !defCardAI?.downed) preAtkAI -= 300;
                    // Brutus chain bonus for AI
                    if (attCardAI?.clanTag === 'lion' && this.state.opponent._brutusChainBonus) {
                        preAtkAI += this.state.opponent._brutusChainBonus;
                        this.state.opponent._brutusChainBonus = 0;
                    }
                    if (preAtkAI && attCardAI) attCardAI.attack += preAtkAI;
                    const result = this.brawlPhase.resolveAttack(
                        step.attackerIdx, targetIdx, 'opponent');
                    if (preAtkAI && attCardAI) attCardAI.attack -= preAtkAI;
                    // Blood Scent (AI side)
                    this._checkBloodScentPromote(attCardAI, step.attackerIdx, 'opponent', result);
                    // Lion's Ambush is a one-shot debuff — clear it after the brawl resolves
                    if (attCardAI?._ambushDebuff) {
                        attCardAI._ambushDebuff = 0;
                        this._recalcClanBonuses();
                    }
                    if (result.moraleDealt > 0 && attCardAI) this._trackMvp(attCardAI, result.moraleDealt, 'opponent');
                    const defenderSlot = this._slotObjects.pl_front[targetIdx];
                    this._playAttackAnimation(attackerSlot, defenderSlot, result, next);
                } else if (playerFrontEmpty) {
                    const result = this.brawlPhase.resolveDirectAttack(
                        step.attackerIdx, 'opponent');
                    this._checkBloodScentPromote(attCardAI, step.attackerIdx, 'opponent', result);
                    if (attCardAI?._ambushDebuff) {
                        attCardAI._ambushDebuff = 0;
                        this._recalcClanBonuses();
                    }
                    if (result.moraleDealt > 0 && attCardAI) this._trackMvp(attCardAI, result.moraleDealt, 'opponent');
                    this._playDirectAttackAnimation(attackerSlot, result);
                    next();
                } else {
                    next();
                }
            };

            // Run ambush prompts first; if not negated, offer Block Enforcer redirect.
            this._promptPlayerAmbushes(step.attackerIdx, targetIdx, (negated) => {
                if (negated) { doAttack(true); return; }
                this._promptBlockEnforcerRedirect(targetIdx, (finalTargetIdx) => {
                    targetIdx = finalTargetIdx;
                    doAttack(false);
                });
            });
        };

        this.time.delayedCall(700, () => runStep(0));
    }

    // ── Ambush prompt system ──────────────────────────────────────────────────
    //
    // Called before each opponent attack. Collects all player face-down ambush
    // cards and presents them one at a time (Master Duel style). The attack
    // resolves — or is negated — once the player has answered each prompt.

    _promptPlayerAmbushes(attackerIdx, targetIdx, onDone) {
        // Collect all face-down ambush cards in the player's back row
        const ambushSlots = this._slotObjects.pl_back.filter(s => {
            const card = this.state.player.field[s.slotIndex];
            return s.cardObject && card?.faceDown && card?.cardType === 'ambush';
        });

        if (!ambushSlots.length) { onDone(false); return; }

        this._enterResolving();

        // Show prompts sequentially; track if any ambush negated the attack
        let negated = false;
        const promptNext = (idx) => {
            if (idx >= ambushSlots.length) {
                this._exitResolving();
                onDone(negated);
                return;
            }

            const slot = ambushSlots[idx];
            const card = this.state.player.field[slot.slotIndex];
            if (!card) { promptNext(idx + 1); return; }

            this._showAmbushPromptModal(card, (activated) => {
                if (activated) {
                    this._playAmbushReveal(slot, card, () => {
                        card.faceDown = false;
                        this.effectBus.trigger('on_ambush', {
                            card, owner: 'player', attackerIdx, targetIdx,
                        });
                        if (card.effectKey === 'no_witnesses_ambush') negated = true;
                        this.state.player.gutter.push(card);
                        this.state.player.field[slot.slotIndex] = null;
                        slot.cardObject?.destroy();
                        slot.cardObject = null;
                        this._refreshZoneCounts();
                        promptNext(idx + 1);
                    });
                } else {
                    promptNext(idx + 1);
                }
            });
        };

        promptNext(0);
    }

    /**
     * Shows the Master-Duel-style YES / NO modal for one ambush card.
     * Pauses the game (no input passes through) until the player decides.
     * @param {object}   card
     * @param {Function} callback   (activated: boolean) => void
     */
    /**
     * If the AI's chosen target is a player Lion (other than Block Enforcer)
     * and the player controls a non-downed Block Enforcer that hasn't redirected
     * yet this turn, prompt the player to redirect the attack to it.
     *
     * onDone(finalTargetIdx) is called with either the original or the redirected
     * slot index.
     */
    _promptBlockEnforcerRedirect(targetIdx, onDone) {
        if (targetIdx == null) { onDone(targetIdx); return; }

        const targetCard = this.state.player.field[targetIdx];
        if (!targetCard || targetCard.clanTag !== 'lion') { onDone(targetIdx); return; }
        if (targetCard.effectKey === 'block_enforcer_redirect') { onDone(targetIdx); return; }

        // Find a non-downed Block Enforcer the player controls that hasn't redirected this turn
        const beSlot = this._slotObjects.pl_front.find(s => {
            const c = this.state.player.field[s.slotIndex];
            return c && c.effectKey === 'block_enforcer_redirect'
                && !c.downed && !c._blockEnforcerRedirectUsed;
        });
        if (!beSlot) { onDone(targetIdx); return; }

        const be = this.state.player.field[beSlot.slotIndex];
        this._enterResolving();

        const overlay = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.65)
            .setDepth(80).setInteractive();
        const PW = 290, PH = 124;
        const px = W / 2, py = H / 2;
        const panel = this.add.rectangle(px, py, PW, PH, 0x0d1020, 0.97)
            .setStrokeStyle(2, 0x4cc9f0, 1).setDepth(81);
        const header = this.add.text(px, py - PH / 2 + 14, `🛡 BLOCK ENFORCER`, {
            fontSize: '11px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            color: '#4cc9f0', stroke: '#000', strokeThickness: 2,
        }).setOrigin(0.5).setDepth(82);
        const effectLine = this.add.text(px, py - 8,
            `Redirect attack on ${targetCard.name} to Block Enforcer instead?`, {
            fontSize: '8px', fontFamily: 'Verdana, sans-serif',
            color: '#ccccee', wordWrap: { width: PW - 24 }, align: 'center',
        }).setOrigin(0.5).setDepth(82);

        const cleanup = () => {
            overlay.destroy(); panel.destroy(); header.destroy(); effectLine.destroy();
            yesBtn.destroy(); noBtn.destroy();
            this._exitResolving();
        };

        const yesBtn = this.add.text(px - 50, py + PH / 2 - 14, 'REDIRECT', {
            fontSize: '10px', fontFamily: 'Arial Black',
            color: '#000000', backgroundColor: '#4cc9f0',
            padding: { x: 8, y: 4 },
        }).setOrigin(0.5).setDepth(82).setInteractive();
        yesBtn.on('pointerdown', () => {
            cleanup();
            be._blockEnforcerRedirectUsed = true;
            this._showFloatingText(beSlot.x, beSlot.y - 30, 'BLOCK ENFORCER: TAKING THE HIT!', '#4cc9f0');
            onDone(beSlot.slotIndex);
        });

        const noBtn = this.add.text(px + 50, py + PH / 2 - 14, 'PASS', {
            fontSize: '10px', fontFamily: 'Arial Black',
            color: '#aaaacc', backgroundColor: '#1c2040',
            padding: { x: 8, y: 4 },
        }).setOrigin(0.5).setDepth(82).setInteractive();
        noBtn.on('pointerdown', () => { cleanup(); onDone(targetIdx); });
    }

    _showAmbushPromptModal(card, callback) {

        // Dim overlay — blocks all input beneath
        const overlay = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.65)
            .setDepth(80).setInteractive();

        const PW = 280, PH = 120;
        const px = W / 2, py = H / 2;

        // Panel background
        const panel = this.add.rectangle(px, py, PW, PH, 0x0d1020, 0.97)
            .setStrokeStyle(2, 0xf4d35e, 1).setDepth(81);

        // Card name header
        const header = this.add.text(px, py - PH / 2 + 14, `⚡ ${card.name.toUpperCase()}`, {
            fontSize: '11px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            color: '#f4d35e', stroke: '#000', strokeThickness: 2,
        }).setOrigin(0.5).setDepth(82);

        // Effect text
        const effectLine = this.add.text(px, py - 8, card.effectText || '', {
            fontSize: '7px', fontFamily: 'Verdana, sans-serif',
            color: '#ccccee', wordWrap: { width: PW - 24 }, align: 'center',
        }).setOrigin(0.5).setDepth(82);

        // Prompt label
        const prompt = this.add.text(px, py + PH / 2 - 34, 'Activate this effect?', {
            fontSize: '9px', fontFamily: 'Verdana, sans-serif', color: '#ffffff',
        }).setOrigin(0.5).setDepth(82);

        const cleanup = () => {
            overlay.destroy(); panel.destroy(); header.destroy();
            effectLine.destroy(); prompt.destroy(); yesBtn.destroy(); noBtn.destroy();
        };

        // YES button
        const yesBtn = this.add.text(px - 44, py + PH / 2 - 14, 'ACTIVATE', {
            fontSize: '10px', fontFamily: 'Arial Black',
            color: '#000000', backgroundColor: '#f4d35e',
            padding: { x: 8, y: 4 },
        }).setOrigin(0.5).setDepth(82).setInteractive();
        yesBtn.on('pointerdown', () => { cleanup(); callback(true); });
        yesBtn.on('pointerover', () => yesBtn.setStyle({ backgroundColor: '#ffe57a' }));
        yesBtn.on('pointerout',  () => yesBtn.setStyle({ backgroundColor: '#f4d35e' }));

        // NO / PASS button
        const noBtn = this.add.text(px + 44, py + PH / 2 - 14, 'PASS', {
            fontSize: '10px', fontFamily: 'Arial Black',
            color: '#aaaacc', backgroundColor: '#1c2040',
            padding: { x: 8, y: 4 },
        }).setOrigin(0.5).setDepth(82).setInteractive();
        noBtn.on('pointerdown', () => { cleanup(); callback(false); });
        noBtn.on('pointerover', () => noBtn.setStyle({ color: '#ffffff' }));
        noBtn.on('pointerout',  () => noBtn.setStyle({ color: '#aaaacc' }));
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    _findSlotByIndex(owner, slotIndex) {
        const rows = owner === 'player'
            ? [...this._slotObjects.pl_front, ...this._slotObjects.pl_back]
            : [...this._slotObjects.opp_front, ...this._slotObjects.opp_back];

        return rows.find(s => s.slotIndex === slotIndex) || null;
    }

    _findFirstOpenBackRowSlot(owner) {
        const row = owner === 'player' ? this._slotObjects.pl_back : this._slotObjects.opp_back;
        return row.find(s => !s.cardObject) || null;
    }

    // ── Settings-aware audio helper ───────────────────────────────────────────

    _sfx(key) {
        if (this.cache.audio.exists(key)) {
            this.sound.play(key, { volume: SettingsManager.sfxVolume });
        }
    }

    shutdown() {
        this.bgm?.stop();
    }
}

// ── Shared card catalog — promoted forms are looked up here ──────────────────
export const CARD_CATALOG = {
    // ── LIONS: Eric (Striver chain) ──────────────────────────────────────────
    'eric_lv1': {
        id: 'eric_lv1', name: 'Eric', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 700, defense: 600, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'eric_lv2',
        art_url: 'eric_lv1',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: You can PROMOTE this card.',
    },
    'eric_lv2': {
        id: 'eric_lv2', name: 'Eric Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 1600, defense: 1300, tributeCost: 0, rarity: 2, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'eric_lv3',
        art_url: 'eric_lv2',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: You can PROMOTE this card.',
    },
    'eric_lv3': {
        id: 'eric_lv3', name: 'Eric Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 8, attack: 2600, defense: 2000, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'eric_lv3_draw', promotesTo: null,
        art_url: 'eric_lv3',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: Draw 1 card.\nAt the start of your turn: gains +100 ATK for each other LIONS card you control.',
    },

    // ── LIONS: Maya (Striver chain) ──────────────────────────────────────────
    'maya_lv1': {
        id: 'maya_lv1', name: 'Maya', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 900, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'maya_lv2',
        art_url: 'maya_lv1', ability: 'maya_promote', abilityOnlyPromote: true,
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'If you control another LIONS card with equal or higher Authority, you can PROMOTE this card.',
    },
    'maya_lv2': {
        id: 'maya_lv2', name: 'Maya Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2000, defense: 1500, tributeCost: 0, rarity: 2, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'maya_lv3',
        art_url: 'maya_lv2', ability: 'maya_promote', abilityOnlyPromote: true,
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'At the start of your turn: if you control another LIONS card with equal or higher Authority, you can PROMOTE this card.',
    },
    'maya_lv3': {
        id: 'maya_lv3', name: 'Maya Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2900, defense: 2500, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'maya_lv3_buff', promotesTo: null,
        art_url: 'maya_lv3',
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'Once per turn: Choose 1 other LIONS card. It gains +400 ATK and +400 DEF until end of turn.',
        ability: 'maya_buff',
    },

    // ── LIONS: Brawlers & Heavies ────────────────────────────────────────────
    'pride_runner': {
        id: 'pride_runner', name: 'Pride Runner', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 1000, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'pride_runner_adjacency', promotesTo: null,
        art_url: 'pride_runner',
        flavourText: "One lion hunts. Two lions own the street.",
        effectText: 'While adjacent to another LIONS character, this card gains +400 ATK.',
    },
    'lion_grunt': {
        id: 'lion_grunt', name: 'Lion Grunt', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 700, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'lion_grunt_synergy', promotesTo: null,
        art_url: 'lion_grunt',
        flavourText: "A lone lion prowls. A pack owns the block.",
        effectText: 'If you control another LIONS character, this card gains +300 ATK.',
    },
    'block_enforcer': {
        id: 'block_enforcer', name: 'Block Enforcer', clan: 'iron_saints', cardType: 'gang_member',
        authority: 3, attack: 1300, defense: 1500, tributeCost: 0, rarity: 2, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'block_enforcer_redirect', promotesTo: null,
        art_url: 'block_enforcer',
        flavourText: "We hold the line. You handle the lion.",
        effectText: 'Once per turn, when an allied LIONS would be targeted in a brawl, you may have this card become the target instead.', // redirect is passive/auto
    },
    'goldfang': {
        id: 'goldfang', name: 'Goldfang', clan: 'iron_saints', cardType: 'gang_member',
        authority: 4, attack: 1700, defense: 1400, tributeCost: 0, rarity: 2, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'goldfang_attacker', promotesTo: null,
        art_url: 'goldfang',
        flavourText: "They hide behind defense. I break it, then I break them.",
        effectText: 'If this card attacks a defending character, it gains +500 ATK during that brawl.',
    },
    'pride_lieutenant': {
        id: 'pride_lieutenant', name: 'Pride Lieutenant', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2300, defense: 1900, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_lieutenant_deploy', promotesTo: null,
        art_url: 'pride_lieutenant',
        flavourText: "Strength is nothing without your people.",
        effectText: 'When deployed: One other LIONS card gains +500 ATK until end of turn.',
    },
    'pride_mentor': {
        id: 'pride_mentor', name: 'Pride Mentor', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2100, defense: 1800, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_mentor_draw', promotesTo: null,
        art_url: 'pride_mentor',
        flavourText: "Strength gets respect. Survival earns wisdom.",
        effectText: 'Once per turn, when a LIONS Striver PROMOTES, draw 2 cards.',
    },
    'brutus': {
        id: 'brutus', name: 'Brutus', clan: 'iron_saints', cardType: 'gang_member',
        authority: 8, attack: 2800, defense: 2500, tributeCost: 0, rarity: 4, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'brutus_enter', promotesTo: null,
        art_url: 'brutus',
        flavourText: "Strength leads. Loyalty follows. We finish.",
        effectText: 'When this enters the grid: Choose 1 enemy character; it loses 700 ATK until the end of your opponent\'s next turn.\nWhen this defeats an opponent\'s character: Your next LIONS attacker this turn gains +300 ATK.',
    },

    // ── LIONS: Hunter (Striver chain) ────────────────────────────────────────
    'hunter_lv1': {
        id: 'hunter_lv1', name: 'Hunter', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 800, defense: 400, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv1', promotesTo: null,
        art_url: 'hunter_lv1',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a Downed character: PROMOTE this card.',
    },
    'hunter_lv2': {
        id: 'hunter_lv2', name: 'Hunter Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 1900, defense: 1000, tributeCost: 0, rarity: 3, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv2', promotesTo: null,
        art_url: 'hunter_lv2',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a character: Choose 1 enemy character → Down it.\nWhen this card KOs a Downed character: PROMOTE this card.',
    },
    'hunter_lv3': {
        id: 'hunter_lv3', name: 'Hunter Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2700, defense: 1900, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv3', promotesTo: null,
        art_url: 'hunter_lv3',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a character: Choose 1 enemy character → Down it.\nWhen this card KOs a Downed character: It may attack again this turn.',
    },

    // ── LIONS: Viper (Striver chain) ─────────────────────────────────────────
    'viper_lv1': {
        id: 'viper_lv1', name: 'Viper', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 1100, defense: 600, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv1', promotesTo: null,
        art_url: 'viper_lv1',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card Downs a character: PROMOTE this card.',
    },
    'viper_lv2': {
        id: 'viper_lv2', name: 'Viper Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2000, defense: 1200, tributeCost: 0, rarity: 1, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv2', promotesTo: null,
        art_url: 'viper_lv2',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card attacks: You may move it to an adjacent lane before the Brawl.\nWhen this card Downs a character: PROMOTE this card.',
    },
    'viper_lv3': {
        id: 'viper_lv3', name: 'Viper Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2600, defense: 1800, tributeCost: 0, rarity: 1, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv3', promotesTo: null,
        art_url: 'viper_lv3',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card attacks: You may move it to an adjacent lane before the Brawl.\nWhen this card KOs a character: You may move this card to an adjacent lane.\nWhen this card KOs a Downed character: It may attack again this turn.',
    },

    // ── LIONS: Additional Brawlers & Heavies ─────────────────────────────────
    'debt_collector': {
        id: 'debt_collector', name: 'Debt Collector', clan: 'iron_saints', cardType: 'gang_member',
        authority: 3, attack: 1400, defense: 700, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'debt_collector', promotesTo: null,
        art_url: 'debt_collector',
        flavourText: "Everyone pays. It's just a matter of when.",
        effectText: 'When this card Downs a character by battle: Your opponent discards 1 card.',
    },
    'bulwark': {
        id: 'bulwark', name: 'Bulwark', clan: 'iron_saints', cardType: 'gang_member',
        authority: 6, attack: 2300, defense: 2600, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'bulwark', promotesTo: null,
        art_url: 'bulwark',
        flavourText: "The wall doesn't move. The wall doesn't break.",
        effectText: 'This card cannot be moved by enemy effects.\nWhile this card is in play: Adjacent allies gain +400 DEF.\nWhen this card is attacked: The attacking character loses 300 ATK during that Brawl.',
    },
    'mauler': {
        id: 'mauler', name: 'Mauler', clan: 'iron_saints', cardType: 'gang_member',
        authority: 6, attack: 2300, defense: 2000, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'mauler', promotesTo: null,
        art_url: 'mauler',
        flavourText: "Down doesn't mean done. Until I say it does.",
        effectText: 'This card deals +500 ATK when attacking a Downed character.\nWhen this card KOs a Downed character: All enemy characters in adjacent lanes take -500 DEF this turn.',
    },
    'kingpin': {
        id: 'kingpin', name: 'Kingpin', clan: 'iron_saints', cardType: 'gang_member',
        authority: 4, attack: 1800, defense: 1000, tributeCost: 0, rarity: 4, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'kingpin', promotesTo: null,
        art_url: 'kingpin',
        flavourText: "When they're down, I take everything.",
        effectText: 'While your opponent controls a Downed character: This card gains +400 ATK.',
    },
    'sovereign': {
        id: 'sovereign', name: 'Sovereign', clan: 'iron_saints', cardType: 'gang_member',
        authority: 10, attack: 2900, defense: 1800, tributeCost: 0, rarity: 5, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'sovereign', promotesTo: null,
        art_url: 'sovereign',
        flavourText: "Bow or break.",
        effectText: 'When this card enters play: All enemy characters with 1500 DEF or less become Downed.\nWhile your opponent controls a Downed character: This card gains +600 ATK.',
    },

    // ── LIONS: Leader ────────────────────────────────────────────────────────
    'king_roan': {
        id: 'king_roan', name: 'King Roan', clan: 'iron_saints', cardType: 'leader',
        authority: 10, attack: 3000, defense: 3000, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'king_roan_leader', promotesTo: null,
        art_url: 'king_roan',
        flavourText: "A lion doesn't ask for respect. He earns it. Then he takes more.",
        effectText: 'DORMANT: While Dormant, all LIONS characters you control gain +300 ATK with 2 or more LIONS on field.\nAWAKEN: When you control 4+ LIONS characters OR your total Authority is 10+.',
        awakenCondition: { lions: 4, authorityThreshold: 10 },
    },

    // ── LIONS: Ambush cards ──────────────────────────────────────────────────
    'lion_ambush': {
        id: 'lion_ambush', name: "Lion's Ambush", clan: 'iron_saints', cardType: 'ambush',
        authority: 2, tributeCost: 0, rarity: 2,
        clanTag: 'lion', effectKey: 'lion_ambush',
        art_url: 'lion_ambush',
        effectText: 'Play when an opponent declares an attack. If they attack a LIONS character, that attacker loses 1000 ATK during this brawl.',
    },
    'no_witnesses': {
        id: 'no_witnesses', name: 'No Witnesses', clan: 'iron_saints', cardType: 'ambush',
        authority: 3, tributeCost: 0, rarity: 3,
        clanTag: 'lion', effectKey: 'no_witnesses_ambush',
        art_url: 'no_witnesses',
        effectText: 'When an opponent brawls a LIONS character: Down the attacking character and negate their attack.',
    },
    'kings_test': {
        id: 'kings_test', name: "King's Test", clan: 'iron_saints', cardType: 'ambush',
        authority: 3, tributeCost: 0, rarity: 3,
        clanTag: 'lion', effectKey: 'kings_test',
        art_url: 'kings_test',
        effectText: 'When a LIONS Striver would be destroyed in battle: Negate that destruction. If it survives, you may PROMOTE it at the start of your next turn.',
    },

    // ── LIONS: Hustle cards ──────────────────────────────────────────────────
    'corner_deal': {
        id: 'corner_deal', name: 'Corner Deal', clan: 'iron_saints', cardType: 'hustle',
        authority: 2, tributeCost: 0, rarity: 1,
        clanTag: 'lion', effectKey: 'corner_deal',
        art_url: 'corner_deal',
        effectText: 'Draw 2 cards, then discard 1 card. If you control a Striver, you do not discard.',
    },
    'blood_scent': {
        id: 'blood_scent', name: 'Blood Scent', clan: 'iron_saints', cardType: 'hustle',
        authority: 3, tributeCost: 0, rarity: 2,
        clanTag: 'lion', effectKey: 'blood_scent',
        art_url: 'blood_scent',
        effectText: 'Choose 1 LIONS Striver you control; its PROMOTE condition is treated as fulfilled this turn.',
    },
    'lion_rescue': {
        id: 'lion_rescue', name: 'Lion Rescue', clan: 'iron_saints', cardType: 'hustle',
        authority: 2, tributeCost: 0, rarity: 1,
        clanTag: 'lion', effectKey: 'lion_rescue',
        art_url: 'lion_rescue',
        effectText: 'Choose 1 Downed LIONS character; Stand it.',
    },
};

// ── Test deck factory (used when no real deck is passed) ──────────────────────
function _buildTestDeck(owner) {
    const base = Object.values(CARD_CATALOG).filter(c => {
        if (c.cardType === 'leader') return false;      // leaders go in hideout
        if (c.cardType === 'gang_member') return c.level === 1;
        return true;
    });
    const deck = [];
    for (let i = 0; i < 5; i++) deck.push(...base.map(c => ({ ...c })));
    return Phaser.Utils.Array.Shuffle(deck).slice(0, 20);
}

// ── Test hideout (promoted forms + leader available for Striver/Leader play) ──
function _buildTestHideout() {
    return [
        { ...CARD_CATALOG['eric_lv2'] },
        { ...CARD_CATALOG['eric_lv2'] },
        { ...CARD_CATALOG['eric_lv3'] },
        { ...CARD_CATALOG['maya_lv2'] },
        { ...CARD_CATALOG['maya_lv2'] },
        { ...CARD_CATALOG['maya_lv3'] },
        { ...CARD_CATALOG['king_roan'] },
    ];
}

// ── Character subtype classifier ─────────────────────────────────────────────
// 'heavy' = boss (authority ≥ 5), 'striver' = promoter (has promotesTo or level 1+promotesTo),
// 'brawler' = everything else that is a gang_member.
export function _charSubtype(card) {
    if (!card || card.cardType !== 'gang_member') return null;
    if (card.subtype) return card.subtype;
    if (card.promotesTo) return 'striver';
    if ((card.authority || 0) >= 5) return 'heavy';
    return 'brawler';
}
