// Puts the Card Forge cards (shared/cards_forge.js) into the database, so they can drop
// from packs, be collected, and be built into decks. Safe to run again after every import:
// existing cards (matched by game ID) are updated in place.
//
//   node backend/scripts/sync_cards.mjs
//
// A clan that's new to the database becomes a pack type, and the shop offers its pack once
// it has at least 3 cards.
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { FORGE_CARDS } from '../../shared/cards_forge.js';

dotenv.config({ path: join(dirname(fileURLToPath(import.meta.url)), '..', '.env') });
// The pool reads the database settings when it loads, so load it after .env
const { pool } = (await import('../db/pool.js')).default;

const cards = Object.values(FORGE_CARDS);
if (!cards.length) {
    console.log('No Forge cards to sync (shared/cards_forge.js is empty). Run tools/import_forge.mjs first.');
    process.exit(0);
}

let added = 0, updated = 0, failed = 0;
try {
    // New clans become pack types (DDL can't take parameters, so check the names first)
    const clans = [...new Set(cards.map(c => c.clan))];
    for (const clan of clans) {
        if (!/^[a-z0-9_]+$/.test(clan)) throw new Error(`Bad clan name "${clan}"`);
        await pool.query(`ALTER TYPE pack_type ADD VALUE IF NOT EXISTS '${clan}'`);
    }
    // Forge cards may cost 0 to 15 Authority (the original limit was 1 to 12)
    await pool.query('ALTER TABLE cards DROP CONSTRAINT IF EXISTS cards_authority_check');
    await pool.query('ALTER TABLE cards ADD CONSTRAINT cards_authority_check CHECK (authority BETWEEN 0 AND 15)');

    for (const c of cards) {
        const unit = c.cardType === 'gang_member' || c.cardType === 'leader';
        const row = [
            c.name, c.clan, c.cardType, c.clanTag || null, unit ? c.subtype : null, unit ? c.level : null,
            c.authority, unit ? c.attack : null, unit ? c.defense : null, c.tributeCost || 0, c.rarity,
            c.effectText || null, c.effectKey || null, c.id, c.flavourText || null,
        ];
        try {
            const { rows } = await pool.query('SELECT id FROM cards WHERE art_url = $1', [c.id]);
            if (rows.length) {
                await pool.query(
                    `UPDATE cards SET name=$1, clan=$2, card_type=$3, clan_tag=$4, subtype=$5, level=$6,
                        authority=$7, attack=$8, defense=$9, tribute_cost=$10, rarity=$11,
                        effect_text=$12, effect_key=$13, flavour_text=$15
                     WHERE art_url=$14`, row);
                updated++;
            } else {
                await pool.query(
                    `INSERT INTO cards (name, clan, card_type, clan_tag, subtype, level, authority, attack, defense,
                        tribute_cost, rarity, effect_text, effect_key, art_url, flavour_text)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`, row);
                added++;
            }
        } catch (err) {
            failed++;
            console.error(`  ! ${c.id} (${c.name}): ${err.message}`);
        }
    }
    console.log(`Forge cards synced: ${added} added, ${updated} updated${failed ? `, ${failed} failed` : ''}.`);
} finally {
    await pool.end();
}
process.exit(failed ? 1 : 0);
