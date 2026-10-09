/**
 * CARD TEXTURES
 * Card art ships at 1054×1492 but is mostly drawn at ~100–200 screen pixels. Scaling that far in
 * one step (WebGL, no mipmaps for these sizes) shimmers and looks grainy, so after loading we
 * build a smoothly downsampled copy of each card (`<key>@s`) by halving it step by step on a
 * canvas. Small views (field, hand, grids, piles) use the copy; zoom views keep the original.
 */

import Phaser from 'phaser';

const SUFFIX = '@s';
const SMALL_W = 360;   // ≈ the largest size a card is drawn on the board at 4K

/** Halve an image repeatedly (high-quality smoothing) until it's close to `targetW`. */
function downsample(img, targetW) {
    let src = img, w = img.width, h = img.height;
    while (w / 2 >= targetW) {
        const c = document.createElement('canvas');
        c.width = Math.round(w / 2);
        c.height = Math.round(h / 2);
        const g = c.getContext('2d');
        g.imageSmoothingEnabled = true;
        g.imageSmoothingQuality = 'high';
        g.drawImage(src, 0, 0, c.width, c.height);
        src = c; w = c.width; h = c.height;
    }
    if (w === targetW) return src;
    const c = document.createElement('canvas');
    c.width = targetW;
    c.height = Math.round(h * targetW / w);
    const g = c.getContext('2d');
    g.imageSmoothingQuality = 'high';
    g.drawImage(src, 0, 0, c.width, c.height);
    return c;
}

/** Builds `<key>@s` for each loaded texture key that is bigger than the small size. */
export function buildSmallCardTextures(scene, keys) {
    for (const key of keys) {
        if (!scene.textures.exists(key) || scene.textures.exists(key + SUFFIX)) continue;
        const img = scene.textures.get(key).getSourceImage();
        if (!img?.width || img.width <= SMALL_W * 1.5) continue;
        try {
            scene.textures.addCanvas(key + SUFFIX, downsample(img, SMALL_W));
            scene.textures.get(key + SUFFIX).setFilter(Phaser.Textures.FilterMode.LINEAR);
        } catch (_) { /* fall back to the full-size texture */ }
    }
}

/** The texture key to draw a card with at small sizes. */
export function cardTex(scene, key) {
    return key && scene.textures.exists(key + SUFFIX) ? key + SUFFIX : key;
}
