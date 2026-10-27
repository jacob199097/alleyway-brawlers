'use strict';

/**
 * TURF DEFENSE rewards and progress (socket/coopMatch.js runs the matches; the bosses, their levels
 * and rewards are in godot/data/bosses.json, read through shared/turf.js).
 *
 * boss_clears keeps each player's attempts and clears of each boss level. Level 1 of a boss is open
 * to everyone; each level after it opens once the one before is cleared. The first clear of a level
 * pays its first_clear (Karat, XP, free packs; level 1 also the boss's prize card), every clear after
 * it pays its clear, and a defeat pays the file's loss. Counters for the achievements: turf_clears,
 * turf_nightmare (a level-3 clear) and turf_bosses (bosses beaten at least once).
 */

const { pool } = require('../db/pool');
const { bump } = require('./counters');
const { calcLevel, levelRewards } = require('./postMatch');

const turf = import('../../shared/turf.js');

/** { bossId: {level: {clears, attempts, best_turns}} } */
async function clearsOf(db, playerId) {
    const { rows } = await db.query(
        'SELECT boss_id, level, clears, attempts, best_turns FROM boss_clears WHERE player_id = $1', [playerId]);
    const out = {};
    for (const r of rows) {
        out[r.boss_id] = out[r.boss_id] || {};
        out[r.boss_id][r.level] = { clears: r.clears, attempts: r.attempts, best_turns: r.best_turns };
    }
    return out;
}

/** Whether a player may fight this boss level: level 1 always, the others once the one before is cleared. */
function unlocked(clears, bossId, level) {
    return Number(level) <= 1 || (clears?.[bossId]?.[Number(level) - 1]?.clears || 0) > 0;
}

/** The Turf Defense screen: every boss, what each level pays and whether it's open, cleared, and
 *  (level 1) whether its prize card has been won. */
async function status(playerId) {
    const { BOSSES, BOSS_DATA, bossInfo } = await turf;
    const clears = await clearsOf(pool, playerId);
    return {
        loss: BOSS_DATA.loss || {},
        bosses: BOSSES.map(b => ({
            ...bossInfo(b, b.levels[0]),
            prize_won: (clears[b.id]?.[1]?.clears || 0) > 0,
            levels: b.levels.map(l => ({
                level: l.level, name: l.name, morale: l.morale, draw: l.draw || 0, authority: l.authority || 0,
                phases: (l.phases || []).map(p => ({ below: p.below, label: p.label })),
                first_clear: l.first_clear || {}, clear: l.clear || {},
                unlocked: unlocked(clears, b.id, l.level),
                clears: clears[b.id]?.[l.level]?.clears || 0,
                attempts: clears[b.id]?.[l.level]?.attempts || 0,
                best_turns: clears[b.id]?.[l.level]?.best_turns ?? null,
            })),
        })),
    };
}

/**
 * A finished Turf Defense match, as the server saw it → the player's rewards:
 *   { won, first, bossId, level, karatEarned, xpEarned, packs, prize (a game card ID or null),
 *     newKarat, newXp, newLevel, leveledUp, packsEarned, avatarsUnlocked, unlockedNext }
 */
async function resolve({ playerId, bossId, level, won, turns }) {
    const { findBoss, bossLevel, BOSS_DATA } = await turf;
    const boss = findBoss(bossId);
    const lv = bossLevel(boss, level);
    if (!boss || !lv) throw new Error(`No boss level ${bossId} ${level}`);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [before] } = await client.query(
            'SELECT clears FROM boss_clears WHERE player_id = $1 AND boss_id = $2 AND level = $3 FOR UPDATE', [playerId, bossId, lv.level]);
        const first = won && !(before?.clears > 0);
        await client.query(
            `INSERT INTO boss_clears (player_id, boss_id, level, clears, attempts, best_turns, first_cleared_at)
             VALUES ($1, $2, $3, $4, 1, $5, CASE WHEN $4 > 0 THEN NOW() END)
             ON CONFLICT (player_id, boss_id, level) DO UPDATE SET
                clears = boss_clears.clears + EXCLUDED.clears,
                attempts = boss_clears.attempts + 1,
                best_turns = CASE WHEN EXCLUDED.best_turns IS NULL THEN boss_clears.best_turns
                                  ELSE LEAST(COALESCE(boss_clears.best_turns, EXCLUDED.best_turns), EXCLUDED.best_turns) END,
                first_cleared_at = COALESCE(boss_clears.first_cleared_at, EXCLUDED.first_cleared_at)`,
            [playerId, bossId, lv.level, won ? 1 : 0, won ? Math.max(1, Math.trunc(Number(turns) || 0)) : null]);
        const pay = won ? (first ? lv.first_clear : lv.clear) || {} : BOSS_DATA.loss || {};
        const karat = Math.max(0, Math.trunc(pay.karat || 0));
        const xp = Math.max(0, Math.trunc(pay.xp || 0));
        const packs = Math.max(0, Math.trunc(pay.packs || 0));
        const { rows: [p] } = await client.query('SELECT karat, xp, level FROM players WHERE id = $1 FOR UPDATE', [playerId]);
        if (!p) throw new Error(`Player ${playerId} not found`);
        const newXp = p.xp + xp;
        const newLevel = calcLevel(newXp);
        const lvUp = levelRewards(p.level, newLevel);
        const { rows: [after] } = await client.query(
            `UPDATE players SET karat = karat + $2, xp = $3, level = $4, free_packs = free_packs + $5,
                    wins = wins + $6, losses = losses + $7
              WHERE id = $1 RETURNING karat`,
            [playerId, karat, newXp, newLevel, packs + lvUp.packsEarned, won ? 1 : 0, won ? 0 : 1]);
        // The first clear of level 1: the boss's prize card (a Striver: with its higher levels, for the Hideout)
        let prize = null;
        const prizeCards = [];
        if (first && lv.level === 1 && boss.prize) {
            const { prizeLine } = await turf;
            for (const id of prizeLine(boss.prize)) {
                const { rows: [card] } = await client.query('SELECT id FROM cards WHERE art_url = $1', [id]);
                if (!card) {
                    console.error(`[Turf] Prize card ${id} isn't in the cards table`);
                    continue;
                }
                await client.query(
                    `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)
                     ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = player_inventory.quantity + 1`,
                    [playerId, card.id]);
                prizeCards.push(id);
            }
            if (prizeCards.length) prize = boss.prize;
        }
        if (won) {
            await bump(client, playerId, 'turf_clears');
            if (lv.level >= 3) await bump(client, playerId, 'turf_nightmare');
            if (first && lv.level === 1) await bump(client, playerId, 'turf_bosses');
        }
        await client.query('COMMIT');
        return {
            outcome: won ? 'win' : 'loss', won, first, bossId, level: lv.level,
            karatEarned: karat, xpEarned: xp, packs, prize, prizeCards,
            newKarat: after.karat, newXp, newLevel, leveledUp: newLevel > p.level, ...lvUp,
            unlockedNext: first && !!bossLevel(boss, lv.level + 1),
        };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { status, resolve, clearsOf, unlocked };
