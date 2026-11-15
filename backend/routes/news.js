'use strict';

/**
 * NEWS EMAILS (utils/news.js)
 *
 *   GET  /news/unsubscribe?u=<player>&t=<signature>   the page an email's Unsubscribe link opens: one button
 *   POST /news/unsubscribe?u=...&t=...                 turns news emails off (the button, and mail programs'
 *                                                      one-click unsubscribe, RFC 8058); no sign-in needed
 *   GET  /api/news            signed in: {on, email}   (the game's Settings → Account)
 *   POST /api/news {on}       signed in: turns them on or off
 *
 * A GET never unsubscribes by itself: mail scanners open links, and that mustn't turn anyone's emails off.
 */

const express = require('express');
const jwt = require('jsonwebtoken');
const news = require('../utils/news');
const { page } = require('./legal');

const pages = express.Router();
const api = express.Router();

const ok = (req) => news.checkToken(String(req.query.u || ''), req.query.t);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

pages.get('/unsubscribe', (req, res) => {
    if (!ok(req)) return res.status(400).send(page('Unsubscribe', `<h1>Unsubscribe</h1>
<p>This link isn't complete. Use the Unsubscribe link at the bottom of the email, or turn news emails off in the
game: Settings, Account.</p>`));
    res.send(page('Unsubscribe', `<h1>Unsubscribe</h1>
<p>Stop getting news emails from AlleyWay Brawlers (new seasons and new cards)? Emails about your account, such as
password resets, still come when you ask for them.</p>
<form method="post" action="/news/unsubscribe?u=${encodeURIComponent(String(req.query.u))}&amp;t=${esc(req.query.t)}">
<button type="submit">Unsubscribe</button></form>`));
});

pages.post('/unsubscribe', express.urlencoded({ extended: false }), async (req, res) => {
    if (!ok(req)) return res.status(400).send(page('Unsubscribe', '<h1>Unsubscribe</h1><p>This link isn\'t complete.</p>'));
    try {
        await news.setWanted(String(req.query.u), false);
    } catch (err) {
        console.error('[news/unsubscribe]', err.message);
        return res.status(500).send(page('Unsubscribe', '<h1>Unsubscribe</h1><p>Something went wrong. Please try again in a minute.</p>'));
    }
    res.send(page('Unsubscribed', `<h1>You're unsubscribed</h1>
<p>No more news emails. Changed your mind? Turn them back on in the game: Settings, Account.</p>`));
});

function signedIn(req) {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) return null;
    try {
        return jwt.verify(header.slice(7), process.env.JWT_SECRET).sub;
    } catch {
        return null;
    }
}

api.get('/', async (req, res) => {
    const id = signedIn(req);
    if (!id) return res.status(401).json({ error: 'Sign in first.' });
    try {
        const w = await news.wanted(id);
        if (!w) return res.status(404).json({ error: 'No such player.' });
        res.json(w);
    } catch (err) {
        console.error('[news]', err.message);
        res.status(500).json({ error: 'Could not read the setting.' });
    }
});

api.post('/', async (req, res) => {
    const id = signedIn(req);
    if (!id) return res.status(401).json({ error: 'Sign in first.' });
    try {
        await news.setWanted(id, !!(req.body && req.body.on));
        res.json(await news.wanted(id));
    } catch (err) {
        console.error('[news]', err.message);
        res.status(500).json({ error: 'Could not save the setting.' });
    }
});

module.exports = { pages, api };
