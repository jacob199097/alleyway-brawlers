'use strict';

/**
 * ONBOARDING — first-time clan selection.
 * After signup the player calls POST /api/onboarding/start-clan with
 * { clan: 'lion_pride' }. The server seeds a starter inventory
 * matching the chosen faction and creates a default 40-card deck for the
 * player so they can immediately enter a duel.
 */

const router         = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }       = require('../db/pool');
const { sendMail }   = require('./mail');

const VALID_CLANS = ['lion_pride'];

/**
 * Lions starter recipe.
 *   • King Roan x1   — leader (kept in inventory; not part of the 40-card main deck)
 *   • Main deck (40 cards):
 *      Maya x3, Hunter x3, Pride Runner x3, Eric x3,
 *      Pride Mentor x2, King's Test x2, Blood Scent x2, Lion Rescue x3,
 *      Corner Deal x2, No Witnesses x3, Goldfang x2, Block Enforcer x3,
 *      Lion Grunt x3, Brutus x2, Pride Lieutenant x2, Debt Collector x2
 *   • Hideout copies (in inventory only, used for promotions in-duel):
 *      Maya Lv.2 x3, Maya Lv.3 x3, Hunter Lv.2 x3, Hunter Lv.3 x3,
 *      Eric Lv.2 x3, Eric Lv.3 x3
 */
const LION_STARTER = {
    leader: { name: 'King Roan', copies: 1 },
    deck: [
        ['Maya',             3],
        ['Hunter',           3],
        ['Pride Runner',     3],
        ['Eric',             3],
        ['Pride Mentor',     2],
        ["King's Test",      2],
        ['Blood Scent',      2],
        ['Lion Rescue',      3],
        ['Corner Deal',      2],
        ['No Witnesses',     3],
        ['Goldfang',         2],
        ['Block Enforcer',   3],
        ['Lion Grunt',       3],
        ['Brutus',           2],
        ['Pride Lieutenant', 2],
        ['Debt Collector',   2],
    ],
    hideout: [
        ['Maya Lv.2',  3], ['Maya Lv.3',  3],
        ['Hunter Lv.2', 3], ['Hunter Lv.3', 3],
        ['Eric Lv.2',  3], ['Eric Lv.3',  3],
    ],
};

router.post('/start-clan', requireAuth, async (req, res) => {
    const { clan } = req.body;
    if (!VALID_CLANS.includes(clan)) {
        return res.status(400).json({ error: 'Invalid clan.' });
    }

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

        await _seedLionsStarter(client, req.playerId);

        await client.query(
            'UPDATE players SET chosen_clan = $1 WHERE id = $2',
            [clan, req.playerId]
        );

        await client.query('COMMIT');

        // Drop a welcome message into the player's mailbox.
        const clanName = 'Lions';
        sendMail(req.playerId, {
            subject: `Welcome to the ${clanName}`,
            body: `Welcome to AlleyWay Brawlers!\n\n` +
                  `Your starter inventory and a 40-card ${clanName} deck have been added to your account. ` +
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

async function _seedLionsStarter(client, playerId) {
    // Lookup all card ids by name in a single query
    const allNames = [LION_STARTER.leader.name,
        ...LION_STARTER.deck.map(([n]) => n),
        ...LION_STARTER.hideout.map(([n]) => n)];
    const { rows } = await client.query(
        `SELECT id, name FROM cards WHERE name = ANY($1::text[]) AND clan='lion_pride'`,
        [allNames]
    );
    const idByName = {};
    for (const r of rows) idByName[r.name] = r.id;

    // Sanity-check that everything we need exists
    const missing = allNames.filter(n => !idByName[n]);
    if (missing.length) {
        throw new Error('Missing Lion cards in DB: ' + missing.join(', '));
    }

    // Inventory: leader + every deck/hideout copy
    const inventoryAdds = [
        [idByName[LION_STARTER.leader.name], LION_STARTER.leader.copies],
        ...LION_STARTER.deck.map(([n, q]) => [idByName[n], q]),
        ...LION_STARTER.hideout.map(([n, q]) => [idByName[n], q]),
    ];
    for (const [cardId, qty] of inventoryAdds) {
        await client.query(
            `INSERT INTO player_inventory (player_id, card_id, quantity)
             VALUES ($1, $2, $3)
             ON CONFLICT (player_id, card_id)
             DO UPDATE SET quantity = player_inventory.quantity + EXCLUDED.quantity`,
            [playerId, cardId, qty]
        );
    }

    // Build the starter deck (always 40 main-deck cards)
    const total = LION_STARTER.deck.reduce((s, [, q]) => s + q, 0);
    if (total !== 40) throw new Error('Lions starter deck must total 40 (got ' + total + ')');

    // Reset any existing default deck so re-running doesn't double up
    await client.query(
        `DELETE FROM decks WHERE player_id = $1 AND name = 'Lions Starter'`,
        [playerId]
    );
    const leaderId = idByName[LION_STARTER.leader.name];
    const { rows: deckRows } = await client.query(
        `INSERT INTO decks (player_id, name, is_active, leader_card_id)
         VALUES ($1, 'Lions Starter', TRUE, $2)
         RETURNING id`,
        [playerId, leaderId]
    );
    const deckId = deckRows[0].id;

    // Make sure no other deck is active
    await client.query(
        `UPDATE decks SET is_active = FALSE WHERE player_id = $1 AND id <> $2`,
        [playerId, deckId]
    );

    for (const [name, copies] of LION_STARTER.deck) {
        await client.query(
            `INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, $3)`,
            [deckId, idByName[name], copies]
        );
    }
}

module.exports = router;
