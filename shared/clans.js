/**
 * Clans and starter decks, worked out from the card catalogue, so a clan added in the Card Forge
 * (or removed) needs no code changes: new players can pick it, the CPU can play it, and the shop
 * and Deck Builder list it.
 *
 *   clanList()            every clan with collectable cards: {id, name, color, tag, cards}
 *   starterRecipe(clan)   its starter: {clan, leader, deck: [[id, copies]], hideout: [[id, copies]]}
 *                         or null when the clan doesn't have enough cards for a 40-card deck yet
 *   pickableClans()       the clans new players can start with (they have a starter)
 *   clanBlurb(clan)       how a clan plays in a line ('' when it has none)
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
    // 28 characters, 12 Hustles/Ambushes. Retuned 2026-10-27 (tools/deck_test.mjs, starter vs starter):
    // the old list (Damian, Scout-157 x2, Skully, Ajax, Sarah) won 26% against Militia and 36% overall.
    // Board control against wide decks (Hull Breach x3, Singularity, Clay x2) and the newer Alysse and
    // Tycho made it 43% / 53% Underworld / 60% Wildcard, 52% overall. Skully and Atlas are left for packs.
    nebula: {
        // (how it plays, shown when new players choose a clan)
        blurb: 'Control the board: freeze enemies in STASIS, force them into DEF and win with a few strong fighters.',
        leader: 'card_nebu_009',   // Archon of Nebula
        deck: [
            // Strivers: Kade, Lyra Quell, Marty, Rouke, Nix
            ['card_nebu_001', 2], ['card_nebu_012', 3], ['card_nebu_030', 2], ['card_nebu_015', 1], ['card_nebu_004', 2],
            // Characters: Sprintz, Megan, Marty & Mike, Dr. Orion Krell, Adira, Alysse, Tycho, Scout-157;
            // Heavies Jax, DS-022, Clay
            ['card_nebu_011', 2], ['card_nebu_018', 2], ['card_nebu_019', 2], ['card_nebu_037', 1], ['card_nebu_033', 1],
            ['card_nebu_042', 2], ['card_nebu_045', 2], ['card_nebu_034', 1],
            ['card_nebu_025', 1], ['card_nebu_035', 2], ['card_nebu_024', 2],
            // Hustles: Supernova Run, Event Horizon, Orbital Strike, Singularity;
            // Ambushes: Gravity Well, Dark Matter, Hull Breach
            ['card_nebu_010', 2], ['card_nebu_008', 1], ['card_nebu_027', 1], ['card_nebu_043', 1],
            ['card_nebu_007', 3], ['card_nebu_026', 1], ['card_nebu_029', 3],
        ],
        hideout: [
            ['card_nebu_002', 3], ['card_nebu_003', 3], ['card_nebu_013', 3], ['card_nebu_014', 3],
            ['card_nebu_031', 3], ['card_nebu_032', 3], ['card_nebu_016', 3], ['card_nebu_017', 3],
            ['card_nebu_005', 3], ['card_nebu_006', 3],
        ],
    },
    // Every Militia base card: 31 characters, 9 Hustles/Ambushes. Even with the Nebula starter
    // (node tools/balance.mjs --vs nebula,militia --starters); the built one only had cheap commons.
    militia: {
        blurb: 'Go wide: fill the board, call in reinforcements, and grind the enemy down with Ambushes and Heavies.',
        leader: 'card_mili_011',   // General Graves
        deck: [
            // Strivers: Thomas, Mary, Rook, Bastion, Lance, Deadwood
            ['card_mili_015', 3], ['card_mili_018', 3], ['card_mili_006', 3], ['card_mili_027', 3],
            ['card_mili_021', 2], ['card_mili_024', 2],
            // Characters: Static, Johnson, Briar, Smoke Runner, Mule, Sergeant Ironwall; Heavies Sarge, The Colonel
            ['card_mili_002', 2], ['card_mili_033', 3], ['card_mili_003', 2], ['card_mili_009', 2],
            ['card_mili_012', 2], ['card_mili_004', 2], ['card_mili_001', 1], ['card_mili_014', 1],
            // Ambushes: Tripwire, Checkpoint Zero, False Retreat; Hustles: Supply Drop, Tactical Sweep, Improvised Armor
            ['card_mili_005', 3], ['card_mili_032', 1], ['card_mili_031', 1],
            ['card_mili_010', 2], ['card_mili_030', 1], ['card_mili_013', 1],
        ],
        hideout: [
            ['card_mili_016', 3], ['card_mili_017', 3], ['card_mili_019', 3], ['card_mili_020', 3],
            ['card_mili_007', 3], ['card_mili_008', 3], ['card_mili_028', 3], ['card_mili_029', 3],
            ['card_mili_022', 3], ['card_mili_023', 3], ['card_mili_025', 3], ['card_mili_026', 3],
        ],
    },
    // 30 characters, 10 Hustles/Ambushes; Rex is for packs. Retuned 2026-10-27 (tools/deck_test.mjs, starter vs
    // starter): the old list won 39% overall (32% against Underworld). Out: Mickey Dukes, Garrison, Hot Streak, a
    // Call the Bluff; in: a third Lucky Lou, a second House Always Wins and Ace Up The Sleeve, Hugo Brandt, Viktor.
    // Now 56% Militia / 46% Nebula / 47% Underworld, 49% overall.
    wildcard: {
        blurb: 'Play the odds: coin flips and dice for big payoffs, DOUBLE OR NOTHING bets, and LOADED DICE to tilt the odds your way.',
        leader: 'card_wild_001',   // Vincent Vale
        deck: [
            // Strivers: Lucky Lou, Dice Delgado, Penny Harlow, Ruby Reyes
            ['card_wild_002', 3], ['card_wild_021', 2], ['card_wild_024', 2], ['card_wild_030', 2],
            // Characters: Sally, Jennifer, Raymond, Trent, Jackie, Roberto, Catherine, Marchetti, Otis, Viktor;
            // Heavies Baxter, Hugo Brandt
            ['card_wild_010', 2], ['card_wild_006', 2], ['card_wild_008', 2], ['card_wild_011', 2], ['card_wild_033', 2],
            ['card_wild_005', 2], ['card_wild_009', 2], ['card_wild_034', 2], ['card_wild_035', 2], ['card_wild_045', 1],
            ['card_wild_007', 1], ['card_wild_041', 1],
            // Hustles: Double Down, Loaded Dice, All In, The House Always Wins;
            // Ambushes: Ace Up The Sleeve, Snake Eyes, Call the Bluff
            ['card_wild_014', 1], ['card_wild_018', 2], ['card_wild_015', 1], ['card_wild_017', 2],
            ['card_wild_016', 2], ['card_wild_019', 1], ['card_wild_037', 1],
        ],
        hideout: [
            ['card_wild_003', 3], ['card_wild_004', 3], ['card_wild_022', 3], ['card_wild_023', 3],
            ['card_wild_025', 3], ['card_wild_026', 3],
            ['card_wild_031', 3], ['card_wild_032', 3],
        ],
    },
    // 30 characters, 10 Hustles/Ambushes: a fast Gutter and UNDEAD, with a few Skeleton makers. Null, Mortivar,
    // Last Rites and Haunting are left for packs. Even-ish with the other starters (node tools/balance.mjs
    // --vs underworld,<clan> --starters: 44-56%); more token makers (Rattle, a third Bone Harvest) made it much weaker.
    underworld: {
        blurb: 'Rise in numbers: flood the board with Skeleton tokens, fill your Gutter, and make your characters UNDEAD so they rise again.',
        leader: 'card_unde_001',   // Veyr - the Hollow King
        deck: [
            // Strivers Dredge, Vespera, Malachar, Bonesy, Wick; Knell, Ferrik, Gravekeeper Mott, Sable, Doctor Morbus,
            // Noctra, Lenore, Grimhound, Ossian, Hollow Wraith; Heavy Omen; Grasping Hands, Raise the Dead, Soul Toll,
            // Bone Harvest, Danse Macabre, Open Grave, Chains of the Damned
            ['card_unde_003', 2], ['card_unde_017', 2], ['card_unde_014', 2], ['card_unde_037', 2], ['card_unde_040', 2],
            ['card_unde_007', 2], ['card_unde_008', 2], ['card_unde_035', 2], ['card_unde_006', 2], ['card_unde_031', 2],
            ['card_unde_013', 2], ['card_unde_036', 2], ['card_unde_010', 2], ['card_unde_032', 1], ['card_unde_033', 1],
            ['card_unde_009', 1], ['card_unde_024', 3], ['card_unde_021', 2], ['card_unde_023', 1], ['card_unde_022', 2],
            ['card_unde_027', 1], ['card_unde_029', 1], ['card_unde_030', 1],
        ],
        hideout: [
            ['card_unde_004', 3], ['card_unde_005', 3], ['card_unde_019', 3], ['card_unde_020', 3],
            ['card_unde_015', 3], ['card_unde_016', 3], ['card_unde_038', 3], ['card_unde_039', 3],
            ['card_unde_041', 3], ['card_unde_042', 3],
        ],
    },
};

// How a clan without a starter yet plays (shown when it can be chosen)
const BLURBS = {};

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

/**
 * The profile pictures everyone has (crops of card art: "card:<id>"): each clan's leader and its
 * three most common characters. More come from achievements and levels (godot/scripts/ui/ui.gd).
 */
export function freeAvatars(catalog = CARD_CATALOG) {
    const out = [];
    const byCommon = (a, b) => (a.rarity || 1) - (b.rarity || 1) || a.id.localeCompare(b.id);
    for (const clan of clanList(catalog)) {
        const cards = Object.values(catalog).filter(c => c.clan === clan.id && !c.token);
        for (const l of cards.filter(c => c.cardType === 'leader').sort(byCommon)) out.push(`card:${l.id}`);
        for (const c of cards.filter(c => c.cardType === 'gang_member' && level(c) === 1).sort(byCommon).slice(0, 3)) out.push(`card:${c.id}`);
    }
    return out;
}

export function clanBlurb(clan) {
    return CURATED[clan]?.blurb || BLURBS[clan] || '';
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
