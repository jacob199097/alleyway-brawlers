// The website on this PC, for working on it: the same pages the server sends (backend/routes/site.js)
// plus the privacy and terms pages, with no database and no game server.
//
//   node tools/site_dev.mjs [port]      then open http://localhost:3100
//
// Pages are built fresh on every request, so a change to website/site.css or site.js shows on reload;
// a change to backend/site/*.js needs this restarted. The download buttons show the builds in builds/
// (the server looks in downloads/); the downloads themselves aren't served here.
// Needs `npm install` in backend/ (express, and sharp for the small pictures).
import { existsSync, readdirSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const BUILDS = join(ROOT, 'builds');
const port = Number(process.argv[2] || 3100);

process.env.SITE_URL = '';   // (no "one real address" here: the pages answer to localhost)
const require = createRequire(join(ROOT, 'backend/package.json'));
const express = require('express');
const download = require('./routes/download');
const site = require('./routes/site');

// The newest build of each platform in builds/, in the shape download.newestInfo gives
download.newestInfo = (platform = 'windows') => {
    const wanted = new RegExp(`^AlleywayBrawlers-(\\d+)\\.(\\d+)\\.(\\d+)-${platform}\\.(zip|apk)$`);
    let best = null;
    for (const file of existsSync(BUILDS) ? readdirSync(BUILDS) : []) {
        const m = wanted.exec(file);
        if (!m) continue;
        const key = Number(m[1]) * 1e6 + Number(m[2]) * 1e3 + Number(m[3]);
        if (!best || key > best.key) best = { key, file, version: `${m[1]}.${m[2]}.${m[3]}`, size: statSync(join(BUILDS, file)).size };
    }
    return best;
};

const app = express();
app.use('/', require('./routes/legal'));
app.use('/', site.router);
app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use(site.notFound);
app.listen(port, () => console.log(`The website: http://localhost:${port}`));
