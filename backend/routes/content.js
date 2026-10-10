'use strict';

/**
 * GAME CONTENT FOR THE DESKTOP CLIENT
 *
 * The Godot client ships with the card data and card art built in. At start-up it asks for
 * this manifest, compares fingerprints (SHA-256), and downloads only what changed, so new or
 * changed cards reach players without a new build. It also tells the client which game version
 * is current (shared/game_version.json) and where to download it (CLIENT_DOWNLOAD_URL in .env).
 *
 *   GET /api/content/manifest        { contentVersion, client: {latest, minimum, downloadUrl},
 *                                      cards: {hash, size}, art: { <id>: {hash, size} } }
 *   GET /api/content/cards.json      the card catalogue (shared/cards.js + Card Forge cards)
 *   GET /api/content/art/<id>.png    a card image (client/assets/cards)
 *
 * The catalogue is read once per server start (restart after `git pull`); image fingerprints
 * are re-checked when the files change.
 */

const express = require('express');
const fs      = require('fs');
const path    = require('path');
const crypto  = require('crypto');

const router = express.Router();
const ART_DIR      = path.join(__dirname, '../../client/assets/cards');
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

function art() {
    const out = {};
    let files = [];
    try {
        files = fs.readdirSync(ART_DIR).filter(f => f.endsWith('.png'));
    } catch {
        return out;
    }
    for (const f of files) {
        const st = fs.statSync(path.join(ART_DIR, f));
        let e = artCache.get(f);
        if (!e || e.mtimeMs !== st.mtimeMs || e.size !== st.size) {
            e = { mtimeMs: st.mtimeMs, size: st.size, hash: sha256(fs.readFileSync(path.join(ART_DIR, f))) };
            artCache.set(f, e);
        }
        out[f.slice(0, -4)] = { hash: e.hash, size: e.size };
    }
    return out;
}

function versions() {
    let v = {};
    try {
        v = JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8'));
    } catch { /* keep defaults */ }
    return {
        latest: String(v.latest || '0.0.0'),
        minimum: String(v.minimum || '0.0.0'),
        downloadUrl: process.env.CLIENT_DOWNLOAD_URL || '',
    };
}

router.get('/manifest', async (_req, res) => {
    try {
        const c = await cards();
        const a = art();
        const contentVersion = sha256(c.hash + JSON.stringify(a)).slice(0, 16);
        res.set('Cache-Control', 'no-cache');
        res.json({ contentVersion, client: versions(), cards: { hash: c.hash, size: c.size }, art: a });
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

module.exports = router;
