'use strict';

/**
 * THE WEBSITE'S PICTURES
 *
 * The art in assets/ is made for the game: a card is a 1054×1492 PNG of 2-3 MB. The website shows the
 * same files made smaller (WebP), the first time each is asked for, and keeps them in
 * backend/.cache/site/ (git-ignored and safe to delete: it fills up again).
 *
 *   /site/pic/<kind>/<name>-<width>.webp     e.g. /site/pic/card/card_nebu_009-360.webp
 *   /site/pic/<kind>/<name>-<width>.jpg      (for link previews: not every app shows WebP)
 *
 *   url(kind, name, width)   that address with ?v=<when the picture last changed>, so browsers keep it;
 *                            '' when there is no such picture
 *   send(req, res, next)     the route
 *   warm(ids)                makes the card pictures the listings use, one at a time, after start-up
 *
 * Only the kinds and widths in KINDS are served, so nobody can fill the disk by asking for odd sizes.
 * Resizing needs `sharp` (an optional dependency: `npm install` in backend/). Without it the full-size
 * PNG is sent instead: the pages still work, only heavier.
 */

const fs   = require('fs');
const path = require('path');

let sharp = null;
try {
    sharp = require('sharp');
    sharp.concurrency(1);   // (the game comes first)
    sharp.cache(false);
} catch { /* not installed: full-size pictures */ }

const ASSETS = path.join(__dirname, '../../assets');
const CACHE  = path.join(__dirname, '../.cache/site');

// kind → where its pictures are in assets/, and the widths the pages use
const KINDS = {
    card:    { file: (n) => `cards/${n}.png`,     widths: [180, 360, 760] },
    emblem:  { file: (n) => `emblems/${n}.png`,   widths: [96, 240, 480] },
    back:    { file: (n) => `card_back_${n}.png`, widths: [360] },
    booster: { file: (n) => `${n}_booster.png`,   widths: [360] },
    deckbox: { file: (n) => `${n}_deckbox.png`,   widths: [360] },
    rank:    { file: (n) => `ranks/${n}.png`,     widths: [160] },
};

const stamps = new Map();   // source file → when it last changed (base 36), or '' when it isn't there

/** The picture in assets/ and its stamp: { file, stamp }, or null. */
function source(kind, name) {
    if (!KINDS[kind] || !/^[a-z0-9_]+$/.test(String(name))) return null;
    const file = path.join(ASSETS, KINDS[kind].file(name));
    if (!stamps.has(file)) {
        let stamp = '';
        try {
            stamp = Math.round(fs.statSync(file).mtimeMs).toString(36);
        } catch { /* no such picture */ }
        stamps.set(file, stamp);
    }
    return stamps.get(file) ? { file, stamp: stamps.get(file) } : null;
}

function url(kind, name, width, ext = 'webp') {
    const src = source(kind, name);
    return src ? `/site/pic/${kind}/${name}-${width}.${ext}?v=${src.stamp}` : '';
}

// One picture at a time, and one job per picture however many visitors ask for it at once
let queue = Promise.resolve();
const making = new Map();   // cache file → its job

/** The small version of a picture: the cache file's name (relative to CACHE), made if missing or stale. */
function small(kind, name, width, ext) {
    const src = source(kind, name);
    const rel = `${kind}/${name}-${width}.${ext}`;
    const out = path.join(CACHE, rel);
    try {
        if (fs.statSync(out).mtimeMs >= fs.statSync(src.file).mtimeMs) return Promise.resolve(rel);
    } catch { /* not made yet */ }
    if (making.has(out)) return making.get(out);

    const job = queue.then(async () => {
        await fs.promises.mkdir(path.dirname(out), { recursive: true });
        const tmp = `${out}.${process.pid}.tmp`;
        const img = sharp(src.file).resize({ width, withoutEnlargement: true });
        await (ext === 'jpg' ? img.flatten({ background: '#0d0d1a' }).jpeg({ quality: 84 }) : img.webp({ quality: 82 })).toFile(tmp);
        await fs.promises.rename(tmp, out);
        return rel;
    }).finally(() => making.delete(out));
    making.set(out, job);
    queue = job.catch(() => {});
    return job;
}

/** GET /site/pic/<kind>/<name>-<width>.<webp|jpg> */
async function send(req, res, next) {
    const m = /^\/([a-z]+)\/([a-z0-9_]+)-(\d+)\.(webp|jpg)$/.exec(req.path);
    const src = m && source(m[1], m[2]);
    if (!src || !KINDS[m[1]].widths.includes(Number(m[3]))) return next();
    // (?v= is the picture's stamp: with it the address changes when the picture does)
    const keep = req.query.v ? { maxAge: '1y', immutable: true } : { maxAge: '1h' };
    if (!sharp) return res.sendFile(src.file, keep);
    try {
        res.sendFile(await small(m[1], m[2], Number(m[3]), m[4]), { root: CACHE, dotfiles: 'allow', ...keep });
    } catch (err) {
        console.error(`[site] couldn't resize ${m[1]}/${m[2]}:`, err.message);
        res.sendFile(src.file, { maxAge: '5m' });
    }
}

/** Makes the listings' card pictures ahead of the first visitor (quietly: a failure only means "later"). */
function warm(ids, width = 360) {
    if (!sharp) return;
    (async () => {
        for (const id of ids) {
            if (!source('card', id)) continue;
            try {
                await small('card', id, width, 'webp');
            } catch { /* made (or reported) when someone asks for it */ }
        }
    })();
}

module.exports = { url, send, warm, source, KINDS, resizing: !!sharp };
