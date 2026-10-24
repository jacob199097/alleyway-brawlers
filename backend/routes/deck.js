'use strict';

const router          = require('express').Router();
const { requireAuth } = require('./middleware');
const { pool }        = require('../db/pool');
const { deckHideout } = require('../utils/deckHideout');

// ── GET /api/deck — list all decks for the player ────────────────────────────
router.get('/', requireAuth, async (req, res) => {
    try {
        const { rows } = await pool.query(
            `SELECT d.id, d.name, d.is_active, d.updated_at, d.games, d.wins,
                    COALESCE(SUM(dc.copies), 0)::int AS card_count
             FROM   decks d
             LEFT JOIN deck_cards dc ON dc.deck_id = d.id
             WHERE  d.player_id = $1
             GROUP  BY d.id
             ORDER  BY d.is_active DESC, d.updated_at DESC`,
            [req.playerId]
        );
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── GET /api/deck/:id — get full deck contents ───────────────────────────────
router.get('/:id', requireAuth, async (req, res) => {
    try {
        const deck = await _getDeckOrFail(req.params.id, req.playerId, res);
        if (!deck) return;

        const { rows } = await pool.query(
            `SELECT c.id, c.name, c.clan, c.card_type, c.authority,
                    c.attack, c.defense, c.rarity, c.art_url, dc.copies
             FROM   deck_cards dc
             JOIN   cards c ON c.id = dc.card_id
             WHERE  dc.deck_id = $1
             ORDER  BY c.authority DESC, c.name`,
            [req.params.id]
        );

        let leader = null;
        if (deck.leader_card_id) {
            const { rows: lr } = await pool.query(
                `SELECT id, name, clan, clan_tag, card_type, subtype, level, authority,
                        attack, defense, rarity, art_url, effect_text, flavour_text
                 FROM cards WHERE id = $1`,
                [deck.leader_card_id]
            );
            leader = lr[0] || null;
        }
        const hideout = await deckHideout(pool, deck, req.playerId);
        res.json({ ...deck, cards: rows, leader, hideout });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/deck — create a new empty deck ─────────────────────────────────
router.post('/', requireAuth, async (req, res) => {
    const { name } = req.body;
    try {
        const { rows } = await pool.query(
            `INSERT INTO decks (player_id, name, hideout_set) VALUES ($1, $2, TRUE) RETURNING *`,
            [req.playerId, name || 'New Deck']
        );
        res.status(201).json(rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── PUT /api/deck/:id/cards — replace deck contents (full sync) ───────────────
// Expects body: { cards: [{ cardId, copies }], leaderCardId, hideout: [{ cardId, copies }] }
// (hideout: the higher levels of Strivers the player puts in the Hideout; left out = unchanged)
router.put('/:id/cards', requireAuth, async (req, res) => {
    const deck = await _getDeckOrFail(req.params.id, req.playerId, res);
    if (!deck) return;

    const { cards, leaderCardId, hideout } = req.body;
    if (!Array.isArray(cards)) return res.status(400).json({ error: 'cards must be an array.' });
    if (hideout !== undefined && !Array.isArray(hideout)) return res.status(400).json({ error: 'hideout must be an array.' });

    // Merge duplicate entries and validate copy counts before touching the DB
    const wanted = new Map();   // cardId → copies
    for (const entry of cards) {
        const copies = entry?.copies ?? 1;
        if (typeof entry?.cardId !== 'string' || !Number.isInteger(copies) || copies < 1) {
            return res.status(400).json({ error: 'Each card needs a cardId and a whole number of copies.' });
        }
        wanted.set(entry.cardId, (wanted.get(entry.cardId) || 0) + copies);
    }
    const hidden = new Map();   // cardId → copies, in the Hideout
    for (const entry of hideout || []) {
        const copies = entry?.copies ?? 1;
        if (typeof entry?.cardId !== 'string' || !Number.isInteger(copies) || copies < 1) {
            return res.status(400).json({ error: 'Each Hideout card needs a cardId and a whole number of copies.' });
        }
        hidden.set(entry.cardId, (hidden.get(entry.cardId) || 0) + copies);
    }
    const totalCopies = [...wanted.values()].reduce((s, n) => s + n, 0);
    if (totalCopies !== 40) return res.status(400).json({ error: `Deck must be exactly 40 cards (currently ${totalCopies}).` });

    // Every card must be a non-leader card the player owns enough copies of (max 3), and a
    // character's first level: its promoted forms wait in the Hideout by themselves
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const { rows: owned } = await pool.query(
        `SELECT c.id, c.name, c.card_type, c.art_url, pi.quantity
         FROM   cards c
         JOIN   player_inventory pi ON pi.card_id = c.id AND pi.player_id = $1
         WHERE  c.id::text = ANY($2::text[])`,
        [req.playerId, [...wanted.keys(), ...hidden.keys()]]
    );
    const ownedById = new Map(owned.map(r => [r.id, r]));
    for (const [cardId, copies] of wanted) {
        const row = ownedById.get(cardId);
        if (!row) return res.status(400).json({ error: 'Deck contains a card you do not own.' });
        if (row.card_type === 'leader') return res.status(400).json({ error: 'Leader cards cannot go in the main deck.' });
        const level = Math.trunc(Number(CARD_CATALOG[row.art_url]?.level) || 1);
        if (row.card_type === 'gang_member' && level > 1) {
            return res.status(400).json({ error: `${row.name} (level ${level}) waits in the Hideout: put its level 1 card in the deck instead.` });
        }
        if (copies > 3) return res.status(400).json({ error: `Max 3 copies of ${row.name}.` });
        if (copies > row.quantity) return res.status(400).json({ error: `You only own ${row.quantity} of ${row.name}.` });
    }
    // The Hideout: only a Striver's higher levels (level 2 and up), up to 3 of each you own
    for (const [cardId, copies] of hidden) {
        const row = ownedById.get(cardId);
        if (!row) return res.status(400).json({ error: 'The Hideout has a card you do not own.' });
        const c = CARD_CATALOG[row.art_url] || {};
        if (row.card_type !== 'gang_member' || c.subtype !== 'striver' || Math.trunc(Number(c.level) || 1) < 2) {
            return res.status(400).json({ error: `${row.name} can't go in the Hideout: only a Striver's higher levels wait there.` });
        }
        if (copies > 3) return res.status(400).json({ error: `Max 3 copies of ${row.name} in the Hideout.` });
        if (copies > row.quantity) return res.status(400).json({ error: `You only own ${row.quantity} of ${row.name}.` });
    }

    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        // Delete existing
        await client.query('DELETE FROM deck_cards WHERE deck_id = $1', [req.params.id]);
        // Insert new
        for (const [cardId, copies] of wanted) {
            await client.query(
                `INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1,$2,$3)`,
                [req.params.id, cardId, copies]
            );
        }
        // Leader (optional) — verify it's a leader card the player owns.
        if (leaderCardId !== undefined) {
            if (leaderCardId === null) {
                await client.query(
                    `UPDATE decks SET leader_card_id = NULL WHERE id = $1`,
                    [req.params.id]
                );
            } else {
                const { rows: lr } = await client.query(
                    `SELECT 1 FROM cards c
                     JOIN player_inventory pi ON pi.card_id = c.id
                     WHERE c.id = $1 AND c.card_type = 'leader' AND pi.player_id = $2`,
                    [leaderCardId, req.playerId]
                );
                if (!lr.length) {
                    await client.query('ROLLBACK');
                    return res.status(400).json({ error: 'Invalid leader card.' });
                }
                await client.query(
                    `UPDATE decks SET leader_card_id = $1 WHERE id = $2`,
                    [leaderCardId, req.params.id]
                );
            }
        }
        if (hideout !== undefined) {
            await client.query('DELETE FROM deck_hideout WHERE deck_id = $1', [req.params.id]);
            for (const [cardId, copies] of hidden) {
                await client.query('INSERT INTO deck_hideout (deck_id, card_id, copies) VALUES ($1, $2, $3)', [req.params.id, cardId, copies]);
            }
            await client.query('UPDATE decks SET hideout_set = TRUE WHERE id = $1', [req.params.id]);
        }
        await client.query(
            `UPDATE decks SET updated_at = NOW() WHERE id = $1`, [req.params.id]
        );
        await client.query('COMMIT');
        res.json({ success: true, totalCopies });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(500).json({ error: err.message });
    } finally {
        client.release();
    }
});

// ── PATCH /api/deck/:id/activate — set as active deck ────────────────────────
router.patch('/:id/activate', requireAuth, async (req, res) => {
    const deck = await _getDeckOrFail(req.params.id, req.playerId, res);
    if (!deck) return;

    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(
            `UPDATE decks SET is_active = FALSE WHERE player_id = $1`, [req.playerId]
        );
        await client.query(
            `UPDATE decks SET is_active = TRUE WHERE id = $1`, [req.params.id]
        );
        await client.query('COMMIT');
        res.json({ success: true });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(500).json({ error: err.message });
    } finally {
        client.release();
    }
});

// ── DELETE /api/deck/:id ──────────────────────────────────────────────────────
router.delete('/:id', requireAuth, async (req, res) => {
    const deck = await _getDeckOrFail(req.params.id, req.playerId, res);
    if (!deck) return;
    await pool.query('DELETE FROM decks WHERE id = $1', [req.params.id]);
    res.json({ success: true });
});

async function _getDeckOrFail(deckId, playerId, res) {
    const { rows } = await pool.query(
        'SELECT * FROM decks WHERE id = $1 AND player_id = $2', [deckId, playerId]
    );
    if (!rows.length) { res.status(404).json({ error: 'Deck not found.' }); return null; }
    return rows[0];
}

module.exports = router;
