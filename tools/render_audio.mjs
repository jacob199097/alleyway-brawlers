// Renders the game's stand-in sounds, ambience and music into assets/sfx as WAV files: synthesised
// here (noise, oscillators, filters, reverb), so the game has every sound before real recordings or
// generated tracks replace them. A file you drop into assets/sfx with the same name (as .ogg, .mp3 or
// .wav) replaces the stand-in: delete the stand-in .wav, then deploy (players download it). Stand-ins
// carry a marker (an INFO "ISFT" of render_audio), so a recording is never rendered over.
//   node tools/render_audio.mjs            every sound
//   node tools/render_audio.mjs amb_crowd  just these
// docs/AUDIO_PROMPTS.md has what each one is for, and prompts to generate the real thing.
import { writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'sfx');
const TAU = Math.PI * 2;

// ── basics ──────────────────────────────────────────────────────────────────

/** A repeatable random number generator (0 <= x < 1). */
function rng(seed) {
    let t = seed >>> 0;
    return () => {
        t += 0x6d2b79f5;
        let r = Math.imul(t ^ (t >>> 15), t | 1);
        r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
        return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
}

const MARK = 'render_audio';
/** Whether a WAV in assets/sfx is one of ours (a stand-in) rather than a recording. */
function isStandIn(file) {
    return readFileSync(file).includes(Buffer.from('ISFT')) && readFileSync(file).includes(Buffer.from(MARK));
}

/** 16-bit PCM WAV, mono or stereo (channels: arrays of floats in -1..1), marked as a stand-in. */
function writeWav(name, rate, channels) {
    const n = channels[0].length, ch = channels.length;
    const info = Buffer.alloc(4 + 8 + 12 + 4);   // LIST INFO with ISFT "render_audio" (+ padding)
    info.write('INFO', 0); info.write('ISFT', 4); info.writeUInt32LE(13, 8); info.write(MARK, 12);
    const listSize = info.length;
    const buf = Buffer.alloc(44 + n * ch * 2 + 8 + listSize);
    buf.write('RIFF', 0); buf.writeUInt32LE(buf.length - 8, 4); buf.write('WAVE', 8);
    buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(ch, 22);
    buf.writeUInt32LE(rate, 24); buf.writeUInt32LE(rate * ch * 2, 28); buf.writeUInt16LE(ch * 2, 32); buf.writeUInt16LE(16, 34);
    buf.write('data', 36); buf.writeUInt32LE(n * ch * 2, 40);
    let o = 44;
    for (let i = 0; i < n; i++) {
        for (let c = 0; c < ch; c++) {
            buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, channels[c][i])) * 32767), o);
            o += 2;
        }
    }
    buf.write('LIST', o); buf.writeUInt32LE(listSize, o + 4); info.copy(buf, o + 8);
    writeFileSync(join(OUT, name + '.wav'), buf);
    console.log(`${name}.wav  ${(n / rate).toFixed(1)} s, ${ch === 2 ? 'stereo' : 'mono'}, ${(buf.length / 1024).toFixed(0)} KB`);
}

/** Scales so the loudest sample is at `peak` (0..1). */
function normalize(channels, peak) {
    let m = 1e-9;
    for (const c of channels) for (const v of c) m = Math.max(m, Math.abs(v));
    for (const c of channels) for (let i = 0; i < c.length; i++) c[i] *= peak / m;
    return channels;
}

/** Seamless loop: render `len + xf` seconds, then fold the extra tail over the start (equal power). */
function loopFold(channels, rate, len) {
    const L = Math.round(len * rate);
    return channels.map((c) => {
        const xf = c.length - L, out = c.slice(0, L);
        for (let i = 0; i < xf; i++) {
            const k = i / xf;
            out[i] = c[i] * Math.sin(k * Math.PI / 2) + c[L + i] * Math.cos(k * Math.PI / 2);
        }
        return out;
    });
}

/** Fades the start and end (seconds) so one-shots never click. */
function fades(channels, rate, inSec, outSec) {
    for (const c of channels) {
        const a = Math.round(inSec * rate), b = Math.round(outSec * rate);
        for (let i = 0; i < a && i < c.length; i++) c[i] *= i / a;
        for (let i = 0; i < b && i < c.length; i++) c[c.length - 1 - i] *= i / b;
    }
    return channels;
}

// ── filters and generators ──────────────────────────────────────────────────

/** RBJ biquad: lp, hp, bp (constant peak), peak. Call .run(x) per sample. */
function biquad(type, rate, freq, q = 0.707, gainDb = 0) {
    const f = { b0: 0, b1: 0, b2: 0, a1: 0, a2: 0, x1: 0, x2: 0, y1: 0, y2: 0 };
    f.set = (fr, qq = q) => {
        const w = TAU * Math.min(fr, rate * 0.45) / rate, cs = Math.cos(w), al = Math.sin(w) / (2 * qq);
        const A = Math.pow(10, gainDb / 40);
        let b0, b1, b2, a0, a1, a2;
        if (type === 'lp') { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
        else if (type === 'hp') { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
        else if (type === 'bp') { b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
        else { b0 = 1 + al * A; b1 = -2 * cs; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * cs; a2 = 1 - al / A; }
        f.b0 = b0 / a0; f.b1 = b1 / a0; f.b2 = b2 / a0; f.a1 = a1 / a0; f.a2 = a2 / a0;
    };
    f.run = (x) => {
        const y = f.b0 * x + f.b1 * f.x1 + f.b2 * f.x2 - f.a1 * f.y1 - f.a2 * f.y2;
        f.x2 = f.x1; f.x1 = x; f.y2 = f.y1; f.y1 = y;
        return y;
    };
    f.set(freq, q);
    return f;
}

/** Pink noise (Paul Kellet's filter). */
function pink(rand) {
    let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
    return () => {
        const w = rand() * 2 - 1;
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.969 * b2 + w * 0.153852;
        b3 = 0.8665 * b3 + w * 0.3104856; b4 = 0.55 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.016898;
        const o = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
        b6 = w * 0.115926;
        return o * 0.11;
    };
}

/** Brown noise (integrated white noise, kept from drifting). */
function brown(rand) {
    let y = 0;
    return () => { y = (y + (rand() * 2 - 1) * 0.02) * 0.998; return y * 3.5; };
}

/** Smooth random 0..1 value that wanders (for slow modulation). */
function wander(rand, rate, speed) {
    let a = rand(), b = rand(), t = 0;
    const step = speed / rate;
    return () => {
        t += step;
        if (t >= 1) { t -= 1; a = b; b = rand(); }
        const k = t * t * (3 - 2 * t);
        return a + (b - a) * k;
    };
}

/** Band-limited sawtooth (polyBLEP). */
function saw(rate) {
    let ph = 0;
    const blep = (t, dt) => {
        if (t < dt) { t /= dt; return t + t - t * t - 1; }
        if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
        return 0;
    };
    return (freq) => {
        const dt = freq / rate;
        ph += dt;
        if (ph >= 1) ph -= 1;
        return 2 * ph - 1 - blep(ph, dt);
    };
}

/** Freeverb-style stereo reverb. room 0..1, damp 0..1. */
function reverb(rate, room = 0.8, damp = 0.4) {
    const scale = rate / 44100;
    const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], aps = [556, 441, 341, 225];
    const make = (spread) => ({
        combs: combs.map((n) => ({ buf: new Float32Array(Math.round((n + spread) * scale)), i: 0, store: 0 })),
        aps: aps.map((n) => ({ buf: new Float32Array(Math.round((n + spread) * scale)), i: 0 })),
    });
    const L = make(0), R = make(23);
    const fb = 0.7 + room * 0.28;
    const run = (ch, x) => {
        let out = 0;
        for (const c of ch.combs) {
            const y = c.buf[c.i];
            c.store = y * (1 - damp) + c.store * damp;
            c.buf[c.i] = x + c.store * fb;
            c.i = (c.i + 1) % c.buf.length;
            out += y;
        }
        for (const a of ch.aps) {
            const b = a.buf[a.i];
            a.buf[a.i] = out + b * 0.5;
            a.i = (a.i + 1) % a.buf.length;
            out = b - out;
        }
        return out;
    };
    return (l, r) => [run(L, l * 0.015), run(R, r * 0.015)];
}

/** Constant-power pan: p -1 (left) .. 1 (right). */
const panL = (p) => Math.cos((p + 1) * Math.PI / 4), panR = (p) => Math.sin((p + 1) * Math.PI / 4);

/** Empty stereo buffers of `sec` seconds. */
const stereo = (rate, sec) => [new Float32Array(Math.round(rate * sec)), new Float32Array(Math.round(rate * sec))];

/** Adds a short event rendered by fn(t) -> sample at time `at`, panned. */
function addEvent(buf, rate, at, dur, pan, fn) {
    const s = Math.round(at * rate), n = Math.round(dur * rate), gl = panL(pan), gr = panR(pan);
    for (let i = 0; i < n && s + i < buf[0].length; i++) {
        if (s + i < 0) continue;
        const v = fn(i / rate);
        buf[0][s + i] += v * gl;
        buf[1][s + i] += v * gr;
    }
}

/** Mixes a dry stereo buffer through reverb, wet amount 0..1. */
function withReverb(buf, rate, wet, room = 0.8, damp = 0.4, extraSec = 0) {
    const rv = reverb(rate, room, damp);
    const n = buf[0].length;
    const out = [new Float32Array(n), new Float32Array(n)];
    for (let i = 0; i < n; i++) {
        const [l, r] = rv(buf[0][i], buf[1][i]);
        out[0][i] = buf[0][i] * (1 - wet * 0.5) + l * wet;
        out[1][i] = buf[1][i] * (1 - wet * 0.5) + r * wet;
    }
    return out;
}

// ── ambience ────────────────────────────────────────────────────────────────

/** Rain on a city street at night: the hiss, drops close by, gutters, distant traffic, a far siren. */
function ambCityRain() {
    const rate = 32000, len = 24, xf = 3, R = rng(11);
    const buf = stereo(rate, len + xf);
    const pl = pink(R), pr = pink(R), bn = brown(R);
    const hpL = biquad('hp', rate, 500), hpR = biquad('hp', rate, 500), lpL = biquad('lp', rate, 7000), lpR = biquad('lp', rate, 7000);
    const rumble = biquad('lp', rate, 110), gust = wander(R, rate, 0.25), swell = wander(R, rate, 0.08);
    for (let i = 0; i < buf[0].length; i++) {
        const g = 0.75 + gust() * 0.4;
        buf[0][i] += lpL.run(hpL.run(pl())) * 0.55 * g;
        buf[1][i] += lpR.run(hpR.run(pr())) * 0.55 * g;
        const low = rumble.run(bn()) * (0.6 + swell() * 0.6);
        buf[0][i] += low * 0.5;
        buf[1][i] += low * 0.5;
    }
    // Drops on puddles and metal close by: tiny filtered ticks everywhere
    for (let k = 0; k < (len + xf) * 70; k++) {
        const at = R() * (len + xf), f = 1800 + R() * 5000, amp = 0.04 + R() * 0.1, dec = 300 + R() * 500;
        const bp = biquad('bp', rate, f, 6);
        let ph = R();
        addEvent(buf, rate, at, 0.025, R() * 2 - 1, (t) => bp.run((R() * 2 - 1)) * Math.exp(-t * dec) * amp * 6 + Math.sin(TAU * f * 0.5 * t + ph) * Math.exp(-t * dec * 1.5) * amp * 0.3);
    }
    // Heavier drips from gutters and fire escapes: a little "plip" now and then
    for (let k = 0; k < (len + xf) * 2.2; k++) {
        const at = R() * (len + xf), f0 = 700 + R() * 700, amp = 0.07 + R() * 0.07;
        addEvent(buf, rate, at, 0.09, R() * 1.6 - 0.8, (t) => Math.sin(TAU * (f0 + 900 * Math.exp(-t * 60)) * t) * Math.exp(-t * 45) * amp);
    }
    // Cars hissing past on the wet road, far off, moving across
    for (const at of [1.5, 8.8, 16.2, 21.5]) {
        const dir = R() < 0.5 ? -1 : 1, dur = 4 + R() * 2;
        const bp = biquad('bp', rate, 500, 0.8), lp = biquad('lp', rate, 2500);
        const s = Math.round(at * rate), n = Math.round(dur * rate);
        for (let i = 0; i < n && s + i < buf[0].length; i++) {
            const k = i / n, env = Math.sin(k * Math.PI) ** 2;
            bp.set(350 + 500 * Math.sin(k * Math.PI), 0.8);
            const v = lp.run(bp.run(pl() * 3)) * env * 0.35, p = dir * (k * 2 - 1);
            buf[0][s + i] += v * panL(p);
            buf[1][s + i] += v * panR(p);
        }
    }
    // A siren, very far away
    {
        const at = 11, dur = 7, lp = biquad('lp', rate, 1200);
        let ph = 0;
        addEvent(buf, rate, at, dur, 0.4, (t) => {
            ph += TAU * (720 + 220 * Math.sin(TAU * 0.55 * t)) / rate;
            return lp.run(Math.sin(ph) + 0.3 * Math.sin(ph * 2)) * Math.sin(Math.PI * t / dur) ** 2 * 0.05;
        });
    }
    let out = withReverb(buf, rate, 0.45, 0.85, 0.5);
    out = loopFold(out, rate, len);
    writeWav('amb_city_rain', rate, normalize(out, 0.5));
}

/** A crowd murmuring in an alley: many voices babbling (formant-filtered buzz in syllables), light rain. */
function ambCrowd() {
    const rate = 32000, len = 20, xf = 3, R = rng(23);
    const buf = stereo(rate, len + xf);
    const vowels = [[730, 1090], [270, 2290], [530, 1840], [570, 840], [440, 1020], [300, 870], [660, 1720], [490, 1350]];
    for (let v = 0; v < 26; v++) {
        const pan = R() * 1.8 - 0.9, base = 95 + R() * 120, osc = saw(rate), dist = 0.4 + R() * 0.6;
        const f1 = biquad('bp', rate, 500, 5), f2 = biquad('bp', rate, 1500, 7), lp = biquad('lp', rate, 2200 + dist * 1200);
        const n = buf[0].length;
        let syl = 0, sylLen = 0, sylPos = 0, talking = R() < 0.7, phrase = R() * 3;
        let va = vowels[0], vb = vowels[1], vib = R() * TAU;
        const gl = panL(pan), gr = panR(pan);
        for (let i = 0; i < n; i++) {
            const t = i / rate;
            phrase -= 1 / rate;
            if (phrase <= 0) { talking = R() < 0.65; phrase = talking ? 1.2 + R() * 3 : 0.5 + R() * 2.5; }
            if (sylPos >= sylLen) { sylPos = 0; sylLen = Math.round(rate * (0.12 + R() * 0.16)); va = vb; vb = vowels[Math.floor(R() * vowels.length)]; syl = 0.5 + R() * 0.5; }
            const k = sylPos / sylLen;
            sylPos++;
            if (i % 64 === 0) { f1.set(va[0] + (vb[0] - va[0]) * k, 5); f2.set(va[1] + (vb[1] - va[1]) * k, 7); }
            const env = talking ? Math.sin(Math.PI * k) ** 0.7 * syl : 0;
            if (env < 0.001 && !talking) continue;
            const pitch = base * (1 + 0.04 * Math.sin(TAU * 5.5 * t + vib) + 0.12 * Math.sin(TAU * 0.7 * t + vib));
            const src = osc(pitch);
            const s = lp.run(f1.run(src) * 1.2 + f2.run(src) * 0.6) * env * 0.16 * dist;
            buf[0][i] += s * gl;
            buf[1][i] += s * gr;
        }
    }
    // Light rain under it
    const pl = pink(R), pr = pink(R), hpL = biquad('hp', rate, 900), hpR = biquad('hp', rate, 900);
    for (let i = 0; i < buf[0].length; i++) { buf[0][i] += hpL.run(pl()) * 0.12; buf[1][i] += hpR.run(pr()) * 0.12; }
    let out = withReverb(buf, rate, 0.7, 0.88, 0.55);
    out = loopFold(out, rate, len);
    writeWav('amb_crowd', rate, normalize(out, 0.45));
}

/** Wind across a rooftop, the city far below, rain on metal. */
function ambRooftop() {
    const rate = 32000, len = 22, xf = 3, R = rng(37);
    const buf = stereo(rate, len + xf);
    const pl = pink(R), pr = pink(R), bn = brown(R);
    const bpL = biquad('bp', rate, 400, 1.2), bpR = biquad('bp', rate, 420, 1.2), whistle = biquad('bp', rate, 900, 12);
    const gust = wander(R, rate, 0.18), tone = wander(R, rate, 0.3), rumble = biquad('lp', rate, 140);
    const hpL = biquad('hp', rate, 1200), hpR = biquad('hp', rate, 1200);
    for (let i = 0; i < buf[0].length; i++) {
        const g = gust(), f = 250 + tone() * 550;
        if (i % 32 === 0) { bpL.set(f, 1.2); bpR.set(f * 1.07, 1.2); whistle.set(700 + tone() * 600, 14); }
        const w = 0.25 + g * g * 0.9;
        const a = pl(), b = pr();
        buf[0][i] += bpL.run(a) * w * 0.9 + whistle.run(a) * g * g * 0.3 + hpL.run(a) * 0.06;
        buf[1][i] += bpR.run(b) * w * 0.9 + hpR.run(b) * 0.06;
        const low = rumble.run(bn()) * 0.6;
        buf[0][i] += low; buf[1][i] += low;
    }
    // Rain ticking on the water tower and vents
    for (let k = 0; k < (len + xf) * 25; k++) {
        const at = R() * (len + xf), f = 2500 + R() * 3500, amp = 0.03 + R() * 0.05;
        addEvent(buf, rate, at, 0.02, R() * 2 - 1, (t) => Math.sin(TAU * f * t) * Math.exp(-t * 500) * amp);
    }
    // A horn far below
    addEvent(buf, rate, 13, 1.6, -0.3, (t) => {
        const env = Math.min(1, t * 8) * Math.exp(-Math.max(0, t - 0.9) * 5);
        return (Math.sin(TAU * 311 * t) + 0.5 * Math.sin(TAU * 392 * t)) * env * 0.03;
    });
    let out = withReverb(buf, rate, 0.4, 0.9, 0.5);
    out = loopFold(out, rate, len);
    writeWav('amb_rooftop', rate, normalize(out, 0.5));
}

// ── one-shots ───────────────────────────────────────────────────────────────

/** A neon tube buzzing as it stutters: mains hum and its harmonics, crackle, cutting in and out. */
function neonBuzz(name, seed, pattern) {
    const rate = 44100, R = rng(seed), dur = pattern[pattern.length - 1][1] + 0.08;
    const n = Math.round(rate * dur), out = new Float32Array(n);
    const hum = (t) => Math.sin(TAU * 120 * t) * 0.5 + Math.sin(TAU * 240 * t) * 0.35 + Math.sin(TAU * 360 * t) * 0.22
        + Math.sin(TAU * 480 * t) * 0.12 + Math.sign(Math.sin(TAU * 120 * t)) * 0.08;
    const hiss = biquad('hp', rate, 3000), band = biquad('bp', rate, 1800, 2);
    let gate = 0;
    for (let i = 0; i < n; i++) {
        const t = i / rate;
        const on = pattern.some(([a, b]) => t >= a && t < b) ? 1 : 0;
        gate += (on - gate) * 0.02;
        const crackle = (R() < 0.004 * (on ? 1 : 0.2) ? (R() * 2 - 1) : 0) * 0.9;
        out[i] = (hum(t) * 0.4 + band.run(hum(t) * (R() - 0.5)) * 0.6 + hiss.run(R() * 2 - 1) * 0.05) * gate + crackle * (0.4 + gate);
    }
    writeWav(name, rate, normalize(fades([out], rate, 0.004, 0.05), 0.55));
}

/** A struck metal bell (inharmonic partials): fight-bell "ding". */
function bell(t, f, decay = 2.2) {
    if (t < 0) return 0;
    const parts = [[1, 1], [2.32, 0.6], [4.25, 0.35], [6.63, 0.2], [9.38, 0.1]];
    let v = 0;
    for (const [m, a] of parts) v += Math.sin(TAU * f * m * t) * a * Math.exp(-t * decay * (1 + m * 0.35));
    return v * Math.min(1, t * 2000);
}

/** Levels a one-shot so its loudest 50 ms sits at targetDb (RMS), capping peaks softly at -1 dB. */
function levelShort(channels, rate, targetDb) {
    const w = Math.round(rate * 0.05);
    let best = 1e-9;
    for (let s = 0; s + w <= channels[0].length; s += Math.round(w / 2)) {
        let e = 0;
        for (const c of channels) for (let i = s; i < s + w; i++) e += c[i] * c[i];
        best = Math.max(best, Math.sqrt(e / (w * channels.length)));
    }
    const g = Math.pow(10, targetDb / 20) / best, t = Math.pow(10, -1.5 / 20);
    for (const c of channels) for (let i = 0; i < c.length; i++) {
        const x = c[i] * g, a = Math.abs(x);
        c[i] = a <= t ? x : Math.sign(x) * (t + (1 - t) * Math.tanh((a - t) / (1 - t)));
    }
    return channels;
}

function phaseBrawl() {
    // The brawl is on: air rushing in, a heavy hit, the fight bell twice, and the crowd roaring up
    const rate = 48000, dur = 2.6, R = rng(5), hitAt = 0.16;
    const buf = stereo(rate, dur);
    const sweep = biquad('bp', rate, 600, 1.2);
    addEvent(buf, rate, 0, hitAt, 0, (t) => {   // rush of air into the hit
        const k = t / hitAt;
        sweep.set(500 + 3500 * k, 1.2);
        return sweep.run(R() * 2 - 1) * k * k * 0.9;
    });
    const body = biquad('lp', rate, 1800);
    addEvent(buf, rate, hitAt, 1.6, 0, (t) => {   // the hit: a falling sub, a thump of noise, a crack
        const sub = Math.sin(TAU * (34 + 70 * Math.exp(-t * 16)) * t) * Math.exp(-t * 3.2);
        const thump = body.run(R() * 2 - 1) * Math.exp(-t * 22) * 0.9;
        const crack = (R() * 2 - 1) * Math.exp(-t * 260) * 0.7;
        return Math.tanh((sub * 1.6 + thump + crack) * 1.3);
    });
    addEvent(buf, rate, hitAt + 0.01, 2.3, -0.2, (t) => bell(t, 1174) * 0.34 + bell(t, 1182) * 0.1);
    addEvent(buf, rate, hitAt + 0.29, 2.1, 0.2, (t) => bell(t, 1174) * 0.3 + bell(t, 1166) * 0.1);
    for (const side of [-0.7, 0.7]) {   // the crowd roaring up and dying down, wide
        const lo = biquad('hp', rate, 280), hi = biquad('lp', rate, 2600), f1 = biquad('bp', rate, 700, 1.2), wob = wander(R, rate, 6);
        addEvent(buf, rate, hitAt, 2.3, side, (t) => {
            if ((t * rate) % 64 < 1) f1.set(550 + wob() * 600, 1.2);
            const n = hi.run(lo.run(R() * 2 - 1));
            const env = Math.min(1, t / 0.35) * Math.exp(-Math.max(0, t - 0.4) * 1.6);
            return (n * 0.5 + f1.run(n) * 1.4) * env * 0.32;
        });
    }
    const out = withReverb(buf, rate, 0.35, 0.84, 0.35);
    writeWav('phase_brawl', rate, levelShort(fades(out, rate, 0.002, 0.4), rate, -12));
}

function phaseDeployment() {
    // A dark synth swell opening up (minor chord, filter rising) with a soft tick
    const rate = 44100, dur = 1.8, R = rng(7);
    const buf = stereo(rate, dur);
    const notes = [110, 130.81, 164.81, 246.94];
    notes.forEach((f, k) => {
        const o1 = saw(rate), o2 = saw(rate), lp = biquad('lp', rate, 300, 1.4);
        addEvent(buf, rate, 0, dur, (k / 3) * 1.2 - 0.6, (t) => {
            if ((t * rate) % 16 < 1) lp.set(300 + 2800 * Math.min(1, t / 0.6) * Math.exp(-Math.max(0, t - 0.6) * 1.5), 1.4);
            const env = Math.min(1, t * 4) * Math.exp(-Math.max(0, t - 0.5) * 2.2);
            return lp.run(o1(f) + o2(f * 1.006)) * env * 0.16;
        });
    });
    addEvent(buf, rate, 0.0, 0.05, 0, (t) => Math.sin(TAU * 2400 * t) * Math.exp(-t * 120) * 0.35 + (R() * 2 - 1) * Math.exp(-t * 300) * 0.2);
    const out = withReverb(buf, rate, 0.4, 0.8, 0.4);
    writeWav('phase_deployment', rate, normalize(fades(out, rate, 0.002, 0.35), 0.7));
}

function phaseRegroup() {
    // Air drawing back (a reversed whoosh) settling on a low, calm tone
    const rate = 44100, dur = 1.3, R = rng(9);
    const buf = stereo(rate, dur), bp = biquad('bp', rate, 2000, 1.5);
    addEvent(buf, rate, 0, 0.7, 0, (t) => {
        const k = t / 0.7;
        bp.set(3000 - 2400 * k, 1.5);
        return bp.run(R() * 2 - 1) * k * k * 0.9;
    });
    addEvent(buf, rate, 0.62, 0.7, 0, (t) => (Math.sin(TAU * 146.83 * t) + Math.sin(TAU * 220 * t) * 0.4) * Math.min(1, t * 40) * Math.exp(-t * 4.5) * 0.35);
    const out = withReverb(buf, rate, 0.4, 0.8, 0.5);
    writeWav('phase_regroup', rate, normalize(fades(out, rate, 0.002, 0.25), 0.6));
}

/** A turn starting. Yours: a quick lift of air into two bright rising stabs (a chord each, a filter
 *  snapping open), a soft thump under them and a sparkle on top. Theirs: two dark falling stabs, the
 *  filter closing, a low pulse under them. chords: [[midi notes], at seconds]. */
function turnSting(name, chords, bright) {
    const rate = 48000, dur = 1.5, R = rng(bright ? 13 : 14);
    const buf = stereo(rate, dur), hz = (m) => 440 * Math.pow(2, (m - 69) / 12), lead = 0.07;
    const air = biquad('bp', rate, 1500, 1.4);
    addEvent(buf, rate, 0, lead, 0, (t) => { const k = t / lead; air.set(bright ? 1200 + 5000 * k : 3000 - 2000 * k, 1.4); return air.run(R() * 2 - 1) * k * 0.35; });
    chords.forEach(([notes, at], ci) => {
        notes.forEach((m, k) => {
            const o1 = saw(rate), o2 = saw(rate), lp = biquad('lp', rate, 800, 1.6), f = hz(m);
            addEvent(buf, rate, lead + at, dur - lead - at, (k - (notes.length - 1) / 2) * 0.5, (t) => {
                if ((t * rate) % 16 < 1) lp.set(bright ? 700 + 5200 * Math.exp(-t * 7) : 2600 * Math.exp(-t * 5) + 300, 1.6);
                const env = Math.min(1, t * 400) * Math.exp(-t * (ci ? (bright ? 2.6 : 3.2) : 7));
                return lp.run(o1(f) + o2(f * (bright ? 1.005 : 0.996))) * env * 0.12;
            });
        });
        addEvent(buf, rate, lead + at, 0.4, 0, (t) => Math.sin(TAU * (bright ? 70 : 52) * t + 6 * Math.exp(-t * 30)) * Math.exp(-t * 11) * (bright ? 0.35 : 0.5));
    });
    if (bright) {
        for (const [f, at, p] of [[2637, 0.19, -0.4], [3136, 0.24, 0.4], [3951, 0.29, 0]]) {
            addEvent(buf, rate, lead + at, 0.8, p, (t) => Math.sin(TAU * f * t) * Math.exp(-t * 7) * 0.06 * Math.min(1, t * 3000));
        }
    }
    const out = withReverb(buf, rate, 0.45, 0.82, 0.4);
    writeWav(name, rate, levelShort(fades(out, rate, 0.002, 0.35), rate, -15));
}

function uiHover() {
    const rate = 44100, n = Math.round(rate * 0.05), out = new Float32Array(n);
    for (let i = 0; i < n; i++) { const t = i / rate; out[i] = Math.sin(TAU * 3200 * t) * Math.exp(-t * 160) * 0.5 + Math.sin(TAU * 1600 * t) * Math.exp(-t * 220) * 0.3; }
    writeWav('hover', rate, normalize([out], 0.25));
}

function uiClick() {
    // A crisp, solid press: a bright tick, a tiny snap of noise and a short low body
    const rate = 48000, dur = 0.1, R = rng(3), buf = stereo(rate, dur), hp = biquad('hp', rate, 3500), bp = biquad('bp', rate, 1900, 2.5);
    addEvent(buf, rate, 0, dur, 0, (t) => {
        const tick = Math.sin(TAU * 4600 * t) * Math.exp(-t * 900) * 0.5;
        const snap = hp.run(R() * 2 - 1) * Math.exp(-t * 600) * 0.6 + bp.run(R() * 2 - 1) * Math.exp(-t * 250) * 0.5;
        const thud = Math.sin(TAU * (130 + 260 * Math.exp(-t * 90)) * t) * Math.exp(-t * 55) * 0.7;
        return tick + snap + thud;
    });
    const out = withReverb(buf, rate, 0.08, 0.4, 0.6);
    writeWav('click', rate, levelShort(fades(out, rate, 0.0003, 0.02), rate, -17));
}

function uiError() {
    // Denied: two low, slightly gritty buzzes, the second lower
    const rate = 48000, dur = 0.34, buf = stereo(rate, dur);
    for (const [at, f] of [[0, 196], [0.15, 147]]) {
        const o1 = saw(rate), o2 = saw(rate), lp = biquad('lp', rate, 1300, 0.9);
        addEvent(buf, rate, at, 0.13, 0, (t) => {
            const env = Math.min(1, t * 600) * (t < 0.1 ? 1 : Math.exp(-(t - 0.1) * 60));
            return Math.tanh(lp.run(o1(f) + o2(f * 1.012) + Math.sign(Math.sin(TAU * f * 0.5 * t)) * 0.5) * 1.6) * env * 0.4;
        });
    }
    writeWav('error', rate, levelShort(fades(buf, rate, 0.0005, 0.03), rate, -17));
}

function karat() {
    // Coins: two quick metallic chinks
    const rate = 44100, dur = 0.5, buf = stereo(rate, dur);
    for (const [at, f, p] of [[0, 2100, -0.2], [0.07, 2650, 0.2]]) {
        addEvent(buf, rate, at, 0.4, p, (t) => (Math.sin(TAU * f * t) + Math.sin(TAU * f * 1.51 * t) * 0.6 + Math.sin(TAU * f * 2.33 * t) * 0.3) * Math.exp(-t * 14) * 0.3 * Math.min(1, t * 3000));
    }
    writeWav('karat', rate, normalize(withReverb(buf, rate, 0.25, 0.6, 0.5), 0.5));
}

function victoryStinger() {
    // A short triumphant brass-ish synth fanfare over a hit: I - IV - V - I
    const rate = 44100, dur = 4.2, buf = stereo(rate, dur), R = rng(17);
    const chords = [[[261.63, 329.63, 392.0], 0], [[349.23, 440, 523.25], 0.32], [[392, 493.88, 587.33], 0.64], [[523.25, 659.25, 783.99], 1.0]];
    chords.forEach(([notes, at], ci) => {
        const last = ci === chords.length - 1, d = last ? 3.0 : 0.38;
        notes.forEach((f, k) => {
            const o1 = saw(rate), o2 = saw(rate), lp = biquad('lp', rate, 800, 1.2);
            addEvent(buf, rate, at, d + 0.3, (k - 1) * 0.5, (t) => {
                if ((t * rate) % 16 < 1) lp.set(800 + 3200 * Math.min(1, t * 12) * Math.exp(-t * (last ? 0.8 : 3)), 1.2);
                const env = Math.min(1, t * 60) * (t < d ? 1 : Math.exp(-(t - d) * 12)) * (last ? Math.exp(-t * 0.7) : 1);
                return lp.run(o1(f) + o2(f * 1.004)) * env * 0.13;
            });
        });
        addEvent(buf, rate, at, 0.5, 0, (t) => Math.tanh(Math.sin(TAU * (60 + 80 * Math.exp(-t * 25)) * t) * Math.exp(-t * 9) * 1.5) * (last ? 0.8 : 0.45));
    });
    addEvent(buf, rate, 1.0, 2.5, 0, (t) => (R() * 2 - 1) * Math.exp(-t * 3.5) * 0.08 * Math.min(1, t * 50));
    const out = withReverb(buf, rate, 0.4, 0.85, 0.35);
    writeWav('music_victory', rate, normalize(fades(out, rate, 0.002, 0.6), 0.8));
}

function defeatStinger() {
    // A slow fall into a low drone: minor, filtered, a last heavy hit
    const rate = 44100, dur = 4.0, buf = stereo(rate, dur);
    const notes = [[392, 0], [349.23, 0.4], [311.13, 0.8], [261.63, 1.2]];
    notes.forEach(([f, at], k) => {
        const o = saw(rate), lp = biquad('lp', rate, 1200, 1);
        addEvent(buf, rate, at, dur - at, k % 2 ? 0.3 : -0.3, (t) => lp.run(o(f) + Math.sin(TAU * f * 0.5 * t)) * Math.min(1, t * 30) * Math.exp(-t * 1.6) * 0.14);
    });
    const drone = saw(rate), dl = biquad('lp', rate, 220);
    addEvent(buf, rate, 1.2, 2.8, 0, (t) => dl.run(drone(65.41)) * Math.min(1, t * 3) * Math.exp(-Math.max(0, t - 1.5) * 1.5) * 0.4);
    addEvent(buf, rate, 1.2, 0.8, 0, (t) => Math.tanh(Math.sin(TAU * (45 + 50 * Math.exp(-t * 20)) * t) * Math.exp(-t * 6) * 1.6) * 0.8);
    const out = withReverb(buf, rate, 0.5, 0.88, 0.45);
    writeWav('music_defeat', rate, normalize(fades(out, rate, 0.002, 0.6), 0.75));
}

// ── music ───────────────────────────────────────────────────────────────────

/** A dark synth loop for duels: a pulsing bass, slow pads, soft drums, an arp now and then. tense: faster
 *  and harder. Stand-ins until generated tracks replace them (docs/AUDIO_PROMPTS.md). */
function duelMusic(name, bpm, tense, seed) {
    const rate = 32000, bars = tense ? 16 : 16, beat = 60 / bpm, len = bars * 4 * beat, xf = 2, R = rng(seed);
    const buf = stereo(rate, len + xf);
    // A minor: Am - F - C - G (calm) / Am - Am - F - E (tense), one chord a bar, looped
    const prog = tense ? [[57, 60, 64], [57, 60, 64], [53, 57, 60], [52, 56, 59]] : [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
    const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);
    for (let bar = 0; bar < bars + 1; bar++) {
        const chord = prog[bar % prog.length], t0 = bar * 4 * beat;
        // Pad: three detuned saws per note, slow attack, lowpass
        chord.forEach((m, k) => {
            const o1 = saw(rate), o2 = saw(rate), lp = biquad('lp', rate, tense ? 1300 : 900, 0.9);
            addEvent(buf, rate, t0, 4 * beat + 0.6, (k - 1) * 0.6, (t) => {
                const env = Math.min(1, t / 0.8) * (t < 4 * beat ? 1 : Math.exp(-(t - 4 * beat) * 6));
                return lp.run(o1(hz(m)) + o2(hz(m) * 1.007)) * env * 0.045;
            });
        });
        // Bass: 8th (calm) or 16th (tense) pulses on the root, plucky filter
        const root = hz(chord[0] - 24), steps = tense ? 16 : 8;
        for (let s = 0; s < steps; s++) {
            const at = t0 + s * (4 * beat / steps), o = saw(rate), lp = biquad('lp', rate, 400, 2);
            const acc = s % (steps / 4) === 0 ? 1 : 0.7;
            addEvent(buf, rate, at, 4 * beat / steps, 0, (t) => {
                if ((t * rate) % 8 < 1) lp.set(180 + (tense ? 1400 : 900) * Math.exp(-t * 25), 2);
                return lp.run(o(root)) * Math.exp(-t * 7) * 0.28 * acc;
            });
        }
        // Drums: kick on 1 and 3 (and more when tense), a clap on 2 and 4, closed hats on the 8ths
        for (let b = 0; b < 4; b++) {
            const at = t0 + b * beat;
            if (b % 2 === 0 || tense) addEvent(buf, rate, at, 0.35, 0, (t) => Math.tanh(Math.sin(TAU * (48 + 110 * Math.exp(-t * 30)) * t) * Math.exp(-t * 9) * 1.8) * 0.5);
            if (b % 2 === 1) {
                const bp = biquad('bp', rate, 1300, 0.9);
                addEvent(buf, rate, at, 0.3, 0.05, (t) => bp.run(R() * 2 - 1) * (Math.exp(-t * 18) + 0.5 * Math.exp(-Math.abs(t - 0.012) * 300)) * 0.45);
            }
            for (const off of tense ? [0, 0.25, 0.5, 0.75] : [0, 0.5]) {
                const hp = biquad('hp', rate, 7000);
                addEvent(buf, rate, at + off * beat, 0.06, 0.3, (t) => hp.run(R() * 2 - 1) * Math.exp(-t * 90) * (off === 0.5 ? 0.16 : 0.09));
            }
        }
        // Arp: a sparse figure every other bar (calm) or every bar (tense), high and echoing
        if (bar % (tense ? 1 : 2) === 1) {
            const seq = [0, 2, 1, 2, 0, 1, 2, 1];
            seq.forEach((ix, s) => {
                const f = hz(chord[ix] + 12), at = t0 + s * beat / 2, o = saw(rate), lp = biquad('lp', rate, 2500, 1);
                addEvent(buf, rate, at, 0.5, s % 2 ? 0.45 : -0.45, (t) => lp.run(o(f)) * Math.exp(-t * 9) * 0.06);
            });
        }
    }
    let out = withReverb(buf, rate, 0.35, 0.8, 0.45);
    out = loopFold(out, rate, len);
    writeWav(name, rate, normalize(out, 0.7));
}

// ── what to render ──────────────────────────────────────────────────────────

const JOBS = {
    amb_city_rain: ambCityRain,
    amb_crowd: ambCrowd,
    amb_rooftop: ambRooftop,
    neon_buzz: () => {
        neonBuzz('neon_buzz_1', 41, [[0, 0.06], [0.12, 0.16], [0.22, 0.5]]);
        neonBuzz('neon_buzz_2', 42, [[0, 0.04], [0.09, 0.2], [0.26, 0.3], [0.4, 0.75]]);
        neonBuzz('neon_buzz_3', 43, [[0, 0.15], [0.19, 0.22], [0.3, 0.34], [0.42, 0.6]]);
    },
    phase_deployment: phaseDeployment,
    phase_brawl: phaseBrawl,
    phase_regroup: phaseRegroup,
    turn_yours: () => turnSting('turn_yours', [[[67, 71, 74], 0], [[74, 79, 83], 0.12]], true),
    turn_theirs: () => turnSting('turn_theirs', [[[63, 66, 70], 0], [[58, 61, 65], 0.14]], false),
    hover: uiHover,
    click: uiClick,
    error: uiError,
    karat,
    music_victory: victoryStinger,
    music_defeat: defeatStinger,
    music_duel: () => duelMusic('music_duel', 96, false, 101),
    music_duel_tense: () => duelMusic('music_duel_tense', 124, true, 202),
};

const want = process.argv.slice(2);
for (const [name, job] of Object.entries(JOBS)) {
    if (want.length && !want.includes(name)) continue;
    // A real recording (ogg/mp3, or a .wav that isn't one of ours) replaces the stand-in: leave it be
    const recorded = ['ogg', 'mp3'].some((ext) => existsSync(join(OUT, `${name}.${ext}`)) || existsSync(join(OUT, `${name}_1.${ext}`)))
        || [`${name}.wav`, `${name}_1.wav`].some((f) => existsSync(join(OUT, f)) && !isStandIn(join(OUT, f)));
    if (recorded) {
        console.log(`${name}: a recording is in place, skipped`);
        continue;
    }
    job();
}
