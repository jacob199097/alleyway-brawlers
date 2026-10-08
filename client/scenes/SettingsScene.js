import { SettingsManager } from '../utils/SettingsManager.js';

const W = 844;
const H = 390;

const CLR_PANEL    = 0x1a1a2e;
const CLR_ACCENT   = 0x4cc9f0;
const CLR_INACTIVE = 0x333355;
const CLR_ACTIVE   = 0x4cc9f0;
const CLR_GOLD     = 0xf4d35e;
const CLR_DANGER   = 0xe63946;

export class SettingsScene extends Phaser.Scene {
    constructor() { super('SettingsScene'); }

    create() {
        this.add.rectangle(W / 2, H / 2, W, H, 0x000000).setAlpha(0.72).setDepth(0);

        const panelW = 760;
        const panelH = 340;
        const px = W / 2;
        const py = H / 2;

        this.add.rectangle(px, py, panelW, panelH, CLR_PANEL)
            .setStrokeStyle(2, CLR_ACCENT).setDepth(1);

        this.add.text(px, py - panelH / 2 + 24, 'SETTINGS', {
            fontSize: '18px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(2);

        this.add.rectangle(px, py - panelH / 2 + 44, panelW - 40, 1, CLR_ACCENT)
            .setAlpha(0.4).setDepth(2);

        // Two columns
        const leftX  = px - 200;
        const rightX = px + 160;
        let cursorL  = py - panelH / 2 + 66;
        let cursorR  = py - panelH / 2 + 66;

        cursorL = this._sectionHeader('AUDIO', leftX - 80, cursorL);
        cursorL = this._volumeRow('BGM Volume', 'bgmVolume', leftX, cursorL);
        cursorL = this._volumeRow('SFX Volume', 'sfxVolume', leftX, cursorL);

        cursorR = this._sectionHeader('VIDEO', rightX - 80, cursorR);
        this._qualityRow(rightX, cursorR);

        this._closeBtn(px - 110, py + panelH / 2 - 28);
        this._logoutBtn(px + 110, py + panelH / 2 - 28);
    }

    _logoutBtn(x, y) {
        const btn = this.add.rectangle(x, y, 180, 36, 0x3a1010)
            .setStrokeStyle(2, CLR_DANGER).setDepth(2).setInteractive({ useHandCursor: true });
        this.add.text(x, y, 'LOG OUT', {
            fontSize: '13px', fontFamily: 'Arial Black', color: '#ffa7b0',
        }).setOrigin(0.5).setDepth(3);
        btn.on('pointerdown', () => btn.setAlpha(0.7));
        btn.on('pointerout',  () => btn.setAlpha(1));
        btn.on('pointerup', () => {
            btn.setAlpha(1);
            // Wipe stored credentials and registry, drop back to login.
            try { localStorage.removeItem('twt_token'); } catch {}
            this.registry.set('player', null);
            this.registry.set('token',  null);
            this.scene.stop('MainMenuScene');
            this.scene.stop();
            this.scene.start('LoginScene');
        });
    }

    _sectionHeader(label, x, y) {
        this.add.text(x, y, label, {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#aaaacc',
        }).setOrigin(0, 0.5).setDepth(2);
        return y + 24;
    }

    _volumeRow(label, key, cx, y) {
        const TRACK_W = 200;
        const TRACK_H = 5;
        const THUMB_R = 11;
        const trackY  = y + 28;

        this.add.text(cx - TRACK_W / 2, y + 6, label, {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0, 0.5).setDepth(2);

        const valText = this.add.text(cx + TRACK_W / 2 + 22, trackY,
            this._pct(SettingsManager[key]), {
                fontSize: '10px', color: '#aaaacc',
            }).setOrigin(0, 0.5).setDepth(2);

        this.add.rectangle(cx, trackY, TRACK_W, TRACK_H, CLR_INACTIVE).setOrigin(0.5).setDepth(2);
        const fill = this.add.rectangle(cx - TRACK_W / 2, trackY, TRACK_W * SettingsManager[key], TRACK_H, CLR_ACCENT)
            .setOrigin(0, 0.5).setDepth(2);

        const muteBtn = this.add.text(cx - TRACK_W / 2 - 26, trackY,
            SettingsManager[key] === 0 ? '🔇' : '🔊', { fontSize: '16px' })
            .setOrigin(0.5).setDepth(3).setInteractive({ useHandCursor: true });
        muteBtn._lastVol = SettingsManager[key] || 0.4;
        muteBtn.on('pointerdown', () => {
            if (SettingsManager[key] > 0) { muteBtn._lastVol = SettingsManager[key]; SettingsManager[key] = 0; muteBtn.setText('🔇'); }
            else { SettingsManager[key] = muteBtn._lastVol; muteBtn.setText('🔊'); }
            this.scene.restart();
        });

        const thumbX = cx - TRACK_W / 2 + TRACK_W * SettingsManager[key];
        const thumb  = this.add.circle(thumbX, trackY, THUMB_R, CLR_ACCENT)
            .setDepth(3).setInteractive({ useHandCursor: true, draggable: true });

        const hitZone = this.add.rectangle(cx, trackY, TRACK_W + THUMB_R * 2, 36, 0x000000)
            .setAlpha(0.001).setDepth(3).setInteractive({ useHandCursor: true });

        const update = (worldX) => {
            const left = cx - TRACK_W / 2;
            const pct  = Phaser.Math.Clamp((worldX - left) / TRACK_W, 0, 1);
            const snp  = Math.round(pct * 20) / 20;
            thumb.setPosition(left + TRACK_W * snp, trackY);
            fill.width = TRACK_W * snp;
            valText.setText(this._pct(snp));
            SettingsManager[key] = snp;
            muteBtn.setText(snp === 0 ? '🔇' : '🔊');
        };

        this.input.setDraggable(thumb);
        thumb.on('drag', (_p, dragX) => update(dragX));
        hitZone.on('pointerdown', ptr => update(ptr.x));

        return y + 72;
    }

    _qualityRow(cx, y) {
        const tiers   = ['low', 'medium', 'high'];
        const labels  = ['LOW', 'MEDIUM', 'HIGH'];
        const descs   = { low: 'No FX', medium: 'Basic FX', high: 'Full FX' };
        const btnW    = 90;
        const gap     = 8;
        const totalW  = tiers.length * btnW + (tiers.length - 1) * gap;
        const startX  = cx - totalW / 2;
        const btnY    = y + 56;

        this.add.text(cx - totalW / 2, y + 6, 'Render Quality', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0, 0.5).setDepth(2);

        tiers.forEach((tier, i) => {
            const bx     = startX + i * (btnW + gap) + btnW / 2;
            const active = SettingsManager.quality === tier;
            const btn    = this.add.rectangle(bx, btnY, btnW, 44,
                active ? CLR_ACTIVE : CLR_INACTIVE)
                .setStrokeStyle(active ? 2 : 1, active ? CLR_GOLD : CLR_INACTIVE)
                .setDepth(2).setInteractive({ useHandCursor: true });
            this.add.text(bx, btnY - 8, labels[i], {
                fontSize: '11px', fontFamily: 'Arial Black', color: active ? '#000000' : '#aaaacc',
            }).setOrigin(0.5).setDepth(3);
            this.add.text(bx, btnY + 10, descs[tier], {
                fontSize: '7px', color: active ? '#000000' : '#666688',
            }).setOrigin(0.5).setDepth(3);
            btn.on('pointerdown', () => { SettingsManager.quality = tier; this.scene.restart(); });
        });
    }

    _closeBtn(x, y) {
        const btn = this.add.rectangle(x, y, 180, 36, CLR_DANGER)
            .setStrokeStyle(1, 0xffffff).setDepth(2).setInteractive({ useHandCursor: true });
        this.add.text(x, y, 'CLOSE', {
            fontSize: '13px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(3);
        btn.on('pointerdown', () => btn.setAlpha(0.7));
        btn.on('pointerup', () => {
            btn.setAlpha(1);
            this.scene.stop();
            this.scene.resume('MainMenuScene');
        });
        btn.on('pointerout', () => btn.setAlpha(1));
    }

    _throttledSfxPreview() {
        if (this._sfxCooldown) return;
        this._sfxCooldown = true;
        try { this.sound.play('sfx_card_play', { volume: SettingsManager.sfxVolume }); } catch (_) {}
        this.time.delayedCall(400, () => { this._sfxCooldown = false; });
    }

    _pct(v) { return `${Math.round(v * 100)}%`; }
}
