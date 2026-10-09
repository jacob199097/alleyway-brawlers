/**
 * SFX
 * Plays a sound effect by key. Uses the loaded audio file when there is one, otherwise
 * synthesises a short punchy sound with WebAudio so every action still has audio feedback
 * (the game ships without sound-effect files for now).
 *
 *   Sfx.play(scene, 'sfx_attack')
 *   Sfx.play(scene, 'sfx_card_play', { pitch: 0.8 })   // pitch < 1 = deeper
 */

import { SettingsManager } from './SettingsManager.js';

// ── Synth building blocks ────────────────────────────────────────────────────

function out(ctx, volume) {
    const g = ctx.createGain();
    g.gain.value = volume;
    g.connect(ctx.destination);
    return g;
}

/** Oscillator note with an attack/decay envelope; `to` glides the pitch. */
function tone(ctx, dest, { type = 'sine', from, to = from, at = 0, dur = 0.2, vol = 0.5 }) {
    const t0  = ctx.currentTime + at;
    const osc = ctx.createOscillator();
    const env = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(from, t0);
    if (to !== from) osc.frequency.exponentialRampToValueAtTime(Math.max(1, to), t0 + dur);
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.exponentialRampToValueAtTime(vol, t0 + 0.008);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(env).connect(dest);
    osc.start(t0);
    osc.stop(t0 + dur + 0.02);
}

let noiseBuf = null;
/** Filtered noise burst (whooshes, hits, crunches). */
function noise(ctx, dest, { at = 0, dur = 0.2, vol = 0.5, filter = 'lowpass', freq = 1200, toFreq = freq, q = 0.8 }) {
    if (!noiseBuf || noiseBuf.sampleRate !== ctx.sampleRate) {
        noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
        const d = noiseBuf.getChannelData(0);
        for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    }
    const t0  = ctx.currentTime + at;
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = filter;
    f.Q.value = q;
    f.frequency.setValueAtTime(freq, t0);
    if (toFreq !== freq) f.frequency.exponentialRampToValueAtTime(Math.max(20, toFreq), t0 + dur);
    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.exponentialRampToValueAtTime(vol, t0 + 0.01);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    src.connect(f).connect(env).connect(dest);
    src.start(t0, Math.random() * 0.5);
    src.stop(t0 + dur + 0.02);
}

// ── Sound recipes (p = pitch multiplier) ────────────────────────────────────

const RECIPES = {
    // Card hits the table: low thump + slap
    sfx_card_play: (c, d, p) => {
        tone(c, d, { type: 'sine', from: 160 * p, to: 55 * p, dur: 0.22, vol: 0.9 });
        noise(c, d, { dur: 0.08, vol: 0.5, filter: 'bandpass', freq: 2400 * p, q: 1.2 });
    },
    // Card slides off the deck
    sfx_draw: (c, d, p) => {
        noise(c, d, { dur: 0.16, vol: 0.35, filter: 'bandpass', freq: 1800 * p, toFreq: 4200 * p, q: 1.5 });
        tone(c, d, { type: 'triangle', from: 900 * p, to: 1400 * p, at: 0.05, dur: 0.07, vol: 0.12 });
    },
    // Swing + punch
    sfx_attack: (c, d, p) => {
        noise(c, d, { dur: 0.18, vol: 0.45, filter: 'bandpass', freq: 600 * p, toFreq: 3000 * p, q: 0.9 });
        tone(c, d, { type: 'square', from: 220 * p, to: 70 * p, at: 0.12, dur: 0.16, vol: 0.35 });
        noise(c, d, { at: 0.12, dur: 0.12, vol: 0.6, filter: 'lowpass', freq: 900 * p });
    },
    // Card shatters
    sfx_destroy: (c, d, p) => {
        tone(c, d, { type: 'sawtooth', from: 180 * p, to: 40 * p, dur: 0.45, vol: 0.45 });
        noise(c, d, { dur: 0.5, vol: 0.7, filter: 'lowpass', freq: 3000 * p, toFreq: 200 * p });
        noise(c, d, { at: 0.04, dur: 0.25, vol: 0.3, filter: 'highpass', freq: 3500 * p });
    },
    // Morale damage to a player
    sfx_damage: (c, d, p) => {
        tone(c, d, { type: 'sine', from: 110 * p, to: 45 * p, dur: 0.35, vol: 0.9 });
        noise(c, d, { dur: 0.2, vol: 0.4, filter: 'lowpass', freq: 600 * p });
    },
    // Effect activates: bright shimmer
    sfx_effect: (c, d, p) => {
        [660, 880, 1320].forEach((f, i) => tone(c, d, { type: 'triangle', from: f * p, at: i * 0.05, dur: 0.3, vol: 0.18 }));
        noise(c, d, { dur: 0.3, vol: 0.12, filter: 'highpass', freq: 5000 });
    },
    // Trap springs
    sfx_ambush: (c, d, p) => {
        tone(c, d, { type: 'square', from: 880 * p, to: 440 * p, dur: 0.12, vol: 0.2 });
        tone(c, d, { type: 'sawtooth', from: 120 * p, to: 60 * p, at: 0.06, dur: 0.3, vol: 0.4 });
    },
    // Promotion: rising arpeggio
    sfx_promote: (c, d, p) => {
        [392, 523, 659, 784, 1047].forEach((f, i) => tone(c, d, { type: 'triangle', from: f * p, at: i * 0.06, dur: 0.25, vol: 0.22 }));
    },
    // Phase / turn change chime
    sfx_phase: (c, d, p) => {
        tone(c, d, { type: 'sine', from: 740 * p, dur: 0.18, vol: 0.2 });
        tone(c, d, { type: 'sine', from: 988 * p, at: 0.07, dur: 0.22, vol: 0.18 });
    },
    sfx_turn: (c, d, p) => {
        tone(c, d, { type: 'triangle', from: 523 * p, dur: 0.2, vol: 0.25 });
        tone(c, d, { type: 'triangle', from: 784 * p, at: 0.1, dur: 0.3, vol: 0.25 });
        noise(c, d, { dur: 0.25, vol: 0.15, filter: 'bandpass', freq: 1200, toFreq: 300 });
    },
    sfx_click: (c, d, p) => tone(c, d, { type: 'square', from: 1200 * p, to: 800 * p, dur: 0.04, vol: 0.12 }),
    sfx_victory: (c, d, p) => {
        [523, 659, 784, 1047].forEach((f, i) => tone(c, d, { type: 'triangle', from: f * p, at: i * 0.12, dur: 0.5, vol: 0.25 }));
    },
    sfx_defeat: (c, d, p) => {
        [392, 349, 311, 233].forEach((f, i) => tone(c, d, { type: 'sawtooth', from: f * p, at: i * 0.16, dur: 0.5, vol: 0.18 }));
    },
};

export const Sfx = {
    play(scene, key, { pitch = 1, volume = 1 } = {}) {
        const vol = SettingsManager.sfxVolume * volume;
        if (vol <= 0) return;
        try {
            if (scene.cache.audio.exists(key)) {
                scene.sound.play(key, { volume: vol, rate: pitch });
                return;
            }
            const recipe = RECIPES[key];
            const ctx = scene.sound.context;   // WebAudio sound manager only
            if (!recipe || !ctx || ctx.state === 'closed') return;
            if (ctx.state === 'suspended') ctx.resume?.();
            recipe(ctx, out(ctx, vol * 0.6), pitch);
        } catch (_) { /* audio is never allowed to break gameplay */ }
    },
};
