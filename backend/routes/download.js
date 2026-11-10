'use strict';

/**
 * GAME DOWNLOADS
 *
 * Builds are copied into <repo>/downloads/ on the server (not in git: each is ~150 MB). Players get
 * them here:
 *
 *   GET /download          the newest build for the browser's device: AlleywayBrawlers-<version>-windows.zip,
 *                          -macos.zip, or -android.apk (an Android phone's browser)
 *   GET /download/windows, /download/mac, /download/android   that platform's newest build
 *   GET /download/<file>   a specific build, or a patch (AlleywayBrawlers-<version>-patch.pck)
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
const ZIP = /^AlleywayBrawlers-(\d+)\.(\d+)\.(\d+)-(?:(windows|macos)\.zip|(android)\.apk)$/;
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

/** The newest full build for a platform ('windows', 'macos' or 'android'): its file name, or null. */
function newest(platform = 'windows') {
    let best = null;
    let bestKey = -1;
    for (const f of fs.existsSync(DIR) ? fs.readdirSync(DIR) : []) {
        const m = ZIP.exec(f);
        if (!m || (m[4] || m[5]) !== platform) continue;
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
    if (!f) return res.status(404).send(`No ${{ macos: 'Mac', android: 'Android' }[platform] || 'Windows'} download is available yet.`);
    res.download(path.join(DIR, f), f);
}

// A Mac or an Android phone (by its browser) gets its own build, anything else the Windows one
router.get('/', (req, res) => {
    const agent = String(req.get('user-agent') || '');
    send(res, /Android/i.test(agent) ? 'android' : /Macintosh|Mac OS X/i.test(agent) ? 'macos' : 'windows');
});
router.get('/mac', (_req, res) => send(res, 'macos'));
router.get('/windows', (_req, res) => send(res, 'windows'));
router.get('/android', (_req, res) => send(res, 'android'));

router.get('/:file', (req, res) => {
    const f = String(req.params.file);
    if (!(ZIP.test(f) || PATCH.test(f)) || !fs.existsSync(path.join(DIR, f))) return res.status(404).send('Not found.');
    res.download(path.join(DIR, f), f);
});

module.exports = { router, newest, patchInfo };
