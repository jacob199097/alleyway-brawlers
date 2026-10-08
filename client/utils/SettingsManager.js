/**
 * SETTINGS MANAGER
 * Singleton that owns all player-configurable settings.
 * Persists to localStorage and applies changes live to the Phaser game instance.
 *
 * Settings:
 *   bgmVolume   : 0.0 – 1.0
 *   sfxVolume   : 0.0 – 1.0
 *   quality     : 'low' | 'medium' | 'high'
 *
 * Usage:
 *   import { SettingsManager } from '../utils/SettingsManager.js';
 *   SettingsManager.init(phaserGame);        // call once in BootScene
 *   SettingsManager.bgmVolume = 0.5;         // updates live + saves
 *   SettingsManager.quality;                 // read current quality
 */

const STORAGE_KEY = 'twt_settings';

const DEFAULTS = {
    bgmVolume: 0.4,
    sfxVolume: 0.8,
    quality:   'high',
};

// Quality presets: map to concrete Phaser / rendering toggles.
// `resolutionScale` shrinks the render target (pixelated upscale) — battle
// effects, particles and animations always stay on so combat remains readable.
const QUALITY_PRESETS = {
    low: {
        roundPixels:       true,
        antialias:         false,
        animationsEnabled: true,
        particlesEnabled:  true,
        resolutionScale:   0.5,
    },
    medium: {
        roundPixels:       true,
        antialias:         false,
        animationsEnabled: true,
        particlesEnabled:  true,
        resolutionScale:   0.75,
    },
    high: {
        roundPixels:       false,
        antialias:         true,
        animationsEnabled: true,
        particlesEnabled:  true,
        resolutionScale:   1.0,
    },
};

class _SettingsManager {
    constructor() {
        this._game    = null;
        this._data    = { ...DEFAULTS };
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /**
     * Must be called once after the Phaser.Game instance is created.
     * Loads persisted settings and applies them immediately.
     * @param {Phaser.Game} game
     */
    init(game) {
        this._game = game;
        this._load();
        this._applyAll();
    }

    // ── BGM Volume ────────────────────────────────────────────────────────────

    get bgmVolume() { return this._data.bgmVolume; }

    set bgmVolume(value) {
        this._data.bgmVolume = Math.round(Math.max(0, Math.min(1, value)) * 100) / 100;
        this._applyBgm();
        this._save();
    }

    // ── SFX Volume ────────────────────────────────────────────────────────────

    get sfxVolume() { return this._data.sfxVolume; }

    set sfxVolume(value) {
        this._data.sfxVolume = Math.round(Math.max(0, Math.min(1, value)) * 100) / 100;
        this._applySfx();
        this._save();
    }

    // ── Quality ───────────────────────────────────────────────────────────────

    get quality() { return this._data.quality; }

    set quality(value) {
        if (!QUALITY_PRESETS[value]) return;
        this._data.quality = value;
        this._applyQuality();
        this._save();
    }

    /** Returns the full preset object for the current quality level. */
    get qualityPreset() { return QUALITY_PRESETS[this._data.quality]; }

    /** Convenience: should non-essential animations play? */
    get animationsEnabled() { return this.qualityPreset.animationsEnabled; }

    // ── Apply helpers ─────────────────────────────────────────────────────────

    _applyAll() {
        this._applyBgm();
        this._applySfx();
        this._applyQuality();
    }

    _applyBgm() {
        if (!this._game) return;
        // Find any currently-playing BGM track (keyed 'bgm_*') and update its volume
        const soundManager = this._game.sound;
        soundManager.getAll().forEach(sound => {
            if (sound.key?.startsWith('bgm_')) {
                sound.setVolume(this._data.bgmVolume);
            }
        });
    }

    _applySfx() {
        if (!this._game) return;
        // SFX sounds are played once and don't persist in the manager,
        // so we store the value and DuelScene reads it at play-time via
        // SettingsManager.sfxVolume when calling this.sound.play(key, { volume }).
        // Nothing to retroactively update here.
    }

    _applyQuality() {
        if (!this._game) return;
        const preset = this.qualityPreset;

        const renderer = this._game.renderer;
        const canvas   = this._game.canvas;
        if (renderer?.config) {
            renderer.config.roundPixels = preset.roundPixels;
        }

        // Reduce render resolution by lowering the renderer's pixel-density
        // multiplier. CSS dimensions stay the same so the smaller buffer is
        // upscaled to fit — animations and particles continue to run, they
        // just rasterise at fewer pixels.
        if (renderer && canvas) {
            const scale = preset.resolutionScale ?? 1;
            renderer.resolution = scale;
            canvas.style.imageRendering = scale < 1 ? 'pixelated' : 'auto';
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    _save() {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(this._data));
        } catch { /* storage unavailable */ }
    }

    _load() {
        try {
            const raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
                const parsed = JSON.parse(raw);
                // Merge — only accept known keys so stale data doesn't corrupt
                if (typeof parsed.bgmVolume === 'number') this._data.bgmVolume = parsed.bgmVolume;
                if (typeof parsed.sfxVolume === 'number') this._data.sfxVolume = parsed.sfxVolume;
                if (QUALITY_PRESETS[parsed.quality])       this._data.quality   = parsed.quality;
            }
        } catch { /* corrupt storage — use defaults */ }
    }

    /** Returns a plain copy of all settings (useful for UI initialisation). */
    snapshot() { return { ...this._data }; }
}

export const SettingsManager = new _SettingsManager();
export { QUALITY_PRESETS };
