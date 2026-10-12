'use strict';
// Gives every player a clan's starter deck (shared/clans.js starterRecipe) as their active deck:
// the cards it needs are topped up in their collection (nobody loses copies they already have),
// a "<Clan> Starter" deck is made (replacing an older one of that name), their other decks stay
// but are no longer active (empty ones, e.g. after retire_cards.js, are deleted), and their
// starting clan is set to it, so nobody is asked to pick one.
//
//   node backend/scripts/give_starter.js nebula            shows what would change
//   node backend/scripts/give_starter.js nebula --apply    does it (all or nothing)
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const apply = process.argv.includes('--apply');
const clan = process.argv.slice(2).find(a => !a.startsWith('--'));

(async () => {
    const { starterRecipe, pickableClans } = await import('../../shared/clans.js');
    const info = pickableClans().find(c => c.id === clan);
    if (!info) {
        console.error(`Name a clan with a starter deck: ${pickableClans().map(c => c.id).join(', ')}`);
        process.exitCode = 1;
        await pool.end();
        return;
    }
    const recipe = starterRecipe(clan);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const ids = [...new Set([recipe.leader, ...recipe.deck.map(([id]) => id), ...recipe.hideout.map(([id]) => id)].filter(Boolean))];
        const { rows } = await client.query('SELECT id, art_url FROM cards WHERE art_url = ANY($1::text[])', [ids]);
        const dbId = Object.fromEntries(rows.map(r => [r.art_url, r.id]));
        const missing = ids.filter(id => !dbId[id]);
        if (missing.length) throw new Error(`These cards aren't on the server yet (run backend/scripts/sync_cards.mjs): ${missing.join(', ')}`);

        const total = recipe.deck.reduce((s, [, q]) => s + q, 0);
        if (total !== 40) throw new Error(`The starter deck must have 40 cards (got ${total}).`);
        const { rows: players } = await client.query('SELECT id, username FROM players ORDER BY created_at');
        const name = `${info.name} Starter`;
        console.log(`${players.length} player(s) get the ${name} (${total} cards, leader ${recipe.leader}) as their active deck.`);
        if (!apply) {
            await client.query('ROLLBACK');
            console.log('\nNothing changed. Run again with --apply to do it.');
            return;
        }

        const owns = [...recipe.deck, ...recipe.hideout];
        if (recipe.leader) owns.push([recipe.leader, 1]);
        for (const p of players) {
            for (const [id, qty] of owns) {
                await client.query(
                    `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, $3)
                     ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = GREATEST(player_inventory.quantity, EXCLUDED.quantity)`,
                    [p.id, dbId[id], qty]);
            }
            await client.query('DELETE FROM decks WHERE player_id = $1 AND name = $2', [p.id, name]);
            const { rows: [deck] } = await client.query(
                'INSERT INTO decks (player_id, name, is_active, leader_card_id) VALUES ($1, $2, TRUE, $3) RETURNING id',
                [p.id, name, recipe.leader ? dbId[recipe.leader] : null]);
            await client.query('UPDATE decks SET is_active = FALSE WHERE player_id = $1 AND id <> $2', [p.id, deck.id]);
            // Decks left with no cards (all retired) go
            await client.query(
                `DELETE FROM decks d WHERE d.player_id = $1 AND d.id <> $2
                 AND NOT EXISTS (SELECT 1 FROM deck_cards dc WHERE dc.deck_id = d.id)`, [p.id, deck.id]);
            for (const [id, copies] of recipe.deck) {
                await client.query('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deck.id, dbId[id], copies]);
            }
            await client.query('UPDATE players SET chosen_clan = $1 WHERE id = $2', [clan, p.id]);
        }
        await client.query('COMMIT');
        console.log('\nDone.');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        console.error('Failed, nothing changed:', err.message);
        process.exitCode = 1;
    } finally {
        client.release();
        await pool.end();
    }
})();
