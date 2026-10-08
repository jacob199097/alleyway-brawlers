'use strict';

const router   = require('express').Router();
const bcrypt   = require('bcrypt');
const jwt      = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../db/pool');
const { sendVerificationEmail, sendPasswordResetEmail } = require('../utils/mailer');

const JWT_SECRET  = process.env.JWT_SECRET  || 'change_me_in_production';
const JWT_EXPIRES = process.env.JWT_EXPIRES || '7d';
const SALT_ROUNDS = 12;

// ── POST /api/auth/register ───────────────────────────────────────────────────
router.post('/register', async (req, res) => {
    const { username, email, password } = req.body;
    if (!username || !email || !password) {
        return res.status(400).json({ error: 'username, email, and password are required.' });
    }
    if (password.length < 8) {
        return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    try {
        const hash  = await bcrypt.hash(password, SALT_ROUNDS);
        const token = uuidv4();

        await pool.query(
            `INSERT INTO players (username, email, password_hash, karat, contraband, email_token, email_verified)
             VALUES ($1, $2, $3, 500, 0, $4, false)`,
            [username.trim(), email.trim().toLowerCase(), hash, token]
        );

        // Fire-and-log verification email — don't block registration on SMTP
        // errors. Prefer APP_BASE_URL (so the link points at the public
        // server address rather than whatever the request happened to use,
        // e.g. a Vite-proxied "localhost"); fall back to the request host.
        const baseUrl = process.env.APP_BASE_URL
            || `${req.protocol}://${req.get('host')}`;
        sendVerificationEmail(email.trim().toLowerCase(), token, baseUrl).catch(err => {
            console.error('[Auth] Verification email failed:', err.message);
        });

        res.status(201).json({
            pending: true,
            message: 'Account created. Check your email for the verification link.',
        });
    } catch (err) {
        if (err.code === '23505') {
            return res.status(409).json({ error: 'Username or email already taken.' });
        }
        console.error('[Auth] Register:', err.message);
        res.status(500).json({ error: 'Registration failed.' });
    }
});

// ── GET /api/auth/verify-email?token=xxx ─────────────────────────────────────
router.get('/verify-email', async (req, res) => {
    const { token } = req.query;
    if (!token) return res.status(400).send('Missing token.');

    try {
        const { rows } = await pool.query(
            `UPDATE players
             SET email_verified = true, email_token = NULL
             WHERE email_token = $1
             RETURNING id, username, email, karat, contraband, level, xp, rank, wins, losses`,
            [token]
        );

        if (!rows.length) {
            return res.status(400).send(_emailPage(
                'Verification failed',
                'This link is invalid or has already been used. If you have already verified your email, you can simply log in.',
                '#ff6b6b'
            ));
        }

        res.send(_emailPage(
            'E-mail confirmed',
            'You may now close this window and log in to AlleyWay Brawlers.',
            '#4cc9f0'
        ));
    } catch (err) {
        console.error('[Auth] Verify email:', err.message);
        res.status(500).send('Verification failed. Please try again.');
    }
});

// ── POST /api/auth/login ──────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) {
        return res.status(400).json({ error: 'email and password are required.' });
    }

    try {
        const { rows } = await pool.query(
            `SELECT id, username, email, password_hash, email_verified,
                    karat, contraband, level, xp, rank, avatar_url, wins, losses,
                    chosen_clan
             FROM players WHERE email = $1`,
            [email.trim().toLowerCase()]
        );
        if (!rows.length) return res.status(401).json({ error: 'Invalid credentials.' });

        const player = rows[0];
        const match  = await bcrypt.compare(password, player.password_hash);
        if (!match) return res.status(401).json({ error: 'Invalid credentials.' });

        if (!player.email_verified) {
            return res.status(403).json({
                error: 'Email not verified. Check your inbox for the activation link.',
                code:  'email_unverified',
            });
        }

        delete player.password_hash;
        delete player.email_verified;
        const token = _sign(player);
        res.json({ token, player });
    } catch (err) {
        console.error('[Auth] Login:', err.message);
        res.status(500).json({ error: 'Login failed.' });
    }
});

// ── POST /api/auth/forgot-password ───────────────────────────────────────────
router.post('/forgot-password', async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'email is required.' });

    // Always return the same response to prevent email enumeration
    const ok = { message: 'If that email is registered you will receive a reset link shortly.' };

    try {
        const { rows } = await pool.query(
            'SELECT id FROM players WHERE email = $1',
            [email.trim().toLowerCase()]
        );
        if (!rows.length) return res.json(ok);

        const token   = uuidv4();
        const expires = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

        await pool.query(
            'UPDATE players SET reset_token = $1, reset_token_expires = $2 WHERE id = $3',
            [token, expires, rows[0].id]
        );

        const baseUrl = process.env.APP_BASE_URL
            || `${req.protocol}://${req.get('host')}`;
        await sendPasswordResetEmail(email.trim().toLowerCase(), token, baseUrl);
        res.json(ok);
    } catch (err) {
        console.error('[Auth] Forgot password:', err.message);
        res.status(500).json({ error: 'Could not send reset email.' });
    }
});

// ── GET /api/auth/reset-password?token=xxx ───────────────────────────────────
// Validates the token and redirects to the client-side reset form
router.get('/reset-password', async (req, res) => {
    const { token } = req.query;
    if (!token) return res.status(400).send('Missing token.');

    try {
        const { rows } = await pool.query(
            `SELECT id FROM players
             WHERE reset_token = $1 AND reset_token_expires > NOW()`,
            [token]
        );
        if (!rows.length) {
            return res.status(400).send('Reset link is invalid or has expired.');
        }

        const appUrl = process.env.APP_CLIENT_URL || 'http://localhost:8080';
        res.redirect(`${appUrl}/reset-password?token=${token}`);
    } catch (err) {
        console.error('[Auth] Reset redirect:', err.message);
        res.status(500).send('Something went wrong. Please try again.');
    }
});

// ── POST /api/auth/reset-password ────────────────────────────────────────────
// Called by the client-side reset form once the player enters a new password
router.post('/reset-password', async (req, res) => {
    const { token, password } = req.body;
    if (!token || !password) {
        return res.status(400).json({ error: 'token and password are required.' });
    }
    if (password.length < 8) {
        return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    try {
        const { rows } = await pool.query(
            `SELECT id FROM players
             WHERE reset_token = $1 AND reset_token_expires > NOW()`,
            [token]
        );
        if (!rows.length) {
            return res.status(400).json({ error: 'Reset link is invalid or has expired.' });
        }

        const hash = await bcrypt.hash(password, SALT_ROUNDS);
        await pool.query(
            `UPDATE players
             SET password_hash = $1, reset_token = NULL, reset_token_expires = NULL
             WHERE id = $2`,
            [hash, rows[0].id]
        );

        res.json({ message: 'Password updated. You can now log in.' });
    } catch (err) {
        console.error('[Auth] Reset password:', err.message);
        res.status(500).json({ error: 'Password reset failed.' });
    }
});

function _emailPage(title, body, color) {
    return `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 body{margin:0;background:#0d0d1a;color:#e6e6f0;font-family:Arial,sans-serif;
      display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
 .card{max-width:440px;background:#101030;border:2px solid ${color};border-radius:10px;
       padding:32px;text-align:center}
 h1{color:${color};margin:0 0 16px;font-size:22px}
 p{color:#cccccc;line-height:1.5;margin:0}
</style></head><body><div class="card"><h1>${title}</h1><p>${body}</p></div></body></html>`;
}

function _sign(player) {
    return jwt.sign(
        { sub: player.id, username: player.username, avatarUrl: player.avatar_url || null },
        JWT_SECRET,
        { expiresIn: JWT_EXPIRES }
    );
}

module.exports = router;
