'use strict';

/**
 * ONBOARDING — first-time clan selection.
 *   GET  /api/onboarding/clans        the clans a new player can pick (shared/clans.js): any clan
 *                                     with enough cards for a starter deck, Card Forge clans included
 *   POST /api/onboarding/start-clan   { clan } — seeds that clan's starter inventory (deck cards,
 *                                     the promoted forms for the Hideout, the leader) and makes the
 *                                     40-card starter deck the active deck.
 */

const router         = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }       = require('../db/pool');
const { sendMail }   = require('./mail');

const clans = import('../../shared/clans.js');

router.get('/clans', requireAuth, async (_req, res) => {
    try {
        const { pickableClans, starterRecipe } = await clans;
        res.json(pickableClans().map(c => ({ ...c, leader: starterRecipe(c.id).leader })));
    } catch (err) {
        console.error('[Onboarding] clans:', err.message);
        res.status(500).json({ error: 'Could not list the clans.' });
    }
});

router.post('/start-clan', requireAuth, async (req, res) => {
    const { clan } = req.body || {};
    const { pickableClans, starterRecipe } = await clans;
    const info = pickableClans().find(c => c.id === clan);
    if (!info) return res.status(400).json({ error: 'Invalid clan.' });

    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        // Don't let a player re-pick — chosen_clan is one-shot.
        const { rows: pRows } = await client.query(
            'SELECT chosen_clan FROM players WHERE id = $1 FOR UPDATE',
            [req.playerId]
        );
        if (!pRows.length) throw new Error('Player not found.');
        if (pRows[0].chosen_clan) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'Clan already selected.' });
        }

        await seedStarter(client, req.playerId, starterRecipe(clan), info.name);

        await client.query(
            'UPDATE players SET chosen_clan = $1 WHERE id = $2',
            [clan, req.playerId]
        );

        await client.query('COMMIT');

        // Drop a welcome message into the player's mailbox.
        sendMail(req.playerId, {
            subject: `Welcome to the ${info.name}`,
            body: `Welcome to AlleyWay Brawlers!\n\n` +
                  `Your starter inventory and a 40-card ${info.name} deck have been added to your account. ` +
                  `Open the Deck Editor to customise it, then head to Fight Mode to take it for a spin.\n\n` +
                  `— Find new packs and Contraband bundles in the Shop. The mailbox here will deliver any system messages, daily-quest rewards or future news.`,
        });

        res.json({ success: true, clan });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('[Onboarding] start-clan failed:', err.message);
        res.status(500).json({ error: err.message });
    } finally {
        client.release();
    }
});

/** Inventory and the active starter deck from a recipe (card game IDs = cards.art_url). */
async function seedStarter(client, playerId, recipe, clanName) {
    const ids = [...new Set([recipe.leader, ...recipe.deck.map(([id]) => id), ...recipe.hideout.map(([id]) => id)].filter(Boolean))];
    const { rows } = await client.query('SELECT id, art_url FROM cards WHERE art_url = ANY($1::text[])', [ids]);
    const dbId = Object.fromEntries(rows.map(r => [r.art_url, r.id]));
    const missing = ids.filter(id => !dbId[id]);
    if (missing.length) {
        throw new Error(`These cards aren't on the server yet (run backend/scripts/sync_cards.mjs): ${missing.join(', ')}`);
    }

    const adds = [...recipe.deck, ...recipe.hideout];
    if (recipe.leader) adds.push([recipe.leader, 1]);
    for (const [id, qty] of adds) {
        await client.query(
            `INSERT INTO player_inventory (player_id, card_id, quantity)
             VALUES ($1, $2, $3)
             ON CONFLICT (player_id, card_id)
             DO UPDATE SET quantity = player_inventory.quantity + EXCLUDED.quantity`,
            [playerId, dbId[id], qty]
        );
    }

    const total = recipe.deck.reduce((s, [, q]) => s + q, 0);
    if (total !== 40) throw new Error(`The starter deck must have 40 cards (got ${total}).`);
    const name = `${clanName} Starter`;
    await client.query('DELETE FROM decks WHERE player_id = $1 AND name = $2', [playerId, name]);
    const { rows: deckRows } = await client.query(
        `INSERT INTO decks (player_id, name, is_active, leader_card_id)
         VALUES ($1, $2, TRUE, $3)
         RETURNING id`,
        [playerId, name, recipe.leader ? dbId[recipe.leader] : null]
    );
    const deckId = deckRows[0].id;
    await client.query('UPDATE decks SET is_active = FALSE WHERE player_id = $1 AND id <> $2', [playerId, deckId]);
    for (const [id, copies] of recipe.deck) {
        await client.query('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deckId, dbId[id], copies]);
    }
}

module.exports = router;
