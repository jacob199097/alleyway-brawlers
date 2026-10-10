// Writes godot/data/cards.json from shared/cards.js (the single source of card rules data), and
// godot/data/content.json: fingerprints of that card data and of every card image the build
// ships with, so the game knows which newer cards to download from the server (backend/routes/content.js).
// Run after changing cards:  node godot/tools/export_cards.mjs
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CARD_CATALOG } from '../../shared/cards.js';

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const json = JSON.stringify(CARD_CATALOG, null, 1) + '\n';
const out = fileURLToPath(new URL('../data/cards.json', import.meta.url));
writeFileSync(out, json);

const artDir = fileURLToPath(new URL('../../assets/cards/', import.meta.url));
const art = {};
for (const f of readdirSync(artDir).filter(f => f.endsWith('.png')).sort()) {
    art[f.slice(0, -4)] = sha256(readFileSync(artDir + f));
}
// Card backs the build ships with (assets/card_back*.png)
const backDir = fileURLToPath(new URL('../../assets/', import.meta.url));
const backs = {};
for (const f of readdirSync(backDir).filter(f => /^card_back(_[a-z0-9_]+)?\.png$/.test(f)).sort()) {
    backs[f.slice(0, -4)] = sha256(readFileSync(backDir + f));
}
writeFileSync(fileURLToPath(new URL('../data/content.json', import.meta.url)),
    JSON.stringify({ cards: sha256(json), art, backs }, null, 1) + '\n');
console.log(`Wrote ${Object.keys(CARD_CATALOG).length} cards to ${out} (and fingerprints for ${Object.keys(art).length} images)`);
