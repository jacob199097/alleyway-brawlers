'use strict';

const router   = require('express').Router();
const bcrypt   = require('bcrypt');
const jwt      = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../db/pool');
const { sendVerificationEmail, sendPasswordResetEmail } = require('../utils/mailer');

const JWT_SECRET  = process.env.JWT_SECRET;
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
// The link in the reset email: validates the token and shows a "choose a new password" page,
// which posts to POST /api/auth/reset-password below.
router.get('/reset-password', async (req, res) => {
    const token = String(req.query.token || '');
    if (!/^[0-9a-f-]{36}$/i.test(token)) {
        return res.status(400).send(_emailPage('Link not valid', 'This password reset link is not valid. Request a new one from the game.', '#e63946'));
    }

    try {
        const { rows } = await pool.query(
            `SELECT id FROM players
             WHERE reset_token = $1 AND reset_token_expires > NOW()`,
            [token]
        );
        if (!rows.length) {
            return res.status(400).send(_emailPage('Link expired', 'This password reset link has expired or was already used. Request a new one from the game.', '#e63946'));
        }
        res.send(_resetPage(token));
    } catch (err) {
        console.error('[Auth] Reset page:', err.message);
        res.status(500).send(_emailPage('Something went wrong', 'Please try the link again in a moment.', '#e63946'));
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

/** The "choose a new password" page (token already checked: a UUID). */
function _resetPage(token) {
    return `<!doctype html><html><head><meta charset="utf-8"><title>Reset your password</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 body{margin:0;background:#0d0d1a;color:#e6e6f0;font-family:Arial,sans-serif;
      display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
 .card{width:100%;max-width:420px;background:#101030;border:2px solid #f4d35e;border-radius:10px;padding:32px}
 h1{color:#f4d35e;margin:0 0 8px;font-size:22px;text-align:center}
 p{color:#cccccc;line-height:1.5;margin:0 0 18px;text-align:center}
 label{display:block;font-size:13px;color:#a8a8c0;margin:12px 0 6px}
 input{width:100%;box-sizing:border-box;padding:12px;border-radius:6px;border:2px solid #4cc9f0;background:#1a1a2e;color:#fff;font-size:16px}
 button{width:100%;margin-top:20px;padding:13px;border:0;border-radius:6px;background:#f4d35e;color:#1a1206;font-weight:bold;font-size:16px;cursor:pointer}
 button:disabled{opacity:.5;cursor:default}
 #msg{margin-top:16px;min-height:1.4em;text-align:center}
</style></head><body><div class="card">
<h1>Choose a new password</h1>
<p>For your Alleyway Brawlers account.</p>
<form id="f">
 <label for="p1">New password (8 characters or more)</label>
 <input id="p1" type="password" autocomplete="new-password" minlength="8" required>
 <label for="p2">Type it again</label>
 <input id="p2" type="password" autocomplete="new-password" minlength="8" required>
 <button id="b" type="submit">Save new password</button>
</form>
<div id="msg"></div>
<script>
const f = document.getElementById('f'), msg = document.getElementById('msg'), b = document.getElementById('b');
const say = (t, ok) => { msg.textContent = t; msg.style.color = ok ? '#4caf50' : '#e63946'; };
f.addEventListener('submit', async (e) => {
  e.preventDefault();
  const p1 = document.getElementById('p1').value, p2 = document.getElementById('p2').value;
  if (p1.length < 8) return say('Use at least 8 characters.');
  if (p1 !== p2) return say("The two passwords don't match.");
  b.disabled = true;
  try {
    const r = await fetch('/api/auth/reset-password', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: '${token}', password: p1 }) });
    const d = await r.json().catch(() => ({}));
    if (r.ok) { f.remove(); say('Password updated. You can log in to the game now.', true); }
    else { b.disabled = false; say(d.error || 'That did not work. Try again.'); }
  } catch { b.disabled = false; say("Can't reach the server. Try again."); }
});
</script></div></body></html>`;
}

function _sign(player) {
    return jwt.sign(
        { sub: player.id, username: player.username, avatarUrl: player.avatar_url || null },
        JWT_SECRET,
        { expiresIn: JWT_EXPIRES }
    );
}

module.exports = router;
