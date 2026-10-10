'use strict';

const router          = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }        = require('../db/pool');
const achievements    = require('../economy/achievements');

// ── GET /api/profile/me ───────────────────────────────────────────────────────
router.get('/me', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT p.id, p.username, p.email, p.karat, p.contraband, p.level, p.xp,
                    p.rank, p.rank_points, p.wins, p.losses, p.draws,
                    p.avatar_url, p.profile_bio, p.chosen_clan, p.created_at,
                    p.dust, p.title AS title_id, p.card_back,
                    -- Collection completion %
                    (
                        SELECT COUNT(DISTINCT pi.card_id)::float /
                               NULLIF((SELECT COUNT(*) FROM cards), 0) * 100
                        FROM player_inventory pi
                        WHERE pi.player_id = p.id
                    ) AS collection_pct
             FROM players p WHERE p.id = $1`,
            [req.playerId]
        );
        if (!rows.length) return res.status(404).json({ error: 'Player not found.' });
        res.json({ ...rows[0], title: await achievements.titleText(rows[0].title_id) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── PATCH /api/profile/me — update bio / avatar ───────────────────────────────
router.patch('/me', requireAuth, async (req, res) => {
    const { bio, avatarUrl } = req.body;
    const updates = [];
    const params  = [];

    if (bio !== undefined) {
        if (bio.length > 200) return res.status(400).json({ error: 'Bio max 200 chars.' });
        params.push(bio);
        updates.push(`profile_bio = $${params.length}`);
    }
    if (avatarUrl !== undefined) {
        // Avatars are unlocked by achievements, so the check lives there
        try {
            const r = await achievements.equip(req.playerId, { avatar: avatarUrl });
            if (r.error) return res.status(400).json(r);
        } catch (err) {
            return res.status(500).json({ error: err.message });
        }
        if (bio === undefined) return res.json({ success: true });
    }
    if (!updates.length) return res.status(400).json({ error: 'Nothing to update.' });

    params.push(req.playerId);
    try {
        await pool.query(
            `UPDATE players SET ${updates.join(', ')} WHERE id = $${params.length}`,
            params
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── GET /api/profile/inventory ────────────────────────────────────────────────
router.get('/inventory', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT c.id, c.name, c.clan, c.clan_tag, c.card_type, c.subtype, c.level,
                    c.authority, c.attack, c.defense, c.rarity, c.art_url,
                    c.effect_text, c.flavour_text,
                    pi.quantity
             FROM   player_inventory pi
             JOIN   cards c ON c.id = pi.card_id
             WHERE  pi.player_id = $1
             ORDER  BY c.rarity DESC, c.name`,
            [req.playerId]
        );
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
