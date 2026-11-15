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
// Phone notifications: with the Firebase project's android/alleyway_push/google-services.json there, an
// APK build also builds the notification plugin (android/alleyway_push, a small Android library), puts it
// into the copy with Firebase Cloud Messaging, and exports with Godot's Gradle build (the first time it
// downloads Gradle and the Android build tools). --prepare (for patches) never does: patches don't change.
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
const PUSH = join(ROOT, 'android', 'alleyway_push');

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
const gradle = pushPlugin();
const out = join(ROOT, 'builds', `AlleywayBrawlers-${version}-android${debug ? '-debug' : ''}.apk`);
if (existsSync(out)) rmSync(out);
console.log(`Exporting the Android ${debug ? 'debug' : 'release'} build ${version} (version code ${code}) …`);
const env = { ...process.env };
if (signing) {
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PATH = signing.path;
    env.GODOT_ANDROID_KEYSTORE_RELEASE_USER = signing.alias;
    env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = signing.password;
}
// (no Gradle daemon: one left running keeps Godot's output open, and Godot waits for it forever)
if (gradle) env.GRADLE_OPTS = `${env.GRADLE_OPTS || ''} -Dorg.gradle.daemon=false`.trim();
execFileSync(godot, ['--headless', '--path', COPY, ...(gradle ? ['--install-android-build-template'] : []),
    debug ? '--export-debug' : '--export-release', 'Android', out], { stdio: 'inherit', env });
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

/**
 * The notification plugin into the copy (an APK build only): its library built with the Firebase project's
 * IDs (res/values/firebase.xml, as Google's own Gradle plugin would write them: Firebase starts itself from
 * them, so notifications show even when the game isn't running), the export plugin that adds it and
 * Firebase Cloud Messaging to the APK, switched on, and the Gradle build. → whether it did (no
 * google-services.json: an APK without notifications, as before).
 */
function pushPlugin() {
    const gs = join(PUSH, 'google-services.json');
    if (!existsSync(gs)) {
        console.log('No android/alleyway_push/google-services.json: this APK gets no phone notifications.');
        return false;
    }
    const pkg = (/^package\/unique_name="([^"]+)"/m.exec(readFileSync(join(COPY, 'export_presets.cfg'), 'utf8')) || [])[1];
    const g = JSON.parse(readFileSync(gs, 'utf8'));
    const client = (g.client || []).find(c => c.client_info?.android_client_info?.package_name === pkg);
    if (!client) throw new Error(`google-services.json has no Android app ${pkg}: add it in the Firebase console and download the file again.`);
    const ids = {
        google_app_id: client.client_info.mobilesdk_app_id, gcm_defaultSenderId: g.project_info.project_number,
        google_api_key: client.api_key?.[0]?.current_key || '', project_id: g.project_info.project_id,
        google_storage_bucket: g.project_info.storage_bucket || '',
    };
    mkdirSync(join(PUSH, 'src', 'main', 'res', 'values'), { recursive: true });
    writeFileSync(join(PUSH, 'src', 'main', 'res', 'values', 'firebase.xml'), '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' +
        Object.entries(ids).map(([k, v]) => `    <string name="${k}" translatable="false">${v}</string>\n`).join('') + '</resources>\n');
    // Godot's library to compile against, the JDK and the SDK: from Godot's Android template and editor settings
    const roaming = process.env.APPDATA || join(homedir(), 'AppData', 'Roaming');
    const tver = execFileSync(godot, ['--version'], { encoding: 'utf8' }).trim().split('.').slice(0, 4).join('.');   // (4.7.2.stable)
    const zip = join(roaming, 'Godot', 'export_templates', tver, 'android_source.zip');
    const lib = join(ROOT, 'builds', 'android_template', 'libs', 'release', 'godot-lib.template_release.aar');
    mkdirSync(join(ROOT, 'builds', 'android_template'), { recursive: true });
    // (Windows' own tar reads zips; Git Bash's GNU tar, first on its PATH, doesn't and takes C: for a host)
    const tar = process.platform === 'win32' ? join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe') : 'bsdtar';
    execFileSync(tar, ['-xf', zip,'-C', join(ROOT, 'builds', 'android_template'), 'libs/release/godot-lib.template_release.aar']);
    const settings = readdirSync(join(roaming, 'Godot')).filter(n => /^editor_settings-.*\.tres$/.test(n)).sort().pop();
    const setting = (k) => (new RegExp(`^export/android/${k} = "([^"]*)"`, 'm').exec(readFileSync(join(roaming, 'Godot', settings), 'utf8')) || [])[1];
    writeFileSync(join(PUSH, 'local.properties'), `sdk.dir=${setting('android_sdk_path').replace(/\\/g, '/')}\n`);
    console.log('Building the notification plugin …');
    // (without NoDefaultCurrentDirectoryInExePath, which Claude Code's shell sets: with it cmd won't run gradlew.bat from cwd)
    const env = { ...process.env, JAVA_HOME: setting('java_sdk_path'), GODOT_LIB: lib };
    delete env.NoDefaultCurrentDirectoryInExePath;
    execFileSync(process.platform === 'win32' ? 'cmd.exe' : './gradlew', [...(process.platform === 'win32' ? ['/c', 'gradlew.bat'] : []), 'assembleRelease', '--no-daemon'],
        { cwd: PUSH, stdio: 'inherit', env });
    // Into the copy, switched on; and the Gradle build
    const addon = join(COPY, 'addons', 'alleyway_push');
    mkdirSync(join(addon, 'bin'), { recursive: true });
    for (const n of ['plugin.cfg', 'plugin.gd']) copyFileSync(join(PUSH, 'addon', n), join(addon, n));
    copyFileSync(join(PUSH, 'build', 'outputs', 'aar', 'alleyway_push-release.aar'), join(addon, 'bin', 'alleyway_push-release.aar'));
    const proj = join(COPY, 'project.godot');
    let text = readFileSync(proj, 'utf8').replace(/\n\[editor_plugins\]\n\nenabled=.*\n/, '\n');
    writeFileSync(proj, text.trimEnd() + '\n\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/alleyway_push/plugin.cfg")\n');
    writeFileSync(presets, readFileSync(presets, 'utf8').replace(/^gradle_build\/use_gradle_build=.*$/m, 'gradle_build/use_gradle_build=true'));
    return true;
}

function* walk(dir) {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
        const p = join(dir, e.name);
        if (e.isDirectory()) {
            // (the copy's Android build template stays: Godot installs it once for the Gradle build)
            if (e.name !== '.godot' && !(dir === COPY && e.name === 'android')) yield* walk(p);
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
