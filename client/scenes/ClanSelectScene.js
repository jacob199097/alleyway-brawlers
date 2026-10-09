import { apiFetch } from '../utils/Platform.js';
import { VIEW_H, VIEW_TOP, VIEW_BOTTOM, EXTRA_H } from '../utils/Layout.js';
/**
 * Shown after first login when the player has not yet picked their starting
 * clan. Two big tiles — Lions and Vipers — and a CONFIRM button. Calls the
 * onboarding endpoint to seed inventory + a starter deck for the chosen clan.
 */

const W = 844;
const H = 390;

const CLANS = [
    {
        id:        'lion_pride',
        label:     'LIONS',
        color:     0xc77a00,
        textColor: '#ffd166',
        imageKey:  'lions_deck',
        blurb:     'Aggressive pride that swarms the field.\nFull starter deck included.',
    },
    {
        id:        'viper_clan',
        label:     'VIPERS',
        color:     0x2e7d32,
        textColor: '#a5d6a7',
        imageKey:  'vipers_deck',
        blurb:     'Slippery street crew of saboteurs.\n(Roster still in development)',
    },
];

export class ClanSelectScene extends Phaser.Scene {
    constructor() {
        super('ClanSelectScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        // Sit on top of the menu video background
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0.6);

        this.add.text(W / 2, VIEW_TOP + 34, 'CHOOSE YOUR CLAN', {
            fontSize: '18px', fontFamily: 'Arial Black', color: '#f4d35e',
            stroke: '#000', strokeThickness: 4,
        }).setOrigin(0.5);

        this.add.text(W / 2, 50, 'Your starter inventory and deck depend on this choice.',
            { fontSize: '10px', color: '#cccccc' }).setOrigin(0.5);

        this._selected = null;
        this._tiles    = {};

        const tileW = 240, tileH = 240;
        const startX = W / 2 - 130;
        const tileY  = 200;

        CLANS.forEach((c, i) => {
            const x = startX + i * 260;
            this._buildTile(c, x, tileY, tileW, tileH);
        });

        this._buildConfirmButton();
    }

    _buildTile(clan, x, y, w, h) {
        const bg = this.add.rectangle(x, y, w, h, 0x1a1a2e, 0.95)
            .setStrokeStyle(2, 0x555577).setInteractive({ useHandCursor: true });

        if (this.textures.exists(clan.imageKey)) {
            this.add.image(x, y - 24, clan.imageKey).setDisplaySize(w - 24, h - 80);
        } else {
            this.add.rectangle(x, y - 24, w - 24, h - 80, clan.color)
                .setStrokeStyle(2, 0xffffff, 0.7);
        }

        this.add.text(x, y + h / 2 - 38, clan.label, {
            fontSize: '14px', fontFamily: 'Arial Black', color: clan.textColor,
        }).setOrigin(0.5);

        this.add.text(x, y + h / 2 - 18, clan.blurb, {
            fontSize: '8px', color: '#cccccc', align: 'center',
            wordWrap: { width: w - 16 },
        }).setOrigin(0.5);

        bg.on('pointerup', () => this._selectClan(clan.id));
        this._tiles[clan.id] = bg;
    }

    _selectClan(id) {
        this._selected = id;
        Object.entries(this._tiles).forEach(([clanId, tile]) => {
            tile.setStrokeStyle(2, clanId === id ? 0xffd700 : 0x555577,
                               clanId === id ? 1 : 0.85);
        });
        this._confirmBtn?.setAlpha(1);
        this._confirmTxt?.setAlpha(1);
    }

    _buildConfirmButton() {
        const x = W / 2, y = VIEW_BOTTOM - 34;
        this._confirmBtn = this.add.rectangle(x, y, 200, 36, 0x1a3a1a)
            .setStrokeStyle(2, 0x4caf50).setInteractive({ useHandCursor: true })
            .setAlpha(0.4);
        this._confirmTxt = this.add.text(x, y, 'CONFIRM', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#a5d6a7',
        }).setOrigin(0.5).setAlpha(0.4);

        this._confirmBtn.on('pointerup', () => {
            if (!this._selected) return;
            this._confirm();
        });
    }

    _confirm() {
        this._confirmBtn.disableInteractive();
        this._confirmTxt.setText('SAVING...');

        apiFetch('/api/onboarding/start-clan', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ clan: this._selected }),
        })
        .then(r => r.json().then(d => ({ ok: r.ok, data: d })))
        .then(({ ok, data }) => {
            if (!ok) {
                this._confirmTxt.setText('CONFIRM');
                this._confirmBtn.setInteractive({ useHandCursor: true });
                this._toast(data.error || 'Could not save clan choice', '#e63946');
                return;
            }
            const player = this.registry.get('player') || {};
            player.chosen_clan = this._selected;
            this.registry.set('player', player);
            this.scene.start('MainMenuScene');
        })
        .catch(() => {
            this._confirmTxt.setText('CONFIRM');
            this._confirmBtn.setInteractive({ useHandCursor: true });
            this._toast('Network error', '#e63946');
        });
    }

    _toast(msg, color) {
        const t = this.add.text(W / 2, VIEW_BOTTOM - 64, msg, {
            fontSize: '11px', color, backgroundColor: '#000', padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(100);
        this.tweens.add({ targets: t, alpha: 0, delay: 1800, duration: 400,
            onComplete: () => t.destroy() });
    }
}
