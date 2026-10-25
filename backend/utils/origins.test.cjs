// Run: node backend/utils/origins.test.cjs
// Which websites may use the server (utils/origins.js): the game (no Origin) and the server's own site.
const assert = require('assert');
const express = require('express');
const http = require('http');
const { allowedOrigins, originAllowed, refuseOtherSites } = require('./origins');

const allowed = allowedOrigins({ PORT: '3000', APP_BASE_URL: 'https://alleywaybrawlers.duckdns.org/', CORS_ORIGINS: 'https://example.test, nonsense' });
assert.ok(originAllowed(undefined, allowed), 'the game sends no Origin');
assert.ok(originAllowed('', allowed));
assert.ok(originAllowed('https://alleywaybrawlers.duckdns.org', allowed), 'its own pages');
assert.ok(originAllowed('http://192.168.0.200:3000', allowed), 'the LAN address');
assert.ok(originAllowed('https://example.test', allowed), 'CORS_ORIGINS');
assert.ok(!originAllowed('https://evil.example', allowed), 'any other website');
assert.ok(!originAllowed('http://alleywaybrawlers.duckdns.org', allowed), 'not over plain http');

const app = express();
app.use(refuseOtherSites(allowed));
app.get('/x', (req, res) => res.json({ ok: true }));
const server = http.createServer(app).listen(0, async () => {
    const port = server.address().port;
    const get = (origin) => new Promise((resolve) => http.get({ port, path: '/x', headers: origin ? { origin } : {} }, (r) => resolve(r.statusCode)));
    assert.equal(await get(null), 200, 'the game gets in');
    assert.equal(await get('https://alleywaybrawlers.duckdns.org'), 200);
    assert.equal(await get('https://evil.example'), 403, 'another site is refused');
    server.close();
    console.log('origins: ok');
});
