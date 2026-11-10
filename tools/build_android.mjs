// Builds the Android version of the game: an APK to install on a phone or tablet (docs/ANDROID.md).
//
//   node tools/build_android.mjs <path to Godot console exe>            the release APK
//   node tools/build_android.mjs <path to Godot console exe> --debug    a debug APK (also runs in the
//       emulator: it carries the x86_64 engine too), signed with Godot's debug key
//   node tools/build_android.mjs <path to Godot console exe> --prepare  only brings the copy below up to
//       date and imports it (tools/make_patch.mjs --android makes Android patches from it)
//
// A phone gets lighter pictures than a PC: card art at most 1024 pixels tall and lossy-compressed,
// the .jpg backgrounds lossy, nothing bigger than the screen (the PC build's pictures make a ~900 MB
// APK). So the APK is exported from a copy of the project, builds/android_project/, where only
// those import settings change; the copy keeps its imported files, so a build only imports again
// what changed since the last one. The PC builds and godot/ itself are never touched.
//
// Needs Godot's Android export templates, a JDK 17 and the Android SDK, set in Godot's editor
// settings (export/android/java_sdk_path, android_sdk_path): docs/ANDROID.md has the setup. A
// release APK is signed with the release key (phones only accept an update signed like the APK they
// have), from ANDROID_KEYSTORE, ANDROID_KEYSTORE_PASS and ANDROID_KEYSTORE_ALIAS, or the file
// %USERPROFILE%\Android\release-keystore.json {"path", "alias", "password"}.
//
// Writes builds/AlleywayBrawlers-<version>-android.apk (-debug.apk with --debug), for downloads/ on
// the server: node tools/deploy.mjs --build-android. A release build also writes the game's files as
// builds/android_<version>/AlleywayBrawlers.pck: keep it, Android patches are made against it (the
// "android" patchBase in shared/game_version.json).
import { copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname, relative, basename } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const debug = argv.includes('--debug');
const prepare = argv.includes('--prepare');
const godot = argv.find(a => !a.startsWith('--')) || process.env.GODOT;
if (!godot || !existsSync(godot)) {
    console.error('usage: node tools/build_android.mjs <path to Godot console exe> [--debug | --prepare]   (or set GODOT)');
    process.exit(2);
}
const SRC = join(ROOT, 'godot');
const COPY = join(ROOT, 'builds', 'android_project');
const version = (/config\/version="([^"]+)"/.exec(readFileSync(join(SRC, 'project.godot'), 'utf8')) || [])[1];
if (!version) throw new Error('No config/version in godot/project.godot');
const [major, minor, patch] = version.split('.').map(Number);
const code = major * 1000000 + minor * 1000 + patch;   // (Android's version code: always higher for a newer version)

// The pictures a phone gets lighter (import settings in the copy only)
const LIGHTER = [
    { test: (p) => p.startsWith('assets/cards/') && p.endsWith('.png.import'),   // card art
      params: { 'compress/mode': 1, 'compress/lossy_quality': 0.82, 'process/size_limit': 1024 } },
    { test: (p) => p.endsWith('.jpg.import'),   // the arenas and screen backgrounds
      params: { 'compress/mode': 1, 'compress/lossy_quality': 0.85, 'process/size_limit': 1920 } },
    { test: (p) => p === 'assets/main_menu_bar.png.import',   // (drawn the width of the screen)
      params: { 'process/size_limit': 1920 } },
    { test: (p) => p === 'assets/quests.png.import',   // (only its frame, 1068 of its 2400 pixels, is drawn)
      params: { 'process/size_limit': 2400 } },
    { test: (p) => p.endsWith('.png.import'),   // everything else: the menu signs, title, card backs, ... are
      params: { 'process/size_limit': 1024 } },  // never drawn bigger than this

];

const signing = debug || prepare ? null : releaseKey();

// 1. The copy: changed files copied over (keeping their times, so Godot sees what really changed),
//    files gone from godot/ removed. The first time, godot/.godot comes too (no importing everything).
if (!existsSync(join(COPY, '.godot')) && existsSync(join(SRC, '.godot'))) {
    console.log('First Android build: copying the imported files …');
    cpSync(join(SRC, '.godot'), join(COPY, '.godot'), { recursive: true });
}
let copied = 0;
let lighter = 0;
const seen = new Set();
// What each lighter .import was last written as (Godot rewrites the file once it has imported it, so
// the copy's own file can't tell whether the settings changed)
const written = join(COPY, '.godot', 'android_lighter.json');
const before = existsSync(written) ? JSON.parse(readFileSync(written, 'utf8')) : {};
const after = {};
sync(SRC);
writeFileSync(written, JSON.stringify(after));
for (const f of walk(COPY)) {
    if (!seen.has(relative(COPY, f).replace(/\\/g, '/'))) rmSync(f);
}
console.log(`Copy up to date (${copied} files copied, ${lighter} pictures set lighter).`);

// 2. The version, and the engines the APK carries
const presets = join(COPY, 'export_presets.cfg');
let cfg = readFileSync(presets, 'utf8');
cfg = cfg.replace(/^version\/code=.*$/m, `version/code=${code}`)
    .replace(/^version\/name=.*$/m, `version/name="${version}"`)
    .replace(/^architectures\/x86_64=.*$/m, `architectures/x86_64=${debug}`);
writeFileSync(presets, cfg);

// 3. Import what changed, then export
console.log('Importing …');
execFileSync(godot, ['--headless', '--path', COPY, '--import'], { stdio: 'inherit', timeout: 3600 * 1000 });
if (prepare) process.exit(0);
const out = join(ROOT, 'builds', `AlleywayBrawlers-${version}-android${debug ? '-debug' : ''}.apk`);
if (existsSync(out)) rmSync(out);
console.log(`Exporting the Android ${debug ? 'debug' : 'release'} build ${version} (version code ${code}) …`);
const env = { ...process.env };
if (signing) {
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PATH = signing.path;
    env.GODOT_ANDROID_KEYSTORE_RELEASE_USER = signing.alias;
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = signing.password;
}
execFileSync(godot, ['--headless', '--path', COPY, debug ? '--export-debug' : '--export-release', 'Android', out], { stdio: 'inherit', env });
if (!existsSync(out)) throw new Error('Godot did not write the APK (are the Android export templates, JDK and SDK set up? docs/ANDROID.md).');
for (const extra of [out + '.idsig']) if (existsSync(extra)) rmSync(extra);
console.log(`\nWrote ${out} (${Math.round(statSync(out).size / 1048576)} MB).`);
if (!debug) {
    // The same files as a pack: what Android patches of later versions are compared against
    const base = join(ROOT, 'builds', `android_${version}`);
    mkdirSync(base, { recursive: true });
    execFileSync(godot, ['--headless', '--path', COPY, '--export-pack', 'Android', join(base, 'AlleywayBrawlers.pck')], { stdio: 'inherit' });
    console.log(`Wrote ${join(base, 'AlleywayBrawlers.pck')} (keep it: patches for this APK are made against it).`);
    console.log('Next: push, then  node tools/deploy.mjs --build-android');
}

function sync(dir) {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
        const from = join(dir, e.name);
        const rel = relative(SRC, from).replace(/\\/g, '/');
        if (rel === '.godot' || rel === 'tests') continue;
        const to = join(COPY, rel);
        if (e.isDirectory()) {
            mkdirSync(to, { recursive: true });
            sync(from);
            continue;
        }
        seen.add(rel);
        const rule = rel.endsWith('.import') && LIGHTER.find(r => r.test(rel));
        if (rule) {
            const text = lighten(readFileSync(from, 'utf8'), rule.params);
            after[rel] = text;
            if (!existsSync(to) || before[rel] !== text) {
                writeFileSync(to, text);
                forget(rel);   // (its imported files: Godot imports it again with the new settings)
                lighter++;
            }
            continue;
        }
        const s = statSync(from);
        if (existsSync(to)) {
            const d = statSync(to);
            if (d.size === s.size && Math.abs(d.mtimeMs - s.mtimeMs) < 2) continue;
        }
        copyFileSync(from, to);
        utimesSync(to, s.atime, s.mtime);
        copied++;
    }
}

/** An .import file with some [params] changed. */
function lighten(text, params) {
    for (const [k, v] of Object.entries(params)) {
        const line = new RegExp(`^${k.replace(/\//g, '\\/')}=.*$`, 'm');
        text = line.test(text) ? text.replace(line, `${k}=${v}`) : text.replace(/^\[params\]\s*$/m, `[params]\n\n${k}=${v}`);
    }
    return text;
}

/** Removes an asset's imported files from the copy, so Godot imports it again. */
function forget(rel) {
    const dir = join(COPY, '.godot', 'imported');
    if (!existsSync(dir)) return;
    const name = basename(rel, '.import') + '-';
    for (const f of readdirSync(dir)) if (f.startsWith(name)) rmSync(join(dir, f));
}

function* walk(dir) {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
        const p = join(dir, e.name);
        if (e.isDirectory()) {
            if (e.name !== '.godot') yield* walk(p);
        } else {
            yield p;
        }
    }
}

/** The release key: from the environment, or %USERPROFILE%\Android\release-keystore.json. */
function releaseKey() {
    let k = { path: process.env.ANDROID_KEYSTORE, password: process.env.ANDROID_KEYSTORE_PASS, alias: process.env.ANDROID_KEYSTORE_ALIAS || 'alleyway' };
    const file = join(homedir(), 'Android', 'release-keystore.json');
    if (!k.path && existsSync(file)) k = { alias: 'alleyway', ...JSON.parse(readFileSync(file, 'utf8')) };
    if (!k.path || !k.password || !existsSync(k.path)) {
        console.error('No release key: set ANDROID_KEYSTORE and ANDROID_KEYSTORE_PASS, or make ' + file +
            ' (docs/ANDROID.md, "The release key"). Or build with --debug.');
        process.exit(1);
    }
    return k;
}
