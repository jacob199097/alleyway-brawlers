/**
 * DECK LOADER
 * Turns the player's saved active deck into the card objects DuelScene plays with.
 *
 *  - Stats come from the server's card rows; rules data (promotesTo, abilities, …) from
 *    CARD_CATALOG, matched by the card's art key.
 *  - The hideout holds the deck's leader plus the promoted forms (Lv.2 / Lv.3) the player
 *    owns for the Strivers in the deck.
 */

import { apiFetch } from './Platform.js';
import { CARD_CATALOG } from '../../shared/cards.js';

/** One server card row → the card shape DuelScene uses. */
export function toDuelCard(row) {
    const base = CARD_CATALOG[row.art_url] || {};
    return {
        ...base,
        id:          base.id || row.art_url || row.id,
        dbId:        row.id,
        name:        row.name,
        clan:        row.clan,
        cardType:    row.card_type,
        authority:   row.authority ?? base.authority,
        attack:      row.attack  ?? base.attack,
        defense:     row.defense ?? base.defense,
        rarity:      row.rarity  ?? base.rarity,
        art_url:     row.art_url || base.art_url,
        clanTag:     row.clan_tag || base.clanTag,
        subtype:     row.subtype  || base.subtype,
        level:       row.level    ?? base.level,
        effectText:  row.effect_text  || base.effectText,
        flavourText: row.flavour_text || base.flavourText,
    };
}

async function getJson(path) {
    const r = await apiFetch(path);
    if (!r.ok) throw new Error(`${path} → ${r.status}`);
    return r.json();
}

/** The card this one promotes into: its promotesTo, or the next `_lvN` form (Viper, Hunter). */
function nextForm(id) {
    const card = CARD_CATALOG[id];
    if (!card) return null;
    if (card.promotesTo) return card.promotesTo;
    const m = /^(.*_lv)(\d)$/.exec(id);
    const guess = m && `${m[1]}${Number(m[2]) + 1}`;
    return guess && CARD_CATALOG[guess] ? guess : null;
}

function shuffle(list) {
    for (let i = list.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [list[i], list[j]] = [list[j], list[i]];
    }
    return list;
}

/**
 * Loads the active deck. Resolves `{ playerDeck, playerHideout, deckName }`, or `null`
 * when the player has no complete 40-card deck.
 */
export async function loadDuelDeck() {
    const decks  = await getJson('/api/deck');
    const active = decks.find(d => d.is_active) || decks[0];
    if (!active || active.card_count < 40) return null;

    const [deck, inventory] = await Promise.all([
        getJson(`/api/deck/${active.id}`),
        getJson('/api/profile/inventory').catch(() => []),
    ]);

    const playerDeck = shuffle(deck.cards.flatMap(row => Array.from({ length: row.copies }, () => toDuelCard(row))));

    // Promoted forms for every Striver chain in the deck, as many as the player owns (max 3)
    const owned = new Map(inventory.map(row => [row.art_url, row]));
    const hideout = [];
    const seen = new Set();
    for (const row of deck.cards) {
        let next = nextForm(row.art_url);
        while (next && !seen.has(next)) {
            seen.add(next);
            const inv = owned.get(next);
            if (inv) for (let i = 0; i < Math.min(3, inv.quantity); i++) hideout.push(toDuelCard(inv));
            next = nextForm(next);
        }
    }
    if (deck.leader) hideout.push(toDuelCard(deck.leader));

    return { playerDeck, playerHideout: hideout, deckName: active.name };
}
