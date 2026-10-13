// Brings cards from the Card Forge into the game.
//
//   node tools/import_forge.mjs <alleyway-cards.zip | unzipped folder>
//
// Takes the Forge's export download (card_catalog.json + cards/<id>.png) and:
//   1. writes shared/cards_forge.js (card rules data, merged into CARD_CATALOG),
//   2. copies the card images to assets/cards and godot/assets/cards,
//   3. regenerates godot/data/cards.json.
// A full export ("Export all Done") is the source of truth: cards not in it are removed here too.
// A changes-only export ("Export changes": export.json says { "changes": true }) is merged in: the
// cards in it are added or updated, and every other card stays as it is.
// Then commit, push, and on the server run:  node backend/scripts/sync_cards.mjs
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, copyFileSync, statSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = process.argv[2];
if (!src || !existsSync(src)) {
    console.error('usage: node tools/import_forge.mjs <alleyway-cards.zip | folder>');
    process.exit(2);
}

// ── 1. Unpack ────────────────────────────────────────────────────────────────
let dir = src;
if (statSync(src).isFile()) {
    dir = mkdtempSync(join(tmpdir(), 'forge-'));
    if (process.platform === 'win32') {
        const q = (p) => `'${p.replace(/'/g, "''")}'`;
        execFileSync('powershell', ['-NoProfile', '-Command',
            `Expand-Archive -LiteralPath ${q(src)} -DestinationPath ${q(dir)} -Force`]);
    } else {
        execFileSync('unzip', ['-q', src, '-d', dir]);          // Linux / macOS
    }
}
const catalogPath = findFile(dir, 'card_catalog.json');
if (!catalogPath) fail(`No card_catalog.json in ${src}. Use the Forge's "Export all" download.`);
const exported = JSON.parse(readFileSync(catalogPath, 'utf8'));
const artDir = join(dirname(catalogPath), 'cards');
const metaPath = join(dirname(catalogPath), 'export.json');
const changesOnly = existsSync(metaPath) && JSON.parse(readFileSync(metaPath, 'utf8')).changes === true;

// ── 2. Clean up each card ────────────────────────────────────────────────────
const TYPES = ['gang_member', 'leader', 'hustle', 'ambush'];
const cards = {};
const warnings = [];
for (const [key, raw] of Object.entries(exported)) {
    const id = String(raw.id || key).trim();
    if (!/^[a-z0-9_]+$/.test(id)) {
        warnings.push(`"${raw.name}": game ID "${id}" should be lower-case letters, digits and _ only; skipped.`);
        continue;
    }
    if (!TYPES.includes(raw.cardType)) warnings.push(`${id}: unknown card type "${raw.cardType}".`);
    const unit = raw.cardType === 'gang_member' || raw.cardType === 'leader';
    const c = {
        id,
        name: String(raw.name || id),
        clan: String(raw.clan || raw.clanTag || 'nebula'),
        cardType: raw.cardType,
        authority: int(raw.authority),
        tributeCost: int(raw.tributeCost),
        rarity: Math.min(5, Math.max(1, int(raw.rarity) || 1)),
        clanTag: String(raw.clanTag || raw.clan || ''),
        effectKey: raw.effectKey || '',
        art_url: id,
        code: raw.code || '',
        flavourText: raw.flavourText || '',
        effectText: raw.effectText || '',
        effects: Array.isArray(raw.effects) ? raw.effects.map(cleanEffect) : [],
    };
    // The clan's name and colour as set in the Forge (shown by the game's screens; shared/clans.js)
    if (raw.clanName) c.clanName = String(raw.clanName);
    if (/^#[0-9a-f]{6}$/i.test(String(raw.clanColor || ''))) c.clanColor = String(raw.clanColor);
    if (unit) {
        c.attack = int(raw.attack);
        c.defense = int(raw.defense);
        c.level = int(raw.level) || 1;
        c.subtype = raw.subtype || 'brawler';
        c.promotesTo = raw.promotesTo || null;
    }
    // Class rules: only Strivers have levels and promote; a Heavy costs one sacrifice
    if (raw.cardType === 'gang_member') {
        if (!['striver', 'brawler', 'heavy'].includes(c.subtype)) {
            warnings.push(`${id}: unknown role "${c.subtype}"; treated as a Brawler.`);
            c.subtype = 'brawler';
        }
        if (c.subtype !== 'striver' && (c.level !== 1 || c.promotesTo)) {
            warnings.push(`${id}: ${c.subtype}s are standalone, so its level was set to 1 and "promotes to" cleared.`);
            c.level = 1;
            c.promotesTo = null;
        }
        c.tributeCost = c.subtype === 'heavy' ? 1 : 0;
    }
    if (raw.cardType === 'leader' && raw.awakenCondition) c.awakenCondition = raw.awakenCondition;
    if (raw.cardType === 'leader' && raw.influence != null) c.influence = int(raw.influence);   // Influence while Dormant
    if (raw.cardType === 'ambush' && raw.ambushClan) c.ambushClan = String(raw.ambushClan);   // springs only for this clan
    // A token: made only by effects in a duel (never in packs, decks or the Card Library)
    if (raw.cardType === 'gang_member' && raw.token) c.token = true;
    cards[id] = c;
}
// A changes-only export updates these cards and keeps all the others
const before = await currentForgeCards();
const incoming = Object.keys(cards);
const all = changesOnly ? { ...before, ...cards } : cards;
for (const c of Object.values(all)) {
    if (c.promotesTo && !all[c.promotesTo]) warnings.push(`${c.id}: promotes to "${c.promotesTo}", which isn't in the game or the export.`);
    const next = all[c.promotesTo];
    if (next && next.subtype !== 'striver') warnings.push(`${c.id}: promotes to "${next.id}", which isn't a Striver.`);
    if (!existsSync(join(artDir, `${c.id}.png`)) && !existsSync(join(ROOT, 'assets/cards', `${c.id}.png`))) warnings.push(`${c.id}: no card image.`);
}

// ── 3. Write the data, copy the art, regenerate Godot's data ────────────────
writeFileSync(join(ROOT, 'shared/cards_forge.js'),
    `/**\n * Cards made in the Card Forge. Generated by tools/import_forge.mjs; don't edit by hand.\n` +
    ` * Merged on top of CARD_CATALOG in shared/cards.js (same id = the Forge version wins).\n */\n\n` +
    `export const FORGE_CARDS = ${JSON.stringify(all, null, 4)};\n`);

let copied = 0;
for (const target of ['assets/cards', 'godot/assets/cards']) {
    const to = join(ROOT, target);
    if (!existsSync(to)) mkdirSync(to, { recursive: true });
    for (const c of Object.values(cards)) {
        const from = join(artDir, `${c.id}.png`);
        if (existsSync(from)) {
            copyFileSync(from, join(to, `${c.id}.png`));
            if (target === 'assets/cards') copied++;
        }
    }
}
execFileSync(process.execPath, [join(ROOT, 'godot/tools/export_cards.mjs')], { stdio: 'inherit' });

const added = incoming.filter(id => !before[id]);
const updated = incoming.filter(id => before[id] && JSON.stringify(before[id]) !== JSON.stringify(cards[id]));
const removed = Object.keys(before).filter(id => !all[id]);
console.log(`\n${changesOnly ? 'Changes only: ' : ''}imported ${incoming.length} Forge cards (${added.length} new, ${updated.length} changed, ${removed.length} removed), ${copied} images; ${Object.keys(all).length} Forge cards in the game.`);
if (updated.length) console.log(`  changed: ${updated.join(', ')}`);
if (added.length) console.log(`  new: ${added.join(', ')}`);
if (removed.length) console.log(`  removed: ${removed.join(', ')} (their image files are left in place)`);
for (const w of warnings) console.log(`  ! ${w}`);
console.log(`\nNext: commit and push, then on the server:\n  git pull && node backend/scripts/sync_cards.mjs && sudo systemctl restart alleyway-backend`);

// ── helpers ──────────────────────────────────────────────────────────────────
function int(v) { return Math.trunc(Number(v ?? 0)) || 0; }

function cleanEffect(e) {
    const out = {};
    // (cost: an Activate ability's cost; per: "for each"; token: the token card's id; label: a
    // "choose one" option's text)
    for (const k of ['when', 'do', 'target', 'until', 'clan', 'kind', 'if', 'role', 'name', 'cost', 'per', 'per_clan', 'token', 'label']) if (e[k] != null && e[k] !== '') out[k] = String(e[k]);
    for (const k of ['atk', 'def', 'amount', 'n', 'times', 'max_auth', 'level', 'cost_n', 'per_max']) if (e[k] != null && e[k] !== '') out[k] = int(e[k]);
    if (e.once) out.once = true;
    if (e.or) out.or = true;   // "choose one": this effect or the next
    if (e.choose) out.choose = true;   // search / recover / revive: the player picks the card
    for (const k of ['if_clan', 'when_clan']) if (e[k] != null) out[k] = String(e[k]);   // ("" = any clan, so kept)
    if (Array.isArray(e.statuses) && e.statuses.length) out.statuses = e.statuses.map(String);   // immune: only these
    return out;
}

function findFile(base, name) {
    for (const entry of readdirSync(base, { withFileTypes: true })) {
        const p = join(base, entry.name);
        if (entry.isFile() && entry.name === name) return p;
        if (entry.isDirectory()) {
            const found = findFile(p, name);
            if (found) return found;
        }
    }
    return null;
}

async function currentForgeCards() {
    try {
        const mod = await import(pathToFileURL(join(ROOT, 'shared/cards_forge.js')).href + `?t=${Date.now()}`);
        return mod.FORGE_CARDS || {};
    } catch {
        return {};
    }
}

function fail(msg) {
    console.error(msg);
    process.exit(1);
}
