// The Steam build: exports the "Windows Steam" preset (the Windows game marked "steam": Steam signs
// players in and updates it, so no in-game patches) into builds/steam/windows/, writes the SteamPipe
// scripts for it, and (with --upload) uploads it with steamcmd. docs/STEAM.md has the whole setup.
//
//   node tools/steam_build.mjs <godot console exe>                    export + write the SteamPipe scripts
//   node tools/steam_build.mjs <godot> --upload [--live]              ...then upload (steamcmd, STEAM_BUILD_USER);
//                                                                     --live also sets it live on the "beta" branch
//   options: --app <App ID> --depot <depot ID>   (default: STEAM_APP_ID / STEAM_DEPOT_ID, or App ID + 1)
//            --steamcmd <path>                    (default: steamcmd on the PATH)
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (name, fallback = '') => { const i = args.indexOf(name); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : fallback; };
const godot = args.find((a, i) => !a.startsWith('--') && !['--app', '--depot', '--steamcmd'].includes(args[i - 1])) || process.env.GODOT;
if (!godot) {
    console.error('usage: node tools/steam_build.mjs <path to Godot console exe> [--upload [--live]] [--app <id>] [--depot <id>]');
    process.exit(2);
}
const steamGd = readFileSync(join(ROOT, 'godot/scripts/steam.gd'), 'utf8');
const gameAppId = (/const APP_ID := (\d+)/.exec(steamGd) || [])[1] || '480';
const appId = opt('--app', process.env.STEAM_APP_ID || gameAppId);
const depotId = opt('--depot', process.env.STEAM_DEPOT_ID || String(Number(appId) + 1));
const version = JSON.parse(readFileSync(join(ROOT, 'shared/game_version.json'), 'utf8')).latest;
if (appId !== gameAppId) {
    console.error(`The game's App ID (godot/scripts/steam.gd: ${gameAppId}) isn't ${appId}: set APP_ID there first.`);
    process.exit(1);
}

// 1. Export
const outDir = join(ROOT, 'builds/steam/windows');
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
console.log(`Exporting the Steam build (v${version}, App ID ${appId}) …`);
execFileSync(godot, ['--headless', '--path', join(ROOT, 'godot'), '--export-release', 'Windows Steam', join(outDir, 'AlleywayBrawlers.exe')], { stdio: 'inherit' });
for (const f of ['AlleywayBrawlers.exe', 'steam_api64.dll']) {
    if (!existsSync(join(outDir, f))) throw new Error(`The export is missing ${f}.`);
}

// 2. SteamPipe scripts (paths are relative to the scripts folder)
const scripts = join(ROOT, 'builds/steam/scripts');
mkdirSync(scripts, { recursive: true });
const appVdf = join(scripts, `app_build_${appId}.vdf`);
writeFileSync(appVdf, `"AppBuild"
{
\t"AppID" "${appId}"
\t"Desc" "AlleyWay Brawlers v${version}"
\t"ContentRoot" "..\\windows\\"
\t"BuildOutput" "..\\output\\"
\t"SetLive" "${args.includes('--live') ? 'beta' : ''}"
\t"Depots"
\t{
\t\t"${depotId}" "depot_build_${depotId}.vdf"
\t}
}
`);
writeFileSync(join(scripts, `depot_build_${depotId}.vdf`), `"DepotBuild"
{
\t"DepotID" "${depotId}"
\t"FileMapping"
\t{
\t\t"LocalPath" "*"
\t\t"DepotPath" "."
\t\t"Recursive" "1"
\t}
\t"FileExclusion" "*.pdb"
}
`);
console.log(`\nSteam build in ${outDir}\nSteamPipe scripts: ${appVdf}`);

// 3. Upload
if (!args.includes('--upload')) {
    console.log('Upload it with:  node tools/steam_build.mjs <godot> --upload   (docs/STEAM.md)');
    process.exit(0);
}
if (appId === '480') {
    console.error("App ID 480 is Valve's test app: nothing can be uploaded to it. Set the game's own App ID first (docs/STEAM.md).");
    process.exit(1);
}
const user = process.env.STEAM_BUILD_USER;
if (!user) {
    console.error('Set STEAM_BUILD_USER to the Steam account that uploads builds (steamcmd asks for its password and Steam Guard code the first time).');
    process.exit(1);
}
const steamcmd = opt('--steamcmd', 'steamcmd');
const r = spawnSync(steamcmd, ['+login', user, '+run_app_build', appVdf, '+quit'], { stdio: 'inherit' });
process.exit(r.status ?? 1);
