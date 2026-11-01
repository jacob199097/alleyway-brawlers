'use strict';

/**
 * VETERAN CARDS: a card a player keeps winning with wears it. Each finished match counts a play for
 * every card that player played in it (summoned, set, used: socket/onlineMatch.js `played`), and a
 * win if they won. Wins with a card earn it tiers (TIERS): scuffs, then a foil edge, then a gold
 * signature. Purely cosmetic: both players see them in a duel (the match profiles' `vets`).
 */

const { pool } = require('../db/pool');

const TIERS = [
    { tier: 1, wins: 5, name: 'Seasoned' },
    { tier: 2, wins: 15, name: 'Battle-Scarred' },
    { tier: 3, wins: 40, name: 'Street Legend' },
];

const tierOf = (wins) => TIERS.filter(t => wins >= t.wins).length;
const validId = (id) => typeof id === 'string' && id.length > 0 && id.length <= 64;

/**
 * A finished match for one player: a play for each card they played, a win too if they won →
 * the cards that reached a new tier: [{id, tier, name}].
 */
async function record(playerId, cardIds, won) {
    const ids = [...new Set(cardIds || [])].filter(validId);
    if (!playerId || !ids.length) return [];
    const { rows } = await pool.query(
        `INSERT INTO card_veterans (player_id, card_id, wins, plays)
         SELECT $1, id, $3, 1 FROM UNNEST($2::text[]) AS id
         ON CONFLICT (player_id, card_id) DO UPDATE SET wins = card_veterans.wins + EXCLUDED.wins,
             plays = card_veterans.plays + 1
         RETURNING card_id, wins`, [playerId, ids, won ? 1 : 0]);
    if (!won) return [];
    return rows.filter(r => tierOf(r.wins) > tierOf(r.wins - 1))
        .map(r => ({ id: r.card_id, tier: tierOf(r.wins), name: TIERS[tierOf(r.wins) - 1].name }));
}

/** The tiers of a player's veteran cards, only those with one: {cardId: tier}. `cardIds` limits it (a deck). */
async function tiers(playerId, cardIds = null) {
    if (!playerId) return {};
    const { rows } = cardIds
        ? await pool.query('SELECT card_id, wins FROM card_veterans WHERE player_id = $1 AND wins >= $2 AND card_id = ANY($3::text[])',
            [playerId, TIERS[0].wins, [...new Set(cardIds)].filter(validId)])
        : await pool.query('SELECT card_id, wins FROM card_veterans WHERE player_id = $1 AND wins >= $2', [playerId, TIERS[0].wins]);
    return Object.fromEntries(rows.map(r => [r.card_id, tierOf(r.wins)]));
}

/** Every card a player has played: {tiers: TIERS, cards: {cardId: {wins, plays, tier}}} (GET /api/veterans). */
async function overview(playerId) {
    const { rows } = await pool.query('SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1', [playerId]);
    return { tiers: TIERS, cards: Object.fromEntries(rows.map(r => [r.card_id, { wins: r.wins, plays: r.plays, tier: tierOf(r.wins) }])) };
}

module.exports = { record, tiers, overview, tierOf, TIERS };
