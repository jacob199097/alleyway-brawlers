// Run: node backend/site/site.test.cjs
// The website (routes/site.js): every page answers, every card and Striver line is on its clan's page,
// the pages load nothing from other sites and set no cookies, and the game's own calls are left alone.
process.env.SITE_URL = 'https://alleywaybrawlers.com';
process.env.CONTACT_EMAIL = 'hello@example.com';
const assert = require('assert');
const express = require('express');
const fs = require('fs');
const http = require('http');
const path = require('path');
const download = require('../routes/download');
const site = require('../routes/site');
const images = require('./images');
const visits = require('./visits');
const { load } = require('./data');

// One build to offer (the server looks in downloads/, which a test machine doesn't have)
download.newestInfo = (platform) => (platform === 'windows' ? { file: 'AlleywayBrawlers-9.9.9-windows.zip', version: '9.9.9', size: 300 * 1048576 } : null);

// The server's order (server.js): the game's routes, the legal pages, the website, its 404, the game's 404
const app = express();
app.get('/api/ping', (req, res) => res.json({ ok: true }));
app.use('/', require('../routes/legal'));
app.use('/', site.router);
app.use(site.notFound);
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

const count = (text, piece) => text.split(piece).length - 1;

const server = http.createServer(app).listen(0, async () => {
    try {
        const at = `http://127.0.0.1:${server.address().port}`;
        const get = (url, headers = {}) => fetch(at + url, { headers: { accept: 'text/html', ...headers }, redirect: 'manual' });
        const d = await load();

        // ── The card data the pages are built from ───────────────────────────────────────────────
        assert.ok(d.cards.length > 100 && d.total <= d.cards.length, 'the cards');
        assert.ok(d.clans.filter((c) => !c.neutral).length >= 2, 'the clans');
        assert.equal(d.clans.reduce((n, c) => n + c.cards.length, 0), d.cards.length, 'every card belongs to one clan (or Neutral)');
        for (const c of d.clans) {
            assert.ok(c.neutral || c.leader, `${c.name} has a leader`);
            for (const line of c.lines) {
                assert.deepEqual(line.levels.map((l) => l.level), [1, 2, 3], `${c.name}: a Striver line is levels 1, 2, 3`);
                assert.ok(line.levels[0].promote && line.levels[1].promote, `${line.levels[0].name} says how it promotes`);
            }
        }
        assert.ok(!d.markup('<script>alert(1)</script> BURN').includes('<script'), 'card text is escaped');

        // ── Every page answers, as a whole page that loads only this site's files ────────────────
        const paths = ['/', '/clans', ...d.clans.map((c) => `/clans/${c.id}`), '/cards', '/how-to-play', '/news', '/support'];
        const html = {};
        for (const p of paths) {
            const r = await get(p);
            assert.equal(r.status, 200, p);
            assert.match(r.headers.get('content-type'), /text\/html/, p);
            assert.equal(r.headers.get('set-cookie'), null, `${p}: no cookies`);
            assert.match(r.headers.get('content-security-policy'), /default-src 'self'/, `${p}: only its own files`);
            const text = html[p] = await r.text();
            assert.match(text, /^<!doctype html>/i, p);
            assert.match(text, /<title>[^<]+<\/title>/, `${p}: a title`);
            assert.ok(!/\bundefined\b|\bNaN\b|\[object Object\]/.test(text.replace(/<script[^>]*>[^]*?<\/script>/g, '')), `${p}: nothing unfilled`);
            // (what the page loads: pictures, the style sheet, the script; a link to another site would be fine)
            for (const m of text.matchAll(/<(?:img|script|source|iframe|video|audio)\b[^>]*?\bsrc="([^"]*)"/g)) {
                assert.ok(m[1].startsWith('/') && !m[1].startsWith('//'), `${p}: loads ${m[1]}`);
            }
            for (const m of text.matchAll(/<link\b[^>]*?\brel="(?:stylesheet|icon|preload|apple-touch-icon)"[^>]*?\bhref="([^"]*)"/g)) {
                assert.ok(m[1].startsWith('/') && !m[1].startsWith('//'), `${p}: loads ${m[1]}`);
            }
            assert.ok(!/<script(?![^>]*\bsrc=)(?![^>]*application\/ld\+json)/.test(text), `${p}: no script written into the page`);
        }
        assert.ok(html['/'].includes('href="/download/windows"'), 'the build there is, is offered');
        assert.ok(!html['/'].includes('href="/download/mac"') && html['/'].includes('Not available yet'), 'a build there isn\'t, is not');
        assert.ok(html['/'].includes('Accounts and progress will be reset'), 'the pre-launch note is by the downloads');
        assert.equal(count(html['/'], '<span class="stage">Alpha</span>'), 2, 'the version says alpha, at the top and by the downloads');
        for (const store of ['Steam', 'Google Play']) {
            assert.equal(count(html['/'], `<small>Coming soon to</small>${store}</span>`), 2, `coming soon to ${store}, at the top and by the downloads`);
        }
        assert.equal(count(html['/'], '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M'), 4, 'each store with its logo');
        assert.ok(html['/'].includes('href="mailto:hello@example.com"'), 'the contact address the legal pages give is in the footer');
        // Support: the FAQ, the release date, where to report a bug; linked from every page's footer and the downloads
        assert.ok(html['/support'].includes('scheduled to be released sometime in Q1 2027'), 'Support: when the game comes out');
        assert.ok(/report a bug[^]*?mailto:hello@example\.com/.test(html['/support']), 'Support: bugs go to the contact address');
        assert.ok(html['/support'].includes('"@type":"FAQPage"'), 'Support: the FAQ for search engines');
        assert.ok(html['/cards'].includes('href="/support"') && html['/'].includes('class="fine help"'), 'Support is linked from the footer and the downloads');

        // ── A clan's page: its leader, every Striver line as three levels, every card ────────────
        for (const c of d.clans) {
            const text = html[`/clans/${c.id}`];
            for (const card of c.cards) assert.ok(text.includes(`data-card="${card.id}"`), `${c.name}: ${card.name} is on its page`);
            assert.equal(count(text, '<li class="level">'), c.lines.length * 3, `${c.name}: its Striver lines`);
            if (c.leader) assert.ok(text.includes(c.leader.name.replace(/&/g, '&amp;')), `${c.name}: its leader`);
        }

        // ── /cards: all of them, and the filters (the browser does the same test as you type) ────
        const shown = (text) => count(text, '<a class="card"') - (text.match(/<a class="card"[^>]* hidden>/g) || []).length;
        assert.equal(count(html['/cards'], 'data-q="'), d.cards.length, 'every card is on /cards');
        assert.equal(shown(html['/cards']), d.cards.length);
        const clan = d.clans.find((c) => !c.neutral);
        assert.equal(shown(await (await get(`/cards?clan=${clan.id}`)).text()), clan.cards.length, 'one clan');
        assert.equal(shown(await (await get(`/cards?clan=${clan.id}&kind=leader`)).text()), clan.cards.filter((c) => c.group === 'leader').length, 'one clan\'s leaders');
        assert.equal(shown(await (await get('/cards?q=zzzzzz')).text()), 0, 'a search nothing matches');
        assert.equal((await get('/cards?clan[]=x&q[]=y')).status, 200, 'junk in the address is survived');

        // ── One card: its page, and the piece the zoom asks for ──────────────────────────────────
        for (const card of d.cards) {
            const r = await get(`/cards/${card.id}`);
            assert.equal(r.status, 200, card.id);
            if (card.line) assert.equal(count(await r.text(), 'class="mini-line"'), 1, `${card.name}: its Striver line`);
        }
        const piece = await (await get(`/cards/${d.cards[0].id}?fragment=1`)).text();
        assert.ok(piece.startsWith('<article') && !piece.includes('<html'), 'the zoom gets only the card');
        const words = await (await get('/site/keywords.json')).json();
        assert.ok(Object.keys(words).length > 5 && Object.values(words).every((w) => w.name && w.text), 'what each keyword means');

        // ── Pages that aren't there ──────────────────────────────────────────────────────────────
        for (const p of ['/cards/no_such_card', '/clans/no_such_clan', '/nowhere']) {
            const r = await get(p);
            assert.equal(r.status, 404, p);
            assert.ok((await r.text()).includes('Dead end'), `${p}: the site's own 404`);
        }
        let r = await get('/api/nowhere');
        assert.equal(r.status, 404);
        assert.deepEqual(await r.json(), { error: 'Not found' }, 'the game\'s calls get the game\'s answer');
        r = await get('/nowhere', { accept: 'application/json' });
        assert.deepEqual(await r.json(), { error: 'Not found' }, 'and so does anything that isn\'t a browser');
        assert.deepEqual(await (await get('/api/ping')).json(), { ok: true });
        assert.equal((await get('/privacy')).status, 200, 'the privacy policy is still there');
        assert.equal((await get('/terms')).status, 200, 'and the terms');

        // ── One address: a page asked for through the server's other names goes to SITE_URL ─────
        r = await get('/clans?x=1', { 'x-forwarded-host': 'play.alleywaybrawlers.com' });
        assert.equal(r.status, 302);
        assert.equal(r.headers.get('location'), 'https://alleywaybrawlers.com/clans?x=1');
        assert.equal((await get('/clans', { 'x-forwarded-host': 'alleywaybrawlers.com' })).status, 200);
        assert.equal((await get('/api/ping', { 'x-forwarded-host': 'play.alleywaybrawlers.com' })).status, 200, 'the game\'s calls are never sent away');
        assert.equal((await get('/site/site.css', { 'x-forwarded-host': 'play.alleywaybrawlers.com' })).status, 200);

        // ── For search engines ───────────────────────────────────────────────────────────────────
        const map = await (await get('/sitemap.xml')).text();
        assert.equal(count(map, '<loc>https://alleywaybrawlers.com/'), paths.length + d.cards.length + 2, 'the sitemap: every page, every card, the two legal pages');
        assert.match(await (await get('/robots.txt')).text(), /Sitemap: https:\/\/alleywaybrawlers\.com\/sitemap\.xml/);

        // ── The site's files: only what's in website/, only the kinds a page uses ────────────────
        for (const file of ['site.css', 'site.js', 'fonts/anton.woff2']) assert.equal((await get(`/site/${file}`)).status, 200, file);
        assert.equal((await get('/favicon.ico')).status, 200);
        for (const p of ['/site/README.md', '/site/shots/shots.json', '/site/..%2Fserver.js', '/site/%2e%2e/package.json']) {
            assert.equal((await get(p)).status, 404, `${p} is not handed out`);
        }
        const shots = JSON.parse(fs.readFileSync(path.join(__dirname, '../../website/shots/shots.json'), 'utf8'));
        for (const m of html['/'].matchAll(/href="(\/site\/shots\/[^"?]+)/g)) assert.equal((await get(m[1])).status, 200, m[1]);
        assert.ok(Object.keys(shots).length > 0 && count(html['/'], 'data-shot') > 3, 'screenshots from the game');

        // ── Pictures: made smaller, in the sizes the pages use and no others ─────────────────────
        const card = d.cards.find((c) => images.source('card', c.id));
        assert.ok(card, 'the card art is in assets/cards');
        r = await get(`/site/pic/card/${card.id}-180.webp`);
        assert.equal(r.status, 200);
        if (images.resizing) {
            assert.equal(r.headers.get('content-type'), 'image/webp');
            const small = (await r.arrayBuffer()).byteLength;
            assert.ok(small > 1000 && small < 60_000, `a small picture is small (${small} bytes)`);
        } else {
            console.log('site: sharp is not installed, so the pictures go out full size (npm install in backend/)');
        }
        for (const p of [`/site/pic/card/${card.id}-181.webp`, `/site/pic/card/${card.id}-180.gif`, '/site/pic/card/..-180.webp', `/site/pic/secret/${card.id}-180.webp`]) {
            assert.equal((await get(p)).status, 404, `${p} is not made`);
        }

        // ── The visit counter: people only, once a day each, and only totals kept ────────────────
        // (everything above came from this machine with no browser: none of it counted)
        assert.equal(visits.state.pending.size, 0, 'robots and the home network aren\'t counted');
        const browser = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
        const phone = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
        const visit = (p, agent, ip, more = {}) => get(p, { 'user-agent': agent, 'x-forwarded-for': ip, ...more });
        await visit('/', browser, '203.0.113.5', { referer: 'https://www.google.com/' });
        await visit('/cards', browser, '203.0.113.5', { referer: 'https://alleywaybrawlers.com/' });
        await visit('/cards', phone, '198.51.100.7', { referer: 'https://old.reddit.com/r/cardgames' });
        await visit('/', 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)', '66.249.66.1');
        await visit(`/cards/${d.cards[0].id}?fragment=1`, browser, '203.0.113.5');
        await visit('/', browser, '203.0.113.9', { 'sec-purpose': 'prefetch' });
        await visit('/nowhere', browser, '203.0.113.5');
        await visit('/', browser, '192.168.0.12');
        // (a stand-in for the database: site_counts as a list)
        const saved = [];
        visits.db.query = async (sql, params) => {
            if (/INSERT INTO site_counts/.test(sql)) {
                params[0].forEach((day, i) => {
                    const row = saved.find((x) => x.day === day && x.kind === params[1][i] && x.key === params[2][i]);
                    if (row) row.n += params[3][i]; else saved.push({ day, kind: params[1][i], key: params[2][i], n: params[3][i] });
                });
            } else if (/SELECT/.test(sql)) {
                return { rows: saved.filter((x) => x.day >= params[0]) };
            }
            return { rows: [] };
        };
        await visits.flush();
        const n = (kind, key) => saved.filter((x) => x.kind === kind && x.key === key).reduce((t, x) => t + x.n, 0);
        assert.equal(n('total', 'views'), 3, 'pages shown: not the robot, the zoom, a prefetch, a 404 or the home network');
        assert.equal(n('total', 'visitors'), 2, 'a visitor counts once a day');
        assert.equal(n('total', 'phone'), 1, 'visitors on a phone');
        assert.equal(n('page', '/cards'), 2);
        assert.equal(n('from', 'Google'), 1, 'came from a search');
        assert.equal(n('from', 'Reddit'), 1, 'came from a link');
        assert.equal(saved.filter((x) => x.kind === 'from').length, 2, 'moving between the site\'s own pages isn\'t "coming from" anywhere');
        assert.ok(!JSON.stringify(saved).includes('203.0.113'), 'no IP address is kept');

        // The counts page: only with the password, never kept by a browser or a search engine
        assert.equal((await get('/stats')).status, 404, 'no password set: no page');
        process.env.SITE_STATS_PASSWORD = 'test-password';
        const login = (pass) => ({ authorization: `Basic ${Buffer.from(`me:${pass}`).toString('base64')}` });
        r = await get('/stats');
        assert.equal(r.status, 401);
        assert.match(r.headers.get('www-authenticate'), /^Basic/, 'the browser asks for the password');
        assert.equal((await get('/stats', login('wrong'))).status, 401, 'a wrong password');
        r = await get('/stats', login('test-password'));
        assert.equal(r.status, 200);
        assert.match(r.headers.get('cache-control'), /no-store/);
        assert.equal(r.headers.get('set-cookie'), null);
        const stats = await r.text();
        assert.match(stats, /<b>2<\/b><span>today/, 'today\'s visitors');
        assert.ok(stats.includes('Reddit') && stats.includes('/cards'), 'where they came from, what they read');
        assert.equal(count(stats, 'class="col"'), 30, 'a bar for each of the last 30 days');
        assert.match(await (await get('/robots.txt')).text(), /Disallow: \/stats/);
        delete process.env.SITE_STATS_PASSWORD;

        console.log(`site: ok (${paths.length} pages, ${d.cards.length} cards, ${d.clans.reduce((n, c) => n + c.lines.length, 0)} Striver lines)`);
    } catch (err) {
        console.error(err);
        process.exitCode = 1;
    } finally {
        server.close();
    }
});
