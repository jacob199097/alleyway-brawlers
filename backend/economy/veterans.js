'use strict';

/**
 * VETERAN CARDS: a card a player keeps fighting with earns card XP. Each finished match counts a play
 * for every card that player played in it (summoned, set, used: socket/onlineMatch.js `played`), and a
 * win if they won: XP = 1 a match + 2 more for a win (xpOf). XP earns the card tiers (TIERS), shown
 * as its frame: bronze, chrome, gold. Purely cosmetic: both players see them in a duel (the match
 * profiles' `vets`), and each other's card XP in the card zoom (`vet_xp`, xpByCard).
 */

const { pool } = require('../db/pool');

const TIERS = [
    { tier: 1, xp: 15, name: 'Seasoned' },
    { tier: 2, xp: 45, name: 'Battle-Scarred' },
    { tier: 3, xp: 120, name: 'Street Legend' },
];
const XP_PLAY = 1, XP_WIN = 2;   // (a win: 3 in all)

const xpOf = (wins, plays) => plays * XP_PLAY + wins * XP_WIN;
const tierOf = (xp) => TIERS.filter(t => xp >= t.xp).length;
const XP_SQL = `(plays * ${XP_PLAY} + wins * ${XP_WIN})`;
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
         RETURNING card_id, wins, plays`, [playerId, ids, won ? 1 : 0]);
    const gained = XP_PLAY + (won ? XP_WIN : 0);
    return rows.map(r => ({ id: r.card_id, xp: xpOf(r.wins, r.plays) }))
        .filter(r => tierOf(r.xp) > tierOf(r.xp - gained))
        .map(r => ({ id: r.id, tier: tierOf(r.xp), name: TIERS[tierOf(r.xp) - 1].name }));
}

/** The tiers of a player's veteran cards, only those with one: {cardId: tier}. `cardIds` limits it (a deck). */
async function tiers(playerId, cardIds = null) {
    if (!playerId) return {};
    const { rows } = cardIds
        ? await pool.query(`SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1 AND ${XP_SQL} >= $2 AND card_id = ANY($3::text[])`,
            [playerId, TIERS[0].xp, [...new Set(cardIds)].filter(validId)])
        : await pool.query(`SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1 AND ${XP_SQL} >= $2`, [playerId, TIERS[0].xp]);
    return Object.fromEntries(rows.map(r => [r.card_id, tierOf(xpOf(r.wins, r.plays))]));
}

/** The card XP of each of these cards the player has played: {cardId: xp} (a duel's profiles, `vet_xp`). */
async function xpByCard(playerId, cardIds) {
    const ids = [...new Set(cardIds || [])].filter(validId);
    if (!playerId || !ids.length) return {};
    const { rows } = await pool.query(`SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1 AND card_id = ANY($2::text[])`, [playerId, ids]);
    return Object.fromEntries(rows.map(r => [r.card_id, xpOf(r.wins, r.plays)]));
}

/** Every card a player has played: {tiers: TIERS, cards: {cardId: {wins, plays, xp, tier}}} (GET /api/veterans). */
async function overview(playerId) {
    const { rows } = await pool.query('SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1', [playerId]);
    return { tiers: TIERS, cards: Object.fromEntries(rows.map(r => [r.card_id, { wins: r.wins, plays: r.plays, xp: xpOf(r.wins, r.plays), tier: tierOf(xpOf(r.wins, r.plays)) }])) };
}

module.exports = { record, tiers, xpByCard, overview, tierOf, xpOf, TIERS };
