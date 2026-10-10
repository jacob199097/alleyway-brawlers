'use strict';

/**
 * ACHIEVEMENTS
 * Goals beyond winning. Each one is measured against a stat (players columns, running totals in
 * player_counters, or the collection) and unlocks by itself once the stat reaches its target:
 * Karat and Dust are paid at once, and cosmetics become usable:
 *
 *   title   shown under the player's name instead of their level title
 *   avatar  'clan:<clan>' — the clan's emblem;  'portraits' — any card you own as your avatar
 *   back    '<clan>' — that clan's card back on any deck (players.card_back)
 *
 * Clan achievements are made from the card data (shared/clans.js), so a new clan gets its own
 * without code changes. Matches report what happened through recordMatch (socket/onlineMatch.js);
 * other unlocks (packs, crafting, friends) are announced over the socket ("achievements").
 */

const { pool } = require('../db/pool');
const { bump, best, counters } = require('./counters');

const FREE_AVATARS = ['profile_001', 'profile_002'];
const START_MORALE = 6000;
const CLUTCH_MORALE = 500;

// { id, name, desc, stat, target, reward: {karat, dust, title, avatar, back} }
const BASE = [
    { id: 'first_win',    name: 'First Blood',      desc: 'Win a match.',                             stat: 'wins', target: 1,    reward: { karat: 100, title: 'Brawler' } },
    { id: 'wins_25',      name: 'Street Fighter',   desc: 'Win 25 matches.',                          stat: 'wins', target: 25,   reward: { karat: 300, title: 'Street Fighter' } },
    { id: 'wins_100',     name: 'King of the Alley', desc: 'Win 100 matches.',                        stat: 'wins', target: 100,  reward: { karat: 1000, title: 'King of the Alley' } },
    { id: 'matches_50',   name: 'Regular',          desc: 'Play 50 matches.',                         stat: 'matches', target: 50, reward: { dust: 200 } },
    { id: 'online_win',   name: 'Real Rival',       desc: 'Beat another player online.',              stat: 'wins_online', target: 1,  reward: { karat: 150 } },
    { id: 'online_25',    name: 'Rival',            desc: 'Beat 25 players online.',                  stat: 'wins_online', target: 25, reward: { dust: 500, title: 'Rival' } },
    { id: 'ranked_win',   name: 'Contender',        desc: 'Win a Ranked match.',                      stat: 'wins_ranked', target: 1,  reward: { karat: 200, title: 'Contender' } },
    { id: 'hard_cpu',     name: 'Machine Breaker',  desc: 'Beat the hard CPU.',                       stat: 'wins_hard_cpu', target: 1, reward: { karat: 200 } },
    { id: 'flawless',     name: 'Untouchable',      desc: 'Win without losing any Morale.',           stat: 'flawless', target: 1, reward: { dust: 300, title: 'Untouchable' } },
    { id: 'clutch',       name: 'Comeback Kid',     desc: `Win with ${CLUTCH_MORALE} Morale or less.`, stat: 'clutch', target: 1, reward: { karat: 200, title: 'Comeback Kid' } },
    { id: 'kos_100',      name: 'Knockout Artist',  desc: "KO 100 of your opponents' characters.",    stat: 'kos', target: 100, reward: { karat: 300, title: 'Knockout Artist' } },
    { id: 'rampage',      name: 'Rampage',          desc: 'KO 5 characters in one match.',            stat: 'best_kos', target: 5, reward: { dust: 200 } },
    { id: 'promote_25',   name: 'Moving Up',        desc: 'Promote 25 characters.',                   stat: 'promotes', target: 25, reward: { dust: 200 } },
    { id: 'awaken',       name: 'Awakening',        desc: 'Awaken your leader.',                      stat: 'awakens', target: 1, reward: { karat: 150 } },
    { id: 'packs_10',     name: 'Pack Rat',         desc: 'Open 10 packs.',                           stat: 'packs', target: 10, reward: { dust: 300 } },
    { id: 'packs_50',     name: 'High Roller',      desc: 'Open 50 packs.',                           stat: 'packs', target: 50, reward: { title: 'High Roller', dust: 600 } },
    { id: 'collect_25',   name: 'Collector',        desc: 'Own 25 different cards.',                  stat: 'collection', target: 25, reward: { avatar: 'portraits', title: 'Collector' } },
    { id: 'legendary',    name: 'Legend in Hand',   desc: 'Own a Legendary card.',                    stat: 'legendaries', target: 1, reward: { dust: 200 } },
    { id: 'craft_1',      name: 'Craftsman',        desc: 'Craft a card.',                            stat: 'crafted', target: 1, reward: { title: 'Craftsman' } },
    { id: 'scrap_50',     name: 'Recycler',         desc: 'Scrap 50 cards.',                          stat: 'scrapped', target: 50, reward: { karat: 150 } },
    { id: 'level_10',     name: 'Veteran',          desc: 'Reach level 10.',                          stat: 'level', target: 10, reward: { karat: 300, title: 'Veteran' } },
    { id: 'level_25',     name: 'Old Guard',        desc: 'Reach level 25.',                          stat: 'level', target: 25, reward: { karat: 800, title: 'Old Guard' } },
    { id: 'friends_5',    name: 'Crew Boss',        desc: 'Have 5 friends.',                          stat: 'friends', target: 5, reward: { karat: 200, title: 'Crew Boss' } },
];

/** Every achievement: the fixed ones, then two per clan in the game. */
async function definitions() {
    const { clanList } = await import('../../shared/clans.js');
    const out = [...BASE];
    for (const c of clanList()) {
        out.push({ id: `clan_${c.id}_10`, name: `${c.name} Loyalist`, desc: `Win 10 matches with a ${c.name} deck.`,
            stat: `wins_clan_${c.id}`, target: 10, clan: c.id,
            reward: { back: c.id, avatar: `clan:${c.id}`, title: `${c.name} Loyalist` } });
        out.push({ id: `clan_${c.id}_50`, name: `${c.name} Legend`, desc: `Win 50 matches with a ${c.name} deck.`,
            stat: `wins_clan_${c.id}`, target: 50, clan: c.id,
            reward: { dust: 500, title: `${c.name} Legend` } });
    }
    return out;
}

/** Everything achievements are measured against, for one player. */
async function stats(db, playerId) {
    const { gameCardIds } = require('./packOpener');
    const [{ rows: [p] }, totals, { rows: owned }, { rows: [f] }] = await Promise.all([
        db.query('SELECT wins, losses, draws, level FROM players WHERE id = $1', [playerId]),
        counters(db, playerId),
        db.query(`SELECT c.art_url, c.rarity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
                  WHERE pi.player_id = $1 AND c.art_url = ANY($2)`, [playerId, await gameCardIds()]),
        db.query(`SELECT COUNT(*)::int AS n FROM friendships WHERE status = 'accepted'
                  AND (requester_id = $1 OR addressee_id = $1)`, [playerId]),
    ]);
    if (!p) return null;
    return {
        ...totals,
        wins: p.wins, level: p.level, matches: p.wins + p.losses + p.draws,
        collection: owned.length, legendaries: owned.filter(r => r.rarity >= 5).length,
        friends: f.n,
    };
}

/** Unlock everything the player has earned but doesn't have yet, paying its Karat and Dust. → the new ones */
async function check(playerId) {
    if (!playerId || String(playerId).startsWith('cpu:')) return [];
    const [defs, st, { rows }] = await Promise.all([
        definitions(), stats(pool, playerId),
        pool.query('SELECT achievement_id FROM player_achievements WHERE player_id = $1', [playerId]),
    ]);
    if (!st) return [];
    const have = new Set(rows.map(r => r.achievement_id));
    const fresh = [];
    for (const a of defs) {
        if (have.has(a.id) || (st[a.stat] || 0) < a.target) continue;
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            // The insert is the claim: a second check running at the same time pays nothing
            const { rowCount } = await client.query(
                `INSERT INTO player_achievements (player_id, achievement_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
                [playerId, a.id]);
            if (rowCount && (a.reward.karat || a.reward.dust)) {
                await client.query('UPDATE players SET karat = karat + $1, dust = dust + $2 WHERE id = $3',
                    [a.reward.karat || 0, a.reward.dust || 0, playerId]);
            }
            await client.query('COMMIT');
            if (rowCount) fresh.push(publicView(a));
        } catch (err) {
            await client.query('ROLLBACK');
            console.error('[Achievements] unlock failed:', err.message);
        } finally {
            client.release();
        }
    }
    return fresh;
}

const publicView = (a) => ({ id: a.id, name: a.name, desc: a.desc, reward: a.reward });

// Unlocks outside a match are announced over the player's socket (server.js sets this)
let notifier = null;
function setNotifier(fn) { notifier = fn; }

/** check(), then tell the player about anything new. For unlocks outside matches. */
async function checkAndAnnounce(playerId) {
    try {
        const fresh = await check(playerId);
        if (fresh.length) notifier?.(playerId, 'achievements', { unlocked: fresh });
        return fresh;
    } catch (err) {
        console.error('[Achievements] check failed:', err.message);
        return [];
    }
}

/**
 * A finished match, from the server's own record of it. Updates the player's totals and returns
 * the achievements it unlocked (sent with mp:over).
 *   m = { playerId, outcome, mode, difficulty, clan, kos, promotes, awakens, morale }
 */
async function recordMatch(m) {
    if (!m.playerId || String(m.playerId).startsWith('cpu:')) return [];
    const win = m.outcome === 'win';
    const id = m.playerId;
    try {
        await bump(pool, id, 'kos', m.kos || 0);
        await best(pool, id, 'best_kos', m.kos || 0);
        await bump(pool, id, 'promotes', m.promotes || 0);
        await bump(pool, id, 'awakens', m.awakens || 0);
        if (win) {
            const cpu = m.mode === 'cpu' || m.mode === 'cpu_ranked';
            if (!cpu) await bump(pool, id, 'wins_online');
            if (m.mode === 'ranked' || m.mode === 'cpu_ranked') await bump(pool, id, 'wins_ranked');
            if (m.mode === 'cpu_ranked' || (m.mode === 'cpu' && m.difficulty === 'hard')) await bump(pool, id, 'wins_hard_cpu');
            if (m.morale >= START_MORALE) await bump(pool, id, 'flawless');
            if (m.morale > 0 && m.morale <= CLUTCH_MORALE) await bump(pool, id, 'clutch');
            if (m.clan && /^[a-z0-9_]+$/.test(m.clan)) await bump(pool, id, `wins_clan_${m.clan}`);
        }
        return await check(id);
    } catch (err) {
        console.error('[Achievements] recordMatch failed:', err.message);
        return [];
    }
}

/** Every achievement with the player's progress, plus what they've unlocked to wear. */
async function overview(playerId) {
    await check(playerId);   // catches up on anything earned before achievements existed
    const [defs, st, { rows }, { rows: [p] }] = await Promise.all([
        definitions(), stats(pool, playerId),
        pool.query('SELECT achievement_id, unlocked_at FROM player_achievements WHERE player_id = $1', [playerId]),
        pool.query('SELECT avatar_url, title, card_back FROM players WHERE id = $1', [playerId]),
    ]);
    const at = new Map(rows.map(r => [r.achievement_id, r.unlocked_at]));
    return {
        achievements: defs.map(a => ({
            ...publicView(a), clan: a.clan || null, target: a.target,
            progress: Math.min(a.target, st?.[a.stat] || 0),
            unlocked: at.has(a.id), unlockedAt: at.get(a.id) || null,
        })),
        cosmetics: await cosmetics(playerId, defs, new Set(at.keys())),
        equipped: { avatar: p?.avatar_url || 'profile_001', title: p?.title || null, back: p?.card_back || null },
    };
}

/** What the player may wear: { avatars, portraits, titles: [{id, text}], backs } */
async function cosmetics(playerId, defs, unlocked) {
    defs = defs || await definitions();
    if (!unlocked) {
        const { rows } = await pool.query('SELECT achievement_id FROM player_achievements WHERE player_id = $1', [playerId]);
        unlocked = new Set(rows.map(r => r.achievement_id));
    }
    const got = defs.filter(a => unlocked.has(a.id));
    return {
        avatars: [...FREE_AVATARS, ...got.map(a => a.reward.avatar).filter(v => v && v !== 'portraits')],
        portraits: got.some(a => a.reward.avatar === 'portraits'),
        titles: got.filter(a => a.reward.title).map(a => ({ id: a.id, text: a.reward.title })),
        backs: ['default', ...got.map(a => a.reward.back).filter(Boolean)],
    };
}

/** The title text for a player's chosen title (players.title holds the achievement id). */
async function titleText(achievementId) {
    if (!achievementId) return null;
    const a = (await definitions()).find(d => d.id === achievementId);
    return a?.reward.title || null;
}

/**
 * Change what the player wears. Each field is optional; null resets title/back to the default.
 * → { ok: true } or { error }
 */
async function equip(playerId, { avatar, title, back } = {}) {
    const mine = await cosmetics(playerId);
    const sets = [], params = [];
    if (avatar !== undefined) {
        let ok = typeof avatar === 'string' && mine.avatars.includes(avatar);
        if (!ok && typeof avatar === 'string' && avatar.startsWith('card:') && mine.portraits) {
            const { rowCount } = await pool.query(
                `SELECT 1 FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
                 WHERE pi.player_id = $1 AND c.art_url = $2`, [playerId, avatar.slice(5)]);
            ok = rowCount > 0;
        }
        if (!ok) return { error: "You haven't unlocked that avatar." };
        params.push(avatar); sets.push(`avatar_url = $${params.length}`);
    }
    if (title !== undefined) {
        if (title !== null && !mine.titles.some(t => t.id === title)) return { error: "You haven't unlocked that title." };
        params.push(title); sets.push(`title = $${params.length}`);
    }
    if (back !== undefined) {
        if (back !== null && !mine.backs.includes(back)) return { error: "You haven't unlocked that card back." };
        params.push(back); sets.push(`card_back = $${params.length}`);
    }
    if (!sets.length) return { error: 'Nothing to change.' };
    params.push(playerId);
    await pool.query(`UPDATE players SET ${sets.join(', ')} WHERE id = $${params.length}`, params);
    return { ok: true };
}

module.exports = { definitions, check, checkAndAnnounce, recordMatch, overview, cosmetics, equip, titleText, setNotifier, FREE_AVATARS };
