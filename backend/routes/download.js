'use strict';

/**
 * GAME DOWNLOADS
 *
 * Windows builds are copied into <repo>/downloads/ on the server (not in git: each zip is
 * ~150 MB). Players get them here:
 *
 *   GET /download          the newest AlleywayBrawlers-<version>-windows.zip
 *   GET /download/<file>   a specific zip from the folder
 *
 * The game's "update needed" screen links to /download unless CLIENT_DOWNLOAD_URL is set.
 */

const express = require('express');
const fs      = require('fs');
const path    = require('path');

const router = express.Router();
const DIR = path.join(__dirname, '../../downloads');
const ZIP = /^AlleywayBrawlers-(\d+)\.(\d+)\.(\d+)-windows\.zip$/;

function newest() {
    let best = null;
    let bestKey = -1;
    for (const f of fs.existsSync(DIR) ? fs.readdirSync(DIR) : []) {
        const m = ZIP.exec(f);
        if (!m) continue;
        const key = Number(m[1]) * 1e6 + Number(m[2]) * 1e3 + Number(m[3]);
        if (key > bestKey) {
            bestKey = key;
            best = f;
        }
    }
    return best;
}

router.get('/', (_req, res) => {
    const f = newest();
    if (!f) return res.status(404).send('No game download is available yet.');
    res.download(path.join(DIR, f), f);
});

router.get('/:file', (req, res) => {
    const f = String(req.params.file);
    if (!ZIP.test(f) || !fs.existsSync(path.join(DIR, f))) return res.status(404).send('Not found.');
    res.download(path.join(DIR, f), f);
});

module.exports = { router, newest };
