'use strict';

/**
 * THE WEBSITE'S VISIT COUNTER (no cookies, no trackers, nothing from other sites)
 *
 * routes/site.js calls see(req, path) for each page it sends. Per day, the database keeps only totals
 * (db/migrate_site_visits.sql, table site_counts):
 *
 *   kind 'total'  key 'views' (pages shown), 'visitors' (people), 'phone' (people on a phone)
 *   kind 'page'   key '/cards'          views of that page
 *   kind 'from'   key 'google.com'      visitors who came from that site (a link, a search)
 *
 * A visitor is counted once a day by a scrambled form of their IP address and browser, made with a key
 * that is new every day and never written down: it stays in the server's memory for that day only, so
 * nobody (us included) can match it to a person or follow anyone from one day to the next. A server
 * restart forgets it, so someone who visits before and after a restart counts twice that day.
 *
 * Not counted: search engines and other robots, the server's own network (192.168.x: you at home), a
 * page fetched ahead of time by the browser, and the card zoom (?fragment=1).
 *
 * Counts wait in memory and are added to the database every half a minute.
 * GET /stats shows them (routes/site.js), behind the password SITE_STATS_PASSWORD in backend/.env.
 */

const crypto = require('crypto');
const { clientIp } = require('../utils/ipHash');

const ROBOT = /bot|crawl|spider|slurp|archiver|preview|fetch|scan|monitor|lighthouse|headless|curl|wget|python|java\/|go-http|node|axios|okhttp|facebookexternalhit|embedly|whatsapp|telegram|discord|skype/i;
const PRIVATE = /^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|::1$|::ffff:(127|10|192\.168)\.|fc|fd|$)/i;
const PHONE = /Mobi|Android|iPhone|iPad|iPod/i;
// The site's own names: moving between its pages isn't "coming from" anywhere
const OWN = /(^|\.)alleywaybrawlers\.(com|duckdns\.org)$/i;
const FLUSH_EVERY = 30_000;
const KEEP_DAYS = 400;   // older days are deleted

const state = { day: '', key: null, seen: new Set(), pending: new Map() };

/** Today's date on the server (YYYY-MM-DD, the server's own time zone). */
function today(now = new Date()) {
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 10);
}

function add(day, kind, key, n = 1) {
    const k = `${day}\t${kind}\t${key}`;
    state.pending.set(k, (state.pending.get(k) || 0) + n);
}

/** The site a visitor came from: its name without "www.", grouped for the big ones; '' = typed in / a bookmark. */
function source(referer) {
    let host = '';
    try {
        host = new URL(referer).hostname.toLowerCase().replace(/^(www|m|l|lm|old|new)\./, '');
    } catch {
        return '';
    }
    if (!host || OWN.test(host)) return '';
    if (/^(google\.|.*\.google\.)/.test(host)) return 'Google';
    if (/(^|\.)bing\.com$/.test(host)) return 'Bing';
    if (/(^|\.)duckduckgo\.com$/.test(host)) return 'DuckDuckGo';
    if (/(^|\.)(reddit\.com|redd\.it)$/.test(host)) return 'Reddit';
    if (/(^|\.)(discord\.com|discordapp\.com|discord\.gg)$/.test(host)) return 'Discord';
    if (/(^|\.)(facebook\.com|fb\.com|messenger\.com)$/.test(host)) return 'Facebook';
    if (/(^|\.)(twitter\.com|x\.com|t\.co)$/.test(host)) return 'X (Twitter)';
    if (/(^|\.)(youtube\.com|youtu\.be)$/.test(host)) return 'YouTube';
    if (/(^|\.)tiktok\.com$/.test(host)) return 'TikTok';
    if (/(^|\.)instagram\.com$/.test(host)) return 'Instagram';
    if (/(^|\.)(steampowered\.com|steamcommunity\.com)$/.test(host)) return 'Steam';
    return host.slice(0, 80);
}

/** Count one page shown to a visitor (routes/site.js, after the page is sent). */
function see(req, page) {
    if (req.method !== 'GET' || req.query.fragment) return;
    const agent = String(req.get('user-agent') || '');
    if (!agent || ROBOT.test(agent)) return;
    if (/prefetch|prerender/i.test(String(req.get('sec-purpose') || req.get('purpose') || req.get('x-moz') || ''))) return;
    const ip = clientIp(req);
    if (PRIVATE.test(ip)) return;

    const day = today();
    if (day !== state.day) {
        state.day = day;
        state.key = crypto.randomBytes(32);
        state.seen = new Set();
    }
    add(day, 'total', 'views');
    add(day, 'page', String(page).slice(0, 120));

    const who = crypto.createHmac('sha256', state.key).update(`${ip}\n${agent}`).digest('base64').slice(0, 16);
    if (state.seen.has(who)) return;
    state.seen.add(who);
    add(day, 'total', 'visitors');
    if (PHONE.test(agent)) add(day, 'total', 'phone');
    const from = source(req.get('referer'));
    if (from) add(day, 'from', from);
}

// ── The database (replaced by a stand-in in backend/site/site.test.cjs) ─────────────────────────
const db = { query: (...args) => require('../db/pool').pool.query(...args) };

/** Adds the waiting counts to the database. */
async function flush() {
    if (!state.pending.size) return;
    const rows = [...state.pending];
    state.pending = new Map();
    try {
        const days = [], kinds = [], keys = [], ns = [];
        for (const [k, n] of rows) {
            const [day, kind, key] = k.split('\t');
            days.push(day); kinds.push(kind); keys.push(key); ns.push(n);
        }
        await db.query(`
            INSERT INTO site_counts (day, kind, key, n)
            SELECT * FROM UNNEST($1::date[], $2::text[], $3::text[], $4::int[])
            ON CONFLICT (day, kind, key) DO UPDATE SET n = site_counts.n + EXCLUDED.n`, [days, kinds, keys, ns]);
    } catch (err) {
        // (kept for the next try)
        for (const [k, n] of rows) state.pending.set(k, (state.pending.get(k) || 0) + n);
        console.error('[site] visit counts not saved yet:', err.message);
    }
}

let timer = null;
/** Starts saving the counts every half a minute, and deletes old days once a day (server.js). */
function start() {
    if (timer) return;
    timer = setInterval(flush, FLUSH_EVERY);
    timer.unref();
    const tidy = () => db.query(`DELETE FROM site_counts WHERE day < CURRENT_DATE - $1::int`, [KEEP_DAYS])
        .catch((err) => console.error('[site] old visit counts:', err.message));
    tidy();
    setInterval(tidy, 24 * 3600_000).unref();
}

/** The last `days` days: each day's totals (oldest first), and the pages and sites over the whole span. */
async function stats(days = 30) {
    await flush();
    const since = today(new Date(Date.now() - (days - 1) * 86_400_000));
    const { rows } = await db.query(`
        SELECT to_char(day, 'YYYY-MM-DD') AS day, kind, key, n FROM site_counts WHERE day >= $1::date`, [since]);
    const byDay = new Map();
    for (let i = days - 1; i >= 0; i--) {
        byDay.set(today(new Date(Date.now() - i * 86_400_000)), { visitors: 0, views: 0, phone: 0 });
    }
    const pages = new Map(), from = new Map();
    for (const r of rows) {
        const n = Number(r.n);
        if (r.kind === 'total' && byDay.has(r.day)) byDay.get(r.day)[r.key] = n;
        else if (r.kind === 'page') pages.set(r.key, (pages.get(r.key) || 0) + n);
        else if (r.kind === 'from') from.set(r.key, (from.get(r.key) || 0) + n);
    }
    const top = (m) => [...m].sort((a, b) => b[1] - a[1]).slice(0, 25);
    return { days: [...byDay].map(([day, t]) => ({ day, ...t })), pages: top(pages), from: top(from) };
}

// ── GET /stats ───────────────────────────────────────────────────────────────────────────────────
const { esc } = require('./data');
const num = (n) => Number(n).toLocaleString('en-GB');
const DAY_NAME = (day) => new Date(`${day}T12:00:00Z`).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });

/** The stats page, from stats(). */
function page(s) {
    const sum = (list, k) => list.reduce((n, d) => n + d[k], 0);
    const last = (n) => s.days.slice(-n);
    const tile = (label, list) => `<div class="tile"><b>${num(sum(list, 'visitors'))}</b><span>${label}</span>
        <small>${num(sum(list, 'views'))} pages shown</small></div>`;
    const most = Math.max(1, ...s.days.map((d) => d.visitors));
    const bars = s.days.map((d) => {
        const tip = `${DAY_NAME(d.day)}: ${num(d.visitors)} visitor${d.visitors === 1 ? '' : 's'}, ${num(d.views)} page${d.views === 1 ? '' : 's'}`;
        return `<div class="col" tabindex="0" data-tip="${esc(tip)}" aria-label="${esc(tip)}"><i style="height:${(d.visitors / most * 100).toFixed(1)}%"></i></div>`;
    }).join('');
    const list = (rows, empty) => (rows.length
        ? `<table>${rows.map(([k, n]) => `<tr><td>${esc(k)}</td><td>${num(n)}</td></tr>`).join('')}</table>`
        : `<p class="none">${empty}</p>`);
    const days = [...s.days].reverse().map((d) => `<tr><td>${DAY_NAME(d.day)}</td><td>${num(d.visitors)}</td>
        <td>${num(d.views)}</td><td>${d.visitors ? Math.round(d.phone / d.visitors * 100) + '%' : '–'}</td></tr>`).join('');
    return `<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Website visits</title>
<style>
:root { --bg: #0b0b16; --panel: #121228; --line: #2c2c5a; --text: #dcdcea; --dim: #a4a4c0; --gold: #f4d35e; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 system-ui, sans-serif; }
main { max-width: 900px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { font-size: 24px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 32px 0 10px; }
.dim, .none { color: var(--dim); } small { color: var(--dim); }
.tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-top: 20px; }
@media (max-width: 479px) { .tile { padding: 10px; } .tile b { font-size: 24px; } }
.tile { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; display: grid; }
.tile b { font-size: 30px; line-height: 1.1; } .tile span { color: var(--text); }
.chart { display: flex; align-items: flex-end; gap: 2px; height: 180px; padding-top: 8px; border-bottom: 1px solid var(--line); }
.col { flex: 1; height: 100%; display: flex; align-items: flex-end; position: relative; outline: none; }
.col i { display: block; width: 100%; min-height: 1px; background: var(--gold); border-radius: 4px 4px 0 0; }
.col:hover i, .col:focus i { background: #fff3b8; }
.col:hover::after, .col:focus::after { content: attr(data-tip); position: absolute; bottom: calc(100% + 6px); left: 50%;
    transform: translateX(-50%); white-space: nowrap; background: #000; border: 1px solid var(--line); border-radius: 6px;
    padding: 4px 8px; font-size: 13px; z-index: 1; pointer-events: none; }
.col:first-child:hover::after, .col:first-child:focus::after { left: 0; transform: none; }
.col:last-child:hover::after, .col:last-child:focus::after { left: auto; right: 0; transform: none; }
.axis { display: flex; justify-content: space-between; font-size: 12px; color: var(--dim); margin-top: 4px; }
.lists { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 0 32px; }
table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
td, th { padding: 6px 4px; border-bottom: 1px solid var(--line); text-align: left; word-break: break-word; }
td:not(:first-child), th:not(:first-child) { text-align: right; white-space: nowrap; }
th { font-weight: 600; color: var(--dim); font-size: 13px; }
</style></head><body><main>
<h1>Website visits</h1>
<p class="dim">alleywaybrawlers.com · people who opened at least one page (robots and your home network aren't counted)</p>
<div class="tiles">${tile('today', last(1))}${tile('last 7 days', last(7))}${tile('last 30 days', last(30))}</div>
<h2>Visitors per day, last 30 days</h2>
<div class="chart">${bars}</div>
<div class="axis"><span>${DAY_NAME(s.days[0].day)}</span><span>today</span></div>
<div class="lists">
<section><h2>Most-read pages (30 days)</h2>${list(s.pages, 'No visits yet.')}</section>
<section><h2>Where visitors came from (30 days)</h2>${list(s.from, 'Nobody has come from a link or a search yet.')}
<p class="dim"><small>Only visits that came through a link or a search. Typed-in addresses and bookmarks aren't listed, and some sites hide where their visitors came from.</small></p></section>
</div>
<h2>Each day</h2>
<table><tr><th>Day</th><th>Visitors</th><th>Pages</th><th>On a phone</th></tr>${days}</table>
</main></body></html>`;
}

module.exports = { see, flush, start, stats, source, page, db, state };
