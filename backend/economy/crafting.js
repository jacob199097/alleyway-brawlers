'use strict';

/**
 * CRAFTING
 * Scrap cards into Dust, spend Dust crafting the cards you're missing. Cards are named by game
 * ID (cards.art_url). Only cards that are in the game (shared/cards.js) can be crafted.
 *
 *   Rarity       Scrap gives   Craft costs
 *   Common            5             40
 *   Uncommon         15            100
 *   Rare             40            250
 *   Epic            120            750
 *   Legendary       400           2000
 *
 * A deck holds up to 3 copies of a card (leaders: 1), so copies beyond that are "extras":
 * scrapExtras turns them all into Dust at once. Scrapping never takes a card below the copies
 * a saved deck uses, and crafting stops at 3 copies (leaders: 1).
 */

const { pool } = require('../db/pool');
const { gameCardIds } = require('./packOpener');
const { bump } = require('./counters');

const VALUES = {
    1: { scrap: 5,   craft: 40 },
    2: { scrap: 15,  craft: 100 },
    3: { scrap: 40,  craft: 250 },
    4: { scrap: 120, craft: 750 },
    5: { scrap: 400, craft: 2000 },
};
const MAX_COPIES = 3;

const keepOf = (cardType) => (cardType === 'leader' ? 1 : MAX_COPIES);
const valueOf = (rarity) => VALUES[rarity] || VALUES[1];

class CraftError extends Error {}

/** Copies of each card the player's saved decks need: card uuid → copies (the most any one deck uses). */
async function copiesInDecks(client, playerId) {
    const { rows } = await client.query(
        `SELECT card_id, MAX(copies)::int AS copies FROM (
             SELECT dc.card_id, dc.copies FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id WHERE d.player_id = $1
             UNION ALL
             SELECT leader_card_id, 1 FROM decks WHERE player_id = $1 AND leader_card_id IS NOT NULL
         ) used GROUP BY card_id`, [playerId]);
    return new Map(rows.map(r => [r.card_id, r.copies]));
}

/** The player's Dust and what scrapping their extras would give. */
async function summary(playerId) {
    const { rows: [p] } = await pool.query('SELECT dust FROM players WHERE id = $1', [playerId]);
    const { rows } = await pool.query(
        `SELECT c.card_type, c.rarity, pi.quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
         WHERE pi.player_id = $1`, [playerId]);
    let extras = 0, extrasDust = 0;
    for (const r of rows) {
        const n = Math.max(0, r.quantity - keepOf(r.card_type));
        extras += n;
        extrasDust += n * valueOf(r.rarity).scrap;
    }
    return { dust: p?.dust ?? 0, values: VALUES, maxCopies: MAX_COPIES, extras, extrasDust };
}

/** Scrap `copies` of one card. → { dust, quantity, gained } */
async function scrap(playerId, gameId, copies = 1) {
    if (!Number.isInteger(copies) || copies < 1 || copies > 99) throw new CraftError('Choose how many copies to scrap.');
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [row] } = await client.query(
            `SELECT c.id, c.name, c.rarity, pi.quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
             WHERE pi.player_id = $1 AND c.art_url = $2 FOR UPDATE OF pi`, [playerId, gameId]);
        if (!row) throw new CraftError("You don't own that card.");
        const needed = (await copiesInDecks(client, playerId)).get(row.id) || 0;
        if (row.quantity - copies < needed) {
            throw new CraftError(needed >= row.quantity
                ? `Your decks use every copy of ${row.name}. Take it out of a deck to scrap it.`
                : `Your decks use ${needed} of ${row.name}, so you can scrap ${row.quantity - needed}.`);
        }
        const gained = copies * valueOf(row.rarity).scrap;
        const left = row.quantity - copies;
        if (left > 0) {
            await client.query('UPDATE player_inventory SET quantity = $1 WHERE player_id = $2 AND card_id = $3', [left, playerId, row.id]);
        } else {
            await client.query('DELETE FROM player_inventory WHERE player_id = $1 AND card_id = $2', [playerId, row.id]);
        }
        const { rows: [p] } = await client.query('UPDATE players SET dust = dust + $1 WHERE id = $2 RETURNING dust', [gained, playerId]);
        await bump(client, playerId, 'scrapped', copies);
        await client.query('COMMIT');
        return { dust: p.dust, quantity: left, gained };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/** Scrap every copy beyond what a deck can hold. → { dust, gained, scrapped } */
async function scrapExtras(playerId) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows } = await client.query(
            `SELECT c.id, c.card_type, c.rarity, pi.quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
             WHERE pi.player_id = $1 FOR UPDATE OF pi`, [playerId]);
        let gained = 0, scrapped = 0;
        for (const r of rows) {
            const n = Math.max(0, r.quantity - keepOf(r.card_type));
            if (!n) continue;
            await client.query('UPDATE player_inventory SET quantity = $1 WHERE player_id = $2 AND card_id = $3', [r.quantity - n, playerId, r.id]);
            gained += n * valueOf(r.rarity).scrap;
            scrapped += n;
        }
        const { rows: [p] } = await client.query('UPDATE players SET dust = dust + $1 WHERE id = $2 RETURNING dust', [gained, playerId]);
        if (scrapped) await bump(client, playerId, 'scrapped', scrapped);
        await client.query('COMMIT');
        return { dust: p.dust, gained, scrapped };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/** Craft one copy of a card. → { dust, quantity, spent } */
async function craft(playerId, gameId) {
    if (!(await gameCardIds()).includes(gameId)) throw new CraftError("That card can't be crafted.");
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [card] } = await client.query('SELECT id, name, card_type, rarity FROM cards WHERE art_url = $1', [gameId]);
        if (!card) throw new CraftError("That card can't be crafted yet.");
        const { rows: [own] } = await client.query(
            'SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2 FOR UPDATE', [playerId, card.id]);
        const have = own?.quantity ?? 0;
        if (have >= keepOf(card.card_type)) {
            throw new CraftError(`You already have ${have === 1 ? 'a copy' : `${have} copies`} of ${card.name}, all a deck can use.`);
        }
        const cost = valueOf(card.rarity).craft;
        const { rows: [p] } = await client.query(
            'UPDATE players SET dust = dust - $1 WHERE id = $2 AND dust >= $1 RETURNING dust', [cost, playerId]);
        if (!p) throw new CraftError(`You need ${cost} Dust to craft ${card.name}.`);
        await client.query(
            `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)
             ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = player_inventory.quantity + 1`, [playerId, card.id]);
        await bump(client, playerId, 'crafted', 1);
        await client.query('COMMIT');
        return { dust: p.dust, quantity: have + 1, spent: cost };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { summary, scrap, scrapExtras, craft, CraftError, VALUES, MAX_COPIES };
