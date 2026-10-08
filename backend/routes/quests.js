'use strict';

const router         = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }       = require('../db/pool');

// ── Quest definitions ─────────────────────────────────────────────────────────

const DAILY_WIN_QUESTS = [
    { id: 'daily_win_1', label: 'Win 1 Match',   target: 1, rewardKarat: 50,  rewardContraband: 0 },
    { id: 'daily_win_3', label: 'Win 3 Matches',  target: 3, rewardKarat: 150, rewardContraband: 0 },
];

const DAILY_OTHER_QUESTS = [
    { id: 'daily_play_10', label: 'Play 10 Cards',    target: 10, rewardKarat: 50,  rewardContraband: 0 },
    { id: 'daily_pack',    label: 'Open a Crew Pack', target: 1,  rewardKarat: 0,   rewardContraband: 15 },
];

const MAIN_QUESTS = [
    { id: 'wins_10',    label: 'Win 10 Matches',  field: 'wins',  target: 10,  rewardKarat: 200 },
    { id: 'wins_50',    label: 'Win 50 Matches',  field: 'wins',  target: 50,  rewardKarat: 500 },
    { id: 'wins_100',   label: 'Win 100 Matches', field: 'wins',  target: 100, rewardKarat: 1000 },
    { id: 'reach_lv5',  label: 'Reach Level 5',   field: 'level', target: 5,   rewardKarat: 100 },
    { id: 'reach_lv10', label: 'Reach Level 10',  field: 'level', target: 10,  rewardKarat: 300 },
    { id: 'reach_lv20', label: 'Reach Level 20',  field: 'level', target: 20,  rewardKarat: 800 },
];

const ALL_QUESTS = [...DAILY_WIN_QUESTS, ...DAILY_OTHER_QUESTS, ...MAIN_QUESTS];

// ── GET /api/quests ───────────────────────────────────────────────────────────
router.get('/', requireAuth, async (req, res) => {
    try {
        const today = new Date().toISOString().slice(0, 10);

        const { rows: [player] } = await pool.query(
            'SELECT wins, level FROM players WHERE id = $1', [req.playerId]
        );

        // Wins today are tracked via a synthetic daily-quest row
        // (solo matches don't insert into the `matches` table).
        const { rows: winRows } = await pool.query(
            `SELECT COALESCE(progress, 0)::int AS ct FROM player_daily_quests
             WHERE player_id=$1 AND quest_id='_daily_wins_today' AND quest_date=$2`,
            [req.playerId, today]
        );
        const winRow = winRows[0] || { ct: 0 };

        // Other daily quest progress (cards played, packs opened)
        const { rows: dailyRows } = await pool.query(
            `SELECT quest_id, progress, claimed FROM player_daily_quests
             WHERE player_id = $1 AND quest_date = $2`,
            [req.playerId, today]
        );
        const dailyMap = {};
        for (const r of dailyRows) dailyMap[r.quest_id] = r;

        // Claimed permanent quests
        const { rows: claimRows } = await pool.query(
            'SELECT quest_id FROM player_quest_claims WHERE player_id = $1', [req.playerId]
        );
        const claimedMain = new Set(claimRows.map(r => r.quest_id));

        const winsToday = winRow.ct;

        const daily = [
            ...DAILY_WIN_QUESTS.map(q => ({
                id: q.id, label: q.label, target: q.target,
                rewardKarat: q.rewardKarat, rewardContraband: q.rewardContraband,
                progress: Math.min(winsToday, q.target),
                claimed:  dailyMap[q.id]?.claimed ?? false,
            })),
            ...DAILY_OTHER_QUESTS.map(q => ({
                id: q.id, label: q.label, target: q.target,
                rewardKarat: q.rewardKarat, rewardContraband: q.rewardContraband,
                progress: dailyMap[q.id]?.progress ?? 0,
                claimed:  dailyMap[q.id]?.claimed  ?? false,
            })),
        ];

        const main = MAIN_QUESTS.map(q => ({
            id: q.id, label: q.label, target: q.target, rewardKarat: q.rewardKarat,
            progress: Math.min(player[q.field] ?? 0, q.target),
            claimed:  claimedMain.has(q.id),
        }));

        res.json({ daily, main });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/quests/claim/:questId ──────────────────────────────────────────
router.post('/claim/:questId', requireAuth, async (req, res) => {
    const { questId } = req.params;
    const today = new Date().toISOString().slice(0, 10);

    const quest = ALL_QUESTS.find(q => q.id === questId);
    if (!quest) return res.status(404).json({ error: 'Unknown quest.' });

    const isMain       = MAIN_QUESTS.includes(quest);
    const isDailyWin   = DAILY_WIN_QUESTS.includes(quest);
    const isDailyOther = DAILY_OTHER_QUESTS.includes(quest);

    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        const { rows: [player] } = await client.query(
            'SELECT wins, level, karat, contraband FROM players WHERE id = $1',
            [req.playerId]
        );

        if (isMain) {
            const { rows: existing } = await client.query(
                'SELECT 1 FROM player_quest_claims WHERE player_id=$1 AND quest_id=$2',
                [req.playerId, questId]
            );
            if (existing.length) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Already claimed.' });
            }
            if ((player[quest.field] ?? 0) < quest.target) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Quest not yet complete.' });
            }
            await client.query(
                'INSERT INTO player_quest_claims (player_id, quest_id) VALUES ($1,$2)',
                [req.playerId, questId]
            );
            await client.query(
                'UPDATE players SET karat = karat + $1 WHERE id = $2',
                [quest.rewardKarat, req.playerId]
            );

        } else if (isDailyWin) {
            const { rows: [row] } = await client.query(
                `SELECT claimed FROM player_daily_quests
                 WHERE player_id=$1 AND quest_id=$2 AND quest_date=$3`,
                [req.playerId, questId, today]
            );
            if (row?.claimed) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Already claimed.' });
            }
            const { rows: winRows } = await client.query(
                `SELECT COALESCE(progress, 0)::int AS ct FROM player_daily_quests
                 WHERE player_id=$1 AND quest_id='_daily_wins_today' AND quest_date=$2`,
                [req.playerId, today]
            );
            const winRow = winRows[0] || { ct: 0 };
            if (winRow.ct < quest.target) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Quest not yet complete.' });
            }
            await client.query(
                `INSERT INTO player_daily_quests (player_id, quest_id, quest_date, progress, claimed)
                 VALUES ($1,$2,$3,$4,TRUE)
                 ON CONFLICT (player_id, quest_id, quest_date)
                 DO UPDATE SET claimed = TRUE`,
                [req.playerId, questId, today, winRow.ct]
            );
            await client.query(
                'UPDATE players SET karat = karat + $1, contraband = contraband + $2 WHERE id = $3',
                [quest.rewardKarat, quest.rewardContraband, req.playerId]
            );

        } else if (isDailyOther) {
            const { rows: [row] } = await client.query(
                `SELECT progress, claimed FROM player_daily_quests
                 WHERE player_id=$1 AND quest_id=$2 AND quest_date=$3`,
                [req.playerId, questId, today]
            );
            if (!row || row.progress < quest.target) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Quest not yet complete.' });
            }
            if (row.claimed) {
                await client.query('ROLLBACK');
                return res.status(400).json({ error: 'Already claimed.' });
            }
            await client.query(
                `UPDATE player_daily_quests SET claimed = TRUE
                 WHERE player_id=$1 AND quest_id=$2 AND quest_date=$3`,
                [req.playerId, questId, today]
            );
            await client.query(
                'UPDATE players SET karat = karat + $1, contraband = contraband + $2 WHERE id = $3',
                [quest.rewardKarat, quest.rewardContraband, req.playerId]
            );
        }

        await client.query('COMMIT');

        const { rows: [updated] } = await pool.query(
            'SELECT karat, contraband FROM players WHERE id = $1', [req.playerId]
        );
        res.json({ success: true, karat: updated.karat, contraband: updated.contraband });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(500).json({ error: err.message });
    } finally {
        client.release();
    }
});

// ── POST /api/quests/progress ─────────────────────────────────────────────────
// Client reports incremental progress (e.g. cards played during a match).
router.post('/progress', requireAuth, async (req, res) => {
    const { questId, amount = 1 } = req.body;
    if (!questId || typeof amount !== 'number' || amount < 1) {
        return res.status(400).json({ error: 'Invalid payload.' });
    }
    await incrementDailyQuest(req.playerId, questId, Math.floor(amount));
    res.json({ ok: true });
});

// ── Internal helpers (called by game server / shop) ───────────────────────────

async function incrementDailyQuest(playerId, questId, amount = 1) {
    const quest = DAILY_OTHER_QUESTS.find(q => q.id === questId);
    if (!quest) return;
    const today = new Date().toISOString().slice(0, 10);
    try {
        await pool.query(
            `INSERT INTO player_daily_quests (player_id, quest_id, quest_date, progress)
             VALUES ($1,$2,$3,$4)
             ON CONFLICT (player_id, quest_id, quest_date)
             DO UPDATE SET progress = LEAST(
                 player_daily_quests.progress + EXCLUDED.progress,
                 $5
             ) WHERE NOT player_daily_quests.claimed`,
            [playerId, questId, today, amount, quest.target]
        );
    } catch (err) {
        console.error('[Quests] incrementDailyQuest failed:', err.message);
    }
}

async function recordDailyWin(playerId) {
    const today = new Date().toISOString().slice(0, 10);
    try {
        await pool.query(
            `INSERT INTO player_daily_quests (player_id, quest_id, quest_date, progress)
             VALUES ($1, '_daily_wins_today', $2, 1)
             ON CONFLICT (player_id, quest_id, quest_date)
             DO UPDATE SET progress = player_daily_quests.progress + 1`,
            [playerId, today]
        );
    } catch (err) {
        console.error('[Quests] recordDailyWin failed:', err.message);
    }
}

module.exports = { router, incrementDailyQuest, recordDailyWin };
