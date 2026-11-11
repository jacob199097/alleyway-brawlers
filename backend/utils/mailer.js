'use strict';

const nodemailer = require('nodemailer');

// Build the transporter once at startup.
// Configure via .env (SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_USER, SMTP_PASS, SMTP_FROM): Brevo since 0.9.140.
const transporter = nodemailer.createTransport({
    host:   process.env.SMTP_HOST,
    port:   parseInt(process.env.SMTP_PORT  || '587'),
    secure: process.env.SMTP_SECURE === 'true',   // true for port 465
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
    },
});

// Send from the SMTP account's own address unless SMTP_FROM says otherwise: mail "from" a domain
// the mail server doesn't own is what spam filters catch first.
const FROM = process.env.SMTP_FROM
    || (process.env.SMTP_USER ? `"AlleyWay Brawlers" <${process.env.SMTP_USER}>` : '"AlleyWay Brawlers" <noreply@alleywaybrawlers.com>');
const DEFAULT_BASE_URL = process.env.APP_BASE_URL || 'http://localhost:3000';

// ── The emails' look ─────────────────────────────────────────────────────────────────────────────
// The game's colours and the website's alley banner (website/img/email-banner.jpg, served by the
// website). Tables and inline styles, because that is all email programs agree on. Every email
// reads fine with pictures blocked (the banner has a dark background and words behind it), and
// nothing in them tracks the reader: no pixels, no link redirects.
const SITE = (process.env.SITE_URL ?? 'https://alleywaybrawlers.com').trim().replace(/\/+$/, '') || 'https://alleywaybrawlers.com';
const C = { bg: '#07070f', panel: '#121228', line: '#2c2c5a', text: '#dcdcea', dim: '#a4a4c0', gold: '#f4d35e', red: '#e63946', cyan: '#4cc9f0' };
const FONT = "Arial, 'Helvetica Neue', Helvetica, sans-serif";
const HEAD = "Impact, 'Arial Black', Arial, sans-serif";

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/**
 * One email in the game's look: { subject, html, text }.
 *   preview  the line inboxes show after the subject
 *   heading  big, gold, in capitals
 *   lines    the paragraphs (plain text)
 *   button   { text, href, color }: the one thing to do
 *   note     small print under the button (how long the link lasts, what to do if it wasn't you)
 *   why      the footer's "you got this because ..."
 */
function email({ subject, preview, heading, lines, button, note, why }) {
    const contact = process.env.CONTACT_EMAIL || '';
    const p = (t, style = '') => `<p style="margin:0 0 16px;font:16px/1.55 ${FONT};color:${C.text};${style}">${esc(t)}</p>`;
    const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark">
<title>${esc(subject)}</title></head>
<body style="margin:0;padding:0;background:${C.bg};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${C.bg};">${esc(preview)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.bg}" style="background:${C.bg};">
<tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.panel}" style="width:100%;max-width:600px;background:${C.panel};border:1px solid ${C.line};border-radius:14px;">
<tr><td bgcolor="${C.bg}" style="background:${C.bg};border-radius:14px 14px 0 0;">
<a href="${SITE}/" style="text-decoration:none;"><img src="${SITE}/site/img/email-banner.jpg" width="600" alt="AlleyWay Brawlers" style="display:block;width:100%;max-width:600px;height:auto;border:0;border-radius:14px 14px 0 0;font:700 28px ${HEAD};color:${C.gold};text-align:center;"></a>
</td></tr>
<tr><td style="padding:28px 32px 8px;">
<h1 style="margin:0 0 18px;font:400 30px/1.15 ${HEAD};letter-spacing:1px;text-transform:uppercase;color:${C.gold};">${esc(heading)}</h1>
${lines.map((t) => p(t)).join('\n')}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 22px;"><tr>
<td bgcolor="${button.color || C.red}" style="background:${button.color || C.red};border-radius:8px;">
<a href="${esc(button.href)}" style="display:inline-block;padding:14px 30px;font:400 20px/1 ${HEAD};letter-spacing:1px;text-transform:uppercase;color:#ffffff;text-decoration:none;border-radius:8px;">${esc(button.text)}</a>
</td></tr></table>
${note ? p(note, `font-size:14px;color:${C.dim};`) : ''}
<p style="margin:0 0 22px;font:13px/1.5 ${FONT};color:${C.dim};">Button not working? Copy this into your browser:<br>
<a href="${esc(button.href)}" style="color:${C.cyan};word-break:break-all;">${esc(button.href)}</a></p>
</td></tr>
<tr><td style="padding:18px 32px 26px;border-top:1px solid ${C.line};">
<p style="margin:0 0 6px;font:13px/1.5 ${FONT};color:${C.dim};"><a href="${SITE}/" style="color:${C.gold};text-decoration:none;font-weight:bold;">AlleyWay Brawlers</a> · Pick a clan. Build a deck. Take the city.</p>
<p style="margin:0;font:12px/1.5 ${FONT};color:${C.dim};">${esc(why)}${contact ? ` Questions? <a href="mailto:${esc(contact)}" style="color:${C.cyan};">${esc(contact)}</a>` : ''}</p>
</td></tr>
</table>
</td></tr>
</table>
</body></html>`;
    const text = [heading, '', ...lines, '', `${button.text}: ${button.href}`, ...(note ? ['', note] : []),
        '', '--', `AlleyWay Brawlers: ${SITE}`, why + (contact ? ` Questions? ${contact}` : '')].join('\n');
    return { subject, html, text };
}

const emails = {
    verification: (link) => email({
        subject: 'Activate your AlleyWay Brawlers account',
        preview: 'One click and your account is ready. The streets are waiting.',
        heading: 'Welcome to the alley',
        lines: ['Your account is almost ready. Confirm this is your email address, and it\'s yours: pick a clan, build a deck and take the city.'],
        button: { text: 'Activate my account', href: link, color: C.red },
        note: 'The game won\'t let you log in until this address is confirmed. Asked for a new link? Use the newest one.',
        why: 'You got this email because someone signed up for AlleyWay Brawlers with this address. If it wasn\'t you, ignore it: the account can\'t be used until the address is confirmed.',
    }),
    passwordReset: (link) => email({
        subject: 'Reset your AlleyWay Brawlers password',
        preview: 'Choose a new password for your account.',
        heading: 'New password',
        lines: ['Someone asked to reset the password for your account. Choose a new one here.'],
        button: { text: 'Choose a new password', href: link, color: C.red },
        note: 'This link works for 1 hour. If you didn\'t ask for it, ignore this email: your password stays as it is.',
        why: 'You got this email because a password reset was asked for on AlleyWay Brawlers with this address.',
    }),
};

async function send(to, mail) {
    await transporter.sendMail({ from: FROM, to, subject: mail.subject, html: mail.html, text: mail.text });
}

async function sendVerificationEmail(email, token, baseUrl = DEFAULT_BASE_URL) {
    await send(email, emails.verification(`${baseUrl}/api/auth/verify-email?token=${token}`));
}

async function sendPasswordResetEmail(email, token, baseUrl = DEFAULT_BASE_URL) {
    await send(email, emails.passwordReset(`${baseUrl}/api/auth/reset-password?token=${token}`));
}

module.exports = { sendVerificationEmail, sendPasswordResetEmail, emails };
