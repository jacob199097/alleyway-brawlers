import { SettingsManager, OPTIONS } from '../utils/SettingsManager.js';
import { isDesktop } from '../utils/Platform.js';

const W = 844;
const H = 390;

const CLR_PANEL    = 0x1a1a2e;
const CLR_ACCENT   = 0x4cc9f0;
const CLR_INACTIVE = 0x333355;
const CLR_ACTIVE   = 0x4cc9f0;
const CLR_GOLD     = 0xf4d35e;
const CLR_DANGER   = 0xe63946;

// Kept across scene.restart() (used to redraw after every change)
let currentTab   = 'audio';
let displayDraft = null;   // Display tab choices not yet applied

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

        this._closeBtn(px - 110, py + panelH / 2 - 28);
        this._logoutBtn(px + 110, py + panelH / 2 - 28);

        if (isDesktop) {
            this._tabs(px, py - panelH / 2 + 64);
            if (currentTab === 'audio')    this._audioTab(px, py - panelH / 2 + 92);
            if (currentTab === 'display')  this._displayTab(py - panelH / 2 + 104);
            if (currentTab === 'graphics') this._graphicsTab(py - panelH / 2 + 98);
            return;
        }

        // Web: two columns
        const leftX  = px - 200;
        const rightX = px + 160;
        let cursorL  = py - panelH / 2 + 66;
        let cursorR  = py - panelH / 2 + 66;

        cursorL = this._sectionHeader('AUDIO', leftX - 80, cursorL);
        cursorL = this._volumeRow('BGM Volume', 'bgmVolume', leftX, cursorL);
        cursorL = this._volumeRow('SFX Volume', 'sfxVolume', leftX, cursorL);

        cursorR = this._sectionHeader('VIDEO', rightX - 80, cursorR);
        this._qualityRow(rightX, cursorR);
    }

    // ── Desktop tabs ──────────────────────────────────────────────────────────

    _tabs(cx, y) {
        const tabs = [['audio', 'AUDIO'], ['display', 'DISPLAY'], ['graphics', 'GRAPHICS']];
        tabs.forEach(([key, label], i) => {
            const x      = cx + (i - 1) * 140;
            const active = currentTab === key;
            const btn = this.add.rectangle(x, y, 130, 24, active ? CLR_ACTIVE : CLR_INACTIVE)
                .setStrokeStyle(1, active ? CLR_GOLD : CLR_INACTIVE)
                .setDepth(2).setInteractive({ useHandCursor: true });
            this.add.text(x, y, label, {
                fontSize: '11px', fontFamily: 'Arial Black', color: active ? '#000000' : '#aaaacc',
            }).setOrigin(0.5).setDepth(3);
            btn.on('pointerup', () => { currentTab = key; this.scene.restart(); });
        });
    }

    _audioTab(cx, y) {
        y = this._volumeRow('BGM Volume', 'bgmVolume', cx, y);
        this._volumeRow('SFX Volume', 'sfxVolume', cx, y);
    }

    _displayTab(y) {
        const labelX = 200, selX = 540, rowH = 36;
        const loading = this.add.text(W / 2, y + rowH, 'Loading displays…', {
            fontSize: '11px', color: '#aaaacc',
        }).setOrigin(0.5).setDepth(2);

        window.desktop.display.info().then(info => {
            if (!this.scene.isActive()) return;
            loading.destroy();
            const current = info.current;
            const draft   = displayDraft ??= { ...current };
            const monitor = info.displays.find(d => d.id === draft.displayId) || info.displays[0];
            const windowed = draft.displayMode === 'windowed';
            const redraw  = (patch) => { Object.assign(draft, patch); this.scene.restart(); };

            this._cycleRow(labelX, selX, y, 'Display Mode',
                ['windowed', 'borderless', 'fullscreen'], v => v.toUpperCase(),
                draft.displayMode, v => redraw({ displayMode: v }), { width: 200 });

            const sizes   = monitor.resolutions;
            const sizeKey = ([w, h]) => `${w}×${h}`;
            const chosen  = sizes.find(([w, h]) => w === draft.windowWidth && h === draft.windowHeight)
                         || sizes[sizes.length - 1];
            this._cycleRow(labelX, selX, y + rowH, 'Resolution',
                windowed ? sizes : [monitor.native], sizeKey,
                windowed ? chosen : monitor.native,
                ([w, h]) => redraw({ windowWidth: w, windowHeight: h }),
                { width: 200, enabled: windowed });

            this._cycleRow(labelX, selX, y + rowH * 2, 'Monitor',
                info.displays.map(d => d.id), id => info.displays.find(d => d.id === id).label,
                monitor.id, id => redraw({ displayId: id }),
                { width: 200, enabled: info.displays.length > 1 });

            const resolved = { ...draft, windowWidth: chosen[0], windowHeight: chosen[1], displayId: monitor.id };
            const changed  = ['displayMode', 'displayId', 'windowWidth', 'windowHeight']
                .some(k => resolved[k] !== current[k]);
            const apply = this._smallBtn(W / 2, y + rowH * 3 + 14, 'APPLY', changed, () => {
                apply.label.setText('CONFIRM…');
                window.desktop.display.apply(resolved).then(() => {
                    displayDraft = null;
                    if (this.scene.isActive()) this.scene.restart();
                });
            });
            this.add.text(W / 2, y + rowH * 3 + 46,
                'You will be asked to keep the new settings — they revert after 10 seconds otherwise.', {
                    fontSize: '9px', fontFamily: 'Arial', color: '#8888aa',
                }).setOrigin(0.5).setDepth(2);
        });
    }

    _graphicsTab(y) {
        const S = SettingsManager;
        const onOff = v => (v ? 'ON' : 'OFF');
        const set = key => v => { S.set(key, v); this.scene.restart(); };
        const rowH = 30;
        const L = { label: 66, sel: 318 };
        const R = { label: 444, sel: 690 };

        this._cycleRow(L.label, L.sel, y, 'Quality',
            ['low', 'medium', 'high', 'custom'], v => v.toUpperCase(), S.quality,
            v => { S.quality = v; this.scene.restart(); });
        this._cycleRow(L.label, L.sel, y + rowH, 'Render Scale',
            OPTIONS.renderScale, v => `${v * 100}%`, S.get('renderScale'), set('renderScale'));
        this._cycleRow(L.label, L.sel, y + rowH * 2, 'Anti-aliasing',
            [true, false], onOff, S.get('antialias'), set('antialias'), { note: 'restart' });
        this._cycleRow(L.label, L.sel, y + rowH * 3, 'Blur Effects',
            [true, false], onOff, S.get('postFx'), set('postFx'));
        this._cycleRow(L.label, L.sel, y + rowH * 4, 'Menu Video',
            [true, false], onOff, S.get('videoBackground'), set('videoBackground'));
        this._cycleRow(L.label, L.sel, y + rowH * 5, 'Particles',
            OPTIONS.particleDensity, v => ({ 0.5: 'LOW', 0.75: 'MEDIUM', 1: 'HIGH' }[v]),
            S.get('particleDensity'), set('particleDensity'));

        this._cycleRow(R.label, R.sel, y, 'V-Sync',
            [true, false], onOff, S.get('vsync'), set('vsync'), { note: 'restart' });
        this._cycleRow(R.label, R.sel, y + rowH, 'FPS Cap',
            OPTIONS.fpsLimit, v => (v ? `${v}` : 'UNLIMITED'), S.get('fpsLimit'), set('fpsLimit'));
        this._cycleRow(R.label, R.sel, y + rowH * 2, 'Show FPS',
            [true, false], onOff, S.get('showFps'), set('showFps'));
        this._cycleRow(R.label, R.sel, y + rowH * 3, 'Pause Unfocused',
            [true, false], onOff, S.get('pauseOnBlur'), set('pauseOnBlur'));

        const pending = S.pendingRestart;
        if (pending.length) {
            this.add.text(R.label, y + rowH * 4 + 4, `Restart required: ${pending.join(', ')}`, {
                fontSize: '10px', fontFamily: 'Arial', color: '#f4d35e',
            }).setOrigin(0, 0.5).setDepth(2);
            this._smallBtn(R.sel - 10, y + rowH * 5, 'APPLY & RESTART', true, () => window.desktop.relaunch(), 170);
        }
    }

    /**
     * Label + "◀ value ▶" selector. Clicking the value or ▶ steps forward, ◀ steps back.
     * values are compared with ===, fmt turns a value into display text.
     */
    _cycleRow(labelX, cx, y, label, values, fmt, current, onChange, opts = {}) {
        const { note, enabled = true, width = 150 } = opts;
        const labelText = this.add.text(labelX, y, label, {
            fontSize: '12px', fontFamily: 'Arial Black', color: enabled ? '#ffffff' : '#666688',
        }).setOrigin(0, 0.5).setDepth(2);
        if (note) {
            this.add.text(labelX + labelText.width + 6, y + 1, `(${note})`, {
                fontSize: '9px', fontFamily: 'Arial', color: '#f4d35e',
            }).setOrigin(0, 0.5).setDepth(2);
        }

        const idx = Math.max(0, values.indexOf(current));
        const box = this.add.rectangle(cx, y, width, 22, CLR_INACTIVE)
            .setStrokeStyle(1, enabled ? CLR_ACCENT : CLR_INACTIVE).setDepth(2);
        this.add.text(cx, y, fmt(values[idx]), {
            fontSize: '11px', fontFamily: 'Arial Black', color: enabled ? '#ffffff' : '#666688',
        }).setOrigin(0.5).setDepth(3);
        if (!enabled || values.length < 2) { box.setAlpha(0.5); return; }

        const step = d => onChange(values[(idx + d + values.length) % values.length]);
        box.setInteractive({ useHandCursor: true }).on('pointerup', () => step(1));
        [[-1, '◀'], [1, '▶']].forEach(([d, glyph]) => {
            this.add.text(cx + d * (width / 2 - 11), y, glyph, {
                fontSize: '10px', color: '#4cc9f0',
            }).setOrigin(0.5).setDepth(4).setPadding(6, 4)
                .setInteractive({ useHandCursor: true })
                .on('pointerup', () => step(d));
        });
    }

    _smallBtn(x, y, label, enabled, cb, width = 140) {
        const btn = this.add.rectangle(x, y, width, 26, enabled ? CLR_ACTIVE : CLR_INACTIVE)
            .setStrokeStyle(1, enabled ? CLR_GOLD : CLR_INACTIVE).setDepth(2);
        btn.label = this.add.text(x, y, label, {
            fontSize: '11px', fontFamily: 'Arial Black', color: enabled ? '#000000' : '#666688',
        }).setOrigin(0.5).setDepth(3);
        if (enabled) {
            btn.setInteractive({ useHandCursor: true }).on('pointerup', () => {
                btn.disableInteractive();
                cb();
            });
        }
        return btn;
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
        hitZone.on('pointerdown', ptr => update(ptr.worldX));

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
            displayDraft = null;
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
