'use strict';

/**
 * THE WEBSITE (public pages, no sign-in: alleywaybrawlers.com)
 *
 *   GET /                 the front page: what the game is, screenshots, the downloads
 *   GET /clans            the clans
 *   GET /clans/<clan>     a clan: its leader, its Striver lines, every card it has
 *   GET /cards            every card, with a search and filters (?q= &clan= &kind= &rarity=)
 *   GET /cards/<id>       one card (?fragment=1: only the card, for the zoom in site.js)
 *   GET /how-to-play      the game's own How to Play, the keywords and the card terms
 *   GET /news             the patch notes
 *   GET /site/...         the site's own files: website/ (styles, script, font, screenshots)
 *   GET /site/pic/...     the game's art made smaller (site/images.js)
 *   GET /robots.txt, /sitemap.xml, /favicon.ico
 *
 * The pages are built from the game's files (site/data.js) by site/pages.js. They read nothing
 * from the database and nothing about players: no cookies, no sign-in, no tracking.
 *
 * SITE_URL in .env is the site's one real address (default https://alleywaybrawlers.com): a page asked
 * for through another of the server's names (play.…, www.…, the DuckDNS one) is sent there, so
 * search engines see one site. Set SITE_URL= (empty) to serve the pages under whatever name is asked.
 */

const express = require('express');
const fs      = require('fs');
const path    = require('path');

const { load }  = require('../site/data');
const pages     = require('../site/pages');
const images    = require('../site/images');
const download  = require('./download');
const legal     = require('./legal');

const router = express.Router();
const WEBSITE = path.join(__dirname, '../../website');
const VERSION = path.join(__dirname, '../../shared/game_version.json');
const SITE_URL = (process.env.SITE_URL ?? 'https://alleywaybrawlers.com').trim().replace(/\/+$/, '');
const SITE_HOST = SITE_URL.replace(/^https?:\/\//, '').toLowerCase();
const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\]|192\.168\.\d+\.\d+)(:\d+)?$/;
const FILES = /\.(css|js|webp|jpg|png|svg|ico|woff2|txt)$/;   // what /site/ serves out of website/

// A page may load only this site's own files (and nothing may frame it)
const HEADERS = {
    'Cache-Control': 'public, max-age=300',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; "
        + "base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
};

/** The name the visitor typed (Apache passes it on), in small letters. */
const hostOf = (req) => String(req.get('x-forwarded-host') || req.get('host') || '').split(',')[0].trim().toLowerCase();

// ── What changes between visits (looked up at most once a minute) ────────────────────────────────
let fresh = null;

/** When any file in website/ last changed (base 36): the ?v= on the site's files. */
function stamp(dir = WEBSITE) {
    let newest = 0;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, e.name);
        newest = Math.max(newest, e.isDirectory() ? stamp(full) : fs.statSync(full).mtimeMs);
    }
    return newest;
}

function current() {
    if (fresh && Date.now() - fresh.at < 60_000) return fresh;
    let latest = '';
    try {
        latest = String(JSON.parse(fs.readFileSync(VERSION, 'utf8')).latest || '');
    } catch { /* no version file: the pages leave the number out */ }
    const builds = {};
    for (const platform of ['windows', 'macos', 'android']) {
        try {
            builds[platform] = download.newestInfo(platform);
        } catch {
            builds[platform] = null;
        }
    }
    let v = '0';
    try {
        v = Math.round(stamp()).toString(36);
    } catch { /* no website/ folder */ }
    fresh = { at: Date.now(), latest, builds, v };
    return fresh;
}

/** What pages.js needs to build a page for this visitor. */
async function context(req) {
    const now = current();
    const host = hostOf(req);
    return {
        d: await load(), v: now.v, latest: now.latest, builds: now.builds,
        base: SITE_URL || `${req.get('x-forwarded-host') ? 'https' : req.protocol}://${host}`,
        canonical: !!SITE_URL,
        contact: legal.contact(),
    };
}

function send(res, html, status = 200) {
    res.status(status).set(HEADERS).type('html').send(html);
}

/** A page: `build(ctx, req)` gives its HTML, or null when there is no such page. */
const page = (build) => async (req, res, next) => {
    // (one address: a visit through the server's other names goes to SITE_URL)
    const host = hostOf(req);
    if (SITE_URL && req.get('x-forwarded-host') && host !== SITE_HOST && !LOCAL.test(host)) {
        return res.redirect(302, SITE_URL + req.originalUrl);
    }
    try {
        const ctx = await context(req);
        const html = build(ctx, req);
        if (html == null) return notFound(req, res, next);
        send(res, html);
    } catch (err) {
        console.error(`[site] ${req.originalUrl}:`, err);
        res.status(500).type('text').send('The website has a problem. The game itself is not affected.');
    }
};

// ── The pages ────────────────────────────────────────────────────────────────────────────────────
router.get('/', page((ctx) => pages.home(ctx)));
router.get('/clans', page((ctx) => pages.clans(ctx)));
router.get('/clans/:id', page((ctx, req) => {
    const clan = ctx.d.clanById.get(String(req.params.id));
    return clan ? pages.clan(ctx, clan) : null;
}));
router.get('/cards', page((ctx, req) => pages.cards(ctx, req.query)));
router.get('/cards/:id', page((ctx, req) => {
    const card = ctx.d.byId.get(String(req.params.id));
    if (!card) return null;
    return req.query.fragment ? pages.cardFragment(ctx, card) : pages.card(ctx, card);
}));
router.get('/how-to-play', page((ctx) => pages.howToPlay(ctx)));
router.get('/news', page((ctx) => pages.news(ctx)));

// ── For search engines and browsers ──────────────────────────────────────────────────────────────
router.get('/robots.txt', (req, res) => {
    const base = SITE_URL || `https://${hostOf(req)}`;
    res.type('text').set('Cache-Control', 'public, max-age=3600')
        .send(`User-agent: *\nDisallow: /api/\nDisallow: /download/\nDisallow: /delete-account\n\nSitemap: ${base}/sitemap.xml\n`);
});

router.get('/sitemap.xml', async (req, res) => {
    try {
        const ctx = await context(req);
        const urls = pages.sitemap(ctx).map((p) => `<url><loc>${ctx.base}${p}</loc></url>`).join('\n');
        res.type('application/xml').set('Cache-Control', 'public, max-age=3600')
            .send(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`);
    } catch (err) {
        console.error('[site] sitemap:', err);
        res.status(500).type('text').send('Not available.');
    }
});

router.get('/favicon.ico', (_req, res, next) => {
    res.sendFile(path.join(WEBSITE, 'img/icon-32.png'), { maxAge: '1d' }, (err) => err && next());
});

// ── The site's files ─────────────────────────────────────────────────────────────────────────────
// What each keyword means, for the pop-ups on card text
router.get('/site/keywords.json', async (req, res) => {
    try {
        res.set('Cache-Control', req.query.v ? 'public, max-age=31536000, immutable' : 'public, max-age=300')
            .json(pages.keywordsJson(await context(req)));
    } catch (err) {
        console.error('[site] keywords:', err);
        res.status(500).json({});
    }
});

router.use('/site/pic', images.send);

// (an address with ?v= changes when the file does, so browsers may keep it for good; so may the font)
router.use('/site', (req, res, next) => (FILES.test(req.path) ? next() : next('router')), express.static(WEBSITE, {
    index: false,
    setHeaders(res, file) {
        const keep = res.req.query.v || file.endsWith('.woff2');
        res.set('Cache-Control', keep ? 'public, max-age=31536000, immutable' : 'public, max-age=3600');
        res.set('X-Content-Type-Options', 'nosniff');
    },
}));

/** A page that isn't there: the site's own "Dead end" for browsers, and nothing new for the game's calls. */
async function notFound(req, res, next) {
    const p = req.path;
    if (!['GET', 'HEAD'].includes(req.method) || /^\/(api|socket\.io|download|site)\//.test(p) || !req.accepts('html')) return next();
    try {
        send(res, pages.notFound(await context(req), p), 404);
    } catch (err) {
        console.error('[site] 404 page:', err);
        next();
    }
}

// The listings' card pictures, made ahead of the first visitor (a few seconds after start-up, in the background)
setTimeout(() => {
    load().then((d) => images.warm(d.cards.map((c) => c.id)))
        .catch((err) => console.error('[site] the card pictures will be made as they are asked for:', err.message));
}, 8000).unref();

module.exports = { router, notFound };
