'use strict';

/**
 * GAME DOWNLOADS
 *
 * Windows builds are copied into <repo>/downloads/ on the server (not in git: each zip is
 * ~150 MB). Players get them here:
 *
 *   GET /download          the newest AlleywayBrawlers-<version>-windows.zip
 *   GET /download/<file>   a specific zip, or a patch (AlleywayBrawlers-<version>-patch.pck)
 *
 * A patch updates the game in place (godot/scripts/patcher.gd): the manifest offers it when its
 * version is the latest one (routes/content.js, patchInfo below).
 *
 * The game's "update needed" screen links to /download unless CLIENT_DOWNLOAD_URL is set.
 */

const express = require('express');
const fs      = require('fs');
const path    = require('path');
const crypto  = require('crypto');

const router = express.Router();
const DIR = path.join(__dirname, '../../downloads');
const ZIP = /^AlleywayBrawlers-(\d+)\.(\d+)\.(\d+)-(windows|macos)\.zip$/;
const PATCH = /^AlleywayBrawlers-(\d+\.\d+\.\d+)-patch(-macos)?\.pck$/;
const hashes = new Map();   // file -> {mtimeMs, size, sha256}

/** The patch for `version` on a platform ('windows' or 'macos'), if one is in the folder: {path, size, sha256}. */
function patchInfo(version, platform = 'windows') {
    const file = `AlleywayBrawlers-${version}-patch${platform === 'macos' ? '-macos' : ''}.pck`;
    const full = path.join(DIR, file);
    if (!PATCH.test(file) || !fs.existsSync(full)) return null;
    const st = fs.statSync(full);
    let h = hashes.get(file);
    if (!h || h.mtimeMs !== st.mtimeMs || h.size !== st.size) {
        h = { mtimeMs: st.mtimeMs, size: st.size, sha256: crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex') };
        hashes.set(file, h);
    }
    return { path: `/download/${file}`, size: h.size, sha256: h.sha256 };
}

/** The newest full build for a platform ('windows' or 'macos'): its file name, or null. */
function newest(platform = 'windows') {
    let best = null;
    let bestKey = -1;
    for (const f of fs.existsSync(DIR) ? fs.readdirSync(DIR) : []) {
        const m = ZIP.exec(f);
        if (!m || m[4] !== platform) continue;
        const key = Number(m[1]) * 1e6 + Number(m[2]) * 1e3 + Number(m[3]);
        if (key > bestKey) {
            bestKey = key;
            best = f;
        }
    }
    return best;
}

/** The newest build for a platform, or a short note when there isn't one. */
function send(res, platform) {
    const f = newest(platform);
    if (!f) return res.status(404).send(`No ${platform === 'macos' ? 'Mac' : 'Windows'} download is available yet.`);
    res.download(path.join(DIR, f), f);
}

// A Mac (by its browser) gets the Mac build, anything else the Windows one
router.get('/', (req, res) => send(res, /Macintosh|Mac OS X/i.test(String(req.get('user-agent') || '')) ? 'macos' : 'windows'));
router.get('/mac', (_req, res) => send(res, 'macos'));
router.get('/windows', (_req, res) => send(res, 'windows'));

router.get('/:file', (req, res) => {
    const f = String(req.params.file);
    if (!(ZIP.test(f) || PATCH.test(f)) || !fs.existsSync(path.join(DIR, f))) return res.status(404).send('Not found.');
    res.download(path.join(DIR, f), f);
});

module.exports = { router, newest, patchInfo };
