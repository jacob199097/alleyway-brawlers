// Makes the website's pictures: the in-game screenshots (website/shots/ + shots.json, which the pages
// read) and the logo, front-page art, link-preview picture and icons (website/img/). All of it is in
// git, so the server needs nothing but a pull: run this only when the game's look has changed.
//
//   node tools/site_shots.mjs                  from the screenshots already in builds/site_shots/
//   node tools/site_shots.mjs <Godot exe>      takes the screenshots first: the mock server and the
//                                              screenshot tour (godot/tests/screens_tour.tscn) in the
//                                              modes below, about 20 minutes with windows opening
//                                              (run it with APPDATA set to a short folder, e.g.
//                                              C:\Users\<you>\gt, so the game's shaders draw right)
//   node tools/site_shots.mjs <Godot exe> --only <mode>     just that tour, then the pictures
//
// SHOTS says which screenshot becomes which picture, with the caption the site shows under it. The
// "site" tour stages its matches (SITE_SCENES in screens_tour.gd: two clans each, one move played) and
// takes a run of shots of each move, so after a new tour look through builds/site_shots/ and pick again.
// Its Turf Defense needs a partner: a headless test player (godot/tests/online_bot.tscn) on the same boss.
// Needs `sharp` (npm install in backend/).
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const TOURS = join(ROOT, 'builds/site_shots');   // (builds/ is not in git: the screenshots are 4 MB each)
const SITE = join(ROOT, 'website');
const PORT = 3999;

// tour mode (its folder in builds/site_shots/) → the tour's flags
const MODES = { site: ['--site', '--autoplay'], 'turf-map': ['--turf-map'] };
const TURF_BOSS = 'veyr';   // (SITE_BOSS in screens_tour.gd)

// [name on the site, screenshot, caption, what it shows (for screen readers), tags]
// 'gallery' puts it in "From the game" on the front page; the pages ask for the others by name.
// The matches are the "site" tour's staged ones (SITE_SCENES in screens_tour.gd), so the clans, cards
// and moments named here are what those scenes play; the number is the frame picked from each run.
const SHOTS = [
    ['duel-casino', 'site/site_casino_14', 'Wildcard against Arsonists in the casino: Garrison, the Pit Boss, deals Smokestack a losing hand.',
        'A match in the casino between a Wildcard deck and an Arsonists deck, both boards full: playing cards fly from Garrison, the Pit Boss, toward Smokestack.'],
    ['duel-turn', 'site/site_deploy_00', 'Every turn starts with the Deployment Phase: call in fighters, play Hustles, set Ambushes.',
        'A Militia against Underworld match in a military base, with the words DEPLOYMENT PHASE across the board.'],
    ['duel-brawl', 'site/site_brawl_30', 'Pirates against Militia on the docks: Hellstorm loses the brawl to Dreadmaw and goes Down.',
        'A match on the docks: a Militia character turned on its side under a DOWNED stamp after an attack by a Pirates Heavy.'],
    ['duel-ko', 'site/site_ko_29', 'Hit a fighter while it\'s Down and it\'s KO\'d: the Herald of the Hollow Throne finishes Catherine.',
        'A match in a graveyard: a Wildcard character bursts into playing cards under a K.O. stamp after an Underworld attack.'],
    ['duel-ambush', 'site/site_ambush_06', 'AMBUSH! A Militia attack runs into the Arsonists\' Inferno Wall.',
        'A match in a volcanic arena: the word AMBUSH! over a face-down Arsonists card turning up as the Militia attacks.'],
    ['awaken', 'site/site_awaken_09', 'Captain Marlow AWAKENS: when the moment comes, a leader takes the street himself.',
        'A Pirates leader card in a burst of rays under the words CAPTAIN MARLOW AWAKENS.', ['gallery']],
    ['legendary', 'site/site_deploy_10', 'A Legendary takes the street: Iron Lieutenant Kessler drops in for the Militia.',
        'A Militia card in a burst of golden rays under the words LEGENDARY · IRON LIEUTENANT KESSLER.', ['gallery']],
    ['inferno', 'site/site_inferno_25', 'Inferno Shockwave: the whole Nebula line catches fire at once.',
        'An Arsonists Hustle sets every Nebula character on the board burning, with Cinder, the Arsonists\' leader, on the field.', ['gallery']],
    ['turf-boss', 'site/site_turf_intro_08', 'Turf Defense: you and a partner against Veyr, the Hollow King, and his army of the dead.',
        'The entrance of a Turf Defense boss: Veyr, the Hollow King, Sovereign of the Dead, with his card and his first line.', ['gallery']],
    ['promote', 'site/site_evolve_29', 'Lyra Quell promotes mid-attack: level 1 to level 2, stronger on the spot.',
        'A Nebula card in a burst of light under the word EVOLVED, two stars lit, with its new level, ATK and DEF underneath.', ['gallery']],
    ['pack', 'site/site_pack_epic_19', 'A Legendary from an Arsonists pack: Pyra, the Undying Flame.',
        'A card in a shower of gold under the word LEGENDARY!, just turned over after opening an Arsonists booster pack.', ['gallery']],
    ['stasis', 'site/site_stasis_22', 'Hull Breach: a Nebula Ambush locks the whole Underworld line in STASIS.',
        'On a frozen board, rings of light lock each Underworld character in STASIS after a Nebula Ambush springs.', ['gallery']],
    ['ffa', 'site/site_ffa_13', 'Free-for-all: four players, one board.',
        'A four-player match, each player with a corner of the board.', ['gallery']],
    ['victory', 'site/site_victory', 'Victory, and the match\'s most valuable card.',
        'The Victory screen after a match, with the match numbers and the most valuable card.', ['gallery']],
    ['main-menu', 'site/site_main_menu', 'The main menu.',
        'The main menu in neon signs: Fight, Deck Editor, Shop, Auction House, Card Library, Achievements, Turf Map and the daily quests.', ['gallery']],
    ['deck-builder', 'site/site_deck_builder', 'The deck builder.',
        'The deck builder: the card collection on the left, the deck and its leader on the right.', ['gallery']],
    ['turf-zoom', 'turf-map/t02b_zoomed', 'The Frozen Lake and The Lab, up close on the turf map.',
        'The turf map zoomed in on two districts: a frozen lake and a glowing green laboratory.', ['gallery']],
    ['card-library', 'site/site_card_library', 'The Card Library: every card, and how many you own.',
        'A grid of cards in the Card Library.'],
    ['turf-map', 'turf-map/t04_claimed', 'The turf map: every district of the city, and who holds it this week.',
        'A painted map of the city at night with a clan emblem over each district.'],
    ['fight-mode', 'site/site_fight_mode', 'Five ways to play.',
        'The battle mode screen: Casual Brawl, Ranked Brawl, VS CPU, Free-for-all and Turf Defense.'],
    ['rank-up', 'site/site_rank_up', 'Ranking up to Underboss.',
        'The words RANK UP over the Underboss emblem.'],
    ['district', 'turf-map/t06a_district_stars', 'A district: who holds it, and who is fighting for it.',
        'A district\'s panel on the turf map: the clan that holds it and each clan\'s influence there this week.'],
];

const args = process.argv.slice(2);
const godot = args.find((a) => !a.startsWith('--') && args[args.indexOf(a) - 1] !== '--only');
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;

let sharp;
try {
    sharp = createRequire(join(ROOT, 'backend/package.json'))('sharp');
} catch {
    console.error('This needs sharp: run `npm install` in backend/ first.');
    process.exit(2);
}

/** Plays the screenshot tour in each mode against the mock server; the PNGs land in builds/site_shots/<mode>/. */
async function tours() {
    if (!existsSync(godot)) throw new Error(`No Godot at ${godot}`);
    if (only && !(only in MODES)) throw new Error(`--only takes one of: ${Object.keys(MODES).join(', ')}`);
    // (a short free-for-all lobby; turns long enough for the tour, which plays its own seat (--autoplay)
    // after showing the other players' moves, not to be put out for being away)
    const mock = spawn(process.execPath, [join(ROOT, 'godot/tests/mock_server.mjs'), String(PORT)], {
        env: { ...process.env, FFA_LOBBY_SECS: '5', FFA_TURN_SECS: '25', FFA_AWAY_SECS: '15' }, stdio: ['ignore', 'pipe', 'inherit'],
    });
    try {
        await new Promise((ok, fail) => {
            mock.stdout.on('data', (d) => String(d).includes('Mock server on') && ok());
            mock.on('exit', (code) => fail(new Error(`The mock server stopped (exit ${code}): is port ${PORT} taken?`)));
            setTimeout(() => fail(new Error('The mock server did not start.')), 15_000).unref();
        });
        for (const [mode, flags] of Object.entries(MODES)) {
            if (only && mode !== only) continue;
            const out = join(TOURS, mode);
            mkdirSync(out, { recursive: true });
            console.log(`Tour "${mode}"...`);
            const partner = mode === 'site' ? spawn(godot, ['--headless', '--path', join(ROOT, 'godot'), 'res://tests/online_bot.tscn', '--',
                'ashfall@example.com', `http://127.0.0.1:${PORT}`, `--turf=${TURF_BOSS}:1`, '--autoplay'], { stdio: 'ignore' }) : null;
            const r = spawnSync(godot, ['--path', join(ROOT, 'godot'), '--rendering-driver', 'opengl3_angle', 'res://tests/screens_tour.tscn',
                '--', out.replace(/\\/g, '/'), `http://127.0.0.1:${PORT}`, ...flags], { stdio: 'ignore', timeout: 900_000 });
            partner?.kill();
            if (r.error) throw new Error(`Tour "${mode}": ${r.error.message}`);
            console.log(`  ${readdirSync(out).filter((f) => f.endsWith('.png')).length} screenshots in builds/site_shots/${mode}/`);
        }
    } finally {
        mock.removeAllListeners('exit');
        mock.kill();
    }
}

/** website/shots/: each pick at 1600 and 800 wide, and shots.json for the pages. */
async function shots() {
    const out = join(SITE, 'shots');
    mkdirSync(out, { recursive: true });
    const list = [];
    for (const [name, from, caption, alt, tags = []] of SHOTS) {
        const src = join(TOURS, `${from}.png`);
        if (!existsSync(src)) {
            console.warn(`  (no ${from}.png: "${name}" is left out)`);
            continue;
        }
        const big = await sharp(src).resize({ width: 1600 }).webp({ quality: 80 }).toFile(join(out, `${name}.webp`));
        await sharp(src).resize({ width: 800 }).webp({ quality: 78 }).toFile(join(out, `${name}-800.webp`));
        list.push({ name, caption, alt, w: big.width, h: big.height, tags });
    }
    writeFileSync(join(out, 'shots.json'), JSON.stringify(list, null, 2) + '\n');
    console.log(`${list.length} screenshots → website/shots/`);
}

/** website/img/: the front page's art and logo, the picture for link previews, the icons. */
async function art() {
    const out = join(SITE, 'img');
    mkdirSync(out, { recursive: true });
    const alley = join(ROOT, 'assets/menu_background.jpg');
    const title = join(ROOT, 'assets/title_alleyway.png');
    const icon = join(ROOT, 'godot/icon.png');

    await sharp(alley).resize({ width: 1920 }).jpeg({ quality: 74, mozjpeg: true }).toFile(join(out, 'hero.jpg'));
    await sharp(alley).resize({ width: 900 }).jpeg({ quality: 72, mozjpeg: true }).toFile(join(out, 'hero-900.jpg'));
    await sharp(title).resize({ width: 900 }).webp({ quality: 88 }).toFile(join(out, 'logo.webp'));
    await sharp(title).resize({ width: 320 }).webp({ quality: 88 }).toFile(join(out, 'logo-320.webp'));

    // Link previews (1200 × 630): the logo over the alley, darkened so the logo reads
    const logo = await sharp(title).resize({ width: 860 }).toBuffer();
    await sharp(alley).resize({ width: 1200, height: 630, fit: 'cover' }).modulate({ brightness: 0.5 })
        .composite([{ input: logo, gravity: 'centre' }]).jpeg({ quality: 82, mozjpeg: true }).toFile(join(out, 'og.jpg'));

    await sharp(icon).resize(32, 32).png().toFile(join(out, 'icon-32.png'));
    await sharp(icon).resize(192, 192).png().toFile(join(out, 'icon-192.png'));
    await sharp(icon).resize(180, 180).flatten({ background: '#0b0b16' }).png().toFile(join(out, 'icon-180.png'));   // (iPhones want no see-through)
    console.log('Logo, front-page art, link preview and icons → website/img/');
}

try {
    if (godot) await tours();
    await shots();
    await art();
} catch (err) {
    console.error(err.message);
    process.exit(1);
}
