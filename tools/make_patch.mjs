// Builds an in-place update (patch) for the game: whatever changed since the full build players have.
//
//   node tools/make_patch.mjs <path to Godot console exe>            the Windows patch
//   node tools/make_patch.mjs <path to Godot console exe> --macos    the Mac patch (-patch-macos.pck), made
//       against the Mac build at builds/macos_<macos.patchBase>/ (tools/build_mac.mjs)
//   node tools/make_patch.mjs <path to Godot console exe> --android  the Android patch (-patch-android.pck),
//       made from the lighter copy of the project (tools/build_android.mjs --prepare) against the pack
//       of the Android build at builds/android_<android.patchBase>/
//
// 1. Raise config/version in godot/project.godot and "latest" in shared/game_version.json
//    (same number; leave "minimum" and "patchBase" alone).
// 2. Run this: it writes builds/AlleywayBrawlers-<version>-patch.pck. With the patchBase build at
//    builds/windows_<patchBase>/AlleywayBrawlers.exe (where a full build is exported), the patch holds
//    only what changed since that build (a few hundred KB); without it, the whole game (much bigger).
//    The Patch preset must export everything the full build does: a file it leaves out is written
//    into the patch as deleted, and players lose it (0.9.7-0.9.8 lost the menu art that way).
// 3. Copy that file into downloads/ on the server. Players on patchBase or newer get it at
//    start-up and the game restarts into it (godot/scripts/patcher.gd).
//
// A patch can't change project settings, the autoload list or add class_name scripts (use
// preload); those need a full build, with "minimum" and "patchBase" raised to its version.
import { existsSync, readFileSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const mac = argv.includes('--macos');
const android = argv.includes('--android');
const which = mac ? 'macos' : android ? 'android' : 'windows';
const label = { windows: 'Windows', macos: 'Mac', android: 'Android' }[which];
const godot = argv.find(a => !a.startsWith('--')) || process.env.GODOT;
if (!godot || !existsSync(godot)) {
    console.error('usage: node tools/make_patch.mjs <path to Godot console exe> [--macos | --android]   (or set GODOT)');
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
const patchBase = which === 'windows' ? v.patchBase : (v[which] && v[which].patchBase);
if (!patchBase) {
    console.error(`shared/game_version.json has no ${which === 'windows' ? 'patchBase' : which + '.patchBase'} (the full build patches apply to).`);
    process.exit(1);
}
if (patchBase === version) {
    console.log(`${version} is the ${label} base build itself: players download it whole, so there's no patch to make.`);
    process.exit(0);
}
const preset = { windows: 'Patch', macos: 'Patch macOS', android: 'Android' }[which];
// (Android: from builds/android_project, the copy with phone-sized pictures its APK was made from)
const dir = android ? join(ROOT, 'builds', 'android_project') : join(ROOT, 'godot');
const out = join(ROOT, 'builds', `AlleywayBrawlers-${version}-patch${which === 'windows' ? '' : '-' + which}.pck`);
const base = which === 'windows' ? join(ROOT, 'builds', `windows_${patchBase}`, 'AlleywayBrawlers.exe')
    : join(ROOT, 'builds', `${which}_${patchBase}`, 'AlleywayBrawlers.pck');
if (android) {
    if (!existsSync(base)) {   // (without it the patch would be the whole 200 MB game)
        console.error(`No ${base}: it is written by the release build of ${patchBase} (tools/build_android.mjs).`);
        process.exit(1);
    }
    execFileSync(process.execPath, [join(ROOT, 'tools', 'build_android.mjs'), godot, '--prepare'], { stdio: 'inherit' });
}
try {
    if (existsSync(base)) {
        // Only the files that differ from the full build players have (Godot compares against its pack)
        execFileSync(godot, ['--headless', '--path', dir, '--export-patch', preset, out, '--patches', base], { stdio: 'inherit' });
    } else {
        console.warn(`No ${base}: the patch carries everything the Patch preset allows, not just the changes.`);
        execFileSync(godot, ['--headless', '--path', dir, '--export-pack', preset, out], { stdio: 'inherit' });
    }
} catch (err) {
    if (existsSync(out)) unlinkSync(out);   // (a half-written patch must never reach downloads/)
    console.error(`\nGodot couldn't make the patch: ${err.message.split('\n')[0]}`);
    process.exit(1);
}
if (!existsSync(out)) throw new Error('Godot did not write the patch.');
// A file the patch deletes is fine when its source is gone from the project on purpose (art replaced,
// e.g. arena_*.png by arena_*.jpg in 0.9.104); one whose source is still there means the Patch preset
// left it out
const sources = projectFiles(join(ROOT, 'godot'));
const sourceOf = (p) => p.replace(/^\.godot\/imported\//, '').replace(/-[0-9a-f]{32}\..*$/, '').replace(/\.(import|remap)$/, '').split('/').pop();
const gone = deletedFiles(out).filter(p => !sources.has(sourceOf(p)));
const removed = deletedFiles(out).filter(p => sources.has(sourceOf(p)));
if (gone.length) console.log(`\nThe patch removes ${gone.length} file(s) whose source is gone from the project, e.g. ${sourceOf(gone[0])}.`);
if (removed.length) {
    console.error(`\nThe patch deletes ${removed.length} file(s) from the full build, e.g.\n  ${removed.slice(0, 5).join('\n  ')}\n` +
        'The Patch preset (godot/export_presets.cfg) must export everything the Windows Desktop preset does.');
    unlinkSync(out);
    process.exit(1);
}
console.log(`\nWrote ${out} (${Math.round(statSync(out).size / 1024)} KB), for ${label} builds ${patchBase} and newer.`);
console.log(`Next: push, then  node tools/deploy.mjs --patch  (it copies the Windows, Mac and Android patches; or by hand):\n` +
    `  scp "${out}" jacob199097@192.168.0.200:/opt/Turf_War/downloads/\n` +
    `  (on the server) cd /opt/Turf_War && git pull && sudo systemctl restart alleyway-backend`);

// The names of the files in the Godot project (not its .godot cache)
function projectFiles(dir, out = new Set()) {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (e.name === '.godot') continue;
        if (e.isDirectory()) projectFiles(join(dir, e.name), out);
        else out.add(e.name);
    }
    return out;
}

// The files a .pck marks as removed (Godot's PCK directory: path, offset, size, md5, flags; bit 2 = removed).
function deletedFiles(file) {
    const b = readFileSync(file);
    let o = 4;
    const u32 = () => { const x = b.readUInt32LE(o); o += 4; return x; };
    const u64 = () => { const x = Number(b.readBigUInt64LE(o)); o += 8; return x; };
    const format = u32();
    o += 16 + 8;                       // engine version, pack flags, file base
    o = format >= 3 ? u64() : o + 64;  // the directory (at the end from format 3)
    const out = [];
    for (let n = u32(); n > 0; n--) {
        const len = u32();
        const path = b.toString('utf8', o, o + len).replace(/\0+$/, '');
        o += len + 8 + 8 + 16;
        if (u32() & 2) out.push(path);
    }
    return out;
}
