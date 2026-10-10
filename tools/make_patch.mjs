// Builds an in-place update (patch) for the game: the code and scenes without the art and audio.
//
//   node tools/make_patch.mjs <path to Godot console exe>
//
// 1. Raise config/version in godot/project.godot and "latest" in shared/game_version.json
//    (same number; leave "minimum" and "patchBase" alone).
// 2. Run this: it writes builds/AlleywayBrawlers-<version>-patch.pck (a few hundred KB).
// 3. Copy that file into downloads/ on the server. Players on patchBase or newer get it at
//    start-up and the game restarts into it (godot/scripts/patcher.gd).
//
// A patch can't change project settings, the autoload list or add class_name scripts (use
// preload); those need a full build, with "minimum" and "patchBase" raised to its version.
import { existsSync, readFileSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.argv[2] || process.env.GODOT;
if (!godot || !existsSync(godot)) {
    console.error('usage: node tools/make_patch.mjs <path to Godot console exe>   (or set GODOT)');
    process.exit(2);
}
const project = readFileSync(join(ROOT, 'godot/project.godot'), 'utf8');
const version = (/config\/version="([^"]+)"/.exec(project) || [])[1];
const v = JSON.parse(readFileSync(join(ROOT, 'shared/game_version.json'), 'utf8'));
if (!version) throw new Error('No config/version in godot/project.godot');
if (v.latest !== version) {
    console.error(`shared/game_version.json says latest ${v.latest}, but the project is ${version}. Make them match first.`);
    process.exit(1);
}
if (!v.patchBase) {
    console.error('shared/game_version.json has no patchBase (the full build patches apply to).');
    process.exit(1);
}
const out = join(ROOT, 'builds', `AlleywayBrawlers-${version}-patch.pck`);
execFileSync(godot, ['--headless', '--path', join(ROOT, 'godot'), '--export-pack', 'Patch', out], { stdio: 'inherit' });
if (!existsSync(out)) throw new Error('Godot did not write the patch.');
console.log(`\nWrote ${out} (${Math.round(statSync(out).size / 1024)} KB), for builds ${v.patchBase} and newer.`);
console.log(`Next: push, then copy it to the server and pull there:\n` +
    `  scp "${out}" jacob199097@192.168.0.200:/opt/Turf_War/downloads/\n` +
    `  (on the server) cd /opt/Turf_War && git pull && sudo systemctl restart alleyway-backend`);
