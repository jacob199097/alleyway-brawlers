'use strict';

/**
 * CLAN MASTERY: experience for each clan a player plays (the clan their deck is mostly made of).
 * Every finished match counts (online and CPU): a win 100 XP, anything else 40. Ten levels; each
 * one past the first pays something (REWARDS): Karat, a profile picture of one of the clan's
 * rarest characters, or a title. Titles and pictures are worn like achievement ones
 * (economy/achievements.js cosmetics: title ids "mastery:<clan>:<level>").
 */

const { pool } = require('../db/pool');

/** XP needed for each level (level 1 = 0). */
const LEVELS = [0, 300, 700, 1200, 1800, 2500, 3300, 4200, 5200, 6300];
const XP = { win: 100, other: 40 };
/** What each level pays: karat, avatar (n-th rarest character of the clan), title. */
const REWARDS = {
    2: { karat: 150 },
    3: { avatar: 0 },
    4: { title: 'Veteran' },
    5: { karat: 300 },
    6: { avatar: 1 },
    7: { title: 'Elite' },
    8: { karat: 500 },
    9: { avatar: 2 },
    10: { title: 'Legend' },
};

const levelOf = (xp) => LEVELS.filter(t => xp >= t).length;

/** The clan's characters for mastery pictures: rarest first, not ones everyone has already. */
async function pictures(clan) {
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const { freeAvatars } = await import('../../shared/clans.js');
    const free = new Set(freeAvatars());
    return Object.values(CARD_CATALOG)
        .filter(c => c.clan === clan && c.cardType === 'gang_member' && !c.token && !free.has(`card:${c.id}`))
        .sort((a, b) => (b.rarity || 1) - (a.rarity || 1) || (Number(b.level) || 1) - (Number(a.level) || 1) || a.id.localeCompare(b.id))
        .map(c => `card:${c.id}`);
}

async function clanName(clan) {
    const { clanList } = await import('../../shared/clans.js');
    return clanList().find(c => c.id === clan)?.name || clan;
}

/** A level's reward as the client shows it: {karat} | {avatar: "card:id"} | {title: "Nebula Veteran"}. */
async function rewardAt(clan, level) {
    const r = REWARDS[level];
    if (!r) return {};
    if (r.karat) return { karat: r.karat };
    if (r.title) return { title: `${await clanName(clan)} ${r.title}` };
    const pics = await pictures(clan);
    return pics[r.avatar] ? { avatar: pics[r.avatar] } : { karat: 200 };   // (a clan with few cards: Karat instead)
}

/**
 * A finished match for one player: adds its XP, pays any levels reached (Karat straight away;
 * pictures and titles become wearable) → banners for the post-match screen.
 */
async function record(playerId, clan, outcome) {
    if (!clan || !/^[a-z0-9_]+$/.test(clan)) return [];
    const gain = outcome === 'win' ? XP.win : XP.other;
    const { rows: [row] } = await pool.query(
        `INSERT INTO clan_mastery (player_id, clan, xp, games, wins) VALUES ($1, $2, $3, 1, $4)
         ON CONFLICT (player_id, clan) DO UPDATE SET xp = clan_mastery.xp + EXCLUDED.xp,
             games = clan_mastery.games + 1, wins = clan_mastery.wins + EXCLUDED.wins
         RETURNING xp`, [playerId, clan, gain, outcome === 'win' ? 1 : 0]);
    const before = levelOf(row.xp - gain), after = levelOf(row.xp);
    const name = await clanName(clan);
    const out = [];
    for (let lv = before + 1; lv <= after; lv++) {
        const reward = await rewardAt(clan, lv);
        if (reward.karat) await pool.query('UPDATE players SET karat = karat + $1 WHERE id = $2', [reward.karat, playerId]);
        out.push({ id: `mastery:${clan}:${lv}`, heading: 'CLAN MASTERY', name: `${name} Mastery ${lv}`,
            desc: `Level ${lv} with ${name}`, reward });
    }
    return out;
}

/** Every clan's mastery for a player (the profile and achievements screens). */
async function overview(playerId) {
    const { clanList } = await import('../../shared/clans.js');
    const { rows } = await pool.query('SELECT clan, xp, games, wins FROM clan_mastery WHERE player_id = $1', [playerId]);
    const mine = new Map(rows.map(r => [r.clan, r]));
    const out = [];
    for (const c of clanList()) {
        const r = mine.get(c.id) || { xp: 0, games: 0, wins: 0 };
        const level = levelOf(r.xp);
        const rewards = [];
        for (let lv = 2; lv <= LEVELS.length; lv++) rewards.push({ level: lv, reward: await rewardAt(c.id, lv) });
        out.push({ clan: c.id, name: c.name, color: c.color, level, max: LEVELS.length, xp: r.xp,
            floor: LEVELS[level - 1], next: LEVELS[level] ?? null, games: r.games, wins: r.wins, rewards });
    }
    return out;
}

/** The pictures and titles a player's mastery levels have unlocked: {avatars, titles: [{id, text}]}. */
async function cosmetics(playerId) {
    const { rows } = await pool.query('SELECT clan, xp FROM clan_mastery WHERE player_id = $1', [playerId]);
    const avatars = [], titles = [];
    for (const r of rows) {
        for (let lv = 2; lv <= levelOf(r.xp); lv++) {
            const reward = await rewardAt(r.clan, lv);
            if (reward.avatar) avatars.push(reward.avatar);
            if (reward.title) titles.push({ id: `mastery:${r.clan}:${lv}`, text: reward.title });
        }
    }
    return { avatars, titles };
}

/** A mastery title's text from its id ("mastery:nebula:4" → "Nebula Veteran"), or null. */
async function titleText(id) {
    const m = /^mastery:([a-z0-9_]+):(\d+)$/.exec(String(id || ''));
    if (!m) return null;
    return (await rewardAt(m[1], Number(m[2]))).title || null;
}

module.exports = { record, overview, cosmetics, titleText, LEVELS, REWARDS };
