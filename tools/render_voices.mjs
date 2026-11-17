// Renders stand-in voice lines into assets/sfx as WAV files: the announcer ("Your turn", "K.O.", "Awakened",
// "Double or nothing", "Fight") and each Turf Defense boss's lines (godot/data/bosses.json "lines"), spoken by
// Windows' built-in speech voice and then shaped per speaker (deeper, a stadium echo, a crackling radio...).
// They are placeholders, marked as stand-ins like tools/render_audio.mjs's: drop a real recording in with the
// same name (as .ogg, .mp3 or .wav), delete the stand-in, deploy. docs/AUDIO_PROMPTS.md has the casting notes.
//   node tools/render_voices.mjs              every line (Windows only: it uses System.Speech)
//   node tools/render_voices.mjs vo_ko archon just these (sound names or boss ids)
import { readFileSync, writeFileSync, mkdtempSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { OUT, isStandIn, writeWav, normalize, biquad, reverb } from './render_audio.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// How each speaker sounds: speed < 1 is deeper and slower; drive: grit; band: [low cut, high cut] (a radio);
// wet / room: the echo around them
const VOICES = {
    announcer: { rate: 1, speed: 0.88, drive: 1.6, band: [90, 9000], wet: 0.32, room: 0.9 },
    archon: { rate: -2, speed: 0.8, drive: 1.2, band: [70, 8000], wet: 0.5, room: 0.95 },
    graves: { rate: 1, speed: 0.93, drive: 2.6, band: [350, 3200], wet: 0.08, room: 0.4 },
    vale: { rate: 0, speed: 0.95, drive: 1.1, band: [80, 9000], wet: 0.15, room: 0.5 },
    veyr: { rate: -3, speed: 0.74, drive: 1.3, band: [60, 3600], wet: 0.55, room: 0.97 },
    cinder: { rate: 1, speed: 0.9, drive: 2.2, band: [90, 7000], wet: 0.2, room: 0.6 },
    marlow: { rate: -1, speed: 0.86, drive: 1.4, band: [80, 7000], wet: 0.25, room: 0.7 },
};

const ANNOUNCER = {
    vo_your_turn: ['Your turn!', 'Your move!'],
    vo_ko: ['Knockout!', 'K. O.!'],
    vo_awakened: ['The leader awakens!', 'Awakened!'],
    vo_double_or_nothing: ['Double or nothing!'],
    vo_fight: ['Fight!'],
};

/** Every line to speak: [{name, text, voice}] (a sound with several takes gets _1, _2, ...). */
function lines() {
    const out = [];
    for (const [name, takes] of Object.entries(ANNOUNCER)) {
        takes.forEach((text, i) => out.push({ name: takes.length > 1 ? `${name}_${i + 1}` : name, sound: name, text, voice: 'announcer' }));
    }
    const { bosses } = JSON.parse(readFileSync(join(ROOT, 'godot/data/bosses.json'), 'utf8'));
    for (const b of bosses) {
        const L = b.lines || {};
        const voice = VOICES[b.id] ? b.id : 'announcer';
        (L.intro || []).forEach((text, i) => out.push({ name: `vo_boss_${b.id}_intro${i + 1}`, boss: b.id, text, voice }));
        for (const [n, text] of Object.entries(L.phase || {})) out.push({ name: `vo_boss_${b.id}_phase${n}`, boss: b.id, text, voice });
        for (const k of ['low', 'player_out', 'defeat', 'victory']) {
            if (L[k]) out.push({ name: `vo_boss_${b.id}_${k}`, boss: b.id, text: L[k], voice });
        }
    }
    return out;
}

/** 16-bit PCM mono WAV → [rate, Float32Array]. */
function readWav(file) {
    const b = readFileSync(file);
    let o = 12, rate = 22050, data = null;
    while (o + 8 <= b.length) {
        const id = b.toString('ascii', o, o + 4), size = b.readUInt32LE(o + 4);
        if (id === 'fmt ') rate = b.readUInt32LE(o + 12);
        if (id === 'data') data = b.subarray(o + 8, o + 8 + size);
        o += 8 + size + (size & 1);
    }
    const x = new Float32Array(data.length / 2);
    for (let i = 0; i < x.length; i++) x[i] = data.readInt16LE(i * 2) / 32768;
    return [rate, x];
}

/** Cuts the silence the speech voice leaves before and after the words. */
function trim(rate, x) {
    let a = 0, b = x.length - 1;
    while (a < b && Math.abs(x[a]) < 0.01) a++;
    while (b > a && Math.abs(x[b]) < 0.01) b--;
    const pad = Math.round(rate * 0.02);
    return x.slice(Math.max(0, a - pad), Math.min(x.length, b + pad));
}

/** Shapes a dry line for its speaker (VOICES). */
function shape(rate, x, v) {
    x = trim(rate, x);
    // Slower and deeper: read the line at `speed` (linear interpolation)
    const n = Math.floor(x.length / v.speed);
    let y = new Float32Array(n);
    for (let i = 0; i < n; i++) {
        const p = i * v.speed, j = Math.floor(p), k = p - j;
        y[i] = (x[j] || 0) * (1 - k) + (x[j + 1] || 0) * k;
    }
    // The band, then grit (soft clipping)
    const hp = biquad('hp', rate, v.band[0]), lp = biquad('lp', rate, v.band[1]);
    const d = v.drive, norm = Math.tanh(d);
    for (let i = 0; i < n; i++) y[i] = Math.tanh(lp.run(hp.run(y[i])) * d * 2.5) / norm;
    // The room: a tail long enough for the echo to die away
    const tail = Math.round(rate * (0.4 + v.wet * 2.2));
    const wet = new Float32Array(n + tail), rv = reverb(rate, v.room, 0.45);
    for (let i = 0; i < n + tail; i++) {
        const s = i < n ? y[i] : 0;
        const [l] = rv(s, s);
        wet[i] = s * (1 - v.wet * 0.4) + l * v.wet * 3.0;
    }
    return wet;
}

const want = process.argv.slice(2);
const todo = lines().filter((l) => !want.length || want.includes(l.name) || want.includes(l.sound) || want.includes(l.boss));
// A real recording in place is never spoken over
const recorded = (name) => ['ogg', 'mp3'].some((ext) => existsSync(join(OUT, `${name}.${ext}`)))
    || (existsSync(join(OUT, `${name}.wav`)) && !isStandIn(join(OUT, `${name}.wav`)));
const jobs = todo.filter((l) => !recorded(l.name));
for (const l of todo.filter((l) => recorded(l.name))) console.log(`${l.name}: a recording is in place, skipped`);
if (!jobs.length) process.exit(0);

// Speak every line to a dry WAV in one PowerShell run (System.Speech, the Windows voice)
const dir = mkdtempSync(join(tmpdir(), 'ab-voices-'));
const list = jobs.map((l, i) => ({ file: join(dir, `${i}.wav`), text: l.text, rate: VOICES[l.voice].rate }));
writeFileSync(join(dir, 'lines.json'), JSON.stringify(list));
const ps = `Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Gender -eq 'Male' } | Select-Object -First 1
if ($v) { $s.SelectVoice($v.VoiceInfo.Name) }
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
foreach ($l in (Get-Content -Raw -Path '${join(dir, 'lines.json').replace(/'/g, "''")}' | ConvertFrom-Json)) {
  $s.Rate = [int]$l.rate
  $s.SetOutputToWaveFile($l.file, $fmt)
  $s.Speak([string]$l.text)
}
$s.SetOutputToNull()`;
writeFileSync(join(dir, 'speak.ps1'), ps);
execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(dir, 'speak.ps1')], { stdio: 'inherit' });
jobs.forEach((l, i) => {
    const [rate, x] = readWav(list[i].file);
    writeWav(l.name, rate, normalize([shape(rate, x, VOICES[l.voice])], 0.85));
});
rmSync(dir, { recursive: true, force: true });
