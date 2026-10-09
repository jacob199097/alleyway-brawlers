import { apiFetch } from '../utils/Platform.js';
import { loadDuelDeck } from '../utils/DeckLoader.js';
import { VIEW_H, VIEW_TOP, VIEW_BOTTOM, EXTRA_H } from '../utils/Layout.js';
const W = 844;
const H = 390;

const RANKS = ['rookie','runner','enforcer','brawler','striver','shot_caller','lieutenant','kingpin','sovereign','undisputed'];
const RANK_COLORS = {
    rookie: 0x8a9ba8, runner: 0x6dbf67, enforcer: 0x4cc9f0, brawler: 0xe07b39,
    striver: 0x9b59b6, shot_caller: 0xf4d35e, lieutenant: 0xf0a500,
    kingpin: 0xe63946, sovereign: 0x00d4ff, undisputed: 0xffffff,
};

export class FightModeScene extends Phaser.Scene {
    constructor() {
        super('FightModeScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        const player = this.registry.get('player') || {};
        this._player = player;
        this._activeDeckSize = 0;

        this._buildBackground();
        this._buildTitle();
        this._buildModeCards(player);
        this._buildBackBtn();

        this._loadActiveDeckSize();
    }

    _loadActiveDeckSize() {
        apiFetch('/api/deck')
            .then(r => r.json())
            .then(decks => {
                const active = (decks || []).find(d => d.is_active);
                this._activeDeckSize = active ? active.card_count : 0;
                this._activeDeckName = active ? active.name : null;
            })
            .catch(() => { this._activeDeckSize = 0; });
    }

    _gateStart(action) {
        // Block duel start unless the active deck has the full 40 cards.
        if (this._activeDeckSize < 40) {
            const msg = this._activeDeckName
                ? `Active deck "${this._activeDeckName}" has ${this._activeDeckSize}/40 cards. Edit your deck before starting.`
                : 'No active deck — open the Deck Editor and build a 40-card deck first.';
            this._showDeckGate(msg);
            return;
        }
        if (this._starting) return;
        this._starting = true;
        // Play with the saved deck (and its leader + promoted forms in the hideout)
        loadDuelDeck()
            .then(deck => {
                if (!deck) throw new Error('no deck');
                action({ playerDeck: deck.playerDeck, playerHideout: deck.playerHideout });
            })
            .catch(() => {
                this._starting = false;
                this._showDeckGate('Could not load your deck from the server. Check your connection and try again.');
            });
    }

    _showDeckGate(msg) {
        const objs = [];
        const reg  = o => { objs.push(o); return o; };
        const close = () => objs.forEach(o => o?.destroy?.());

        reg(this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0.7).setDepth(100).setInteractive());
        reg(this.add.rectangle(W / 2, H / 2, 460, 160, 0x101030, 0.98)
            .setStrokeStyle(2, 0xe63946).setDepth(101));
        reg(this.add.text(W / 2, H / 2 - 44, 'CAN\'T START DUEL', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0.5).setDepth(102));
        reg(this.add.text(W / 2, H / 2 - 8, msg, {
            fontSize: '11px', color: '#cccccc', wordWrap: { width: 420 }, align: 'center',
        }).setOrigin(0.5).setDepth(102));

        const mk = (x, label, fill, stroke, color, onTap) => {
            const bg = reg(this.add.rectangle(x, H / 2 + 36, 150, 30, fill)
                .setStrokeStyle(2, stroke).setDepth(102).setInteractive({ useHandCursor: true }));
            reg(this.add.text(x, H / 2 + 36, label, {
                fontSize: '11px', fontFamily: 'Arial Black', color,
            }).setOrigin(0.5).setDepth(103));
            bg.on('pointerup', () => { close(); onTap(); });
        };
        mk(W / 2 - 86, 'DECK EDITOR', 0x1a3a4a, 0x4cc9f0, '#9ddcff',
           () => this.scene.start('DeckBuilderScene'));
        mk(W / 2 + 86, 'CLOSE',       0x222244, 0x8888aa, '#cccccc', () => {});
    }

    _buildBackground() {
        if (this.textures.exists('duel_background')) {
            this.add.image(W / 2, H / 2, 'duel_background').setDisplaySize(W, VIEW_H);
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.6);
        } else {
            this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x080818);
        }
        this.add.rectangle(W / 2, VIEW_TOP, W, 3, 0x4cc9f0).setOrigin(0.5, 0);
    }

    _buildTitle() {
        this.add.text(W / 2, VIEW_TOP + 28, 'SELECT BATTLE MODE', {
            fontSize: '20px', fontFamily: 'Arial Black', color: '#ffffff',
            stroke: '#000000', strokeThickness: 3,
        }).setOrigin(0.5);
        this.add.rectangle(W / 2, VIEW_TOP + 44, 260, 2, 0x4cc9f0).setOrigin(0.5);
    }

    _buildModeCards(player) {
        const modes = [
            {
                id: 'casual',
                title: 'CASUAL BRAWL',
                sub: 'Quick match vs CPU · No RP at stake (online play coming soon)',
                color: 0x4cc9f0,
                locked: false,
                action: () => this._gateStart(deck => this.scene.start('RPSScene', { duelData: { isAI: true, ...deck } })),
            },
            {
                id: 'ranked',
                title: 'RANKED BRAWL',
                sub: player.level >= 5 ? 'Ranked vs CPU · earn Rank Points' : `Unlocks at Level 5 (you are Lv ${player.level || 1})`,
                color: 0xf4d35e,
                locked: (player.level || 1) < 5,
                action: () => this._gateStart(deck => this.scene.start('RPSScene', { duelData: { isAI: true, ranked: true, ...deck } })),
            },
            {
                id: 'cpu',
                title: 'VS CPU',
                sub: 'Practice against the AI',
                color: 0x9b59b6,
                locked: false,
                action: () => this._gateStart(deck => this.scene.start('RPSScene', { duelData: { isAI: true, ...deck } })),
            },
        ];

        const cardW  = 228;
        const cardH  = 280 + Math.round(EXTRA_H * 0.6);   // taller cards in the 16:9 view
        const gap    = 18;
        const totalW = modes.length * cardW + (modes.length - 1) * gap;
        const startX = (W - totalW) / 2 + cardW / 2;
        const cy     = H / 2 + 22;

        modes.forEach((mode, i) => {
            const cx = startX + i * (cardW + gap);
            this._buildCard(cx, cy, cardW, cardH, mode, player);
        });
    }

    _buildCard(cx, cy, cardW, cardH, mode, player) {
        const col    = mode.color;
        const alpha  = mode.locked ? 0.45 : 0.92;

        // Card background
        const bg = this.add.rectangle(cx, cy, cardW, cardH, 0x0d0d20)
            .setStrokeStyle(2, col, alpha)
            .setAlpha(alpha);

        // Color accent strip at top
        this.add.rectangle(cx, cy - cardH / 2 + 4, cardW - 4, 6, col)
            .setAlpha(mode.locked ? 0.3 : 0.9);

        // Mode title
        this.add.text(cx, cy - cardH / 2 + 24, mode.title, {
            fontSize: '13px', fontFamily: 'Arial Black',
            color: mode.locked ? '#666666' : `#${col.toString(16).padStart(6, '0')}`,
            stroke: '#000000', strokeThickness: 2,
        }).setOrigin(0.5);

        // Sub-text
        this.add.text(cx, cy - cardH / 2 + 44, mode.sub, {
            fontSize: '8px', fontFamily: 'Arial', color: mode.locked ? '#444455' : '#aaaaaa',
            wordWrap: { width: cardW - 20 }, align: 'center',
        }).setOrigin(0.5, 0);

        if (mode.id === 'ranked' && !mode.locked) {
            this._buildRankDisplay(cx, cy, player);
        } else if (mode.id === 'ranked' && mode.locked) {
            this._buildLockIcon(cx, cy - 20, col);
        } else if (mode.id === 'casual') {
            this._buildCasualIcon(cx, cy - 20, col);
        } else if (mode.id === 'cpu') {
            this._buildCpuIcon(cx, cy - 20, col);
        }

        if (mode.locked) {
            this.add.text(cx, cy + cardH / 2 - 36, '🔒 LOCKED', {
                fontSize: '10px', fontFamily: 'Arial Black', color: '#666666',
            }).setOrigin(0.5);
            this.add.text(cx, cy + cardH / 2 - 20, '(Locked until Level 5)', {
                fontSize: '8px', fontFamily: 'Arial', color: '#444455',
            }).setOrigin(0.5);
            return;
        }

        // Interactive button at the bottom of each card
        const btnW = cardW - 20;
        const btnH = 32;
        const btnY = cy + cardH / 2 - 24;
        const btn = this.add.rectangle(cx, btnY, btnW, btnH, col)
            .setInteractive({ useHandCursor: true });
        this.add.text(cx, btnY, 'SELECT', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#000000',
        }).setOrigin(0.5).setDepth(1);

        btn.on('pointerover',  () => btn.setAlpha(0.85));
        btn.on('pointerout',   () => btn.setAlpha(1));
        btn.on('pointerdown',  () => btn.setAlpha(0.7));
        btn.on('pointerup',    () => { btn.setAlpha(1); mode.action(); });
    }

    _buildRankDisplay(cx, cy, player) {
        const rank  = player.rank || 'rookie';
        const rKey  = `rank_${rank}`;
        const rCol  = RANK_COLORS[rank] || 0xffffff;

        if (this.textures.exists(rKey)) {
            this.add.image(cx, cy - 24, rKey).setDisplaySize(90, 90);
        } else {
            const gfx = this.add.graphics();
            gfx.lineStyle(4, rCol, 1);
            gfx.strokeCircle(cx, cy - 24, 40);
            gfx.fillStyle(rCol, 0.15);
            gfx.fillCircle(cx, cy - 24, 40);
            this.add.text(cx, cy - 24, rank[0].toUpperCase(), {
                fontSize: '30px', fontFamily: 'Arial Black',
                color: `#${rCol.toString(16).padStart(6, '0')}`,
            }).setOrigin(0.5);
        }

        this.add.text(cx, cy + 28, rank.replace(/_/g, ' ').toUpperCase(), {
            fontSize: '10px', fontFamily: 'Arial Black',
            color: `#${rCol.toString(16).padStart(6, '0')}`,
            stroke: '#000000', strokeThickness: 2,
        }).setOrigin(0.5);

        this.add.text(cx, cy + 44, `${player.rank_points || 0} RP`, {
            fontSize: '9px', color: '#aaaaaa',
        }).setOrigin(0.5);
    }

    _buildLockIcon(cx, cy, col) {
        const gfx = this.add.graphics();
        gfx.lineStyle(5, col, 0.4);
        gfx.beginPath();
        gfx.arc(cx, cy - 18, 14, Phaser.Math.DegToRad(200), Phaser.Math.DegToRad(340), true);
        gfx.strokePath();
        gfx.fillStyle(col, 0.2);
        gfx.fillRoundedRect(cx - 18, cy - 2, 36, 26, 5);
    }

    _buildCasualIcon(cx, cy, col) {
        const gfx = this.add.graphics();
        gfx.lineStyle(3, col, 0.8);
        gfx.strokeCircle(cx - 18, cy, 24);
        gfx.strokeCircle(cx + 18, cy, 24);
        gfx.fillStyle(col, 0.15);
        gfx.fillCircle(cx - 18, cy, 24);
        gfx.fillCircle(cx + 18, cy, 24);
        this.add.text(cx - 18, cy, 'PL', {
            fontSize: '10px', fontFamily: 'Arial Black', color: `#${col.toString(16).padStart(6, '0')}`,
        }).setOrigin(0.5);
        this.add.text(cx + 18, cy, 'PL', {
            fontSize: '10px', fontFamily: 'Arial Black', color: `#${col.toString(16).padStart(6, '0')}`,
        }).setOrigin(0.5);
        this.add.text(cx, cy, 'VS', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5);
    }

    _buildCpuIcon(cx, cy, col) {
        const gfx = this.add.graphics();
        gfx.lineStyle(3, col, 0.7);
        gfx.strokeRect(cx - 28, cy - 24, 56, 48);
        gfx.lineStyle(2, col, 0.5);
        for (let i = 0; i < 3; i++) {
            gfx.lineBetween(cx - 14 + i * 14, cy - 24, cx - 14 + i * 14, cy - 30);
            gfx.lineBetween(cx - 14 + i * 14, cy + 24, cx - 14 + i * 14, cy + 30);
        }
        this.add.text(cx, cy, 'CPU', {
            fontSize: '16px', fontFamily: 'Arial Black',
            color: `#${col.toString(16).padStart(6, '0')}`,
        }).setOrigin(0.5);
    }

    _buildBackBtn() {
        const btn = this.add.text(40, VIEW_BOTTOM - 22, '← BACK', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#888888',
            backgroundColor: '#111122', padding: { x: 8, y: 4 },
        }).setOrigin(0.5).setInteractive({ useHandCursor: true });
        btn.on('pointerover',  () => btn.setColor('#ffffff'));
        btn.on('pointerout',   () => btn.setColor('#888888'));
        btn.on('pointerup',    () => this.scene.start('MainMenuScene'));
    }
}
