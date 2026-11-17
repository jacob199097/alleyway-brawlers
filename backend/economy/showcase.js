'use strict';

/**
 * PROFILE SHOWCASE
 * Up to SIZE cards a player picks to show off (their "pride cards"): on their profile, to friends viewing it, and
 * under their leader in the match intro. Stored as game card ids in order (players.showcase). Only cards the
 * player owns: checked when it's saved, and again when it's read (a card sold or scrapped since drops out).
 */

const { pool } = require('../db/pool');

const SIZE = 3;

class ShowcaseError extends Error {}

const validId = (id) => typeof id === 'string' && /^[a-z0-9_]{1,64}$/.test(id);

/** Of these game card ids, the ones the player owns (at least one copy), in the order given. */
async function ownedOf(playerId, ids, db = pool) {
    if (!ids.length) return [];
    const { rows } = await db.query(
        `SELECT DISTINCT c.art_url FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
         WHERE pi.player_id = $1 AND pi.quantity > 0 AND c.art_url = ANY($2::text[])`, [playerId, ids]);
    const have = new Set(rows.map(r => r.art_url));
    return ids.filter(id => have.has(id));
}

/** The player's showcase: [gameId] (only what they still own). */
async function get(playerId) {
    if (!playerId) return [];
    const { rows } = await pool.query('SELECT showcase FROM players WHERE id = $1', [playerId]);
    const ids = (rows[0]?.showcase || []).filter(validId).slice(0, SIZE);
    return ownedOf(playerId, ids);
}

/** Save the showcase: up to SIZE different cards the player owns, in order. → [gameId] */
async function set(playerId, cards) {
    if (!Array.isArray(cards) || cards.length > SIZE) throw new ShowcaseError(`Pick up to ${SIZE} cards.`);
    if (!cards.every(validId)) throw new ShowcaseError('Unknown card.');
    if (new Set(cards).size !== cards.length) throw new ShowcaseError('Each card can be shown once.');
    const owned = await ownedOf(playerId, cards);
    if (owned.length !== cards.length) throw new ShowcaseError('You can only show cards you own.');
    await pool.query('UPDATE players SET showcase = $1 WHERE id = $2', [cards, playerId]);
    return cards;
}

module.exports = { get, set, ownedOf, SIZE, ShowcaseError };
