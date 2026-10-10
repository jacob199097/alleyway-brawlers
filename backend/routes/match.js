'use strict';

const express              = require('express');
const { requireAuth }      = require('./middleware');
const { pool }             = require('../db/pool');
const { resolveSoloMatch } = require('../economy/postMatch');
const { incrementDailyQuest } = require('./quests');

const router = express.Router();

// Results that a client reports can't be trusted, so this route no longer pays rewards: CPU
// matches now run on the server (socket/onlineMatch.js, mp:cpu) and are rewarded there.
// It still closes the session and records the outcome, for older clients.
// Session rules (kept):
//   * a session can be completed once, by its owner, and only after a minimum
//     real-time duration; starting a new match abandons the previous session
//   * rewarded completions are capped per day
//   * cards-played quest progress is capped per match
const MIN_SOLO_MATCH_SECS       = 60;
const MAX_SESSION_AGE_HOURS     = 3;
const DAILY_SOLO_REWARD_CAP     = 25;
const MAX_CARDS_PLAYED_PER_MATCH = 40;

/**
 * POST /api/match/start
 * Called by the client when a solo (AI) duel begins.
 * Body: { ranked?: boolean }  →  { matchId }
 */
router.post('/start', requireAuth, async (req, res) => {
    const ranked = req.body?.ranked === true;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(
            `UPDATE solo_matches SET completed_at = NOW(), outcome = 'abandoned'
             WHERE  player_id = $1 AND completed_at IS NULL`,
            [req.playerId]
        );
        const { rows } = await client.query(
            'INSERT INTO solo_matches (player_id, ranked) VALUES ($1, $2) RETURNING id',
            [req.playerId, ranked]
        );
        await client.query('COMMIT');
        res.json({ matchId: rows[0].id });
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('[match/start]', err.message);
        res.status(500).json({ error: 'Failed to start match.' });
    } finally {
        client.release();
    }
});

/**
 * POST /api/match/complete
 * Called by the client after a solo (AI) duel ends.
 * Body: { matchId, result: 'win'|'loss'|'draw', cardsPlayed, playerMorale, opponentMorale, turns }
 */
router.post('/complete', requireAuth, async (req, res) => {
    const playerId = req.playerId;
    const { matchId, result, cardsPlayed, playerMorale, opponentMorale, turns } = req.body;

    if (!['win', 'loss', 'draw'].includes(result)) {
        return res.status(400).json({ error: 'Invalid result value.' });
    }
    if (typeof matchId !== 'string' || !/^[0-9a-f-]{36}$/i.test(matchId)) {
        return res.status(400).json({ error: 'Invalid matchId.' });
    }

    try {
        const { rows: [session] } = await pool.query(
            `SELECT completed_at,
                    EXTRACT(EPOCH FROM (NOW() - started_at))::int AS age_secs
             FROM   solo_matches WHERE id = $1 AND player_id = $2`,
            [matchId, playerId]
        );
        if (!session)             return res.status(404).json({ error: 'Match not found.' });
        if (session.completed_at) return res.status(409).json({ error: 'Match already completed.' });
        if (session.age_secs > MAX_SESSION_AGE_HOURS * 3600) {
            return res.status(410).json({ error: 'Match session expired.' });
        }
        if (session.age_secs < MIN_SOLO_MATCH_SECS) {
            return res.status(400).json({ error: 'Match too short to record.' });
        }

        const { rows: [{ rewarded_today }] } = await pool.query(
            `SELECT COUNT(*)::int AS rewarded_today FROM solo_matches
             WHERE  player_id = $1 AND rewarded AND completed_at >= date_trunc('day', NOW())`,
            [playerId]
        );
        const rewardable = false;   // see the note at the top: client-reported results don't pay
        void rewarded_today;

        // Claim the session atomically — a concurrent second request updates 0 rows.
        const { rowCount } = await pool.query(
            `UPDATE solo_matches SET completed_at = NOW(), outcome = $1, rewarded = $2
             WHERE  id = $3 AND player_id = $4 AND completed_at IS NULL`,
            [result, rewardable, matchId, playerId]
        );
        if (!rowCount) return res.status(409).json({ error: 'Match already completed.' });

        if (!rewardable) {
            return res.json({ ok: true, rewards: {
                outcome: result, karatEarned: 0, xpEarned: 0, firstWinBonus: false,
                leveledUp: false, rankChanged: false, rankPointDelta: 0, clientReported: true,
            }});
        }

        let rewards;
        try {
            rewards = await resolveSoloMatch({
                playerId,
                outcome: result,
                matchMeta: { playerMorale, opponentMorale, turns },
            });
        } catch (err) {
            // Release the session so the player can retry instead of losing the reward
            await pool.query(
                `UPDATE solo_matches SET completed_at = NULL, outcome = NULL, rewarded = FALSE WHERE id = $1`,
                [matchId]
            );
            throw err;
        }

        const played = Math.min(MAX_CARDS_PLAYED_PER_MATCH, Math.max(0, Math.floor(Number(cardsPlayed) || 0)));
        if (played > 0) incrementDailyQuest(playerId, 'daily_play_10', played).catch(() => {});

        res.json({ ok: true, rewards });
    } catch (err) {
        console.error('[match/complete]', err.message);
        res.status(500).json({ error: 'Failed to record match result.' });
    }
});

module.exports = router;
