/**
 * CARD CATALOG
 * Rules data for every card, keyed by game ID (also the art key: assets/cards/<id>.png).
 * Shared by the client (solo duels, deck loading) and the server (online matches).
 * Cards from the Card Forge (shared/cards_forge.js, written by tools/import_forge.mjs) are
 * merged in at the bottom.
 */

import { FORGE_CARDS } from './cards_forge.js';

export const CARD_CATALOG = {
    // ── LIONS: Eric (Striver chain) ──────────────────────────────────────────
    'eric_lv1': {
        id: 'eric_lv1', name: 'Eric', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 700, defense: 600, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'eric_lv2',
        art_url: 'eric_lv1',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: You can PROMOTE this card.',
    },
    'eric_lv2': {
        id: 'eric_lv2', name: 'Eric Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 1600, defense: 1300, tributeCost: 0, rarity: 2, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'eric_lv3',
        art_url: 'eric_lv2',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: You can PROMOTE this card.',
    },
    'eric_lv3': {
        id: 'eric_lv3', name: 'Eric Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 8, attack: 2600, defense: 2000, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'eric_lv3_draw', promotesTo: null,
        art_url: 'eric_lv3',
        flavourText: "I don't follow footsteps. I leave my own.",
        effectText: 'When this card sends an opponent\'s character to the Gutter: Draw 1 card.\nAt the start of your turn: gains +100 ATK for each other LIONS card you control.',
    },

    // ── LIONS: Maya (Striver chain) ──────────────────────────────────────────
    'maya_lv1': {
        id: 'maya_lv1', name: 'Maya', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 900, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'maya_lv2',
        art_url: 'maya_lv1', ability: 'maya_promote', abilityOnlyPromote: true,
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'If you control another LIONS card with equal or higher Authority, you can PROMOTE this card.',
    },
    'maya_lv2': {
        id: 'maya_lv2', name: 'Maya Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2000, defense: 1500, tributeCost: 0, rarity: 2, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'lion_clan_bonus', promotesTo: 'maya_lv3',
        art_url: 'maya_lv2', ability: 'maya_promote', abilityOnlyPromote: true,
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'At the start of your turn: if you control another LIONS card with equal or higher Authority, you can PROMOTE this card.',
    },
    'maya_lv3': {
        id: 'maya_lv3', name: 'Maya Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2900, defense: 2500, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'maya_lv3_buff', promotesTo: null,
        art_url: 'maya_lv3',
        flavourText: "Loyalty isn't given. It's earned in the streets.",
        effectText: 'Once per turn: Choose 1 other LIONS card. It gains +400 ATK and +400 DEF until end of turn.',
        ability: 'maya_buff',
    },

    // ── LIONS: Brawlers & Heavies ────────────────────────────────────────────
    'pride_runner': {
        id: 'pride_runner', name: 'Pride Runner', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 1000, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'pride_runner_adjacency', promotesTo: null,
        art_url: 'pride_runner',
        flavourText: "One lion hunts. Two lions own the street.",
        effectText: 'While adjacent to another LIONS character, this card gains +400 ATK.',
    },
    'lion_grunt': {
        id: 'lion_grunt', name: 'Lion Grunt', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 700, defense: 500, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'lion_grunt_synergy', promotesTo: null,
        art_url: 'lion_grunt',
        flavourText: "A lone lion prowls. A pack owns the block.",
        effectText: 'If you control another LIONS character, this card gains +300 ATK.',
    },
    'block_enforcer': {
        id: 'block_enforcer', name: 'Block Enforcer', clan: 'iron_saints', cardType: 'gang_member',
        authority: 3, attack: 1300, defense: 1500, tributeCost: 0, rarity: 2, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'block_enforcer_redirect', promotesTo: null,
        art_url: 'block_enforcer',
        flavourText: "We hold the line. You handle the lion.",
        effectText: 'Once per turn, when an allied LIONS would be targeted in a brawl, you may have this card become the target instead.', // redirect is passive/auto
    },
    'goldfang': {
        id: 'goldfang', name: 'Goldfang', clan: 'iron_saints', cardType: 'gang_member',
        authority: 4, attack: 1700, defense: 1400, tributeCost: 0, rarity: 2, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'goldfang_attacker', promotesTo: null,
        art_url: 'goldfang',
        flavourText: "They hide behind defense. I break it, then I break them.",
        effectText: 'If this card attacks a defending character, it gains +500 ATK during that brawl.',
    },
    'pride_lieutenant': {
        id: 'pride_lieutenant', name: 'Pride Lieutenant', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2300, defense: 1900, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_lieutenant_deploy', promotesTo: null,
        art_url: 'pride_lieutenant',
        flavourText: "Strength is nothing without your people.",
        effectText: 'When deployed: One other LIONS card gains +500 ATK until end of turn.',
    },
    'pride_mentor': {
        id: 'pride_mentor', name: 'Pride Mentor', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2100, defense: 1800, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'pride_mentor_draw', promotesTo: null,
        art_url: 'pride_mentor',
        flavourText: "Strength gets respect. Survival earns wisdom.",
        effectText: 'Once per turn, when a LIONS Striver PROMOTES, draw 2 cards.',
    },
    'brutus': {
        id: 'brutus', name: 'Brutus', clan: 'iron_saints', cardType: 'gang_member',
        authority: 8, attack: 2800, defense: 2500, tributeCost: 0, rarity: 4, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'brutus_enter', promotesTo: null,
        art_url: 'brutus',
        flavourText: "Strength leads. Loyalty follows. We finish.",
        effectText: 'When this enters the grid: Choose 1 enemy character; it loses 700 ATK until the end of your opponent\'s next turn.\nWhen this defeats an opponent\'s character: Your next LIONS attacker this turn gains +300 ATK.',
    },

    // ── LIONS: Hunter (Striver chain) ────────────────────────────────────────
    'hunter_lv1': {
        id: 'hunter_lv1', name: 'Hunter', clan: 'iron_saints', cardType: 'gang_member',
        authority: 1, attack: 800, defense: 400, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv1', promotesTo: null,
        art_url: 'hunter_lv1',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a Downed character: PROMOTE this card.',
    },
    'hunter_lv2': {
        id: 'hunter_lv2', name: 'Hunter Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 1900, defense: 1000, tributeCost: 0, rarity: 3, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv2', promotesTo: null,
        art_url: 'hunter_lv2',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a character: Choose 1 enemy character → Down it.\nWhen this card KOs a Downed character: PROMOTE this card.',
    },
    'hunter_lv3': {
        id: 'hunter_lv3', name: 'Hunter Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2700, defense: 1900, tributeCost: 0, rarity: 3, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'hunter_lv3', promotesTo: null,
        art_url: 'hunter_lv3',
        flavourText: "The hunt never ends. Only the hunted changes.",
        effectText: 'When this card attacks a Downed character: +500 ATK this Brawl.\nWhen this card KOs a character: Choose 1 enemy character → Down it.\nWhen this card KOs a Downed character: It may attack again this turn.',
    },

    // ── LIONS: Viper (Striver chain) ─────────────────────────────────────────
    'viper_lv1': {
        id: 'viper_lv1', name: 'Viper', clan: 'iron_saints', cardType: 'gang_member',
        authority: 2, attack: 1100, defense: 600, tributeCost: 0, rarity: 1, level: 1,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv1', promotesTo: null,
        art_url: 'viper_lv1',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card Downs a character: PROMOTE this card.',
    },
    'viper_lv2': {
        id: 'viper_lv2', name: 'Viper Lv.2', clan: 'iron_saints', cardType: 'gang_member',
        authority: 5, attack: 2000, defense: 1200, tributeCost: 0, rarity: 1, level: 2,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv2', promotesTo: null,
        art_url: 'viper_lv2',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card attacks: You may move it to an adjacent lane before the Brawl.\nWhen this card Downs a character: PROMOTE this card.',
    },
    'viper_lv3': {
        id: 'viper_lv3', name: 'Viper Lv.3', clan: 'iron_saints', cardType: 'gang_member',
        authority: 9, attack: 2600, defense: 1800, tributeCost: 0, rarity: 1, level: 3,
        subtype: 'striver', clanTag: 'lion', effectKey: 'viper_lv3', promotesTo: null,
        art_url: 'viper_lv3',
        flavourText: "Fast, precise, silent. They never see me twice.",
        effectText: 'When this card attacks: You may move it to an adjacent lane before the Brawl.\nWhen this card KOs a character: You may move this card to an adjacent lane.\nWhen this card KOs a Downed character: It may attack again this turn.',
    },

    // ── LIONS: Additional Brawlers & Heavies ─────────────────────────────────
    'debt_collector': {
        id: 'debt_collector', name: 'Debt Collector', clan: 'iron_saints', cardType: 'gang_member',
        authority: 3, attack: 1400, defense: 700, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'debt_collector', promotesTo: null,
        art_url: 'debt_collector',
        flavourText: "Everyone pays. It's just a matter of when.",
        effectText: 'When this card Downs a character by battle: Your opponent discards 1 card.',
    },
    'bulwark': {
        id: 'bulwark', name: 'Bulwark', clan: 'iron_saints', cardType: 'gang_member',
        authority: 6, attack: 2300, defense: 2600, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'bulwark', promotesTo: null,
        art_url: 'bulwark',
        flavourText: "The wall doesn't move. The wall doesn't break.",
        effectText: 'This card cannot be moved by enemy effects.\nWhile this card is in play: Adjacent allies gain +400 DEF.\nWhen this card is attacked: The attacking character loses 300 ATK during that Brawl.',
    },
    'mauler': {
        id: 'mauler', name: 'Mauler', clan: 'iron_saints', cardType: 'gang_member',
        authority: 6, attack: 2300, defense: 2000, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'mauler', promotesTo: null,
        art_url: 'mauler',
        flavourText: "Down doesn't mean done. Until I say it does.",
        effectText: 'This card deals +500 ATK when attacking a Downed character.\nWhen this card KOs a Downed character: All enemy characters in adjacent lanes take -500 DEF this turn.',
    },
    'kingpin': {
        id: 'kingpin', name: 'Kingpin', clan: 'iron_saints', cardType: 'gang_member',
        authority: 4, attack: 1800, defense: 1000, tributeCost: 0, rarity: 4, level: 1,
        subtype: 'brawler', clanTag: 'lion', effectKey: 'kingpin', promotesTo: null,
        art_url: 'kingpin',
        flavourText: "When they're down, I take everything.",
        effectText: 'While your opponent controls a Downed character: This card gains +400 ATK.',
    },
    'sovereign': {
        id: 'sovereign', name: 'Sovereign', clan: 'iron_saints', cardType: 'gang_member',
        authority: 10, attack: 2900, defense: 1800, tributeCost: 0, rarity: 5, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'sovereign', promotesTo: null,
        art_url: 'sovereign',
        flavourText: "Bow or break.",
        effectText: 'When this card enters play: All enemy characters with 1500 DEF or less become Downed.\nWhile your opponent controls a Downed character: This card gains +600 ATK.',
    },

    // ── LIONS: Leader ────────────────────────────────────────────────────────
    'king_roan': {
        id: 'king_roan', name: 'King Roan', clan: 'iron_saints', cardType: 'leader',
        authority: 10, attack: 3000, defense: 3000, tributeCost: 0, rarity: 3, level: 1,
        subtype: 'heavy', clanTag: 'lion', effectKey: 'king_roan_leader', promotesTo: null,
        art_url: 'king_roan',
        flavourText: "A lion doesn't ask for respect. He earns it. Then he takes more.",
        effectText: 'DORMANT: While Dormant, all LIONS characters you control gain +300 ATK with 2 or more LIONS on field.\nAWAKEN: When you control 4+ LIONS characters OR your total Authority is 10+.',
        awakenCondition: { lions: 4, authorityThreshold: 10 },
    },

    // ── LIONS: Ambush cards ──────────────────────────────────────────────────
    'lion_ambush': {
        id: 'lion_ambush', name: "Lion's Ambush", clan: 'iron_saints', cardType: 'ambush',
        authority: 2, tributeCost: 0, rarity: 2,
        clanTag: 'lion', effectKey: 'lion_ambush',
        art_url: 'lion_ambush',
        effectText: 'Play when an opponent declares an attack. If they attack a LIONS character, that attacker loses 1000 ATK during this brawl.',
    },
    'no_witnesses': {
        id: 'no_witnesses', name: 'No Witnesses', clan: 'iron_saints', cardType: 'ambush',
        authority: 3, tributeCost: 0, rarity: 3,
        clanTag: 'lion', effectKey: 'no_witnesses_ambush',
        art_url: 'no_witnesses',
        effectText: 'When an opponent brawls a LIONS character: Down the attacking character and negate their attack.',
    },
    'kings_test': {
        id: 'kings_test', name: "King's Test", clan: 'iron_saints', cardType: 'ambush',
        authority: 3, tributeCost: 0, rarity: 3,
        clanTag: 'lion', effectKey: 'kings_test',
        art_url: 'kings_test',
        effectText: 'When a LIONS Striver would be destroyed in battle: Negate that destruction. If it survives, you may PROMOTE it at the start of your next turn.',
    },

    // ── LIONS: Hustle cards ──────────────────────────────────────────────────
    'corner_deal': {
        id: 'corner_deal', name: 'Corner Deal', clan: 'iron_saints', cardType: 'hustle',
        authority: 2, tributeCost: 0, rarity: 1,
        clanTag: 'lion', effectKey: 'corner_deal',
        art_url: 'corner_deal',
        effectText: 'Draw 2 cards, then discard 1 card. If you control a Striver, you do not discard.',
    },
    'blood_scent': {
        id: 'blood_scent', name: 'Blood Scent', clan: 'iron_saints', cardType: 'hustle',
        authority: 3, tributeCost: 0, rarity: 2,
        clanTag: 'lion', effectKey: 'blood_scent',
        art_url: 'blood_scent',
        effectText: 'Choose 1 LIONS Striver you control; its PROMOTE condition is treated as fulfilled this turn.',
    },
    'lion_rescue': {
        id: 'lion_rescue', name: 'Lion Rescue', clan: 'iron_saints', cardType: 'hustle',
        authority: 2, tributeCost: 0, rarity: 1,
        clanTag: 'lion', effectKey: 'lion_rescue',
        art_url: 'lion_rescue',
        effectText: 'Choose 1 Downed LIONS character; Stand it.',
    },
};

// Card Forge cards on top (same id replaces the hand-written card)
Object.assign(CARD_CATALOG, FORGE_CARDS);
