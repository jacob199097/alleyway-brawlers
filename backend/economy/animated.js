'use strict';

/**
 * ANIMATED CARDS
 * A card whose art can move (its `artFx`, set in the Card Forge) has an animated version a player can own:
 * crafted in the Card Library for Dust (CRAFT_FACTOR times the card's own craft cost) or bought in the
 * shop for Contraband (CONTRABAND). Owning it makes every copy of that card play its animation, in the
 * player's collection and in their matches (both players see it: the match profiles' `anim`).
 *
 *   Rarity       Dust (4x craft)   Contraband
 *   Common            160              150
 *   Uncommon          400              250
 *   Rare             1000              400
 *   Epic             3000              700
 *   Legendary        8000             1200
 *
 * Crafting needs a copy of the card; buying gives one too if the player has none. An animated version
 * is never scrapped, traded or sold, and stays when copies of the card are scrapped.
 */

const { pool } = require('../db/pool');
const { VALUES } = require('./crafting');
const { bump } = require('./counters');

const CRAFT_FACTOR = 4;
const CONTRABAND = { 1: 150, 2: 250, 3: 400, 4: 700, 5: 1200 };

class AnimatedError extends Error {}

const validId = (id) => typeof id === 'string' && /^[a-z0-9_]{1,64}$/.test(id);

/** The cards with an animated version: {gameId: rarity} (shared/cards.js: those with artFx; tokens never). */
async function animatable() {
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const out = {};
    for (const [id, c] of Object.entries(CARD_CATALOG)) if (c.artFx && !c.token) out[id] = Number(c.rarity) || 1;
    return out;
}

const pricesOf = (rarity) => ({ dust: (VALUES[rarity] || VALUES[1]).craft * CRAFT_FACTOR, contraband: CONTRABAND[rarity] || CONTRABAND[1] });

/** The player's animated cards: [gameId] (all, or only these ids: a match's deck). */
async function owned(playerId, cardIds = null) {
    if (!playerId) return [];
    const { rows } = cardIds
        ? await pool.query('SELECT card_id FROM animated_cards WHERE player_id = $1 AND card_id = ANY($2::text[])',
            [playerId, [...new Set(cardIds)].filter(validId)])
        : await pool.query('SELECT card_id FROM animated_cards WHERE player_id = $1', [playerId]);
    return rows.map(r => r.card_id);
}

/** GET /api/animated: what can be animated, at what price, and which the player owns. */
async function overview(playerId) {
    const cards = await animatable();
    const mine = new Set(await owned(playerId));
    return {
        craftFactor: CRAFT_FACTOR,
        cards: Object.entries(cards).map(([id, rarity]) => ({ id, rarity, ...pricesOf(rarity), owned: mine.has(id) })),
    };
}

/** Take one: with Dust (craft: needs a copy of the card) or Contraband (buy: gives a copy if none). */
async function acquire(playerId, gameId, currency) {
    if (!['dust', 'contraband'].includes(currency)) throw new AnimatedError('Pay with Dust or Contraband.');
    const rarity = validId(gameId) ? (await animatable())[gameId] : null;
    if (!rarity) throw new AnimatedError('That card has no animated version.');
    const cost = pricesOf(rarity)[currency];
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [card] } = await client.query('SELECT id, name FROM cards WHERE art_url = $1', [gameId]);
        if (!card) throw new AnimatedError("That card isn't in the game yet.");
        const { rows: [has] } = await client.query('SELECT 1 FROM animated_cards WHERE player_id = $1 AND card_id = $2 FOR UPDATE', [playerId, gameId]);
        if (has) throw new AnimatedError(`You already have the animated ${card.name}.`);
        const { rows: [own] } = await client.query('SELECT quantity FROM player_inventory WHERE player_id = $1 AND card_id = $2', [playerId, card.id]);
        if (currency === 'dust' && !(own?.quantity > 0)) throw new AnimatedError(`Craft or find ${card.name} first: the animated version is for a card you have.`);
        const col = currency === 'dust' ? 'dust' : 'contraband';
        const { rows: [p] } = await client.query(
            `UPDATE players SET ${col} = ${col} - $1 WHERE id = $2 AND ${col} >= $1 RETURNING dust, contraband`, [cost, playerId]);
        if (!p) throw new AnimatedError(`You need ${cost} ${currency === 'dust' ? 'Dust' : 'Contraband'} for the animated ${card.name}.`);
        let gaveCard = false;
        if (!(own?.quantity > 0)) {   // (bought for Contraband: the card itself comes with it)
            await client.query(
                `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)
                 ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = player_inventory.quantity + 1`, [playerId, card.id]);
            gaveCard = true;
        }
        await client.query('INSERT INTO animated_cards (player_id, card_id, source) VALUES ($1, $2, $3)', [playerId, gameId, currency]);
        await bump(client, playerId, 'animated', 1);
        await client.query('COMMIT');
        return { id: gameId, dust: p.dust, contraband: p.contraband, spent: cost, currency, gaveCard };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { overview, owned, acquire, animatable, pricesOf, AnimatedError, CRAFT_FACTOR, CONTRABAND };
