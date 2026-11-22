'use strict';

/**
 * VETERAN CARDS: each card has three mastery quests (godot/data/veteran_quests.json, by what the card is:
 * questKind), done in order; each one done earns the card its next tier, shown as its frame: bronze, chrome,
 * gold. The server counts them from the matches it runs: a match's events go through track() (socket/
 * onlineMatch.js, coopMatch.js), and at the end record() adds them to the card's row, with a play for every
 * card the player played (summoned, set, used, their leader) and a win if they won. Purely cosmetic: both
 * players see the frames in a duel (the match profiles' `vets`), and each other's card XP in the card zoom
 * (`vet_xp`, xpByCard: plays + 2 a win, as before the quests).
 * Tiers earned by card XP before the quests (0.9.185) are kept (legacy_tier, migrate_veteran_quests.sql).
 */

const fs = require('fs');
const path = require('path');
const db = () => require('../db/pool').pool;   // (loaded when used: the match servers load this file for track)

const TIERS = [
    { tier: 1, name: 'Seasoned' },
    { tier: 2, name: 'Battle-Scarred' },
    { tier: 3, name: 'Street Legend' },
];
const XP_PLAY = 1, XP_WIN = 2;   // (card XP, shown in the zoom: a win is 3 in all)
const STATS = ['kos', 'downs', 'direct', 'effects', 'promotes', 'awakens'];   // counted by track()

const KINDS = (() => {
    try { return JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/veteran_quests.json'), 'utf8')).kinds || {}; }
    catch { return {}; }
})();

const xpOf = (wins, plays) => plays * XP_PLAY + wins * XP_WIN;
const validId = (id) => typeof id === 'string' && id.length > 0 && id.length <= 64;

let catalog = null;
async function cards() {
    if (!catalog) catalog = (await import('../../shared/cards.js')).CARD_CATALOG;
    return catalog;
}

/** Which quests a card has (same as UI.veteran_kind in the game). */
function questKind(c) {
    if (!c) return 'character';
    if (c.cardType === 'leader') return 'leader';
    if (c.cardType !== 'gang_member') return 'card';
    if (c.subtype === 'striver' && c.promotesTo) return 'striver';
    if (c.subtype === 'heavy') return 'heavy';
    return (c.effects || []).length ? 'effects' : 'character';
}

/** A row's number for a quest's stat (fights: Downs and KOs). */
function statOf(row, stat) {
    if (stat === 'fights') return (Number(row.kos) || 0) + (Number(row.downs) || 0);
    return Number(row[stat]) || 0;
}

/** A card's tier from its row: the quests done in order, or its tier from before the quests if higher. */
function tierOf(card, row) {
    const quests = KINDS[questKind(card)] || [];
    let t = 0;
    while (t < quests.length && statOf(row, quests[t].stat) >= quests[t].need) t += 1;
    return Math.max(t, Number(row.legacy_tier) || 0);
}

/** A match's tracker for one player: what each of their cards did. */
function tracker() {
    return { cards: {}, by: null };
}

/** One of the match's events (me: the player's seat). A KO, a Down or a direct hit counts for the card
 *  whose attack it came in (the last "attack" of theirs, until the phase or turn changes). */
function track(t, ev, me) {
    if (!t || !ev) return;
    const add = (id, k, v = 1) => {
        if (!validId(id) || !v) return;
        const r = t.cards[id] || (t.cards[id] = {});
        r[k] = (r[k] || 0) + v;
    };
    switch (ev.type) {
        case 'attack': t.by = ev.side === me ? ev.card?.id ?? null : null; break;
        case 'phase': case 'turn': t.by = null; break;
        case 'clash': if (ev.side === me && ev.vs === 'DIRECT' && t.by) add(t.by, 'direct', Math.max(0, Number(ev.att) || 0)); break;
        case 'ko': if (ev.side !== me && !ev.exiled && t.by) add(t.by, 'kos'); break;
        case 'downed': if (ev.side !== me && t.by) add(t.by, 'downs'); break;
        case 'effect': {   // (not the lines that say it did nothing)
            const text = String(ev.text || '');
            if (ev.side === me && ev.card && !/: (not now|nothing to find in the deck|nothing in the deck to send)$/.test(text)) add(ev.card.id, 'effects');
            break;
        }
        case 'promote': if (ev.side === me && ev.from) add(ev.from.id, 'promotes'); break;
        case 'awaken': if (ev.side === me && ev.card) add(ev.card.id, 'awakens'); break;
    }
}

/**
 * A finished match for one player: a play for each card they played (a win too if they won), and what
 * the tracker counted → the cards that reached a new tier: [{id, tier, name}].
 */
async function record(playerId, cardIds, won, t = null) {
    const counted = t?.cards || {};
    const ids = [...new Set([...(cardIds || []), ...Object.keys(counted)])].filter(validId);
    if (!playerId || !ids.length) return [];
    const col = (k) => ids.map(id => Math.max(0, Math.trunc(Number(counted[id]?.[k]) || 0)));
    const { rows } = await db().query(
        `INSERT INTO card_veterans (player_id, card_id, wins, plays, ${STATS.join(', ')})
         SELECT $1, x.id, $3, 1, ${STATS.map(k => `x.${k}`).join(', ')}
           FROM UNNEST($2::text[], ${STATS.map((_, i) => `$${i + 4}::int[]`).join(', ')}) AS x(id, ${STATS.join(', ')})
         ON CONFLICT (player_id, card_id) DO UPDATE SET wins = card_veterans.wins + EXCLUDED.wins,
             plays = card_veterans.plays + 1, ${STATS.map(k => `${k} = card_veterans.${k} + EXCLUDED.${k}`).join(', ')}
         RETURNING card_id, wins, plays, legacy_tier, ${STATS.join(', ')}`,
        [playerId, ids, won ? 1 : 0, ...STATS.map(col)]);
    const cat = await cards();
    const out = [];
    for (const r of rows) {
        const before = { ...r, wins: r.wins - (won ? 1 : 0), plays: r.plays - 1 };
        for (const k of STATS) before[k] = (Number(r[k]) || 0) - (Number(counted[r.card_id]?.[k]) || 0);
        const card = cat[r.card_id], now = tierOf(card, r);
        if (now > tierOf(card, before)) out.push({ id: r.card_id, tier: now, name: TIERS[now - 1].name });
    }
    return out;
}

const COLS = `card_id, wins, plays, legacy_tier, ${STATS.join(', ')}`;

/** The tiers of a player's veteran cards, only those with one: {cardId: tier}. `cardIds` limits it (a deck). */
async function tiers(playerId, cardIds = null) {
    if (!playerId) return {};
    const { rows } = cardIds
        ? await db().query(`SELECT ${COLS} FROM card_veterans WHERE player_id = $1 AND card_id = ANY($2::text[])`,
            [playerId, [...new Set(cardIds)].filter(validId)])
        : await db().query(`SELECT ${COLS} FROM card_veterans WHERE player_id = $1`, [playerId]);
    const cat = await cards();
    const out = {};
    for (const r of rows) {
        const t = tierOf(cat[r.card_id], r);
        if (t > 0) out[r.card_id] = t;
    }
    return out;
}

/** The card XP of each of these cards the player has played: {cardId: xp} (a duel's profiles, `vet_xp`). */
async function xpByCard(playerId, cardIds) {
    const ids = [...new Set(cardIds || [])].filter(validId);
    if (!playerId || !ids.length) return {};
    const { rows } = await db().query(`SELECT card_id, wins, plays FROM card_veterans WHERE player_id = $1 AND card_id = ANY($2::text[])`, [playerId, ids]);
    return Object.fromEntries(rows.map(r => [r.card_id, xpOf(r.wins, r.plays)]));
}

/** Every card a player has played: {tiers: TIERS, cards: {cardId: {wins, plays, xp, tier, kos, downs, direct,
 *  effects, promotes, awakens}}} (GET /api/veterans; the game words each card's quests from veteran_quests.json). */
async function overview(playerId) {
    const { rows } = await db().query(`SELECT ${COLS} FROM card_veterans WHERE player_id = $1`, [playerId]);
    const cat = await cards();
    return { tiers: TIERS, cards: Object.fromEntries(rows.map(r => [r.card_id, {
        wins: r.wins, plays: r.plays, xp: xpOf(r.wins, r.plays), tier: tierOf(cat[r.card_id], r),
        ...Object.fromEntries(STATS.map(k => [k, Number(r[k]) || 0])),
    }])) };
}

module.exports = { record, tiers, xpByCard, overview, tracker, track, tierOf, questKind, statOf, xpOf, TIERS, KINDS };
