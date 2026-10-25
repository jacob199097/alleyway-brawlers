'use strict';

/**
 * ACCOUNT DELETION
 *
 *   POST /api/account/delete   {password}            signed in (the game: Settings → Account)
 *                              {email, password}     not signed in (the /delete-account web page)
 *
 * The password is checked, then the player and everything that is theirs goes for good: the
 * collection, decks, currencies, progress, friends, messages, mail, quests, achievements, replays
 * of their matches and their error reports (ON DELETE CASCADE, db/migrate_account_deletion.sql).
 * Other players' match history keeps those matches with the deleted side left empty, and
 * redeemed payments stay marked as used (without the player) so they can't be claimed twice.
 */

const router = require('express').Router();
const bcrypt = require('bcrypt');
const jwt    = require('jsonwebtoken');
const { pool } = require('../db/pool');

const WINDOW_MS = 15 * 60 * 1000;
const TRIES_PER_WINDOW = 10;        // per IP address: password guesses
const recent = new Map();           // ip -> {start, count}

function clientIp(req) {
    return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

function tooMany(ip) {
    const now = Date.now();
    const r = recent.get(ip);
    if (!r || now - r.start > WINDOW_MS) {
        recent.set(ip, { start: now, count: 1 });
        return false;
    }
    r.count += 1;
    return r.count > TRIES_PER_WINDOW;
}

/** The signed-in player's id from the Authorization header, or null. */
function signedIn(req) {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) return null;
    try {
        return jwt.verify(header.slice(7), process.env.JWT_SECRET).sub;
    } catch {
        return null;
    }
}

/** Deletes a player and everything that is theirs, in one transaction. */
async function deleteAccount(playerId) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        // Tables made on first use by their routes (they may not exist yet), keyed by the id as text
        const { rows: [t] } = await client.query(
            `SELECT to_regclass('match_replays') IS NOT NULL AS replays, to_regclass('client_errors') IS NOT NULL AS errors`);
        if (t.replays) await client.query('DELETE FROM match_replays WHERE p1 = $1 OR p2 = $1', [String(playerId)]);
        if (t.errors) await client.query('DELETE FROM client_errors WHERE player_id = $1', [String(playerId)]);
        const { rowCount } = await client.query('DELETE FROM players WHERE id = $1', [playerId]);
        await client.query('COMMIT');
        return rowCount > 0;
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

router.post('/delete', async (req, res) => {
    const { email, password } = req.body || {};
    if (!password) return res.status(400).json({ error: 'Enter your password to delete your account.' });
    if (tooMany(clientIp(req))) return res.status(429).json({ error: 'Too many tries. Wait 15 minutes and try again.' });
    const me = signedIn(req);
    if (!me && !email) return res.status(400).json({ error: 'Enter the email and password of the account.' });
    try {
        const { rows } = me
            ? await pool.query('SELECT id, username, password_hash FROM players WHERE id = $1', [me])
            : await pool.query('SELECT id, username, password_hash FROM players WHERE email = $1', [String(email).trim().toLowerCase()]);
        if (!rows.length || !(await bcrypt.compare(String(password), rows[0].password_hash))) {
            return res.status(401).json({ error: me ? 'That password is not right.' : 'That email and password do not match an account.' });
        }
        await deleteAccount(rows[0].id);
        console.log(`[Account] Deleted ${rows[0].username} (${rows[0].id})`);
        res.json({ deleted: true });
    } catch (err) {
        console.error('[Account] Delete:', err.message);
        res.status(500).json({ error: 'Could not delete the account. Try again in a moment.' });
    }
});

module.exports = router;
module.exports.deleteAccount = deleteAccount;
