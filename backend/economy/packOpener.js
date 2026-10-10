'use strict';

/**
 * BOOSTER PACK GACHA SYSTEM
 * Handles purchasing and opening clan-specific booster packs.
 *
 * Pack contents: 3 cards per pack
 *   - Slot 1: guaranteed Rare+ (rarity >= 3)
 *   - Slot 2: Uncommon+ (rarity >= 2)  — weighted
 *   - Slot 3: Any rarity               — weighted
 *
 * Rarity drop weights (out of 100):
 *   Common(1): 50 | Uncommon(2): 28 | Rare(3): 14 | Epic(4): 6 | Legendary(5): 2
 */

const { pool } = require('../db/pool');
const { incrementDailyQuest } = require('../routes/quests');
const { bump } = require('./counters');

// The cards in the game (shared/cards.js, which includes the Card Forge cards), by art_url.
// Retired cards can stay in the database for old records, but never drop from packs.
let _gameIds = null;
async function gameCardIds() {
    if (!_gameIds) {
        const { CARD_CATALOG } = await import('../../shared/cards.js');
        _gameIds = Object.keys(CARD_CATALOG);
    }
    return _gameIds;
}

const PACK_COST = 200;            // karat per pack
const PACK_COST_CONTRABAND = 100; // contraband per pack
const CARDS_PER_PACK = 3;

// Weight tables indexed by minimum rarity slot
const WEIGHT_TABLES = {
    any:       [{ rarity: 1, weight: 50 }, { rarity: 2, weight: 28 }, { rarity: 3, weight: 14 }, { rarity: 4, weight: 6 }, { rarity: 5, weight: 2 }],
    uncommon:  [{ rarity: 2, weight: 55 }, { rarity: 3, weight: 28 }, { rarity: 4, weight: 13 }, { rarity: 5, weight: 4 }],
    rare:      [{ rarity: 3, weight: 65 }, { rarity: 4, weight: 27 }, { rarity: 5, weight: 8 }],
};

// Which weight table each of the 3 slots uses
const SLOT_TABLES = ['rare', 'uncommon', 'any'];

// ── Weighted Random ───────────────────────────────────────────────────────────
function weightedPick(table) {
    const total = table.reduce((s, e) => s + e.weight, 0);
    let roll = Math.random() * total;
    for (const entry of table) {
        roll -= entry.weight;
        if (roll <= 0) return entry.rarity;
    }
    return table[table.length - 1].rarity;
}

/**
 * Pulls CARDS_PER_PACK card IDs from a clan pool, respecting per-slot rarity.
 * Uses weighted random without repeating the same card twice per pack.
 */
async function drawPack(clan, client) {
    const selected = [];
    const usedIds  = new Set();
    const inGame   = await gameCardIds();

    for (let slot = 0; slot < CARDS_PER_PACK; slot++) {
        const table    = WEIGHT_TABLES[SLOT_TABLES[slot]];
        let   card     = null;
        let   attempts = 0;

        // Retry up to 5 times to avoid duplicates within the pack
        while (!card && attempts < 5) {
            attempts++;
            const rarity = weightedPick(table);

            const { rows } = await client.query(
                `SELECT id, name, clan, clan_tag, card_type, subtype, level, authority,
                        attack, defense, rarity, art_url, effect_key, effect_text, flavour_text
                 FROM cards
                 WHERE  clan = $1 AND rarity = $2
                 AND    id   <> ALL($3::uuid[]) AND art_url = ANY($4)
                 ORDER BY RANDOM()
                 LIMIT 1`,
                [clan, rarity, [...usedIds], inGame]
            );

            if (rows.length) {
                card = rows[0];
            } else {
                // Fallback: relax rarity constraint (take any available in clan)
                const fallback = await client.query(
                    `SELECT id, name, clan, clan_tag, card_type, subtype, level, authority,
                        attack, defense, rarity, art_url, effect_key, effect_text, flavour_text
                 FROM cards
                     WHERE  clan = $1 AND id <> ALL($2::uuid[]) AND art_url = ANY($3)
                     ORDER BY RANDOM()
                     LIMIT 1`,
                    [clan, [...usedIds], inGame]
                );
                if (fallback.rows.length) card = fallback.rows[0];
            }
        }

        if (!card) throw new Error(`Pack pool for clan '${clan}' is too small to fill slot ${slot}.`);

        selected.push(card);
        usedIds.add(card.id);
    }

    return selected;
}

// ── Core Export ───────────────────────────────────────────────────────────────

/**
 * Purchases and opens one booster pack for a player.
 *
 * @param {string} playerId  - UUID
 * @param {string} packType  - a clan with a pack (routes/shop.js validPacks), e.g. 'lion_pride'
 * @returns {Promise<{ cardsReceived: Array, newGold: number }>}
 */
async function openPack(playerId, packType, currency = 'karat') {
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // ── Use a pre-bought pack if the player has one, otherwise charge ────
        let newKarat = null;
        let newContraband = null;
        const { rowCount: usedOwnedPack } = await client.query(
            `UPDATE player_packs
             SET    quantity = quantity - 1
             WHERE  player_id = $1 AND pack_type = $2 AND quantity > 0`,
            [playerId, packType]
        );
        if (usedOwnedPack) {
            const { rows } = await client.query(
                'SELECT karat, contraband FROM players WHERE id = $1', [playerId]
            );
            newKarat      = rows[0].karat;
            newContraband = rows[0].contraband;
        } else if (currency === 'contraband') {
            const { rows } = await client.query(
                `UPDATE players
                 SET    contraband = contraband - $1
                 WHERE  id = $2 AND contraband >= $1
                 RETURNING karat, contraband`,
                [PACK_COST_CONTRABAND, playerId]
            );
            if (!rows.length) {
                throw new Error('Insufficient Contraband to purchase a booster pack.');
            }
            newKarat      = rows[0].karat;
            newContraband = rows[0].contraband;
        } else {
            const { rows } = await client.query(
                `UPDATE players
                 SET    karat = karat - $1
                 WHERE  id = $2 AND karat >= $1
                 RETURNING karat, contraband`,
                [PACK_COST, playerId]
            );
            if (!rows.length) {
                throw new Error('Insufficient Karat to purchase a booster pack.');
            }
            newKarat      = rows[0].karat;
            newContraband = rows[0].contraband;
        }

        // ── Draw cards ───────────────────────────────────────────────────────
        const cards = await drawPack(packType, client);

        // ── Add cards to player inventory ────────────────────────────────────
        for (const card of cards) {
            await client.query(
                `INSERT INTO player_inventory (player_id, card_id, quantity)
                 VALUES ($1, $2, 1)
                 ON CONFLICT (player_id, card_id)
                 DO UPDATE SET quantity = player_inventory.quantity + 1`,
                [playerId, card.id]
            );
        }

        await bump(client, playerId, 'packs', 1);
        await client.query('COMMIT');

        // Daily quest: opened a crew pack
        incrementDailyQuest(playerId, 'daily_pack', 1).catch(() => {});
        // Achievements: packs opened, cards collected (required here: achievements requires this file)
        require('./achievements').checkAndAnnounce(playerId);

        return {
            cardsReceived: cards.map(c => ({
                id:           c.id,
                cardId:       c.art_url || c.effect_key || c.id,
                name:         c.name,
                clan:         c.clan,
                clan_tag:     c.clan_tag,
                clanTag:      c.clan_tag,
                cardType:     c.card_type,
                subtype:      c.subtype,
                level:        c.level,
                authority:    c.authority,
                attack:       c.attack,
                defense:      c.defense,
                rarity:       c.rarity,
                art_url:      c.art_url,
                effectKey:    c.effect_key,
                effectText:   c.effect_text,
                flavourText:  c.flavour_text,
            })),
            newKarat,
            newContraband,
        };

    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Purchases a pack without opening it (adds to player_packs inventory).
 */
async function buyPack(playerId, packType) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        const { rows } = await client.query(
            `UPDATE players SET karat = karat - $1
             WHERE id = $2 AND karat >= $1
             RETURNING karat`,
            [PACK_COST, playerId]
        );
        if (!rows.length) throw new Error('Insufficient Karat.');

        await client.query(
            `INSERT INTO player_packs (player_id, pack_type, quantity)
             VALUES ($1, $2, 1)
             ON CONFLICT (player_id, pack_type)
             DO UPDATE SET quantity = player_packs.quantity + 1`,
            [playerId, packType]
        );

        await client.query('COMMIT');
        return { success: true, newGold: rows[0].karat };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { openPack, buyPack, gameCardIds };
