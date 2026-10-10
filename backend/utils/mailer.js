'use strict';

const nodemailer = require('nodemailer');

// Build the transporter once at startup.
// Configure via .env — see comments for each provider below.
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
    || (process.env.SMTP_USER ? `"AlleyWay Brawlers" <${process.env.SMTP_USER}>` : '"AlleyWay Brawlers" <noreply@alleywaybrawlers.duckdns.org>');
const DEFAULT_BASE_URL = process.env.APP_BASE_URL || 'http://localhost:3000';

async function sendVerificationEmail(email, token, baseUrl = DEFAULT_BASE_URL) {
    const link = `${baseUrl}/api/auth/verify-email?token=${token}`;
    await transporter.sendMail({
        from:    FROM,
        to:      email,
        subject: 'Activate your AlleyWay Brawlers account',
        html: `
            <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto">
                <h2 style="color:#4cc9f0">Welcome to AlleyWay Brawlers!</h2>
                <p>Click the button below to verify your email and activate your account.</p>
                <a href="${link}"
                   style="display:inline-block;padding:12px 28px;background:#4cc9f0;
                          color:#04060c;font-weight:bold;border-radius:6px;text-decoration:none">
                    Activate Account
                </a>
                <p style="color:#888;font-size:12px;margin-top:24px">
                    This link expires in 24 hours. If you didn't create an account, ignore this email.
                </p>
            </div>`,
        text: `Activate your account: ${link}\n\nLink expires in 24 hours.`,
    });
}

async function sendPasswordResetEmail(email, token, baseUrl = DEFAULT_BASE_URL) {
    const link = `${baseUrl}/api/auth/reset-password?token=${token}`;
    await transporter.sendMail({
        from:    FROM,
        to:      email,
        subject: 'Reset your AlleyWay Brawlers password',
        html: `
            <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto">
                <h2 style="color:#4cc9f0">Password Reset</h2>
                <p>Click the button below to choose a new password.</p>
                <a href="${link}"
                   style="display:inline-block;padding:12px 28px;background:#ff3b4e;
                          color:#ffffff;font-weight:bold;border-radius:6px;text-decoration:none">
                    Reset Password
                </a>
                <p style="color:#888;font-size:12px;margin-top:24px">
                    This link expires in 1 hour. If you didn't request a reset, ignore this email.
                </p>
            </div>`,
        text: `Reset your password: ${link}\n\nLink expires in 1 hour.`,
    });
}

module.exports = { sendVerificationEmail, sendPasswordResetEmail };
