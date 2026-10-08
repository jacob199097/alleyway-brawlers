import { showCardZoom } from '../utils/CardZoom.js';
import { apiFetch } from '../utils/Platform.js';

const W = 844;
const H = 390;

export class PostMatchScene extends Phaser.Scene {
    constructor() { super('PostMatchScene'); }

    init(data) { this._data = data || {}; }

    create() {
        const d      = this._data;
        const isWin  = d.result === 'win';
        const accent = isWin ? 0xf4d35e : 0xe63946;

        // Background: blurred snapshot of the duel we just played. Falls back
        // to a dark solid colour if the snapshot wasn't supplied.
        if (d.snapshotKey && this.textures.exists(d.snapshotKey)) {
            const bg = this.add.image(W / 2, H / 2, d.snapshotKey)
                .setDisplaySize(W, H).setDepth(0);
            try { bg.postFX?.addBlur?.(0, 2, 2, 1.0); } catch (_) {}
            // Slight darken so the foreground panels stay readable
            this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.35).setDepth(1);
        } else {
            this.cameras.main.setBackgroundColor(0x0a0a18);
        }

        // ── Victory / Defeat image — centered, compact (not full-screen) ─────
        const imgKey = isWin ? 'victory_screen' : 'defeat_screen';
        const IMG_W = Math.round(W * 0.48);   // ~405px — leaves board visible on sides
        const IMG_H = Math.round(IMG_W * 1024 / 1536);  // preserve 3:2 aspect ≈ 270px
        const imgY  = IMG_H / 2 + 4;          // vertically near top, a few px padding
        if (this.textures.exists(imgKey)) {
            this.add.image(W / 2, imgY, imgKey)
                .setDisplaySize(IMG_W, IMG_H)
                .setDepth(2);
        } else {
            // Fallback: large styled text
            this.add.text(W / 2, imgY, isWin ? 'VICTORY' : 'DEFEAT', {
                fontSize: '48px', fontFamily: 'Arial Black',
                color: isWin ? '#f4d35e' : '#e63946',
                stroke: '#000000', strokeThickness: 8,
            }).setOrigin(0.5).setDepth(2);
        }

        // ── Gradient veil under image so stat panels stay readable ────────────
        const veil = this.add.graphics().setDepth(3);
        veil.fillGradientStyle(0x000000, 0x000000, 0x000000, 0x000000, 0, 0, 0.75, 0.75);
        veil.fillRect(0, H * 0.42, W, H * 0.58);

        // ── Stat panels (left) and MVP (right) ────────────────────────────────
        this._buildOutcomePanel(d, isWin, accent);
        this._buildMvpPanel(d.mvpCard);

        // PLAY AGAIN / MAIN MENU buttons are baked into the victory/defeat
        // image artwork — make those regions tappable instead of drawing
        // separate buttons over the top.
        this._wireImageButtons(isWin);

        // ── Fade in ───────────────────────────────────────────────────────────
        const fadeVeil = this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 1).setDepth(200);
        this.tweens.add({ targets: fadeVeil, alpha: 0, duration: 700, ease: 'Power2',
            onComplete: () => fadeVeil.destroy() });

        // ── Rewards API call ──────────────────────────────────────────────────
        this._submitMatchResult();
    }

    // ── Outcome panel (lower-left) ────────────────────────────────────────────

    _buildOutcomePanel(d, isWin, accent) {
        const PX = 10, PY = H * 0.44, PW = 210, PH = H * 0.5 - 38;
        const cx = PX + PW / 2;

        this.add.rectangle(cx, PY + PH / 2, PW, PH, 0x060610, 0.88)
            .setStrokeStyle(1, accent, 0.9).setDepth(10);

        const statFont = { fontSize: '7px', color: '#888899', fontFamily: 'Verdana, sans-serif' };
        const valFont  = { fontSize: '11px', fontFamily: 'Arial Black', color: '#ffffff' };

        let ry = PY + 14;
        const row = (label, value, color = '#ffffff') => {
            this.add.text(cx, ry, label, { ...statFont }).setOrigin(0.5, 0.5).setDepth(11);
            ry += 12;
            this.add.text(cx, ry, String(value), { ...valFont, color }).setOrigin(0.5, 0.5).setDepth(11);
            ry += 18;
        };

        const reasonStr = isWin
            ? "Opponent's Morale reduced to 0"
            : (d.reason === 'timeout' ? 'Time ran out' : 'Your Morale reduced to 0');
        this.add.text(cx, ry, reasonStr, {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#ffffff',
            align: 'center', wordWrap: { width: PW - 20 },
        }).setOrigin(0.5, 0).setDepth(11);
        ry += 22;

        this.add.rectangle(cx, ry, PW - 16, 1, 0x4cc9f0, 0.3).setDepth(11); ry += 8;

        row('YOUR MORALE', d.playerMorale ?? '—', isWin ? '#4cc9f0' : '#e63946');
        row('OPP MORALE',  d.opponentMorale ?? '—', isWin ? '#e63946' : '#4cc9f0');
        row('TURNS PLAYED', d.turns ?? '—');

        this.add.rectangle(cx, ry, PW - 16, 1, 0x4cc9f0, 0.3).setDepth(11); ry += 8;

        // XP bar
        this.add.text(cx, ry, 'XP EARNED', statFont).setOrigin(0.5, 0.5).setDepth(11); ry += 12;
        this._xpBarBg = this.add.rectangle(cx, ry, PW - 28, 8, 0x1a1a3a).setOrigin(0.5, 0.5).setDepth(11);
        this._xpBar   = this.add.rectangle(cx - (PW - 28) / 2, ry, 0, 8, 0x4cc9f0).setOrigin(0, 0.5).setDepth(12);
        this._xpLabel = this.add.text(cx, ry + 10, '...', {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5, 0).setDepth(12);
        ry += 24;

        this._rewardText = this.add.text(cx, ry, '', {
            fontSize: '8px', fontFamily: 'Arial Black',
            color: '#f4d35e', align: 'center', lineSpacing: 3,
        }).setOrigin(0.5, 0).setDepth(11);
    }

    // ── MVP panel (lower-right) ───────────────────────────────────────────────

    _buildMvpPanel(mvp) {
        const PX = W - 224, PY = H * 0.44, PW = 210, PH = H * 0.5 - 38;
        const cx = PX + PW / 2;

        this.add.rectangle(cx, PY + PH / 2, PW, PH, 0x060610, 0.88)
            .setStrokeStyle(1, 0xf4d35e, 0.9).setDepth(10);

        this.add.text(cx, PY + 12, 'MVP BRAWLER', {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#f4d35e', letterSpacing: 2,
        }).setOrigin(0.5, 0.5).setDepth(11);
        this.add.rectangle(cx, PY + 22, PW - 16, 1, 0xf4d35e, 0.5).setDepth(11);

        if (!mvp) {
            this.add.text(cx, PY + PH / 2, 'No data', {
                fontSize: '9px', color: '#555577',
            }).setOrigin(0.5, 0.5).setDepth(11);
            return;
        }

        const CW = 72, CH = 100;
        const cardX = cx - 36, cardY = PY + 32 + CH / 2;

        if (mvp.artKey && this.textures.exists(mvp.artKey)) {
            const img = this.add.image(cardX, cardY, mvp.artKey)
                .setDisplaySize(CW, CH).setDepth(12)
                .setInteractive({ useHandCursor: true });
            img.on('pointerup', () => showCardZoom(this, { ...mvp, id: mvp.artKey, art_url: mvp.artKey }));
        } else {
            this.add.rectangle(cardX, cardY, CW, CH, 0x1a1a2e)
                .setStrokeStyle(1, 0xb388c9, 0.9).setDepth(12);
            this.add.text(cardX, cardY, mvp.name, {
                fontSize: '7px', fontFamily: 'Arial Black', color: '#ffffff',
                wordWrap: { width: CW - 6 }, align: 'center',
            }).setOrigin(0.5, 0.5).setDepth(13);
        }

        this.add.rectangle(cardX, cardY, CW + 4, CH + 4, 0x000000, 0)
            .setStrokeStyle(2, 0xf4d35e, 0.85).setDepth(13);

        const infoX = cx + 32;
        const infoY = PY + 32;

        const ownerLabel = mvp.owner === 'player' ? 'YOUR CARD' : 'THEIR CARD';
        const ownerColor = mvp.owner === 'player' ? '#4cc9f0' : '#e63946';

        this.add.text(infoX, infoY, ownerLabel, {
            fontSize: '6px', fontFamily: 'Arial Black', color: ownerColor,
        }).setOrigin(0.5, 0).setDepth(12);

        this.add.text(infoX, infoY + 14, mvp.name.toUpperCase(), {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#ffd86b',
            wordWrap: { width: 90 }, align: 'center',
        }).setOrigin(0.5, 0).setDepth(12);

        this.add.text(infoX, infoY + 34, `${(mvp.totalDamage || 0).toLocaleString()}\nMORALE DEALT`, {
            fontSize: '7px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            fontStyle: 'bold', color: '#ffffff', stroke: '#000000', strokeThickness: 2,
            align: 'center', lineSpacing: 2,
        }).setOrigin(0.5, 0).setDepth(12);

        if (mvp.owner === 'player' && this._data.playerRank) {
            this.add.text(infoX, infoY + 62, `🏅 ${this._data.playerRank.replace(/_/g, ' ').toUpperCase()}`, {
                fontSize: '7px', fontFamily: 'Arial Black', color: '#f4d35e',
                wordWrap: { width: 90 }, align: 'center',
            }).setOrigin(0.5, 0).setDepth(12);
        }
    }

    // ── Bottom navigation buttons ─────────────────────────────────────────────

    _wireImageButtons(isWin) {
        // The victory/defeat artwork bakes its own PLAY AGAIN / MAIN MENU buttons
        // along the bottom edge. We overlay invisible hit-zones so taps in those
        // regions navigate appropriately.
        const IMG_W = Math.round(W * 0.48);
        const IMG_H = Math.round(IMG_W * 1024 / 1536);
        const imgCX = W / 2;
        const imgTopY = 4;
        // Buttons are along the bottom ~22% of the artwork, split left/right.
        const zoneH  = Math.round(IMG_H * 0.22);
        const zoneY  = imgTopY + IMG_H - zoneH / 2;
        const halfW  = IMG_W / 2;

        const playZone = this.add.rectangle(imgCX - halfW / 2, zoneY, halfW, zoneH, 0x000000, 0)
            .setDepth(50).setInteractive({ useHandCursor: true });
        const menuZone = this.add.rectangle(imgCX + halfW / 2, zoneY, halfW, zoneH, 0x000000, 0)
            .setDepth(50).setInteractive({ useHandCursor: true });

        playZone.on('pointerup', () => this._navigate('FightModeScene'));
        menuZone.on('pointerup', () => this._navigate('MainMenuScene'));
    }

    _makeBtn(cx, cy, bw, bh, label, fill, stroke, textColor, cb) {
        const bg = this.add.rectangle(cx, cy, bw, bh, fill)
            .setStrokeStyle(2, stroke, 0.9).setDepth(20).setInteractive({ useHandCursor: true });
        this.add.text(cx, cy, label, {
            fontSize: '10px', fontFamily: 'Arial Black', color: textColor ?? '#ffffff',
        }).setOrigin(0.5).setDepth(21);
        bg.on('pointerover',  () => bg.setAlpha(0.8));
        bg.on('pointerout',   () => bg.setAlpha(1));
        bg.on('pointerdown',  () => bg.setAlpha(0.6));
        bg.on('pointerup',    () => { bg.setAlpha(1); cb?.(); });
    }

    // ── Navigate away ─────────────────────────────────────────────────────────

    _navigate(sceneName) {
        this.cameras.main.fadeOut(350, 0, 0, 0);
        this.time.delayedCall(380, () => {
            if (this.scene.get('DuelScene')?.scene.isPaused() ||
                this.scene.get('DuelScene')?.scene.isActive()) {
                this.scene.stop('DuelScene');
            }
            this.scene.stop();
            this.scene.start(sceneName);
        });
    }

    // ── Rewards API call ──────────────────────────────────────────────────────

    _submitMatchResult() {
        const token = this.registry.get('token');
        const d     = this._data;

        // Multiplayer rewards were already applied by the server and arrive with the match result
        if (d.rewards) { this._showRewards(d.rewards); return; }

        if (!token || !d.soloMatchId) {
            this._animateXpBar(0, 0);
            this._rewardText?.setText('Rewards not recorded');
            return;
        }

        apiFetch('/api/match/complete', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                matchId:        d.soloMatchId,
                result:         d.result,
                cardsPlayed:    d.cardsPlayed,
                playerMorale:   d.playerMorale,
                opponentMorale: d.opponentMorale,
                turns:          d.turns,
            }),
        })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data?.rewards) {
                this._animateXpBar(0, 0);
                this._rewardText?.setText(data?.error || 'Rewards not recorded');
                return;
            }
            this._showRewards(data.rewards);
        })
        .catch(() => {
            this._animateXpBar(0, 0);
            this._rewardText?.setText('Network error — rewards not recorded');
        });
    }

    _showRewards(r) {
        this._animateXpBar(r.xpEarned ?? 0, r.xpPercent ?? 0);

        const lines = [`+${r.karatEarned ?? 0} Karat`];
        if (r.dailyCapReached) lines.push('Daily reward limit reached');
        if (r.firstWinBonus)   lines.push('★ First Win Bonus!');
        if (r.leveledUp)       lines.push(`→ Level ${r.newLevel}!`);
        this._rewardText?.setText(lines.join('\n'));

        if (r.rankChanged) this._showRankUp(r.newRank);
    }

    // ── Animated XP bar fill ──────────────────────────────────────────────────

    _animateXpBar(xpEarned, pct) {
        const maxW = 182;
        const targetW = Math.max(4, Math.round(maxW * Math.min(1, pct)));
        this._xpLabel?.setText(`+${xpEarned} XP`);
        this.tweens.add({
            targets: this._xpBar, width: targetW,
            duration: 800, ease: 'Power2', delay: 500,
        });
    }

    // ── Rank-up celebration ───────────────────────────────────────────────────

    _showRankUp(newRank) {
        const rankStr = (newRank || '').replace(/_/g, ' ').toUpperCase();
        const banner = this.add.text(W / 2, H / 2 - 10, `⬆ RANK UP!\n${rankStr}`, {
            fontSize: '20px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 5,
            align: 'center', lineSpacing: 4,
        }).setOrigin(0.5).setDepth(100).setAlpha(0).setScale(0.5);

        this.tweens.add({
            targets: banner, alpha: 1, scaleX: 1, scaleY: 1,
            duration: 350, ease: 'Back.Out', delay: 1200,
            onComplete: () => {
                this.cameras.main.shake(250, 0.01);
                this.time.delayedCall(1800, () => {
                    this.tweens.add({ targets: banner, alpha: 0, duration: 400, ease: 'Power2',
                        onComplete: () => banner.destroy() });
                });
            },
        });
    }
}
