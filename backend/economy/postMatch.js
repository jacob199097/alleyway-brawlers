'use strict';

const { pool } = require('../db/pool');
const { recordDailyWin } = require('../routes/quests');

// ── XP Rewards ────────────────────────────────────────────────────────────────
const BASE_XP = {
    win:  100,
    loss:  20,
    draw:  60,
};
const FIRST_WIN_BONUS_XP  = 100;   // awarded once per calendar day on first win

// ── Karat & Rank Point Rewards ────────────────────────────────────────────────
const REWARDS = {
    win:  { karat: 50,  rankPoints:  25 },
    loss: { karat: 10,  rankPoints: -10 },
    draw: { karat: 20,  rankPoints:   5 },
};

// ── Rank Tier Thresholds ──────────────────────────────────────────────────────
const RANK_TIERS = [
    { tier: 'rookie',       min:    0 },
    { tier: 'street_tough', min:  200 },
    { tier: 'enforcer',     min:  500 },
    { tier: 'underboss',    min: 1000 },
    { tier: 'kingpin',      min: 1800 },
    { tier: 'legend',       min: 3000 },
];

// ── Level Thresholds (cumulative XP to reach each level) ─────────────────────
// Formula: XP to advance from level N = floor(100 * N^1.5)
// Cumulative XP to reach level N = sum of floor(100 * i^1.5) for i = 1..N-1
const LEVEL_THRESHOLDS = (() => {
    const thresholds = [0]; // index 0 unused; index 1 = 0 XP (starting level)
    thresholds[1] = 0;
    for (let lvl = 2; lvl <= 50; lvl++) {
        thresholds[lvl] = thresholds[lvl - 1] + Math.floor(100 * Math.pow(lvl - 1, 1.5));
    }
    return thresholds;
})();

// ── Helpers ───────────────────────────────────────────────────────────────────

function calcLevel(totalXp) {
    let level = 1;
    for (let lvl = 50; lvl >= 1; lvl--) {
        if (totalXp >= LEVEL_THRESHOLDS[lvl]) {
            level = lvl;
            break;
        }
    }
    return level;
}

function calcRank(rankPoints) {
    const clamped = Math.max(0, rankPoints);
    let tier = 'rookie';
    for (const entry of RANK_TIERS) {
        if (clamped >= entry.min) tier = entry.tier;
    }
    return { tier, points: clamped };
}

// ── Core Export ───────────────────────────────────────────────────────────────

async function resolveMatch({ winnerId, loserId, p1Id, p2Id, matchMeta = {} }) {
    const isDraw = !winnerId;

    const assignments = isDraw
        ? [{ playerId: p1Id, outcome: 'draw' }, { playerId: p2Id, outcome: 'draw' }]
        : [{ playerId: winnerId, outcome: 'win' }, { playerId: loserId, outcome: 'loss' }];

    const client = await pool.connect();
    const results = {};

    try {
        await client.query('BEGIN');

        // Record match history
        const matchInsert = await client.query(
            `INSERT INTO matches
               (player_one_id, player_two_id, winner_id,
                p1_morale_end, p2_morale_end, turns, duration_secs)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             RETURNING id`,
            [
                isDraw ? p1Id : winnerId,
                isDraw ? p2Id : loserId,
                isDraw ? null : winnerId,
                matchMeta.p1MoraleEnd  ?? null,
                matchMeta.p2MoraleEnd  ?? null,
                matchMeta.turns        ?? null,
                matchMeta.durationSecs ?? null,
            ]
        );
        const matchId = matchInsert.rows[0].id;

        for (const { playerId, outcome } of assignments) {
            const reward = REWARDS[outcome];
            // Casual and friendly matches don't move Rank Points
            const rankDelta = matchMeta.ranked === false ? 0 : reward.rankPoints;

            const { rows } = await client.query(
                `SELECT karat, xp, level, rank_points, wins, losses, draws, first_win_date
                 FROM   players
                 WHERE  id = $1
                 FOR UPDATE`,
                [playerId]
            );
            if (!rows.length) throw new Error(`Player ${playerId} not found`);
            const p = rows[0];

            // XP: base + first-win-of-day bonus (wins only)
            let xpEarned = BASE_XP[outcome];
            let firstWinBonus = false;
            const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

            if (outcome === 'win') {
                const lastWinDate = p.first_win_date
                    ? p.first_win_date.toISOString().slice(0, 10)
                    : null;
                if (lastWinDate !== today) {
                    xpEarned     += FIRST_WIN_BONUS_XP;
                    firstWinBonus = true;
                }
            }

            const newXp      = p.xp + xpEarned;
            const newLevel   = calcLevel(newXp);
            const newKarat   = p.karat + reward.karat;
            const newRankPts = p.rank_points + rankDelta;
            const { tier: newRank, points: clampedRankPts } = calcRank(newRankPts);

            const newWins   = p.wins   + (outcome === 'win'  ? 1 : 0);
            const newLosses = p.losses + (outcome === 'loss' ? 1 : 0);
            const newDraws  = p.draws  + (outcome === 'draw' ? 1 : 0);

            await client.query(
                `UPDATE players SET
                    karat          = $1,
                    xp             = $2,
                    level          = $3,
                    rank_points    = $4,
                    rank           = $5,
                    wins           = $6,
                    losses         = $7,
                    draws          = $8,
                    first_win_date = CASE WHEN $9 THEN $10::DATE ELSE first_win_date END
                 WHERE id = $11`,
                [
                    newKarat, newXp, newLevel, clampedRankPts, newRank,
                    newWins, newLosses, newDraws,
                    firstWinBonus, today,
                    playerId,
                ]
            );

            results[playerId] = {
                outcome,
                karatEarned:    reward.karat,
                xpEarned,
                firstWinBonus,
                newKarat,
                newXp,
                newLevel,
                leveledUp:      newLevel > p.level,
                newRank,
                rankChanged:    newRank !== p.rank,
                rankPointDelta: rankDelta,
                matchId,
            };
        }

        await client.query('COMMIT');
        return results;

    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

// ── Solo (AI) match: update one real player only ──────────────────────────────

async function resolveSoloMatch({ playerId, outcome, matchMeta = {} }) {
    if (!['win', 'loss', 'draw'].includes(outcome)) throw new Error('Invalid outcome');
    const reward = REWARDS[outcome];
    // Only Ranked matches move Rank Points
    const rankDelta = matchMeta.ranked === true ? reward.rankPoints : 0;

    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        const { rows } = await client.query(
            `SELECT karat, xp, level, rank_points, rank, wins, losses, draws, first_win_date
             FROM   players
             WHERE  id = $1
             FOR UPDATE`,
            [playerId]
        );
        if (!rows.length) throw new Error(`Player ${playerId} not found`);
        const p = rows[0];

        const scale    = Number(matchMeta.rewardScale ?? 1);
        let xpEarned   = Math.round(BASE_XP[outcome] * scale);
        let firstWinBonus = false;
        const today    = new Date().toISOString().slice(0, 10);

        if (outcome === 'win') {
            const lastWinDate = p.first_win_date
                ? p.first_win_date.toISOString().slice(0, 10)
                : null;
            if (lastWinDate !== today) {
                xpEarned     += FIRST_WIN_BONUS_XP;
                firstWinBonus = true;
            }
        }

        const newXp       = p.xp + xpEarned;
        const newLevel    = calcLevel(newXp);
        const karatEarned = Math.round(reward.karat * scale);
        const newKarat    = p.karat + karatEarned;
        const newRankPts  = p.rank_points + rankDelta;
        const { tier: newRank, points: clampedRankPts } = calcRank(newRankPts);

        const newWins   = p.wins   + (outcome === 'win'  ? 1 : 0);
        const newLosses = p.losses + (outcome === 'loss' ? 1 : 0);
        const newDraws  = p.draws  + (outcome === 'draw' ? 1 : 0);

        await client.query(
            `UPDATE players SET
                karat          = $1,
                xp             = $2,
                level          = $3,
                rank_points    = $4,
                rank           = $5,
                wins           = $6,
                losses         = $7,
                draws          = $8,
                first_win_date = CASE WHEN $9 THEN $10::DATE ELSE first_win_date END
             WHERE id = $11`,
            [
                newKarat, newXp, newLevel, clampedRankPts, newRank,
                newWins, newLosses, newDraws,
                firstWinBonus, today,
                playerId,
            ]
        );

        await client.query('COMMIT');

        if (outcome === 'win') {
            recordDailyWin(playerId).catch(() => {});
        }

        return {
            outcome,
            karatEarned,
            xpEarned,
            firstWinBonus,
            newKarat,
            newXp,
            newLevel,
            leveledUp:      newLevel > p.level,
            newRank,
            rankChanged:    newRank !== p.rank,
            rankPointDelta: rankDelta,
        };

    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

// CPU matches run on the server (socket/onlineMatch.js), so the result is trusted. Each one is
// logged in solo_matches, and only DAILY_CPU_REWARD_CAP per day pay out.
const DAILY_CPU_REWARD_CAP = 25;

// CPU difficulty scales Karat and XP (Ranked always plays the hard CPU)
const CPU_REWARD_SCALE = { easy: 0.5, normal: 1, hard: 1.5 };

async function resolveCpuMatch({ playerId, outcome, ranked = false, difficulty = 'normal' }) {
    const { rows: [{ rewarded_today }] } = await pool.query(
        `SELECT COUNT(*)::int AS rewarded_today FROM solo_matches
         WHERE  player_id = $1 AND rewarded AND completed_at >= date_trunc('day', NOW())`,
        [playerId]
    );
    const rewardable = rewarded_today < DAILY_CPU_REWARD_CAP;
    await pool.query(
        `INSERT INTO solo_matches (player_id, ranked, completed_at, outcome, rewarded)
         VALUES ($1, $2, NOW(), $3, $4)`,
        [playerId, ranked, outcome, rewardable]
    );
    if (!rewardable) {
        return { outcome, karatEarned: 0, xpEarned: 0, firstWinBonus: false, leveledUp: false,
            rankChanged: false, rankPointDelta: 0, dailyCapReached: true };
    }
    return resolveSoloMatch({ playerId, outcome, matchMeta: { ranked, rewardScale: ranked ? 1 : CPU_REWARD_SCALE[difficulty] ?? 1 } });
}

module.exports = { resolveMatch, resolveSoloMatch, resolveCpuMatch, calcLevel, calcRank, LEVEL_THRESHOLDS };
