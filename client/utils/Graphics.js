/**
 * GRAPHICS RUNTIME
 * Live-applied render options. SettingsManager owns the values and calls in here.
 *
 *  - Render scale (desktop only): scenes are laid out in an 844-wide world (Layout.js), but the canvas is
 *    sized to the window's physical pixels × renderScale and every scene camera is zoomed to
 *    match, so art and text stay sharp at 1080p/1440p/4K (above 100% supersamples).
 *    Web keeps the 844×390 canvas (zoom 1) and is unaffected.
 *    Scene code that reads pointer positions must use pointer.worldX/worldY.
 *  - FPS cap: frame limiter around the game step (keeps the remainder, so a 60 cap on a
 *    60 Hz display stays at 60 instead of halving like Phaser's built-in limit).
 *  - FPS overlay, pause-when-unfocused (desktop only).
 */

import Phaser from 'phaser';
import { isDesktop } from './Platform.js';

import { W, H, BASE_H } from './Layout.js';

const MAX_CANVAS = 8192;

let game          = null;
let renderScale   = 1;
let zoom          = 1;
let limitMs       = 0;
let pauseOnBlur   = false;
let pausedForBlur = false;
let fpsEl         = null;
let framesRendered = 0;

// ── Render scale ─────────────────────────────────────────────────────────────

function computeZoom() {
    if (!isDesktop) return 1;
    const fit = Math.min(window.innerWidth / W, window.innerHeight / H) * (window.devicePixelRatio || 1);
    const z   = Phaser.Math.Clamp(fit * renderScale, 0.25, MAX_CANVAS / W);
    return Math.round(z * 100) / 100;
}

/** Text is rasterised to its own canvas; match its resolution to the zoom so it isn't blurry. */
function textResolution() {
    return Phaser.Math.Clamp(Math.ceil(zoom * 2) / 2, 1, 4);
}

/** Converted scenes (fullLayout) use the whole 844×H world; the rest draw in the centred
 *  844×390 band they were designed for, with the letterbox showing above and below. */
function fitCameras(scene) {
    if (!scene.cameras) return;
    const viewH = scene.fullLayout ? H : BASE_H;
    const top   = Math.round(((H - viewH) / 2) * zoom);
    for (const cam of scene.cameras.cameras) {
        cam.setViewport(0, top, game.scale.width, Math.round(viewH * zoom));
        cam.setZoom(zoom);
        cam.centerOn(W / 2, viewH / 2);
    }
}

function forEachText(list, fn) {
    for (const obj of list) {
        if (obj instanceof Phaser.GameObjects.Text) fn(obj);
        else if (obj.list) forEachText(obj.list, fn);   // containers
    }
}

function applyZoom() {
    const z = computeZoom();
    zoom = z;
    game.scale.resize(Math.round(W * z), Math.round(H * z));
    const res = textResolution();
    for (const scene of game.scene.scenes) {
        fitCameras(scene);   // includes paused/sleeping scenes so they're right when resumed
        if (scene.sys.displayList) forEachText(scene.sys.displayList.list, t => { if (t._autoRes) t.setResolution(res); });
    }
}

function installRenderScale() {
    // Every scene start: zoom its cameras (cameras are recreated on each start/restart)
    for (const scene of game.scene.scenes) {
        scene.sys.events.on(Phaser.Scenes.Events.CREATE, () => fitCameras(scene));
    }
    // Texts created without an explicit resolution follow the zoom
    const factory  = Phaser.GameObjects.GameObjectFactory.prototype;
    const makeText = factory.text;
    factory.text = function (x, y, text, style) {
        const t = makeText.call(this, x, y, text, style);
        if (!style?.resolution) {
            t._autoRes = true;
            const res = textResolution();
            if (res !== 1) t.setResolution(res);
        }
        return t;
    };
    let pending = false;
    window.addEventListener('resize', () => {
        if (pending) return;
        pending = true;
        requestAnimationFrame(() => { pending = false; applyZoom(); });
    });
    applyZoom();
}

// ── FPS cap / overlay ────────────────────────────────────────────────────────

function installFrameLimiter() {
    const loop  = game.loop;
    const step  = loop.callback;
    let pendingDelta = 0;
    let budget       = 0;
    loop.callback = (time, delta) => {
        if (!limitMs) { step(time, delta); return; }
        pendingDelta += delta;
        budget       += delta;
        if (budget < limitMs - 0.5) return;
        budget = Math.min(budget - limitMs, limitMs);
        const d = pendingDelta;
        pendingDelta = 0;
        step(time, d);
    };
    game.events.on(Phaser.Core.Events.POST_RENDER, () => { framesRendered++; });
}

function startFpsOverlay() {
    if (fpsEl) return;
    fpsEl = document.createElement('div');
    fpsEl.style.cssText = `
        position:fixed;top:6px;left:8px;z-index:1000;pointer-events:none;
        font:12px/1.4 Consolas,monospace;color:#7CFC9A;background:rgba(0,0,0,.55);
        padding:1px 6px;border-radius:3px;
    `;
    document.body.appendChild(fpsEl);
    let last = performance.now();
    framesRendered = 0;
    fpsEl._timer = setInterval(() => {
        const now = performance.now();
        fpsEl.textContent = `${Math.round(framesRendered * 1000 / (now - last))} FPS`;
        framesRendered = 0;
        last = now;
    }, 500);
}

function stopFpsOverlay() {
    if (!fpsEl) return;
    clearInterval(fpsEl._timer);
    fpsEl.remove();
    fpsEl = null;
}

// ── Focus ────────────────────────────────────────────────────────────────────

function installFocusHandling() {
    game.events.on(Phaser.Core.Events.BLUR, () => {
        if (!pauseOnBlur || pausedForBlur) return;
        pausedForBlur = true;
        game.loop.sleep();
    });
    game.events.on(Phaser.Core.Events.FOCUS, () => {
        if (!pausedForBlur) return;
        pausedForBlur = false;
        game.loop.wake(true);
    });
}

// ── Public API ───────────────────────────────────────────────────────────────

export const Graphics = {
    /** Current camera zoom (1 on web). Effects that zoom the camera should multiply by this. */
    get zoom() { return zoom; },

    /** Called once from SettingsManager.init. */
    init(g, settings) {
        game        = g;
        renderScale = settings.renderScale;
        installFrameLimiter();
        this.setFpsLimit(isDesktop ? settings.fpsLimit : 0);
        if (!isDesktop) return;
        installRenderScale();
        installFocusHandling();
        this.setShowFps(settings.showFps);
        this.setPauseOnBlur(settings.pauseOnBlur);
    },

    setRenderScale(scale) {
        renderScale = scale;
        if (game && isDesktop) applyZoom();
    },

    setFpsLimit(fps) {
        limitMs = fps > 0 ? 1000 / fps : 0;
    },

    setShowFps(on) {
        if (!isDesktop) return;
        if (on) startFpsOverlay(); else stopFpsOverlay();
    },

    /** Off: keep running and keep the music playing in the background (Phaser pauses audio by default). */
    setPauseOnBlur(on) {
        if (!game || !isDesktop) return;
        pauseOnBlur = on;
        game.sound.pauseOnBlur = on;
    },
};
