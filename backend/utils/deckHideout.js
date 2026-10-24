'use strict';

// A deck's Hideout: the higher levels of its Strivers that wait off the field during a match
// (a Striver can only promote to a level waiting there). The player puts them in with the Deck
// Editor (deck_hideout). A deck not saved since then (decks.hideout_set FALSE) keeps the old
// Hideout: every higher level of its Strivers the player owns, up to 3 of each.

const engine = import('../../shared/duel/DuelState.js');

const COLUMNS = `c.id, c.name, c.clan, c.card_type, c.subtype, c.level, c.authority,
                 c.attack, c.defense, c.rarity, c.art_url`;

/** The deck's Hideout as card rows with `copies` (never more than the player owns). */
async function deckHideout(db, deck, playerId) {
    if (deck.hideout_set) {
        const { rows } = await db.query(
            `SELECT ${COLUMNS}, LEAST(dh.copies, pi.quantity)::int AS copies
             FROM   deck_hideout dh
             JOIN   cards c             ON c.id = dh.card_id
             JOIN   player_inventory pi ON pi.card_id = c.id AND pi.player_id = $2
             WHERE  dh.deck_id = $1
             ORDER  BY c.name, c.level`, [deck.id, playerId]);
        return rows.filter(r => r.copies > 0);
    }
    const { nextForm } = await engine;
    const { rows: inDeck } = await db.query(
        `SELECT c.art_url FROM deck_cards dc JOIN cards c ON c.id = dc.card_id WHERE dc.deck_id = $1`, [deck.id]);
    const { rows: inv } = await db.query(
        `SELECT ${COLUMNS}, pi.quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
         WHERE pi.player_id = $1`, [playerId]);
    const owned = new Map(inv.map(r => [r.art_url, r]));
    const out = [];
    const seen = new Set();
    for (const r of inDeck) {
        let next = nextForm(r.art_url);
        while (next && !seen.has(next)) {
            seen.add(next);
            const o = owned.get(next);
            if (o) out.push({ ...o, quantity: undefined, copies: Math.min(3, o.quantity) });
            next = nextForm(next);
        }
    }
    return out;
}

module.exports = { deckHideout };
