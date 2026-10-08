/**
 * Persistent toast queue. Toasts stack at the bottom-right of the screen,
 * each one visible for ~2.4s, fading out before the next one slides up.
 *
 * Usage: import { showToast } from '../utils/Toast.js';
 *        showToast(this, 'Saved!', 'success');
 */

import { sceneH } from './Layout.js';

const W = 844;

const COLORS = {
    info:    { fill: 0x1a1a2e, stroke: 0x4cc9f0, text: '#9ddcff' },
    success: { fill: 0x0f2a1a, stroke: 0x2d6a4f, text: '#a7e8c1' },
    warn:    { fill: 0x2a200a, stroke: 0xf4d35e, text: '#f4d35e' },
    error:   { fill: 0x2a0d12, stroke: 0xe63946, text: '#ffa7b0' },
};

const TOAST_W = 220;
const TOAST_H = 32;
const TOAST_GAP = 6;
const BOTTOM_MARGIN = 12;
const ANCHOR_X = W - 12 - TOAST_W / 2;

// One queue per scene-game instance, tracked by scene reference
function _stackKey(scene) {
    if (!scene.game._toastStack) scene.game._toastStack = [];
    return scene.game._toastStack;
}

export function showToast(scene, message, kind = 'info', duration = 2400) {
    if (!scene || !message) return;
    const colors = COLORS[kind] || COLORS.info;
    const stack  = _stackKey(scene);

    const slot   = stack.length;
    const targetY = (sceneH(scene) - BOTTOM_MARGIN) - (slot * (TOAST_H + TOAST_GAP)) - TOAST_H / 2;
    const startY  = targetY + 28;

    const bg = scene.add.rectangle(ANCHOR_X, startY, TOAST_W, TOAST_H, colors.fill, 0.95)
        .setStrokeStyle(2, colors.stroke).setDepth(9000).setAlpha(0);
    const txt = scene.add.text(ANCHOR_X, startY, message, {
        fontSize: '11px', fontFamily: 'Arial Black', color: colors.text,
        wordWrap: { width: TOAST_W - 16 }, align: 'center',
    }).setOrigin(0.5).setDepth(9001).setAlpha(0);

    const entry = { bg, txt, scene };
    stack.push(entry);

    scene.tweens.add({
        targets: [bg, txt], alpha: 1, y: targetY, duration: 220, ease: 'Power2',
    });

    scene.time.delayedCall(duration, () => {
        scene.tweens.add({
            targets: [bg, txt], alpha: 0, duration: 240, ease: 'Power2',
            onComplete: () => {
                bg.destroy(); txt.destroy();
                const idx = stack.indexOf(entry);
                if (idx >= 0) stack.splice(idx, 1);
                // Slide remaining toasts down to fill the gap
                stack.forEach((e, i) => {
                    const ny = (sceneH(e.scene) - BOTTOM_MARGIN) - (i * (TOAST_H + TOAST_GAP)) - TOAST_H / 2;
                    if (e.scene && e.scene.tweens) {
                        e.scene.tweens.add({ targets: [e.bg, e.txt], y: ny, duration: 180, ease: 'Power2' });
                    }
                });
            },
        });
    });
}
