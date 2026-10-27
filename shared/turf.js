// Turf Defense: two players against a clan's leader at full power. The bosses, their levels,
// lines and rewards are in godot/data/bosses.json (the game reads the same file); this builds a
// level's boss deck and the match rules for the shared engine (DuelState.js, rules.teams/boss).
// The server runs the matches (backend/socket/coopMatch.js) and pays the rewards (economy/turf.js).

import fs from 'fs';
import { CARD_CATALOG } from './cards.js';
import { starterRecipe, expand } from './clans.js';

export const BOSS_DATA = JSON.parse(fs.readFileSync(new URL('../godot/data/bosses.json', import.meta.url), 'utf8'));
export const BOSSES = BOSS_DATA.bosses;
export const SEATS = ['p1', 'p2', 'boss'];

export const findBoss = (id) => BOSSES.find(b => b.id === id) || null;

/** A boss's prize: the card, and (a Striver) the levels it promotes into, so it can promote. */
export function prizeLine(id) {
    const out = [];
    for (let cur = id; cur && CARD_CATALOG[cur] && !out.includes(cur); cur = CARD_CATALOG[cur].promotesTo || '') out.push(cur);
    return out;
}

/** Every boss-only card (the prizes and their levels): never in packs, never crafted. */
export function prizeCardIds() {
    return new Set(BOSSES.flatMap(b => prizeLine(b.prize)));
}
export const bossLevel = (boss, n) => (boss?.levels || []).find(l => l.level === Number(n)) || null;

/** The boss's deck at a level: its clan's starter, with the level's "add" cards in place of its
 *  cheapest characters (lowest Authority, then ATK), so it stays the same size. */
export function bossSetup(boss, level) {
    const recipe = starterRecipe(boss.clan);
    if (!recipe) throw new Error(`No starter deck for ${boss.clan}`);
    const deck = expand(recipe.deck);
    const lv = typeof level === 'object' ? level : bossLevel(boss, level);
    const added = new Set();
    for (const [id, n] of lv?.add || []) {
        if (!CARD_CATALOG[id]) continue;
        for (let i = 0; i < n; i++) {
            const cheap = deck
                .map((x, k) => ({ k, c: CARD_CATALOG[x] }))
                .filter(x => x.c && x.c.cardType === 'gang_member' && !added.has(deck[x.k]))
                .sort((a, b) => (a.c.authority - b.c.authority) || (a.c.attack - b.c.attack) || (a.k - b.k))[0];
            if (cheap) deck.splice(cheap.k, 1);
            deck.push(id);
            added.add(id);
        }
    }
    return { deck, hideout: expand(recipe.hideout), leader: boss.leader || recipe.leader };
}

/** The match rules: both players, then the boss, in turn order; the boss's Morale, its extra draw and
 *  Authority each turn, and its phases. */
export function turfRules(boss, level) {
    const lv = typeof level === 'object' ? level : bossLevel(boss, level);
    return {
        order: SEATS,
        teams: { p1: 'crew', p2: 'crew', boss: 'boss' },
        morale: { boss: lv.morale },
        boss: { seat: 'boss', name: boss.name, draw: lv.draw || 0, authority: lv.authority || 0, phases: lv.phases || [] },
    };
}

/** What the game shows of a boss (the start of a match, the Turf Defense screen): no decks. */
export function bossInfo(boss, level) {
    const lv = typeof level === 'object' ? level : bossLevel(boss, level);
    return {
        id: boss.id, clan: boss.clan, name: boss.name, short: boss.short || boss.name, title: boss.title, color: boss.color, arena: boss.arena,
        portrait: boss.portrait, prize: boss.prize, lines: boss.lines,
        level: lv.level, level_name: lv.name, morale: lv.morale, draw: lv.draw || 0, authority: lv.authority || 0,
        phases: (lv.phases || []).map(p => ({ below: p.below, label: p.label })),
    };
}
