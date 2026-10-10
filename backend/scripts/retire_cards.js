'use strict';
// Removes cards that are no longer in the game (not in shared/cards.js, which includes the Card
// Forge cards) from the database: out of decks and collections, then the cards themselves.
// Unopened packs of clans that no longer have a pack are refunded (PACK_REFUND Karat each), and
// players whose starting clan is gone pick a clan again (with that clan's starter) next login.
//
//   node backend/scripts/retire_cards.js            shows what would change
//   node backend/scripts/retire_cards.js --apply    does it (all or nothing)
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const PACK_REFUND = 200;     // what a pack costs in the shop (routes/shop.js)
const CLANS_IN_GAME = ['lion_pride'];   // starting clans players can still pick (routes/onboarding.js)
const apply = process.argv.includes('--apply');

(async () => {
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const inGame = Object.keys(CARD_CATALOG);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: retired } = await client.query(
            'SELECT id, name, clan::text AS clan FROM cards WHERE NOT (art_url = ANY($1)) ORDER BY clan, name', [inGame]);
        const ids = retired.map(r => r.id);
        console.log(`${retired.length} card(s) not in the game:`);
        for (const r of retired) console.log(`  - ${r.name} (${r.clan})`);

        const count = async (sql, params) => Number((await client.query(sql, params)).rows[0].n);
        const inDecks = await count('SELECT COUNT(DISTINCT deck_id) AS n FROM deck_cards WHERE card_id = ANY($1)', [ids]);
        const owned = await count('SELECT COUNT(*) AS n FROM player_inventory WHERE card_id = ANY($1)', [ids]);
        const leaders = await count('SELECT COUNT(*) AS n FROM decks WHERE leader_card_id = ANY($1)', [ids]);
        console.log(`They're in ${inDecks} deck(s) (${leaders} as leader) and ${owned} collection entr(ies).`);

        // Clans that keep a pack: ones with cards still in the game
        const { rows: keep } = await client.query(
            `SELECT DISTINCT clan::text AS clan FROM cards WHERE art_url = ANY($1)`, [inGame]);
        const packClans = keep.map(r => r.clan);
        const { rows: packs } = await client.query(
            `SELECT player_id, pack_type::text AS pack, quantity FROM player_packs
             WHERE quantity > 0 AND NOT (pack_type::text = ANY($1))`, [packClans]);
        const refund = packs.reduce((n, p) => n + p.quantity, 0);
        console.log(`${refund} unopened pack(s) of removed clans (${[...new Set(packs.map(p => p.pack))].join(', ') || 'none'}): refund ${PACK_REFUND} Karat each.`);

        const reclan = await count(`SELECT COUNT(*) AS n FROM players WHERE chosen_clan IS NOT NULL AND NOT (chosen_clan = ANY($1))`, [CLANS_IN_GAME]);
        console.log(`${reclan} player(s) started with a clan that's gone: they choose again at next login.`);

        if (!apply) {
            await client.query('ROLLBACK');
            console.log('\nNothing changed. Run again with --apply to do it.');
            return;
        }
        await client.query('DELETE FROM deck_cards WHERE card_id = ANY($1)', [ids]);
        await client.query('UPDATE decks SET leader_card_id = NULL WHERE leader_card_id = ANY($1)', [ids]);
        await client.query('DELETE FROM player_inventory WHERE card_id = ANY($1)', [ids]);
        await client.query('DELETE FROM cards WHERE id = ANY($1)', [ids]);
        for (const p of packs) {
            await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2', [p.quantity * PACK_REFUND, p.player_id]);
        }
        await client.query(`DELETE FROM player_packs WHERE NOT (pack_type::text = ANY($1))`, [packClans]);
        await client.query(`UPDATE players SET chosen_clan = NULL WHERE chosen_clan IS NOT NULL AND NOT (chosen_clan = ANY($1))`, [CLANS_IN_GAME]);
        await client.query('COMMIT');
        console.log('\nDone. Decks that lost cards need topping back up to 40 in the Deck Editor.');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        console.error('Failed, nothing changed:', err.message);
        process.exitCode = 1;
    } finally {
        client.release();
        await pool.end();
    }
})();
