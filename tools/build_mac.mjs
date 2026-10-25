// Builds the Mac version of the game from this PC: one app that runs on Apple Silicon and Intel Macs
// (Godot's "universal" build), signed ad hoc (no Apple Developer account: see "Mac build" in
// docs/CARD_PIPELINE.md for what players do the first time they open it).
//
//   node tools/build_mac.mjs <path to Godot console exe>
//
// Needs Godot's macOS export template (macos.zip in Godot's export_templates/<version>/ folder).
// Writes:
//   builds/macos_<version>/AlleywayBrawlers.zip   the export; keep it, with the game data pulled out of
//   builds/macos_<version>/AlleywayBrawlers.pck   it: Mac patches are made against this (make_patch --macos)
//   builds/AlleywayBrawlers-<version>-macos.zip   for downloads/ on the server (node tools/deploy.mjs --build-mac)
// Set "macos": {"patchBase": "<version>"} in shared/game_version.json to the version of the Mac build
// players have, as "patchBase" is for Windows.
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.argv[2] || process.env.GODOT;
if (!godot || !existsSync(godot)) {
    console.error('usage: node tools/build_mac.mjs <path to Godot console exe>   (or set GODOT)');
    process.exit(2);
}
const version = (/config\/version="([^"]+)"/.exec(readFileSync(join(ROOT, 'godot/project.godot'), 'utf8')) || [])[1];
if (!version) throw new Error('No config/version in godot/project.godot');

const dir = join(ROOT, 'builds', `macos_${version}`);
mkdirSync(dir, { recursive: true });
const zip = join(dir, 'AlleywayBrawlers.zip');
if (existsSync(zip)) rmSync(zip);
console.log(`Exporting the Mac build ${version} …`);
execFileSync(godot, ['--headless', '--path', join(ROOT, 'godot'), '--export-release', 'macOS', zip], { stdio: 'inherit' });
if (!existsSync(zip)) throw new Error('Godot did not write the Mac build (is the macOS export template installed?).');

// The game data inside the app (<name>.app/Contents/Resources/<name>.pck), for making patches
const tmp = join(dir, 'unpacked');
rmSync(tmp, { recursive: true, force: true });
mkdirSync(tmp);
const tar = existsSync('C:\\Windows\\System32\\tar.exe') ? 'C:\\Windows\\System32\\tar.exe' : 'tar';
execFileSync(tar, ['-xf', zip, '-C', tmp]);
const pck = find(tmp, (f) => f.endsWith('.pck'));
if (!pck) throw new Error('No .pck inside the Mac build.');
const base = join(dir, 'AlleywayBrawlers.pck');
if (existsSync(base)) rmSync(base);
renameSync(pck, base);
const app = find(tmp, (f) => f.endsWith('.app'), true);
rmSync(tmp, { recursive: true, force: true });

const out = join(ROOT, 'builds', `AlleywayBrawlers-${version}-macos.zip`);
copyFileSync(zip, out);
console.log(`\nWrote ${out} (${Math.round(statSync(out).size / 1048576)} MB${app ? `, ${app.split(/[\\/]/).pop()}` : ''}).`);
console.log('Next: set "macos": {"patchBase": "' + version + '"} in shared/game_version.json if this is a new Mac base build,\n' +
    'push, then  node tools/deploy.mjs --build-mac');

function find(d, test, dirs = false) {
    for (const e of readdirSync(d, { withFileTypes: true })) {
        const p = join(d, e.name);
        if (test(e.name) && (dirs ? e.isDirectory() : e.isFile())) return p;
        if (e.isDirectory()) {
            const r = find(p, test, dirs);
            if (r) return r;
        }
    }
    return null;
}
