'use strict';

/**
 * ONBOARDING — first-time clan selection.
 *   GET  /api/onboarding/clans        the clans a new player can pick (shared/clans.js): any clan
 *                                     with enough cards for a starter deck, Card Forge clans included
 *   POST /api/onboarding/start-clan   { clan } — seeds that clan's starter inventory (deck cards,
 *                                     the promoted forms for the Hideout, the leader) and makes the
 *                                     40-card starter deck the active deck.
 * Until the launch wipe (GIVE_ALL_STARTERS) every player also gets every other clan's starter: new
 * players when they pick a clan, everyone else when the server starts (a new clan reaches them too).
 */

const router         = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }       = require('../db/pool');
const { sendMail }   = require('./mail');

const clans = import('../../shared/clans.js');

// Pre-launch: everyone gets every clan's starter deck (and its cards). Set to false for the wipe.
const GIVE_ALL_STARTERS = true;

router.get('/clans', requireAuth, async (_req, res) => {
    try {
        const { pickableClans, starterRecipe, clanBlurb } = await clans;
        res.json(pickableClans().map(c => ({ ...c, leader: starterRecipe(c.id).leader, blurb: clanBlurb(c.id) })));
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
        await client.query('INSERT INTO player_starter_grants (player_id, clan) VALUES ($1, $2) ON CONFLICT DO NOTHING', [req.playerId, clan]);

        await client.query(
            'UPDATE players SET chosen_clan = $1 WHERE id = $2',
            [clan, req.playerId]
        );

        await client.query('COMMIT');
        if (GIVE_ALL_STARTERS) {
            await grantStarters(req.playerId, false).catch(err => console.error('[Onboarding] other starters:', err.message));
        }

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

/** Every clan's starter a player who has picked a clan hasn't been given yet: its cards and its deck
 *  (not made active). Returns the clans' names; with mail, tells the player in their mailbox. */
async function grantStarters(playerId, mail = true) {
    const { pickableClans, starterRecipe } = await clans;
    const given = [];
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows } = await client.query('SELECT chosen_clan FROM players WHERE id = $1 FOR UPDATE', [playerId]);
        if (!rows.length || !rows[0].chosen_clan) { await client.query('ROLLBACK'); return given; }
        const { rows: had } = await client.query('SELECT clan FROM player_starter_grants WHERE player_id = $1', [playerId]);
        const have = new Set(had.map(r => r.clan));
        // (a "<Clan> Starter" deck already there, given before this was recorded: that counts, and stays as it is)
        const { rows: decks } = await client.query("SELECT name FROM decks WHERE player_id = $1 AND name LIKE '% Starter'", [playerId]);
        const named = new Set(decks.map(r => r.name));
        for (const c of pickableClans()) {
            if (have.has(c.id)) continue;
            if (named.has(`${c.name} Starter`)) {
                await client.query('INSERT INTO player_starter_grants (player_id, clan) VALUES ($1, $2) ON CONFLICT DO NOTHING', [playerId, c.id]);
                continue;
            }
            await seedStarter(client, playerId, starterRecipe(c.id), c.name, false);
            await client.query('INSERT INTO player_starter_grants (player_id, clan) VALUES ($1, $2) ON CONFLICT DO NOTHING', [playerId, c.id]);
            given.push(c.name);
        }
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
    if (mail && given.length) {
        sendMail(playerId, {
            subject: 'Every starter deck, on the house',
            body: `Until the game launches, you get every clan's starter deck to try them all.\n\n` +
                  `Added to your account: the ${given.join(', ')} starter deck${given.length === 1 ? '' : 's'} and their cards. ` +
                  `Find them in the Deck Builder.`,
        });
    }
    return given;
}

/** At start-up (GIVE_ALL_STARTERS): every player who has picked a clan gets the starters they're missing. */
async function grantStartersToEveryone() {
    if (!GIVE_ALL_STARTERS) return;
    const { rows } = await pool.query('SELECT id FROM players WHERE chosen_clan IS NOT NULL');
    let players = 0, decks = 0;
    for (const { id } of rows) {
        try {
            const given = await grantStarters(id);
            if (given.length) { players += 1; decks += given.length; }
        } catch (err) {
            console.error(`[Onboarding] starters for ${id}:`, err.message);
        }
    }
    if (players) console.log(`[Onboarding] Gave ${decks} starter deck(s) to ${players} player(s)`);
}

/** Inventory and a starter deck from a recipe (card game IDs = cards.art_url); active: it becomes the
 *  player's active deck. name: the deck's name (a deck already called that is replaced). */
async function seedStarter(client, playerId, recipe, clanName, active = true, name = `${clanName} Starter`) {
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
    await client.query('DELETE FROM decks WHERE player_id = $1 AND name = $2', [playerId, name]);
    const { rows: deckRows } = await client.query(
        `INSERT INTO decks (player_id, name, is_active, leader_card_id, hideout_set)
         VALUES ($1, $2, $3, $4, TRUE)
         RETURNING id`,
        [playerId, name, active, recipe.leader ? dbId[recipe.leader] : null]
    );
    const deckId = deckRows[0].id;
    if (active) await client.query('UPDATE decks SET is_active = FALSE WHERE player_id = $1 AND id <> $2', [playerId, deckId]);
    for (const [id, copies] of recipe.deck) {
        await client.query('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deckId, dbId[id], copies]);
    }
    for (const [id, copies] of recipe.hideout) {
        await client.query('INSERT INTO deck_hideout (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deckId, dbId[id], Math.min(3, copies)]);
    }
}

module.exports = router;
module.exports.grantStartersToEveryone = grantStartersToEveryone;
module.exports.seedStarter = seedStarter;
