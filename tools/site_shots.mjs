// Makes the website's pictures: the in-game screenshots (website/shots/ + shots.json, which the pages
// read) and the logo, front-page art, link-preview picture and icons (website/img/). All of it is in
// git, so the server needs nothing but a pull: run this only when the game's look has changed.
//
//   node tools/site_shots.mjs                  from the screenshots already in builds/site_shots/
//   node tools/site_shots.mjs <Godot exe>      takes the screenshots first: the mock server and the
//                                              screenshot tour (godot/tests/screens_tour.tscn) in the
//                                              four modes below, about 15 minutes with windows opening
//   node tools/site_shots.mjs <Godot exe> --only <mode>     just that tour, then the pictures
//
// SHOTS says which screenshot becomes which picture, with the caption the site shows under it. The
// duels are played by the CPU, so after a new tour look through builds/site_shots/ and pick again.
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

// tour mode (its folder in builds/site_shots/) → the tour's flag
const MODES = { site: '--site', 'turf-map': '--turf-map', default: '', 'evolve-only': '--evolve-only' };

// [name on the site, screenshot, caption, what it shows (for screen readers), tags]
// 'gallery' puts it in "From the game" on the front page; the pages ask for the others by name.
const SHOTS = [
    ['duel-casino', 'site/site_duel_casino_09', 'A brawl in the casino: one attack, straight across the table.',
        'A match in the casino arena, with an attack landing on the opponent\'s side of the board.'],
    ['duel-docks', 'site/site_duel_docks_13', 'An attack on the docks.',
        'A match on the docks, with an attack beam between two characters.'],
    ['duel-alley', 'site/site_duel_alley_12', 'Downed in the back alley. One more hit and it\'s a KO.',
        'A match in the back alley: a character lies turned on its side under a DOWNED stamp.'],
    ['duel-turn', 'site/site_duel_casino_14', 'Every turn starts with the Deployment Phase.',
        'A match on turn 7 with the words DEPLOYMENT PHASE across the board.'],
    ['duel-ambush', 'site/site_duel_alley_14', 'The Brawl Phase, with cards set face-down on both sides.',
        'A match with the words BRAWL PHASE across the board and face-down cards in both back rows.'],
    ['promote', 'turf-map/t06_zoom', 'A Striver up close: what it takes to promote is on the card.',
        'A Striver card enlarged, with a strip under it saying it promotes as it fights.'],
    ['evolved', 'evolve-only/e13', 'A Striver promotes to level 2 in the middle of a fight.',
        'A character card in a burst of light under the word EVOLVED, two stars lit, level 1 to level 2.', ['gallery']],
    ['pack', 'default/03_pack_done', 'Three cards from a booster pack.',
        'Three cards face-up after opening a booster pack.', ['gallery']],
    ['card-library', 'site/site_card_library', 'The Card Library: every card, and how many you own.',
        'A grid of cards in the Card Library.'],
    ['turf-map', 'turf-map/t04_claimed', 'The turf map: every district of the city, and who holds it this week.',
        'A painted map of the city at night with a clan emblem over each district.'],
    ['fight-mode', 'site/site_fight_mode', 'Five ways to play.',
        'The battle mode screen: Casual Brawl, Ranked Brawl, VS CPU, Free-for-all and Turf Defense.'],
    ['main-menu', 'site/site_main_menu', 'The main menu.',
        'The main menu in neon signs: Fight, Deck Editor, Shop, Auction House, Card Library, Achievements, Turf Map and the daily quests.', ['gallery']],
    ['deck-builder', 'site/site_deck_builder', 'The deck builder.',
        'The deck builder: the card collection on the left, the deck of 40 cards and its leader on the right.', ['gallery']],
    ['ffa', 'default/08_ffa_duel_160', 'Free-for-all: four players, one board.',
        'A four-player match, each player with a corner of the board.', ['gallery']],
    ['victory', 'default/06_post_match_early', 'Victory.',
        'The Victory screen after a match, with the match numbers and the most valuable card.', ['gallery']],
    ['rank-up', 'default/06_rank_up', 'Ranking up to Underboss.',
        'The words RANK UP over the Underboss emblem.', ['gallery']],
    ['turf-zoom', 'turf-map/t02b_zoomed', 'The Frozen Lake and The Lab, up close on the turf map.',
        'The turf map zoomed in on two districts: a frozen lake and a glowing green laboratory.', ['gallery']],
    ['district', 'turf-map/t06a_district_stars', 'A district: who holds it, and who is fighting for it.',
        'A district\'s panel on the turf map: the clan that holds it and each clan\'s influence there this week.', ['gallery']],
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
    // (a free-for-all the tour can sit through: short lobby and turns)
    const mock = spawn(process.execPath, [join(ROOT, 'godot/tests/mock_server.mjs'), String(PORT)], {
        env: { ...process.env, FFA_LOBBY_SECS: '5', FFA_TURN_SECS: '4', FFA_AWAY_SECS: '2' }, stdio: ['ignore', 'pipe', 'inherit'],
    });
    try {
        await new Promise((ok, fail) => {
            mock.stdout.on('data', (d) => String(d).includes('Mock server on') && ok());
            mock.on('exit', (code) => fail(new Error(`The mock server stopped (exit ${code}): is port ${PORT} taken?`)));
            setTimeout(() => fail(new Error('The mock server did not start.')), 15_000).unref();
        });
        for (const [mode, flag] of Object.entries(MODES)) {
            if (only && mode !== only) continue;
            const out = join(TOURS, mode);
            mkdirSync(out, { recursive: true });
            console.log(`Tour "${mode}"...`);
            const r = spawnSync(godot, ['--path', join(ROOT, 'godot'), '--rendering-driver', 'opengl3_angle', 'res://tests/screens_tour.tscn',
                '--', out.replace(/\\/g, '/'), `http://127.0.0.1:${PORT}`, ...(flag ? [flag] : [])], { stdio: 'ignore', timeout: 900_000 });
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
