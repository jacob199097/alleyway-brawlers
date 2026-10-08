import { getPlayerTitle } from '../utils/PlayerTitle.js';
import { apiFetch, TAP_VERB } from '../utils/Platform.js';
import { VIEW_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

// All profile icons available in-game — add new keys here as assets are added
const AVAILABLE_ICONS = ['profile_001', 'profile_002'];

export class ProfileScene extends Phaser.Scene {
    constructor() {
        super('ProfileScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.6);

        apiFetch('/api/profile/me')
            .then(r => r.json())
            .then(p => this._render(p))
            .catch(() => this.add.text(W / 2, H / 2, 'Failed to load profile.', {
                color: '#e63946', fontSize: '14px',
            }).setOrigin(0.5));
    }

    _render(p) {
        // ── Left column: identity + icon selector ─────────────────────────────
        const lx = 170;

        // Current profile icon (circular)
        const iconKey = (p.avatar_url && this.textures.exists(p.avatar_url))
            ? p.avatar_url : 'profile_001';
        const iconR = 44;
        const iconX = lx;
        const iconY = 60;

        const maskGfx = this.make.graphics({ add: false });
        maskGfx.fillCircle(iconX, iconY, iconR);
        this.add.image(iconX, iconY, iconKey)
            .setDisplaySize(iconR * 2, iconR * 2)
            .setMask(maskGfx.createGeometryMask());

        const gfx = this.add.graphics();
        gfx.lineStyle(2, 0x4cc9f0, 1);
        gfx.strokeCircle(iconX, iconY, iconR + 2);

        this.add.text(lx, 118, `${TAP_VERB.toUpperCase()} ICON TO CHANGE`, {
            fontSize: '7px', color: '#555577',
        }).setOrigin(0.5);

        // Icon selector row
        this._buildIconSelector(lx, p.avatar_url || 'profile_001');

        // Name / title / rank
        this.add.text(lx, 152, p.username, {
            fontSize: '20px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);
        this.add.text(lx, 174, getPlayerTitle(p.level), {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0.5);
        this.add.text(lx, 190, p.rank.replace(/_/g, ' ').toUpperCase(), {
            fontSize: '10px', color: '#4cc9f0',
        }).setOrigin(0.5);

        // Level + XP bar
        const xpInLevel = p.xp % Math.floor(100 * Math.pow(p.level, 1.5)) || 0;
        const xpNeeded  = Math.floor(100 * Math.pow(p.level, 1.5));
        const barW      = 240;
        this.add.text(lx, 210, `Level ${p.level}  —  ${xpInLevel} / ${xpNeeded} XP`, {
            fontSize: '10px', color: '#cccccc',
        }).setOrigin(0.5);
        this.add.rectangle(lx, 226, barW, 8, 0x1a1a3a).setOrigin(0.5);
        this.add.rectangle(lx - barW / 2, 226, barW * Math.min(1, xpInLevel / xpNeeded), 8, 0x4cc9f0).setOrigin(0, 0.5);

        this.add.text(lx, 244, `${p.rank_points} Rank Points`, {
            fontSize: '10px', color: '#888888',
        }).setOrigin(0.5);

        if (p.profile_bio) {
            this.add.text(lx, 264, `"${p.profile_bio}"`, {
                fontSize: '9px', color: '#888888', wordWrap: { width: 300 }, align: 'center',
            }).setOrigin(0.5);
        }

        // ── Right: stats grid (3 × 2) ─────────────────────────────────────────
        const stats = [
            ['Karat',      `${p.karat ?? 0}`],
            ['Contraband', `${p.contraband ?? 0}`],
            ['Wins',       `${p.wins}`],
            ['Losses',     `${p.losses}`],
            ['Win Rate',   p.wins + p.losses > 0 ? `${((p.wins / (p.wins + p.losses)) * 100).toFixed(1)}%` : '—'],
            ['Collection', `${(p.collection_pct || 0).toFixed(1)}%`],
        ];

        const colXs = [520, 650, 780];
        stats.forEach(([label, val], i) => {
            const col = i % 3;
            const row = Math.floor(i / 3);
            const x   = colXs[col];
            const y   = 100 + row * 100;

            this.add.rectangle(x, y, 110, 70, 0x1a1a2e).setStrokeStyle(1, 0x4cc9f0).setAlpha(0.85);
            this.add.text(x, y - 20, label.toUpperCase(), {
                fontSize: '8px', color: '#888888',
            }).setOrigin(0.5);
            this.add.text(x, y + 4, val.toString(), {
                fontSize: '18px', fontFamily: 'Arial Black', color: '#f4d35e',
            }).setOrigin(0.5);
        });

        this._makeBtn(lx, H - 30, '← BACK', () => this.scene.start('MainMenuScene'));
    }

    _buildIconSelector(cx, currentKey) {
        // Render available icons in a row; highlight the active one
        const iconSize = 32;
        const gap      = 8;
        const totalW   = AVAILABLE_ICONS.length * iconSize + (AVAILABLE_ICONS.length - 1) * gap;
        const startX   = cx - totalW / 2 + iconSize / 2;

        AVAILABLE_ICONS.forEach((key, i) => {
            const x       = startX + i * (iconSize + gap);
            const y       = 128;
            const isActive = key === currentKey;
            const r       = iconSize / 2;

            // Border (gold if active, dim otherwise)
            const gfx = this.add.graphics();
            gfx.lineStyle(isActive ? 2 : 1, isActive ? 0xf4d35e : 0x333355, 1);
            gfx.strokeCircle(x, y, r + 2);

            // Icon image with circular mask
            if (this.textures.exists(key)) {
                const mGfx = this.make.graphics({ add: false });
                mGfx.fillCircle(x, y, r);
                this.add.image(x, y, key)
                    .setDisplaySize(iconSize, iconSize)
                    .setMask(mGfx.createGeometryMask())
                    .setInteractive({ useHandCursor: true })
                    .on('pointerup', () => this._selectIcon(key));
            }
        });
    }

    _selectIcon(key) {
        apiFetch('/api/profile/me', {
            method:  'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ avatarUrl: key }),
        })
        .then(r => r.json())
        .then(d => {
            if (d.success) {
                const player = this.registry.get('player');
                if (player) { player.avatar_url = key; this.registry.set('player', player); }
                this.scene.restart();
            }
        })
        .catch(() => {});
    }

    _makeBtn(x, y, label, cb) {
        const btn = this.add.rectangle(x, y, 180, 36, 0x333355)
            .setStrokeStyle(1, 0xffffff).setInteractive().setOrigin(0.5);
        this.add.text(x, y, label, {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#fff',
        }).setOrigin(0.5);
        btn.on('pointerup', cb);
    }
}
