/**
 * LAYOUT
 * Shared world dimensions and anchors.
 *
 * Scenes were designed for an 844×390 mobile-landscape world. On desktop the world is 16:9
 * at the same width (844×475), so every x coordinate stays valid and only vertical layout
 * needs to adapt.
 *
 *  - A scene that hasn't been converted is drawn in a centred 844×390 band; the space above
 *    and below shows the themed letterbox (LetterboxScene). Nothing to do.
 *  - A scene can set `this.fullLayout = 'center'` to fill the 16:9 view with its 390-tall
 *    design centred (it only has to stretch its full-screen layers — see VIEW_* below).
 *  - A converted scene sets `this.fullLayout = true` in its constructor and lays out against
 *    `H` using the anchors below. On web H === BASE_H, so the same code keeps working there.
 */

import { isDesktop } from './Platform.js';

export const W      = 844;
export const BASE_H = 390;                       // the height scenes were originally designed for
export const H      = isDesktop ? 475 : BASE_H;  // 844×475 ≈ 16:9
export const EXTRA_H = H - BASE_H;               // 85 on desktop, 0 on web

/** A y from the 390-tall design, kept centred in the taller world. */
export const midY = (y) => y + EXTRA_H / 2;

/** A y from the 390-tall design for something anchored to the bottom edge. */
export const bottomY = (y) => y + EXTRA_H;

// Scenes with `fullLayout = 'center'` keep their 390-tall design and get it centred in the
// 16:9 view; world y then runs VIEW_TOP..VIEW_BOTTOM. Full-screen layers (backgrounds, dim
// overlays, input shields) should span that instead of 0..390.
export const VIEW_TOP    = -EXTRA_H / 2;
export const VIEW_BOTTOM = BASE_H + EXTRA_H / 2;
export const VIEW_H      = BASE_H + EXTRA_H;

/** Visible world area of a scene for its layout mode — for overlays drawn into any scene. */
export function sceneView(scene) {
    const mode   = scene?.fullLayout;
    const top    = mode === 'center' ? VIEW_TOP : 0;
    const bottom = mode === 'center' ? VIEW_BOTTOM : mode ? H : BASE_H;
    return { top, bottom, h: bottom - top, cy: (top + bottom) / 2 };
}
