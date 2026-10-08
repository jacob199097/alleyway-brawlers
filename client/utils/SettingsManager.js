/**
 * SETTINGS MANAGER
 * Singleton that owns all player-configurable settings.
 * Persists to localStorage on web and to settings.json (via window.desktop) on desktop,
 * and applies changes live to the Phaser game instance.
 *
 * Settings:
 *   bgmVolume, sfxVolume : 0.0 – 1.0
 *   quality              : 'low' | 'medium' | 'high' | 'custom' — preset over the keys below
 *   renderScale          : canvas pixels relative to the window (desktop only, see Graphics.js)
 *   antialias            : WebGL antialiasing (applies on restart)
 *   postFx               : blur on the match-end screens
 *   videoBackground      : animated menu background (static image when off)
 *   particleDensity      : multiplier on combat particle counts
 *   vsync                : desktop only, applies on restart (Chromium switch in desktop/main.js)
 *   fpsLimit             : 0 = unlimited
 *   showFps, pauseOnBlur : desktop only
 *
 * Usage:
 *   import { SettingsManager } from '../utils/SettingsManager.js';
 *   SettingsManager.init(phaserGame);        // call once in BootScene
 *   SettingsManager.bgmVolume = 0.5;         // updates live + saves
 *   SettingsManager.set('fpsLimit', 144);    // any key
 */

import { isDesktop } from './Platform.js';
import { Graphics } from './Graphics.js';

const STORAGE_KEY = 'twt_settings';

// Quality presets: the graphics keys a preset sets. Changing any of them by hand → 'custom'.
const QUALITY_PRESETS = {
    low: {
        renderScale:     0.75,
        antialias:       false,
        postFx:          false,
        videoBackground: false,
        particleDensity: 0.5,
    },
    medium: {
        renderScale:     1,
        antialias:       true,
        postFx:          false,
        videoBackground: true,
        particleDensity: 0.75,
    },
    high: {
        renderScale:     1,
        antialias:       true,
        postFx:          true,
        videoBackground: true,
        particleDensity: 1,
    },
};
const PRESET_KEYS = Object.keys(QUALITY_PRESETS.high);

/** Allowed values for the multiple-choice settings (also drives the settings UI). */
export const OPTIONS = {
    renderScale:     [0.5, 0.75, 1, 1.5, 2],
    particleDensity: [0.5, 0.75, 1],
    fpsLimit:        [30, 60, 120, 144, 165, 240, 0],
};

const DEFAULTS = {
    bgmVolume:   0.4,
    sfxVolume:   0.8,
    quality:     'high',
    ...QUALITY_PRESETS.high,
    vsync:       true,
    fpsLimit:    0,
    showFps:     false,
    pauseOnBlur: false,
};

const isBool   = v => typeof v === 'boolean';
const isVolume = v => typeof v === 'number' && v >= 0 && v <= 1;
const VALID = {
    bgmVolume:       isVolume,
    sfxVolume:       isVolume,
    quality:         v => v === 'custom' || !!QUALITY_PRESETS[v],
    renderScale:     v => OPTIONS.renderScale.includes(v),
    antialias:       isBool,
    postFx:          isBool,
    videoBackground: isBool,
    particleDensity: v => OPTIONS.particleDensity.includes(v),
    vsync:           isBool,
    fpsLimit:        v => OPTIONS.fpsLimit.includes(v),
    showFps:         isBool,
    pauseOnBlur:     isBool,
};

class _SettingsManager {
    constructor() {
        this._game = null;
        this._data = { ...DEFAULTS };
        // Loaded at import time so main.js can build the Phaser config from it
        this._load();
        this._launchAntialias = this._data.antialias;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /**
     * Must be called once after the Phaser.Game instance is created.
     * Applies the loaded settings to it.
     * @param {Phaser.Game} game
     */
    init(game) {
        this._game = game;
        Graphics.init(game, this._data);
        this._applyBgm();
    }

    // ── Generic access ────────────────────────────────────────────────────────

    get(key) { return this._data[key]; }

    set(key, value) {
        if (!VALID[key]?.(value)) return;
        if (key === 'quality') { this.quality = value; return; }
        this._data[key] = value;
        if (PRESET_KEYS.includes(key)) this._data.quality = this._matchPreset();
        this._apply(key);
        this._save();
    }

    // ── Audio ─────────────────────────────────────────────────────────────────

    get bgmVolume() { return this._data.bgmVolume; }
    set bgmVolume(value) { this.set('bgmVolume', Math.round(Math.max(0, Math.min(1, value)) * 100) / 100); }

    get sfxVolume() { return this._data.sfxVolume; }
    set sfxVolume(value) { this.set('sfxVolume', Math.round(Math.max(0, Math.min(1, value)) * 100) / 100); }

    // ── Graphics ──────────────────────────────────────────────────────────────

    get quality() { return this._data.quality; }

    /** Picking a preset overwrites the preset keys; 'custom' just keeps the current values. */
    set quality(value) {
        if (!VALID.quality(value)) return;
        this._data.quality = value;
        if (QUALITY_PRESETS[value]) {
            Object.assign(this._data, QUALITY_PRESETS[value]);
            PRESET_KEYS.forEach(k => this._apply(k));
        }
        this._save();
    }

    get antialias()       { return this._data.antialias; }
    get postFx()          { return this._data.postFx; }
    get videoBackground() { return this._data.videoBackground; }
    get fpsLimit()        { return isDesktop ? this._data.fpsLimit : 0; }

    /** Effects always play; quality only thins out particle counts. */
    get animationsEnabled() { return true; }

    /** Scale a particle count by the density setting (never below 1). */
    particles(count) { return Math.max(1, Math.round(count * this._data.particleDensity)); }

    /** Settings that changed since launch and only take effect after a restart. */
    get pendingRestart() {
        const pending = [];
        if (this._data.antialias !== this._launchAntialias) pending.push('Anti-aliasing');
        if (isDesktop && this._data.vsync !== window.desktop.launch?.vsync) pending.push('V-sync');
        return pending;
    }

    // ── Apply helpers ─────────────────────────────────────────────────────────

    _apply(key) {
        if (!this._game) return;
        switch (key) {
            case 'bgmVolume':       this._applyBgm(); break;
            case 'renderScale':     Graphics.setRenderScale(this._data.renderScale); break;
            case 'fpsLimit':        Graphics.setFpsLimit(this.fpsLimit); break;
            case 'showFps':         Graphics.setShowFps(this._data.showFps); break;
            case 'pauseOnBlur':     Graphics.setPauseOnBlur(this._data.pauseOnBlur); break;
            case 'videoBackground': this._restartVideoBackground(); break;
            // sfxVolume, postFx, particleDensity are read at use; antialias & vsync need a restart
        }
    }

    _applyBgm() {
        if (!this._game) return;
        // Find any currently-playing BGM track (keyed 'bgm_*') and update its volume
        this._game.sound.getAll().forEach(sound => {
            if (sound.key?.startsWith('bgm_')) sound.setVolume(this._data.bgmVolume);
        });
    }

    _restartVideoBackground() {
        const scenes = this._game.scene;
        if (scenes.isActive('VideoBackgroundScene')) scenes.getScene('VideoBackgroundScene').scene.restart();
    }

    _matchPreset() {
        const match = Object.entries(QUALITY_PRESETS)
            .find(([, preset]) => PRESET_KEYS.every(k => preset[k] === this._data[k]));
        return match ? match[0] : 'custom';
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    _save() {
        if (isDesktop) {
            window.desktop.settings.set({ ...this._data });
            return;
        }
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(this._data));
        } catch { /* storage unavailable */ }
    }

    _readStored() {
        if (isDesktop) {
            const stored = window.desktop.settings.get();
            if ('quality' in stored) return stored;
            // First run on settings.json — carry over what earlier builds kept in localStorage
        }
        try {
            return JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
        } catch { return null; }
    }

    _load() {
        const stored = this._readStored();
        if (!stored || typeof stored !== 'object') return;
        // A saved preset fills in any preset keys older saves don't have
        if (QUALITY_PRESETS[stored.quality]) Object.assign(this._data, QUALITY_PRESETS[stored.quality]);
        // Merge — only accept known keys with valid values so stale data doesn't corrupt
        for (const key of Object.keys(VALID)) {
            if (key in stored && VALID[key](stored[key])) this._data[key] = stored[key];
        }
    }

    /** Returns a plain copy of all settings (useful for UI initialisation). */
    snapshot() { return { ...this._data }; }
}

export const SettingsManager = new _SettingsManager();
export { QUALITY_PRESETS };
