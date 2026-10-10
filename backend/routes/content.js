'use strict';

/**
 * GAME CONTENT FOR THE DESKTOP CLIENT
 *
 * The Godot client ships with the card data and card art built in. At start-up it asks for
 * this manifest, compares fingerprints (SHA-256), and downloads only what changed, so new or
 * changed cards reach players without a new build. It also tells the client which game version
 * is current (shared/game_version.json) and where to download it (CLIENT_DOWNLOAD_URL in .env).
 *
 *   GET /api/content/manifest        { contentVersion, client: {latest, minimum, downloadUrl, patch},
 *                                      cards: {hash, size}, art: { <id>: {hash, size} } }
 *   GET /api/content/cards.json      the card catalogue (shared/cards.js + Card Forge cards)
 *   GET /api/content/art/<id>.png    a card image (assets/cards)
 *   GET /api/content/back/<id>.png   a card back (assets/card_back*.png), e.g. card_back_militia
 *   The manifest also lists backs: { <id>: {hash, size} }, so a new clan's back needs no new build.
 *
 * The catalogue is read once per server start (restart after `git pull`); image fingerprints
 * are re-checked when the files change.
 */

const express = require('express');
const fs      = require('fs');
const path    = require('path');
const crypto  = require('crypto');

const { patchInfo } = require('./download');

const router = express.Router();
const ART_DIR      = path.join(__dirname, '../../assets/cards');
const BACK_DIR     = path.join(__dirname, '../../assets');
const VERSION_FILE = path.join(__dirname, '../../shared/game_version.json');

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

let catalog = null;            // { json, hash, size }
const artCache = new Map();    // file name → { mtimeMs, size, hash }

async function cards() {
    if (!catalog) {
        const { CARD_CATALOG } = await import('../../shared/cards.js');
        // Byte-for-byte what godot/tools/export_cards.mjs writes, so fingerprints line up
        const json = JSON.stringify(CARD_CATALOG, null, 1) + '\n';
        catalog = { json, hash: sha256(json), size: Buffer.byteLength(json) };
    }
    return catalog;
}

/** Fingerprints of the PNGs in dir that pass keep(fileName): { <id>: {hash, size} }. */
function fingerprints(dir, keep) {
    const out = {};
    let files = [];
    try {
        files = fs.readdirSync(dir).filter(f => f.endsWith('.png') && keep(f));
    } catch {
        return out;
    }
    for (const f of files) {
        const full = path.join(dir, f);
        const st = fs.statSync(full);
        let e = artCache.get(full);
        if (!e || e.mtimeMs !== st.mtimeMs || e.size !== st.size) {
            e = { mtimeMs: st.mtimeMs, size: st.size, hash: sha256(fs.readFileSync(full)) };
            artCache.set(full, e);
        }
        out[f.slice(0, -4)] = { hash: e.hash, size: e.size };
    }
    return out;
}
const art = () => fingerprints(ART_DIR, () => true);
const backs = () => fingerprints(BACK_DIR, (f) => /^card_back(_[a-z0-9_]+)?\.png$/.test(f));

function versions() {
    let v = {};
    try {
        v = JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8'));
    } catch { /* keep defaults */ }
    const latest = String(v.latest || '0.0.0');
    const patch = v.patchBase ? patchInfo(latest) : null;
    return {
        latest,
        minimum: String(v.minimum || '0.0.0'),
        // An in-place update to the latest version for builds at patchBase or newer (godot/scripts/patcher.gd)
        patch: patch ? { version: latest, base: String(v.patchBase), ...patch } : null,
        // The server hosts the builds itself (routes/download.js) unless .env points elsewhere
        downloadUrl: process.env.CLIENT_DOWNLOAD_URL
            || (process.env.APP_BASE_URL ? `${process.env.APP_BASE_URL.replace(/\/+$/, '')}/download` : ''),
    };
}

router.get('/manifest', async (_req, res) => {
    try {
        const c = await cards();
        const a = art();
        const b = backs();
        const contentVersion = sha256(c.hash + JSON.stringify(a) + JSON.stringify(b)).slice(0, 16);
        res.set('Cache-Control', 'no-cache');
        res.json({ contentVersion, client: versions(), cards: { hash: c.hash, size: c.size }, art: a, backs: b });
    } catch (err) {
        console.error('[content/manifest]', err.message);
        res.status(500).json({ error: 'Could not build the content manifest.' });
    }
});

router.get('/cards.json', async (_req, res) => {
    try {
        const c = await cards();
        res.set('Cache-Control', 'no-cache');
        res.type('application/json').send(c.json);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Card ids are lower-case letters, digits and _, so nothing outside the art folder is reachable
router.get('/art/:file', (req, res) => {
    const file = String(req.params.file);
    if (!/^[a-z0-9_]+\.png$/.test(file)) return res.status(404).end();
    res.set('Cache-Control', 'public, max-age=86400');
    res.sendFile(path.join(ART_DIR, file), (err) => {
        if (err && !res.headersSent) res.status(404).end();
    });
});

router.get('/back/:file', (req, res) => {
    const file = String(req.params.file);
    if (!/^card_back(_[a-z0-9_]+)?\.png$/.test(file)) return res.status(404).end();
    res.set('Cache-Control', 'public, max-age=86400');
    res.sendFile(path.join(BACK_DIR, file), (err) => {
        if (err && !res.headersSent) res.status(404).end();
    });
});

module.exports = router;
