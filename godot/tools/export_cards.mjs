// Writes godot/data/cards.json from shared/cards.js (the single source of card rules data).
// Run after changing cards:  node godot/tools/export_cards.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CARD_CATALOG } from '../../shared/cards.js';

const out = fileURLToPath(new URL('../data/cards.json', import.meta.url));
writeFileSync(out, JSON.stringify(CARD_CATALOG, null, 1) + '\n');
console.log(`Wrote ${Object.keys(CARD_CATALOG).length} cards to ${out}`);
