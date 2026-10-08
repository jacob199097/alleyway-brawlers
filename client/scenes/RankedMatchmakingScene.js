import { VIEW_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

const RANKS = [
    'rookie',
    'runner',
    'enforcer',
    'brawler',
    'striver',
    'shot_caller',
    'lieutenant',
    'kingpin',
    'sovereign',
    'undisputed',
];

const RANK_COLORS = {
    rookie:      0x8a9ba8,
    runner:      0x6dbf67,
    enforcer:    0x4cc9f0,
    brawler:     0xe07b39,
    striver:     0x9b59b6,
    shot_caller: 0xf4d35e,
    lieutenant:  0xf0a500,
    kingpin:     0xe63946,
    sovereign:   0x00d4ff,
    undisputed:  0xffffff,
};

function rankLabel(rank) {
    return rank.replace(/_/g, ' ').toUpperCase();
}

export class RankedMatchmakingScene extends Phaser.Scene {
    constructor() {
        super('RankedMatchmakingScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        const player = this.registry.get('player') || {};
        this._player = player;
        this._state  = 'idle'; // 'idle' | 'searching'

        this._buildBackground();

        if ((player.level || 1) < 5) {
            this._buildLockScreen(player);
        } else {
            this._buildLobby(player);
        }
    }

    // ── Background ────────────────────────────────────────────────────────────

    _buildBackground() {
        if (this.textures.exists('duel_background')) {
            this.add.image(W / 2, H / 2, 'duel_background').setDisplaySize(W, VIEW_H);
            // Dark overlay so text stays readable
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.62);
        } else {
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x0a0a1a);
        }

        // Subtle gold top-edge accent
        this.add.rectangle(W / 2, 0, W, 3, 0xf4d35e).setOrigin(0.5, 0);
    }

    // ── Lock screen ───────────────────────────────────────────────────────────

    _buildLockScreen(player) {
        const cx = W / 2;
        const cy = H / 2;

        // Padlock drawn with rectangles
        this._drawPadlock(cx, cy - 80, 0xf4d35e);

        this.add.text(cx, cy - 22, 'RANKED MODE', {
            fontSize: '28px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 4,
        }).setOrigin(0.5);

        this.add.text(cx, cy + 14, 'Unlock at Level 5', {
            fontSize: '16px', fontFamily: 'Arial', color: '#cccccc',
        }).setOrigin(0.5);

        // Level progress bar
        const level  = player.level || 1;
        const pct    = Math.min(1, level / 5);
        const barW   = 280;
        const barH   = 12;
        const barY   = cy + 50;

        this.add.text(cx, barY - 16, `Level ${level} / 5 required`, {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#888888',
        }).setOrigin(0.5);

        this.add.rectangle(cx, barY, barW, barH, 0x1a1a3a).setOrigin(0.5);
        if (pct > 0) {
            this.add.rectangle(cx - barW / 2, barY, barW * pct, barH, 0x4cc9f0)
                .setOrigin(0, 0.5);
        }

        this.add.text(cx, barY + 16, `${level} / 5`, {
            fontSize: '10px', color: '#4cc9f0',
        }).setOrigin(0.5);

        this._makeBtn(cx, H - 38, '← BACK', () => this.scene.start('MainMenuScene'), 0x333355, '#ffffff', 200, 36);
    }

    _drawPadlock(cx, cy, color) {
        const gfx = this.add.graphics();

        // Shackle (arc at top) — drawn as a thick arc
        gfx.lineStyle(7, color, 1);
        gfx.beginPath();
        gfx.arc(cx, cy, 16, Phaser.Math.DegToRad(200), Phaser.Math.DegToRad(340), true);
        gfx.strokePath();

        // Lock body
        gfx.fillStyle(color, 1);
        gfx.fillRoundedRect(cx - 20, cy + 4, 40, 30, 5);

        // Keyhole: dark circle + notch
        gfx.fillStyle(0x0a0a1a, 1);
        gfx.fillCircle(cx, cy + 16, 6);
        gfx.fillRect(cx - 3, cy + 20, 6, 8);
    }

    // ── Ranked lobby ──────────────────────────────────────────────────────────

    _buildLobby(player) {
        this._lobbyGroup = this.add.group();

        // Title
        const title = this.add.text(W / 2, 22, 'RANKED MODE', {
            fontSize: '22px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5);
        this._lobbyGroup.add(title);

        // Gold underline
        const ul = this.add.rectangle(W / 2, 37, 220, 2, 0xf4d35e).setOrigin(0.5);
        this._lobbyGroup.add(ul);

        this._buildLeftPanel(player);
        this._buildCenterStrip(player);
        this._buildRightPanel(player);
        this._buildInfoText();

        // Back button
        const backBtn = this._makeBtn(54, H - 28, '← BACK', () => this.scene.start('MainMenuScene'), 0x333355, '#ffffff', 90, 30);
        this._lobbyGroup.add(backBtn.rect);
        this._lobbyGroup.add(backBtn.label);

        // Searching overlay (hidden initially)
        this._buildSearchingOverlay();
    }

    // Left panel: rank badge + name + points
    _buildLeftPanel(player) {
        const lx   = 110;
        const rank  = player.rank || 'rookie';
        const rKey  = `rank_${rank}`;
        const rCol  = RANK_COLORS[rank] || 0xffffff;

        // Panel background
        const panel = this.add.rectangle(lx, H / 2 + 12, 190, 280, 0x0d0d20)
            .setStrokeStyle(1, rCol).setAlpha(0.85);
        this._lobbyGroup.add(panel);

        // Rank image or fallback circle
        if (this.textures.exists(rKey)) {
            const img = this.add.image(lx, 120, rKey).setDisplaySize(120, 120);
            this._lobbyGroup.add(img);
        } else {
            this._drawRankBadgeFallback(lx, 120, rank, rCol);
        }

        // Rank name
        const rName = this.add.text(lx, 192, rankLabel(rank), {
            fontSize: '14px', fontFamily: 'Arial Black', color: `#${rCol.toString(16).padStart(6, '0')}`,
            stroke: '#000000', strokeThickness: 2,
        }).setOrigin(0.5);
        this._lobbyGroup.add(rName);

        // Rank points
        const rp = this.add.text(lx, 214, `${player.rank_points || 0} RP`, {
            fontSize: '12px', fontFamily: 'Arial', color: '#cccccc',
        }).setOrigin(0.5);
        this._lobbyGroup.add(rp);

        // Season label
        const season = this.add.text(lx, 240, 'SEASON 1', {
            fontSize: '9px', color: '#555577',
        }).setOrigin(0.5);
        this._lobbyGroup.add(season);

        // Win/loss callout (if available)
        const wins   = player.wins   || 0;
        const losses = player.losses || 0;
        const wr     = wins + losses > 0
            ? ((wins / (wins + losses)) * 100).toFixed(1) + '%'
            : '—';
        const wlText = this.add.text(lx, 270, `W ${wins}  /  L ${losses}  —  ${wr}`, {
            fontSize: '9px', color: '#888888',
        }).setOrigin(0.5);
        this._lobbyGroup.add(wlText);
    }

    _drawRankBadgeFallback(cx, cy, rank, color) {
        const gfx = this.add.graphics();
        gfx.lineStyle(4, color, 1);
        gfx.strokeCircle(cx, cy, 50);
        gfx.fillStyle(color, 0.15);
        gfx.fillCircle(cx, cy, 50);
        this._lobbyGroup.add(gfx);

        const t = this.add.text(cx, cy, rank[0].toUpperCase(), {
            fontSize: '36px', fontFamily: 'Arial Black',
            color: `#${color.toString(16).padStart(6, '0')}`,
        }).setOrigin(0.5);
        this._lobbyGroup.add(t);
    }

    // Center: horizontal rank progression strip
    _buildCenterStrip(player) {
        const currentRank  = player.rank || 'rookie';
        const currentIdx   = RANKS.indexOf(currentRank);
        const iconSize     = 40;
        const gap          = 8;
        const totalW       = RANKS.length * iconSize + (RANKS.length - 1) * gap;
        const startX       = (W - totalW) / 2;
        const stripY       = 82;

        // Connector line behind icons
        const lineGfx = this.add.graphics();
        lineGfx.lineStyle(2, 0x333355, 1);
        lineGfx.lineBetween(startX + iconSize / 2, stripY, startX + totalW - iconSize / 2, stripY);
        this._lobbyGroup.add(lineGfx);

        // Fill line up to current rank
        const fillLineGfx = this.add.graphics();
        fillLineGfx.lineStyle(2, 0xf4d35e, 1);
        const fillEndX = startX + iconSize / 2 + currentIdx * (iconSize + gap);
        fillLineGfx.lineBetween(startX + iconSize / 2, stripY, fillEndX, stripY);
        this._lobbyGroup.add(fillLineGfx);

        RANKS.forEach((rank, i) => {
            const x       = startX + i * (iconSize + gap) + iconSize / 2;
            const rKey    = `rank_${rank}`;
            const rCol    = RANK_COLORS[rank] || 0xffffff;
            const isCur   = i === currentIdx;
            const isPast  = i < currentIdx;

            if (isCur) {
                // Gold glow ring
                const glowGfx = this.add.graphics();
                glowGfx.lineStyle(3, 0xf4d35e, 0.9);
                glowGfx.strokeCircle(x, stripY, iconSize / 2 + 4);
                glowGfx.lineStyle(1, 0xf4d35e, 0.4);
                glowGfx.strokeCircle(x, stripY, iconSize / 2 + 8);
                this._lobbyGroup.add(glowGfx);

                // Pulse tween on the glow
                this.tweens.add({
                    targets: glowGfx,
                    alpha:   { from: 0.6, to: 1 },
                    duration: 900,
                    yoyo: true,
                    repeat: -1,
                    ease: 'Sine.easeInOut',
                });
            }

            if (this.textures.exists(rKey)) {
                const alpha = isCur ? 1 : isPast ? 0.85 : 0.3;
                const img   = this.add.image(x, stripY, rKey)
                    .setDisplaySize(iconSize, iconSize)
                    .setAlpha(alpha);
                this._lobbyGroup.add(img);
            } else {
                // Fallback circle
                const gfx = this.add.graphics();
                const alpha = isCur ? 1 : isPast ? 0.6 : 0.25;
                gfx.fillStyle(rCol, alpha);
                gfx.fillCircle(x, stripY, iconSize / 2 - 2);
                this._lobbyGroup.add(gfx);

                const letter = this.add.text(x, stripY, rank[0].toUpperCase(), {
                    fontSize: '13px', fontFamily: 'Arial Black',
                    color: `#${rCol.toString(16).padStart(6, '0')}`,
                }).setOrigin(0.5).setAlpha(alpha);
                this._lobbyGroup.add(letter);
            }

            // Label below for current and adjacent ranks
            if (isCur || i === currentIdx - 1 || i === currentIdx + 1 || i === 0 || i === RANKS.length - 1) {
                const lbl = this.add.text(x, stripY + iconSize / 2 + 6, rankLabel(rank), {
                    fontSize: '6px', fontFamily: 'Arial Black',
                    color: isCur ? '#f4d35e' : '#555577',
                }).setOrigin(0.5, 0);
                this._lobbyGroup.add(lbl);
            }
        });
    }

    // Right side: Find Match button
    _buildRightPanel(player) {
        const rx = W - 130;
        const cy = H / 2 + 20;

        // Panel background
        const panel = this.add.rectangle(rx, cy, 210, 220, 0x0d0d20)
            .setStrokeStyle(1, 0xf4d35e).setAlpha(0.85);
        this._lobbyGroup.add(panel);

        // Season badge
        const seasonBadge = this.add.text(rx, cy - 85, '🏆  RANKED MATCH', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);
        this._lobbyGroup.add(seasonBadge);

        // Divider
        const div = this.add.rectangle(rx, cy - 68, 170, 1, 0xf4d35e).setAlpha(0.4);
        this._lobbyGroup.add(div);

        // RP reward hint
        const rpHint = this.add.text(rx, cy - 50, '+15 RP on win\n−10 RP on loss', {
            fontSize: '10px', fontFamily: 'Arial', color: '#aaaaaa',
            align: 'center', lineSpacing: 6,
        }).setOrigin(0.5);
        this._lobbyGroup.add(rpHint);

        // Current rank points to next rank indicator
        const currentRank  = player.rank || 'rookie';
        const currentIdx   = RANKS.indexOf(currentRank);
        const nextRank     = RANKS[currentIdx + 1] || null;
        if (nextRank) {
            const nextTxt = this.add.text(rx, cy - 10, `Next rank: ${rankLabel(nextRank)}`, {
                fontSize: '9px', color: '#777799',
            }).setOrigin(0.5);
            this._lobbyGroup.add(nextTxt);
        }

        // FIND RANKED MATCH gold button
        const btnW   = 178;
        const btnH   = 46;
        const btnY   = cy + 48;

        const btnRect = this.add.rectangle(rx, btnY, btnW, btnH, 0xd4a017)
            .setStrokeStyle(2, 0xf4d35e)
            .setInteractive({ useHandCursor: true });
        const btnText = this.add.text(rx, btnY, 'FIND RANKED MATCH', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#000000',
        }).setOrigin(0.5);

        btnRect.on('pointerover',  () => btnRect.setFillStyle(0xf4d35e));
        btnRect.on('pointerout',   () => btnRect.setFillStyle(0xd4a017));
        btnRect.on('pointerdown',  () => btnRect.setAlpha(0.8));
        btnRect.on('pointerup',    () => {
            btnRect.setAlpha(1);
            this._startSearching();
        });

        this._lobbyGroup.add(btnRect);
        this._lobbyGroup.add(btnText);

        this._findMatchBtn  = btnRect;
        this._findMatchText = btnText;
    }

    // Info text strip across the bottom center
    _buildInfoText() {
        const infoY = H - 22;
        const info  = this.add.text(W / 2, infoY,
            'Win to gain Rank Points  •  Lose fewer at higher ranks  •  Each season resets to Rookie',
            {
                fontSize: '9px', fontFamily: 'Arial', color: '#555577',
                align: 'center',
            }
        ).setOrigin(0.5);
        this._lobbyGroup.add(info);
    }

    // ── Searching overlay ─────────────────────────────────────────────────────

    _buildSearchingOverlay() {
        // Container for searching state UI — hidden at first
        this._searchGroup = this.add.group();

        const cx = W / 2;
        const cy = H / 2;

        // Dim overlay
        const overlay = this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.72);
        this._searchGroup.add(overlay);

        // Spinner ring (graphics object, rotated in update)
        const spinnerGfx = this.add.graphics();
        this._drawSpinner(spinnerGfx, cx, cy - 50, 30);
        this._spinnerGfx = spinnerGfx;
        this._searchGroup.add(spinnerGfx);

        // "Searching for opponent..." text
        this._searchText = this.add.text(cx, cy + 2, 'Searching for opponent...', {
            fontSize: '18px', fontFamily: 'Arial Black', color: '#4cc9f0',
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5);
        this._searchGroup.add(this._searchText);

        // Animated dots sub-text
        this._dotsText = this.add.text(cx, cy + 30, '', {
            fontSize: '13px', color: '#888888',
        }).setOrigin(0.5);
        this._searchGroup.add(this._dotsText);

        // Cancel button
        const cancelBtn = this._makeBtn(cx, cy + 80, 'CANCEL', () => this._cancelSearching(), 0x333355, '#ffffff', 160, 38);
        this._searchGroup.add(cancelBtn.rect);
        this._searchGroup.add(cancelBtn.label);

        // Hide initially
        this._setGroupVisible(this._searchGroup, false);

        this._spinnerAngle = 0;
        this._dotsCount    = 0;
        this._dotsTimer    = null;
        this._matchTimer   = null;
    }

    _drawSpinner(gfx, cx, cy, r) {
        gfx.clear();
        // Background ring
        gfx.lineStyle(5, 0x222244, 1);
        gfx.strokeCircle(cx, cy, r);
        // Arc (partial) — drawn via beginPath arc
        gfx.lineStyle(5, 0x4cc9f0, 1);
        const start = Phaser.Math.DegToRad(this._spinnerAngle);
        const end   = Phaser.Math.DegToRad(this._spinnerAngle + 270);
        gfx.beginPath();
        gfx.arc(cx, cy, r, start, end, false);
        gfx.strokePath();
    }

    // ── State transitions ─────────────────────────────────────────────────────

    _startSearching() {
        if (this._state === 'searching') return;
        this._state = 'searching';

        this._setGroupVisible(this._lobbyGroup,  false);
        this._setGroupVisible(this._searchGroup, true);

        this._spinnerAngle = 0;
        this._dotsCount    = 0;

        // Dots animation
        this._dotsTimer = this.time.addEvent({
            delay: 500,
            loop: true,
            callback: () => {
                this._dotsCount = (this._dotsCount + 1) % 4;
                this._dotsText.setText('Ranking you up' + '.'.repeat(this._dotsCount));
            },
        });

        // Simulate match found after 2.5s
        this._matchTimer = this.time.delayedCall(2500, () => {
            this._onMatchFound();
        });
    }

    _cancelSearching() {
        if (this._state !== 'searching') return;
        this._state = 'idle';

        if (this._dotsTimer)  { this._dotsTimer.destroy();  this._dotsTimer  = null; }
        if (this._matchTimer) { this._matchTimer.remove();  this._matchTimer = null; }

        this._setGroupVisible(this._searchGroup, false);
        this._setGroupVisible(this._lobbyGroup,  true);
    }

    _onMatchFound() {
        this._searchText.setText('MATCH FOUND!');
        this._dotsText.setText('Launching duel...');

        this.time.delayedCall(600, () => {
            this.scene.start('DuelScene', { ranked: true, isAI: true });
        });
    }

    // ── update ────────────────────────────────────────────────────────────────

    update(time, delta) {
        if (this._state === 'searching' && this._spinnerGfx) {
            this._spinnerAngle = (this._spinnerAngle + delta * 0.36) % 360;
            const cx = W / 2;
            const cy = H / 2;
            this._drawSpinner(this._spinnerGfx, cx, cy - 50, 30);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _makeBtn(x, y, label, cb, bgColor = 0x333355, textColor = '#ffffff', w = 180, h = 36) {
        const rect = this.add.rectangle(x, y, w, h, bgColor)
            .setStrokeStyle(1, 0xffffff)
            .setInteractive({ useHandCursor: true })
            .setOrigin(0.5);
        const lbl = this.add.text(x, y, label, {
            fontSize: '12px', fontFamily: 'Arial Black', color: textColor,
        }).setOrigin(0.5);

        rect.on('pointerover',  () => rect.setAlpha(0.85));
        rect.on('pointerout',   () => rect.setAlpha(1));
        rect.on('pointerdown',  () => rect.setAlpha(0.7));
        rect.on('pointerup',    () => { rect.setAlpha(1); cb(); });

        return { rect, label: lbl };
    }

    _setGroupVisible(group, visible) {
        group.getChildren().forEach(child => {
            child.setVisible(visible);
            if (visible) child.setActive(true);
        });
        // Disable interactivity while hidden so buttons don't ghost-fire
        group.getChildren().forEach(child => {
            if (child.input) {
                if (visible) child.setInteractive({ useHandCursor: true });
                else child.disableInteractive();
            }
        });
    }

    shutdown() {
        if (this._dotsTimer)  this._dotsTimer.destroy();
        if (this._matchTimer) this._matchTimer.remove();
    }
}
