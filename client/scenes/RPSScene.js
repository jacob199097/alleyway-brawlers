import { VIEW_H, VIEW_TOP, VIEW_BOTTOM, EXTRA_H } from '../utils/Layout.js';

/**
 * Rock Paper Scissors — determines who goes first.
 * Winner chooses first or second. Draws replay.
 *
 * Receives: { duelData: <object passed to DuelScene.init> }
 */

const W = 844;
const H = 390;

const CHOICES = ['rock', 'paper', 'scissors'];

const CHOICE_META = {
    rock:     { emoji: '🪨', label: 'ROCK',     color: 0xe07b39, beats: 'scissors' },
    paper:    { emoji: '📄', label: 'PAPER',    color: 0x4cc9f0, beats: 'rock'     },
    scissors: { emoji: '✂️',  label: 'SCISSORS', color: 0xe63946, beats: 'paper'   },
};

function beats(a, b) {
    return CHOICE_META[a]?.beats === b;
}

export class RPSScene extends Phaser.Scene {
    constructor() {
        super('RPSScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    init(data) {
        this._duelData = data.duelData || {};
        this._round    = data._round   || 1;
    }

    create() {
        this._resolving  = false;

        this._buildBackground();
        this._buildUI();
    }

    // ── Background ────────────────────────────────────────────────────────────

    _buildBackground() {
        if (this.textures.exists('duel_background')) {
            this.add.image(W / 2, H / 2, 'duel_background').setDisplaySize(W, VIEW_H);
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.55);
        } else {
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x080818);
        }
    }

    // ── Main UI (choice phase) ────────────────────────────────────────────────

    _buildUI() {
        this._uiObjs = [];
        const reg = o => { this._uiObjs.push(o); return o; };

        // Title
        reg(this.add.text(W / 2, VIEW_TOP + 34, 'SCISSORS · PAPER · ROCK', {
            fontSize: '18px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 4,
        }).setOrigin(0.5));

        const sub = this._round > 1 ? `ROUND ${this._round} — DRAW! Play again` : 'Choose your throw to decide who goes first';
        reg(this.add.text(W / 2, 50, sub, {
            fontSize: '9px', fontFamily: 'Arial', color: '#aaaaaa',
        }).setOrigin(0.5));

        reg(this.add.rectangle(W / 2, 63, 400, 1, 0xf4d35e).setAlpha(0.5));

        // vs divider line
        reg(this.add.text(W / 2, H / 2 - 10, 'VS', {
            fontSize: '22px', fontFamily: 'Arial Black', color: '#ffffff',
            stroke: '#000000', strokeThickness: 4, alpha: 0.6,
        }).setOrigin(0.5));

        // Player label (left) / CPU label (right)
        reg(this.add.text(W / 2 - 160, H / 2 + 40, 'YOU', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5));
        reg(this.add.text(W / 2 + 160, H / 2 + 40, 'CPU', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0.5));

        // Three choice buttons
        const btnW = 190, btnH = 220;
        const btnY = H / 2 - 18;
        const xs   = [W / 2 - 290, W / 2, W / 2 + 290];

        CHOICES.forEach((choice, i) => {
            const meta = CHOICE_META[choice];
            const cx   = xs[i];

            const bg = this.add.rectangle(cx, btnY, btnW, btnH, 0x0d0d20)
                .setStrokeStyle(2, meta.color, 0.8)
                .setInteractive({ useHandCursor: true })
                .setAlpha(0.9);
            reg(bg);

            // Accent stripe
            reg(this.add.rectangle(cx, btnY - btnH / 2 + 4, btnW - 4, 5, meta.color).setAlpha(0.8));

            // Emoji (large)
            const emoji = this.add.text(cx, btnY - 38, meta.emoji, {
                fontSize: '54px',
            }).setOrigin(0.5);
            reg(emoji);

            // Label
            reg(this.add.text(cx, btnY + 62, meta.label, {
                fontSize: '14px', fontFamily: 'Arial Black',
                color: `#${meta.color.toString(16).padStart(6, '0')}`,
                stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5));

            bg.on('pointerover',  () => { bg.setAlpha(1); bg.setStrokeStyle(3, meta.color, 1); });
            bg.on('pointerout',   () => { bg.setAlpha(0.9); bg.setStrokeStyle(2, meta.color, 0.8); });
            bg.on('pointerdown',  () => bg.setAlpha(0.65));
            bg.on('pointerup',    () => {
                if (this._resolving) return;
                this._resolving = true;
                this._onPlayerChoice(choice);
            });
        });
    }

    // ── Resolution ────────────────────────────────────────────────────────────

    _onPlayerChoice(playerChoice) {
        const cpuChoice = CHOICES[Math.floor(Math.random() * CHOICES.length)];
        this._destroyUI();
        this._showResolution(playerChoice, cpuChoice);
    }

    _destroyUI() {
        this._uiObjs.forEach(o => o?.destroy());
        this._uiObjs = [];
    }

    _showResolution(playerChoice, cpuChoice) {
        const pm = CHOICE_META[playerChoice];
        const cm = CHOICE_META[cpuChoice];

        // Background stays; show both choices large
        const panelY = H / 2 - 20;

        // Player choice (left)
        this.add.rectangle(W / 2 - 155, panelY, 230, 200, 0x0d0d20)
            .setStrokeStyle(2, pm.color, 0.9).setAlpha(0.92);
        this.add.text(W / 2 - 155, panelY - 55, 'YOU', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5);
        const plEmoji = this.add.text(W / 2 - 155, panelY - 12, pm.emoji, {
            fontSize: '58px',
        }).setOrigin(0.5).setAlpha(0).setScale(0.4);
        this.add.text(W / 2 - 155, panelY + 60, pm.label, {
            fontSize: '13px', fontFamily: 'Arial Black',
            color: `#${pm.color.toString(16).padStart(6, '0')}`,
        }).setOrigin(0.5);

        this.tweens.add({ targets: plEmoji, alpha: 1, scaleX: 1, scaleY: 1, duration: 320, ease: 'Back.Out' });

        // VS in center
        this.add.text(W / 2, panelY, 'VS', {
            fontSize: '20px', fontFamily: 'Arial Black', color: '#ffffff',
            stroke: '#000000', strokeThickness: 4, alpha: 0.7,
        }).setOrigin(0.5);

        // CPU choice (right) — revealed after short delay for drama
        this.add.rectangle(W / 2 + 155, panelY, 230, 200, 0x0d0d20)
            .setStrokeStyle(2, cm.color, 0.9).setAlpha(0.92);
        this.add.text(W / 2 + 155, panelY - 55, 'CPU', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0.5);
        const cpuEmoji = this.add.text(W / 2 + 155, panelY - 12, '❓', {
            fontSize: '54px',
        }).setOrigin(0.5);

        this.time.delayedCall(500, () => {
            this.tweens.add({
                targets: cpuEmoji, scaleX: 0, duration: 120, ease: 'Linear',
                onComplete: () => {
                    cpuEmoji.setText(cm.emoji);
                    this.tweens.add({ targets: cpuEmoji, scaleX: 1, duration: 180, ease: 'Back.Out' });
                },
            });

            this.time.delayedCall(300, () => {
                this.add.text(W / 2 + 155, panelY + 60, cm.label, {
                    fontSize: '13px', fontFamily: 'Arial Black',
                    color: `#${cm.color.toString(16).padStart(6, '0')}`,
                }).setOrigin(0.5);

                this.time.delayedCall(400, () => this._showResult(playerChoice, cpuChoice));
            });
        });
    }

    _showResult(playerChoice, cpuChoice) {
        const isDraw    = playerChoice === cpuChoice;
        const playerWon = beats(playerChoice, cpuChoice);

        let resultText, resultColor;
        if (isDraw)        { resultText = "DRAW!";       resultColor = '#f4d35e'; }
        else if (playerWon){ resultText = "YOU WIN! 🎉"; resultColor = '#4cc9f0'; }
        else               { resultText = "CPU WINS!";   resultColor = '#e63946'; }

        const banner = this.add.text(W / 2, VIEW_TOP + 58, resultText, {
            fontSize: '26px', fontFamily: 'Arial Black', color: resultColor,
            stroke: '#000000', strokeThickness: 5,
        }).setOrigin(0.5).setScale(0).setAlpha(0);
        this.tweens.add({ targets: banner, scaleX: 1, scaleY: 1, alpha: 1, duration: 280, ease: 'Back.Out' });

        this.cameras.main.shake(200, 0.007);

        if (isDraw) {
            this.add.text(W / 2, VIEW_BOTTOM - 34, `Round ${this._round} is a draw — throwing again...`, {
                fontSize: '9px', color: '#888888',
            }).setOrigin(0.5);

            this.time.delayedCall(1800, () => {
                this.cameras.main.fadeOut(300, 0, 0, 0);
                this.cameras.main.once('camerafadeoutcomplete', () => {
                    this.scene.start('RPSScene', { duelData: this._duelData, _round: this._round + 1 });
                });
            });
            return;
        }

        // Winner chooses position
        if (playerWon) {
            this._showPositionChoice('player');
        } else {
            // CPU decides — flavour text then proceed
            const cpuGoesFist = Math.random() < 0.5;
            const cpuDecision = cpuGoesFist ? 'first' : 'second';
            const firstPlayer = cpuGoesFist ? 'opponent' : 'player';
            this.add.text(W / 2, VIEW_BOTTOM - 60, `CPU chooses to go ${cpuDecision}!`, {
                fontSize: '11px', fontFamily: 'Arial Black', color: '#e63946',
                stroke: '#000000', strokeThickness: 2,
            }).setOrigin(0.5).setAlpha(0).setDepth(10);
            this.tweens.add({
                targets: this.children.list[this.children.list.length - 1],
                alpha: 1, duration: 300, delay: 400,
            });
            this.time.delayedCall(2000, () => this._launchDuel(firstPlayer));
        }
    }

    _showPositionChoice(winner) {
        const cy = VIEW_BOTTOM - 62;

        this.add.text(W / 2, cy - 20, 'You won! Choose your starting position:', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000000', strokeThickness: 2,
        }).setOrigin(0.5);

        const btnY   = cy + 18;
        const btnW   = 160;
        const btnH   = 32;

        // GO FIRST
        const firstBg = this.add.rectangle(W / 2 - 88, btnY, btnW, btnH, 0x004444)
            .setStrokeStyle(2, 0x4cc9f0).setInteractive({ useHandCursor: true });
        this.add.text(W / 2 - 88, btnY, '⚡ GO FIRST', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5).setDepth(1);
        firstBg.on('pointerover',  () => firstBg.setAlpha(0.8));
        firstBg.on('pointerout',   () => firstBg.setAlpha(1));
        firstBg.on('pointerup',    () => this._launchDuel('player'));

        // GO SECOND
        const secBg = this.add.rectangle(W / 2 + 88, btnY, btnW, btnH, 0x440044)
            .setStrokeStyle(2, 0x9b59b6).setInteractive({ useHandCursor: true });
        this.add.text(W / 2 + 88, btnY, '🛡 GO SECOND', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#c77dff',
        }).setOrigin(0.5).setDepth(1);
        secBg.on('pointerover',  () => secBg.setAlpha(0.8));
        secBg.on('pointerout',   () => secBg.setAlpha(1));
        secBg.on('pointerup',    () => this._launchDuel('opponent'));
    }

    // ── Launch ────────────────────────────────────────────────────────────────

    _launchDuel(firstPlayer) {
        this.cameras.main.fadeOut(400, 0, 0, 0);
        this.cameras.main.once('camerafadeoutcomplete', () => {
            this.scene.start('DuelScene', {
                ...this._duelData,
                firstPlayer,
            });
        });
    }
}
