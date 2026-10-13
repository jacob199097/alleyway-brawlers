/**
 * Clans and starter decks, worked out from the card catalogue, so a clan added in the Card Forge
 * (or removed) needs no code changes: new players can pick it, the CPU can play it, and the shop
 * and Deck Builder list it.
 *
 *   clanList()            every clan with collectable cards: {id, name, color, tag, cards}
 *   starterRecipe(clan)   its starter: {clan, leader, deck: [[id, copies]], hideout: [[id, copies]]}
 *                         or null when the clan doesn't have enough cards for a 40-card deck yet
 *   pickableClans()       the clans new players can start with (they have a starter)
 *   expand(pairs)         [[id, 2]] → [id, id]
 *
 * Used by backend/routes/onboarding.js, backend/scripts/retire_cards.js and shared/duel/DuelAI.js.
 */
import { CARD_CATALOG } from './cards.js';

const DECK_SIZE = 40;
const MAX_COPIES = 3;
const CHARACTER_TARGET = 28;   // a built starter fills up to this many characters before effects

// Hand-picked starters. Used while every card in the recipe exists; otherwise the clan gets a
// starter built from its cards.
const CURATED = {
    // Every Nebula base card: 30 characters, 10 Hustles/Ambushes
    nebula: {
        leader: 'card_nebu_009',   // Archon of Nebula
        deck: [
            // Strivers: Kade, Lyra Quell, Marty, Skully
            ['card_nebu_001', 3], ['card_nebu_012', 3], ['card_nebu_030', 3], ['card_nebu_020', 2],
            // Characters
            ['card_nebu_011', 2], ['card_nebu_018', 2], ['card_nebu_019', 2], ['card_nebu_023', 2],
            ['card_nebu_028', 2], ['card_nebu_034', 2], ['card_nebu_036', 2], ['card_nebu_037', 1],
            ['card_nebu_033', 1], ['card_nebu_025', 1], ['card_nebu_035', 1], ['card_nebu_024', 1],
            // Hustles and Ambushes
            ['card_nebu_007', 3], ['card_nebu_010', 2], ['card_nebu_008', 1], ['card_nebu_026', 1],
            ['card_nebu_029', 1], ['card_nebu_038', 1], ['card_nebu_027', 1],
        ],
        hideout: [
            ['card_nebu_002', 3], ['card_nebu_003', 3], ['card_nebu_013', 3], ['card_nebu_014', 3],
            ['card_nebu_031', 3], ['card_nebu_032', 3], ['card_nebu_021', 3], ['card_nebu_022', 3],
        ],
    },
};

const level = (c) => Math.trunc(Number(c.level) || 1);
const isCollectable = (c) => c.cardType !== 'leader' && !c.token;   // (tokens are made only by effects)
const inDeck = (c) => isCollectable(c) && !(c.cardType === 'gang_member' && level(c) > 1);

export function clanList(catalog = CARD_CATALOG) {
    const out = new Map();
    for (const c of Object.values(catalog)) {
        if (!c.clan) continue;
        if (!out.has(c.clan)) {
            out.set(c.clan, { id: c.clan, name: c.clanName || prettify(c.clan), color: c.clanColor || '#b388ff', tag: c.clanTag || '', cards: 0 });
        }
        if (isCollectable(c)) out.get(c.clan).cards += 1;
    }
    return [...out.values()].filter(c => c.cards > 0).sort((a, b) => a.name.localeCompare(b.name));
}

export function starterRecipe(clan, catalog = CARD_CATALOG) {
    const cards = Object.values(catalog).filter(c => c.clan === clan);
    const has = (id) => catalog[id] && catalog[id].clan === clan;
    const cur = CURATED[clan];
    if (cur && has(cur.leader) && [...cur.deck, ...cur.hideout].every(([id]) => has(id))) {
        return { clan, leader: cur.leader, deck: cur.deck.map(p => [...p]), hideout: cur.hideout.map(p => [...p]) };
    }
    const byValue = (a, b) => (a.rarity || 1) - (b.rarity || 1) || (a.authority || 0) - (b.authority || 0) || a.id.localeCompare(b.id);
    const pool = cards.filter(inDeck).sort(byValue);
    if (pool.length * MAX_COPIES < DECK_SIZE) return null;
    // Commoner cards get more copies (rarity 1–2: 3, rarity 3: 2, rarer: 1), characters first
    const want = (c) => ((c.rarity || 1) <= 2 ? 3 : (c.rarity || 1) === 3 ? 2 : 1);
    const copies = new Map();
    let total = 0;
    const add = (list, cap, limit) => {
        for (const c of list) {
            while (total < limit && (copies.get(c.id) || 0) < cap(c)) {
                copies.set(c.id, (copies.get(c.id) || 0) + 1);
                total += 1;
            }
        }
    };
    const characters = pool.filter(c => c.cardType === 'gang_member');
    const effects = pool.filter(c => c.cardType !== 'gang_member');
    add(characters, want, CHARACTER_TARGET);
    add(effects, want, DECK_SIZE);
    add(characters, want, DECK_SIZE);
    add(pool, () => MAX_COPIES, DECK_SIZE);   // still short: up to 3 of anything
    if (total < DECK_SIZE) return null;
    const deck = pool.filter(c => copies.has(c.id)).map(c => [c.id, copies.get(c.id)]);
    // Promoted forms of the deck's Strivers wait in the Hideout
    const hideout = [];
    const seen = new Set();
    for (const [id] of deck) {
        for (let next = nextForm(id, catalog); next && !seen.has(next); next = nextForm(next, catalog)) {
            seen.add(next);
            hideout.push([next, MAX_COPIES]);
        }
    }
    const leader = cards.filter(c => c.cardType === 'leader').sort(byValue)[0];
    return { clan, leader: leader ? leader.id : '', deck, hideout };
}

export function pickableClans(catalog = CARD_CATALOG) {
    return clanList(catalog).filter(c => starterRecipe(c.id, catalog));
}

export const expand = (pairs) => pairs.flatMap(([id, n]) => Array(n).fill(id));

/** The form a card promotes into: promotesTo, or the next `_lvN` card (same as nextForm in DuelState). */
function nextForm(id, catalog) {
    const c = catalog[id];
    if (c && c.promotesTo) return catalog[c.promotesTo] ? c.promotesTo : '';
    const m = /^(.*_lv)(\d)$/.exec(id);
    const guess = m ? `${m[1]}${Number(m[2]) + 1}` : '';
    return guess && catalog[guess] ? guess : '';
}

function prettify(id) {
    return id.replace(/_/g, ' ').replace(/\b\w/g, ch => ch.toUpperCase());
}
