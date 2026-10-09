import { RARITY_LABEL, RARITY_COLOR } from '../cards/RarityConfig.js';
import { attachHoldZoom, showCardZoom } from '../utils/CardZoom.js';
import { apiFetch } from '../utils/Platform.js';
import { VIEW_H, VIEW_TOP, VIEW_BOTTOM, EXTRA_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

const PACK_META = {
    lion_pride:    { label: 'Lion Clan',     color: 0xc77a00, textColor: '#ffd166', imageKey: 'lion_booster' },
    viper_clan:    { label: 'Viper Clan',    color: 0x2e7d32, textColor: '#a5d6a7', imageKey: 'viper_booster' },
};

const RARITY_LABELS = Object.fromEntries(Object.entries(RARITY_LABEL).map(([k, v]) => [k, v.toUpperCase()]));
const RARITY_COLORS = RARITY_COLOR;

export class ShopScene extends Phaser.Scene {
    constructor() {
        super('ShopScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.6);

        this._buildHeader();
        this._buildPacksPanel();
        this._buildContrabandButton();
        this._buildBackButton();
    }

    _buildHeader() {
        this.add.text(W / 2, VIEW_TOP + 26, 'CARD PACKS', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);

        this._karatText = this.add.text(W / 2, VIEW_TOP + 48, '', {
            fontSize: '11px', color: '#f4d35e',
        }).setOrigin(0.5);
        this._refreshKarat();
    }

    _buildPacksPanel() {
        const packs   = Object.entries(PACK_META);
        const panelW  = W - 40;
        // Cap card size so two packs don't fill the entire panel
        const cardW   = Math.min(140 + Math.round(EXTRA_H * 0.4), Math.floor(panelW / packs.length) - 8);
        const spacing = Math.min(220, panelW / packs.length);
        const cardH   = Math.round(cardW * 1.6);   // maintain ~booster aspect ratio
        const startX  = W / 2 - ((packs.length - 1) * spacing) / 2;

        packs.forEach(([packId, meta], i) => {
            const x = startX + i * spacing;
            this._buildPackCard(packId, meta, x, cardW, cardH);
        });
    }

    _buildContrabandButton() {
        const x = W - 90, y = VIEW_BOTTOM - 56;
        const w = 160, h = 38;
        const bg = this.add.rectangle(x, y, w, h, 0x6a0d8a)
            .setStrokeStyle(2, 0xe040fb).setInteractive({ useHandCursor: true });
        this.add.text(x, y, 'PURCHASE CONTRABAND', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(1);
        bg.on('pointerdown', () => bg.setAlpha(0.6));
        bg.on('pointerout',  () => bg.setAlpha(1));
        bg.on('pointerup',   () => { bg.setAlpha(1); this.scene.start('ContrabandScene'); });
    }

    _buildPackCard(packId, meta, x, cardW = 120, cardH = 192) {
        const y        = H / 2 - 10;
        const hasImage = meta.imageKey && this.textures.exists(meta.imageKey);
        const btnW     = Math.min(cardW - 4, 130);

        if (hasImage) {
            // Full booster pack image — fills the whole card slot
            this.add.image(x, y, meta.imageKey).setDisplaySize(cardW, cardH);
            // Gold glow border
            this.add.rectangle(x, y, cardW + 4, cardH + 4, 0x000000, 0)
                .setStrokeStyle(2, 0xffd700, 0.9);
        } else {
            // Fallback colored card
            this.add.rectangle(x, y, cardW, cardH, meta.color)
                .setStrokeStyle(2, 0xffffff, 0.85);

            this.add.text(x, y - cardH / 2 + 12, meta.label.toUpperCase(), {
                fontSize: '8px', fontFamily: 'Arial Black', color: meta.textColor,
            }).setOrigin(0.5);

            this.add.text(x, y - cardH / 2 + 26, '3 cards · 1 Rare min', {
                fontSize: '6px', color: '#cccccc',
            }).setOrigin(0.5);
        }

        // Buy buttons: Karat (left) + Contraband (right) below the art
        const halfW = Math.floor((btnW - 4) / 2);
        const btnY  = y + cardH / 2 + 18;

        const karatBtn = this.add.rectangle(x - halfW / 2 - 2, btnY, halfW, 28, 0x1a1a2e)
            .setStrokeStyle(1, 0xf4d35e)
            .setInteractive({ useHandCursor: true });
        this.add.text(x - halfW / 2 - 2, btnY, '200K', {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(1);
        karatBtn.on('pointerdown', () => karatBtn.setAlpha(0.6));
        karatBtn.on('pointerout',  () => karatBtn.setAlpha(1));
        karatBtn.on('pointerup',   () => { karatBtn.setAlpha(1); this._buyAndOpen(packId, meta, 'karat'); });

        const cbBtn = this.add.rectangle(x + halfW / 2 + 2, btnY, halfW, 28, 0x2d0040)
            .setStrokeStyle(1, 0xe040fb)
            .setInteractive({ useHandCursor: true });
        this.add.text(x + halfW / 2 + 2, btnY, '100 CB', {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#e040fb',
        }).setOrigin(0.5).setDepth(1);
        cbBtn.on('pointerdown', () => cbBtn.setAlpha(0.6));
        cbBtn.on('pointerout',  () => cbBtn.setAlpha(1));
        cbBtn.on('pointerup',   () => { cbBtn.setAlpha(1); this._buyAndOpen(packId, meta, 'contraband'); });

        // Hover shimmer for image packs (visual only — no click-through buy)
        if (hasImage) {
            const shimmer = this.add.rectangle(x, y, cardW, cardH, 0xffd700, 0);
            this.tweens.add({ targets: shimmer, alpha: { from: 0, to: 0.08 },
                yoyo: true, repeat: -1, duration: 1400 });
        }
    }

    _buyAndOpen(packId, meta, currency = 'karat') {

        apiFetch('/api/shop/open', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ packType: packId, currency }),
        })
        .then(r => r.json().then(d => ({ ok: r.ok, data: d })))
        .then(({ ok, data }) => {
            if (!ok) { this._showToast(data.error || 'Purchase failed', '#e63946'); return; }
            this._karatText.setText(`Karat: ${data.newKarat}K`);
            // Keep registry in sync so other scenes show fresh balances
            const player = this.registry.get('player') || {};
            player.karat      = data.newKarat;
            player.contraband = data.newContraband;
            this.registry.set('player', player);
            this._playRevealAnimation(data.cardsReceived, meta);
        })
        .catch(() => this._showToast('Network error', '#e63946'));
    }

    _playRevealAnimation(cards, meta) {
        // Hide every existing shop GameObject so only the title-screen
        // VideoBackgroundScene shows behind the reveal.
        const hidden = [];
        for (const obj of this.children.list) {
            if (obj.visible !== false) {
                hidden.push(obj);
                obj.setVisible(false);
            }
        }

        const layer = this.add.container(0, 0).setDepth(80);
        const all   = [];
        const reg   = o => { all.push(o); return o; };

        // Restore the shop UI when the reveal cleans up
        all.__restore = () => hidden.forEach(o => o?.setVisible?.(true));

        // ── Stage 1: subtle vignette so cards pop against the menu video ─────
        const overlay = reg(this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0)
            .setDepth(80).setInteractive());
        this.tweens.add({ targets: overlay, alpha: 0.55, duration: 250 });

        // Title at top stays visible through the whole reveal
        const title = reg(this.add.text(W / 2, 28,
            `OPENING — ${(meta.label || '').toUpperCase()}`, {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 4,
        }).setOrigin(0.5).setDepth(99).setAlpha(0));
        this.tweens.add({ targets: title, alpha: 1, duration: 350, delay: 150 });

        // ── Stage 2: Booster pack slides in, shakes, tears ───────────────────
        const packKey = meta.imageKey || null;
        const packCX  = W / 2, packCY = H / 2;
        const packW   = 120, packH  = 190;

        let packImg;
        if (packKey && this.textures.exists(packKey)) {
            packImg = reg(this.add.image(packCX, H + packH, packKey)
                .setDisplaySize(packW, packH).setDepth(85));
        } else {
            packImg = reg(this.add.rectangle(packCX, H + packH, packW, packH, meta.color ?? 0x333366)
                .setStrokeStyle(2, 0xffffff, 0.8).setDepth(85));
        }

        // Slide up to centre
        this.tweens.add({
            targets: packImg, y: packCY,
            duration: 500, ease: 'Back.Out',
            onComplete: () => {
                // Shake
                this.tweens.add({
                    targets: packImg, x: packCX + 6, duration: 40,
                    yoyo: true, repeat: 5,
                    onComplete: () => {
                        this._tearPack(packImg, packCX, packCY, packW, packH, layer, reg, () => {
                            this._flipCardsReveal(cards, meta, layer, reg, overlay, all);
                        });
                    },
                });
            },
        });
    }

    _tearPack(packImg, cx, cy, pw, ph, layer, reg, onDone) {
        // Flash + rip lines
        const flash = reg(this.add.rectangle(cx, cy, pw + 20, ph + 20, 0xffffff, 0).setDepth(86));
        this.tweens.add({ targets: flash, alpha: 0.7, duration: 60, yoyo: true,
            onComplete: () => flash.destroy() });

        // Tear effect: top half flies up, bottom half flies down
        const topMask  = this.add.rectangle(cx, cy - ph / 4, pw, ph / 2, 0x000000, 0);
        const botMask  = this.add.rectangle(cx, cy + ph / 4, pw, ph / 2, 0x000000, 0);

        this.cameras.main.shake(180, 0.012);

        // Scatter pack image off screen
        this.tweens.add({ targets: packImg, y: cy - 160, alpha: 0, duration: 340, ease: 'Cubic.In' });

        // Burst rays from tear point
        const colors = [0xffd700, 0xff9800, 0xffffff];
        for (let i = 0; i < 12; i++) {
            const angle  = (i / 12) * Math.PI * 2;
            const dist   = 50 + Math.random() * 30;
            const ray    = reg(this.add.rectangle(
                cx + Math.cos(angle) * dist * 0.3,
                cy + Math.sin(angle) * dist * 0.3,
                dist * 0.8, 4 + Math.random() * 4,
                colors[i % colors.length], 0.9,
            ).setDepth(87).setRotation(angle));
            this.tweens.add({ targets: ray, scaleX: 1.6, alpha: 0, duration: 380, ease: 'Power2',
                onComplete: () => ray.destroy() });
        }

        this.time.delayedCall(360, () => onDone?.());
    }

    _flipCardsReveal(cards, meta, layer, reg, overlay, all) {
        const count  = cards.length;
        const CARD_W = 140, CARD_H = 200;
        const gap    = Math.min(170, (W - 60) / count);
        const startX = W / 2 - ((count - 1) * gap) / 2;
        const cardY  = H / 2 - 8;

        // Sort: show commons first, legendaries last (escalating drama)
        const sorted = [...cards].sort((a, b) => (a.rarity ?? 1) - (b.rarity ?? 1));

        sorted.forEach((card, i) => {
            const x = startX + i * gap;
            this.time.delayedCall(i * 420, () => {
                this._flipOneCard(card, x, cardY, CARD_W, CARD_H, reg, overlay, all);
            });
        });

        // After the last card flips, show post-reveal action buttons.
        // Account for per-rarity suspense on the highest-rarity card in the pack.
        const maxRarity   = sorted.reduce((m, c) => Math.max(m, c.rarity ?? 1), 1);
        const suspenseBuf = maxRarity >= 5 ? 1500 : maxRarity >= 4 ? 800 : 200;
        const totalDelay  = count * 420 + 700 + suspenseBuf;
        this.time.delayedCall(totalDelay, () => {
            this._buildPostRevealButtons(reg, all);
        });
    }

    _transitionToScene(sceneKey) {
        // Fade the entire scene to black, then start the next one.
        const fader = this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0)
            .setDepth(9999);
        this.tweens.add({
            targets: fader, alpha: 1, duration: 260, ease: 'Cubic.In',
            onComplete: () => this.scene.start(sceneKey),
        });
    }

    _buildPostRevealButtons(reg, all) {
        const fadeAndCleanup = (after) => {
            // Smooth fade-out of every reveal object, then destroy + restore shop
            const targets = all.filter(o => o && o.scene);
            this.tweens.add({
                targets, alpha: 0, duration: 260, ease: 'Cubic.In',
                onComplete: () => {
                    all.forEach(o => o?.destroy?.());
                    all.__restore?.();
                    after?.();
                },
            });
        };
        const btnY = H - 40;

        const continueBtn = reg(this.add.rectangle(W / 2 - 90, btnY, 160, 36, 0x1a1a2e)
            .setStrokeStyle(2, 0xf4d35e).setDepth(99).setInteractive({ useHandCursor: true })
            .setAlpha(0));
        const continueTxt = reg(this.add.text(W / 2 - 90, btnY, 'CONTINUE', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(100).setAlpha(0));
        continueBtn.on('pointerdown', () => continueBtn.setAlpha(0.6));
        continueBtn.on('pointerout',  () => continueBtn.setAlpha(1));
        continueBtn.on('pointerup',   () => fadeAndCleanup());

        const deckBtn = reg(this.add.rectangle(W / 2 + 90, btnY, 180, 36, 0x2d0040)
            .setStrokeStyle(2, 0xe040fb).setDepth(99).setInteractive({ useHandCursor: true })
            .setAlpha(0));
        const deckTxt = reg(this.add.text(W / 2 + 90, btnY, 'GO TO DECK EDITOR', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#e040fb',
        }).setOrigin(0.5).setDepth(100).setAlpha(0));
        deckBtn.on('pointerdown', () => deckBtn.setAlpha(0.6));
        deckBtn.on('pointerout',  () => deckBtn.setAlpha(1));
        deckBtn.on('pointerup',   () => fadeAndCleanup(() => this._transitionToScene('DeckBuilderScene')));

        this.tweens.add({
            targets: [continueBtn, continueTxt, deckBtn, deckTxt],
            alpha: 1, duration: 300,
        });
    }

    _flipOneCard(card, x, y, cw, ch, reg, overlay, all) {
        const rarityHex = parseInt((RARITY_COLORS[card.rarity] ?? '#aaaaaa').replace('#', ''), 16);
        const isLegend  = card.rarity >= 5;
        const isEpic    = card.rarity >= 4;

        // Rarity-coloured glow behind card
        const glow = reg(this.add.rectangle(x, y, cw + 12, ch + 12, rarityHex, 0).setDepth(87));
        this.tweens.add({ targets: glow, alpha: isLegend ? 0.6 : isEpic ? 0.4 : 0.25,
            duration: 300 });

        // Card back (starts visible, flips to front).
        // Uses the loaded `card_back` texture if available; otherwise a plain
        // blank dark rectangle so the back side never shows placeholder art.
        let back;
        if (this.textures.exists('card_back')) {
            back = reg(this.add.image(x, y, 'card_back').setDepth(88));
            back.setDisplaySize(cw, ch);
        } else {
            back = reg(this.add.rectangle(x, y, cw, ch, 0x0d0d18)
                .setStrokeStyle(2, 0x222233).setDepth(88));
        }

        // Fly in from above
        back.setY(y - 180).setAlpha(0);
        this.tweens.add({ targets: back, y, alpha: 1, duration: 280, ease: 'Back.Out',
            onComplete: () => {
                // Suspense build: vertical light beam from behind the card.
                // Higher rarity = brighter & longer hesitation before flip.
                const beamColor = isLegend ? 0xff6b35 : isEpic ? 0xffd700 : rarityHex;
                const beam = reg(this.add.rectangle(x, y, isLegend ? 28 : isEpic ? 18 : 10, H, beamColor, 0)
                    .setDepth(86));
                this.tweens.add({ targets: beam, alpha: isLegend ? 0.85 : isEpic ? 0.55 : 0.3,
                    duration: 220, yoyo: true, hold: isLegend ? 700 : isEpic ? 320 : 60,
                    onComplete: () => beam.destroy() });

                // Side rays for epic+ — diagonal beams converging on the card
                if (isEpic) {
                    for (let r = 0; r < (isLegend ? 8 : 4); r++) {
                        const ang = (r / (isLegend ? 8 : 4)) * Math.PI;
                        const ray = reg(this.add.rectangle(x, y, 6, 360, beamColor, 0)
                            .setDepth(86).setRotation(ang));
                        this.tweens.add({ targets: ray, alpha: 0.55,
                            duration: 220, yoyo: true, hold: isLegend ? 600 : 240,
                            onComplete: () => ray.destroy() });
                    }
                }

                // Suspense delay before the actual flip.
                const suspenseMs = isLegend ? 850 : isEpic ? 420 : 80;

                // Fakeout: legendary cards "almost" flip then snap back before
                // committing — squash to ~70% width then rebound.
                const flipFn = () => this.tweens.add({
                    targets: back, scaleX: 0, duration: 140, ease: 'Linear',
                    onComplete: () => {
                        back.destroy();
                        const artKey = card.cardId ?? card.id ?? null;
                        let front;
                        if (this.textures.exists(artKey)) {
                            front = reg(this.add.image(x, y, artKey).setDepth(88));
                            front.setDisplaySize(cw, ch);
                        } else {
                            front = reg(this.add.rectangle(x, y, cw, ch, 0x0d1020)
                                .setStrokeStyle(2, rarityHex).setDepth(88));
                        }
                        // Capture the scale set by setDisplaySize so the tween
                        // can restore it (setScale(0,1) below would otherwise
                        // overwrite it and the tween would scale to native size).
                        const finalSX = front.scaleX;
                        const finalSY = front.scaleY;
                        front.setScale(0, finalSY);

                        const border = reg(this.add.rectangle(x, y, cw + 2, ch + 2, 0x000000, 0)
                            .setStrokeStyle(2, rarityHex, 0.9).setDepth(89).setScale(0, 1));

                        this.tweens.add({ targets: front,  scaleX: finalSX, duration: 160, ease: 'Back.Out' });
                        this.tweens.add({ targets: border, scaleX: 1,       duration: 160, ease: 'Back.Out' });

                        // Name + rarity label
                        const nameTxt = reg(this.add.text(x, y + ch / 2 + 8, card.name, {
                            fontSize: '7px', fontFamily: 'Arial Black',
                            color: RARITY_COLORS[card.rarity] ?? '#aaaaaa',
                            wordWrap: { width: cw }, align: 'center',
                        }).setOrigin(0.5).setDepth(90).setAlpha(0));
                        const rarTxt = reg(this.add.text(x, y + ch / 2 + 20,
                            RARITY_LABELS[card.rarity] ?? 'Common', {
                            fontSize: '6px', color: RARITY_COLORS[card.rarity] ?? '#aaaaaa',
                        }).setOrigin(0.5).setDepth(90).setAlpha(0));
                        this.tweens.add({ targets: [nameTxt, rarTxt], alpha: 1, duration: 200, delay: 100 });

                        // Legendary: rainbow shimmer pulse
                        if (isLegend) {
                            this._legendaryShimmer(glow, rarityHex);
                        }

                        // Camera shake escalates with rarity
                        if (card.rarity >= 3) this.cameras.main.shake(120 * (card.rarity - 2), 0.006 * (card.rarity - 1));

                        // Tap individual card to zoom
                        if (front.setInteractive) {
                            front.setInteractive();
                            front.cardZoomData = { ...card, art_url: card.art_url ?? card.cardId ?? card.id };
                            front.on('pointerup', () => {
                                showCardZoom(this, {
                                    ...card,
                                    art_url: card.art_url ?? card.cardId ?? card.id,
                                });
                            });
                        }
                    },
                });

                // Trigger the flip after the suspense, with a legendary fakeout.
                if (isLegend) {
                    this.time.delayedCall(suspenseMs - 350, () => {
                        // Squash partially as if about to flip…
                        this.tweens.add({ targets: back, scaleX: 0.7, duration: 140, ease: 'Sine.easeIn',
                            onComplete: () => {
                                // …snap back (fakeout)…
                                this.tweens.add({ targets: back, scaleX: 1.05, duration: 130, ease: 'Back.Out',
                                    onComplete: () => {
                                        this.cameras.main.shake(80, 0.005);
                                        this.tweens.add({ targets: back, scaleX: 1.0, duration: 90 });
                                        // …then commit to the real flip.
                                        this.time.delayedCall(180, flipFn);
                                    },
                                });
                            },
                        });
                    });
                } else {
                    this.time.delayedCall(suspenseMs, flipFn);
                }
            },
        });
    }

    _legendaryShimmer(glow, baseColor) {
        const shimmerColors = [0xffd700, 0xff6b35, 0xc77dff, 0x4cc9f0, 0xffd700];
        let ci = 0;
        const cycle = () => {
            if (!glow.active) return;
            this.tweens.add({
                targets: glow, alpha: 0.75, duration: 200,
                onComplete: () => {
                    if (!glow.active) return;
                    glow.setFillStyle(shimmerColors[ci % shimmerColors.length]);
                    ci++;
                    this.tweens.add({ targets: glow, alpha: 0.4, duration: 200,
                        onComplete: cycle });
                },
            });
        };
        cycle();
    }

    _buildBackButton() {
        const btn = this.add.rectangle(40, VIEW_BOTTOM - 24, 72, 28, 0x333355)
            .setStrokeStyle(1, 0xffffff).setInteractive({ useHandCursor: true });
        this.add.text(40, VIEW_BOTTOM - 24, '← BACK', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#fff',
        }).setOrigin(0.5).setDepth(1);
        btn.on('pointerup', () => this.scene.start('MainMenuScene'));
    }

    _refreshKarat() {
        const player = this.registry.get('player');
        this._karatText.setText(`Karat: ${player?.karat ?? '—'}K`);
    }

    _showToast(msg, color = '#e63946') {
        const t = this.add.text(W / 2, VIEW_BOTTOM - 24, msg, {
            fontSize: '13px', color, backgroundColor: '#000000',
            padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(100);
        this.tweens.add({ targets: t, alpha: 0, delay: 2000, duration: 500,
            onComplete: () => t.destroy() });
    }
}
