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

/** World height of a given scene: H if it is converted (fullLayout), else the 390 band. */
export const sceneH = (scene) => (scene?.fullLayout ? H : BASE_H);
