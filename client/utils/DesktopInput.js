/**
 * DESKTOP INPUT (desktop build only)
 * Mouse & keyboard on top of the touch-first scenes, without changing how they handle taps.
 *
 *  - Right-click a card: zoom it (right-click / Esc closes). Right-clicks never reach Phaser,
 *    so they can't trigger the left-click actions scenes wire to every pointer button.
 *  - Hover a card: gold outline + name tooltip.
 *  - Keys: Esc (close zoom → close settings → open settings in menu/duel),
 *          Space/Enter (NEXT phase), 1–9 (pick a hand card), Tab (hold: zone counts).
 *    A key only acts when the button/card it stands for could be clicked right now
 *    (nothing modal drawn over it), so shortcuts can't skip a prompt.
 *    F11 (fullscreen) is handled in the Electron main process.
 *  - Themed cursor.
 *
 * How cards are found: scenes either tag display objects (`obj.cardZoomData`, or a CardObject's
 * hit frame via `obj.cardObject`) or implement `cardAt(worldX, worldY)` → { cardData, bounds }.
 */

import Phaser from 'phaser';
import { showCardZoom, closeCardZoom, isCardZoomOpen } from './CardZoom.js';
import { openSettings } from '../scenes/SettingsScene.js';

const BACKGROUND_SCENES = new Set(['LetterboxScene', 'VideoBackgroundScene']);
const DUEL_SCENES       = new Set(['DuelScene', 'MultiplayerDuelScene']);
const SETTINGS_FROM     = new Set(['MainMenuScene', ...DUEL_SCENES]);
const TOOLTIP_DELAY_MS  = 300;

let game   = null;
let canvas = null;

// ── Finding what's under a point ─────────────────────────────────────────────

function toCanvas(clientX, clientY) {
    const r = canvas.getBoundingClientRect();
    return {
        x: (clientX - r.left) * (canvas.width / r.width),
        y: (clientY - r.top) * (canvas.height / r.height),
    };
}

/** Topmost running, non-background scene (the one the player is interacting with). */
function topScene() {
    return game.scene.getScenes(true, true).find(s => !BACKGROUND_SCENES.has(s.scene.key)) || null;
}

function isShown(obj) {
    for (let o = obj; o; o = o.parentContainer) {
        if (!o.visible || o.alpha === 0 || !o.active) return false;
    }
    return true;
}

/** Card data for a display object, or null. Opponents' face-down cards stay hidden. */
function cardDataOf(obj) {
    if (obj.cardZoomData) return obj.cardZoomData;
    const card = obj.cardObject;
    if (!card || (card._faceDown && card.mode === 'field_opp')) return null;
    return card.cardData;
}

/** Display objects in render order (top-level sorted by depth; containers in list order). */
function renderOrder(scene) {
    const out = [];
    const walk = list => {
        for (const o of list) {
            out.push(o);
            if (o.type === 'Container') walk(o.list);
        }
    };
    walk(scene.sys.displayList.list.slice().sort((a, b) => a.depth - b.depth));
    return out;
}

/**
 * What's under a world point in a scene: the last-drawn card and the last-drawn clickable
 * object there. A card only counts if nothing clickable is drawn on top of it.
 */
function probe(scene, wx, wy) {
    let card = null;
    let topClickable = null;
    for (const o of renderOrder(scene)) {
        const data = cardDataOf(o);
        const clickable = !!o.input?.enabled;
        if ((!data && !clickable) || !o.getBounds || !isShown(o)) continue;
        if (!o.getBounds().contains(wx, wy)) continue;
        if (clickable) topClickable = o;
        if (data) card = { obj: o, cardData: data };
        else if (card) card = null;   // a menu / shield / button drawn over the card
    }
    return { card, topClickable };
}

/** The card under a client (mouse) position, in the scene the player is using. */
function cardUnder(clientX, clientY) {
    const scene = topScene();
    if (!scene) return null;
    const p   = toCanvas(clientX, clientY);
    const cam = scene.cameras.main;
    if (p.x < cam.x || p.y < cam.y || p.x > cam.x + cam.width || p.y > cam.y + cam.height) return null;
    const w = cam.getWorldPoint(p.x, p.y);

    const custom = scene.cardAt?.(w.x, w.y);
    if (custom) return { scene, cardData: custom.cardData, bounds: custom.bounds };

    const { card } = probe(scene, w.x, w.y);
    return card ? { scene, cardData: card.cardData, obj: card.obj } : null;
}

/** Run `action` if `obj` is the clickable thing at its own centre (accept() widens that). */
function pressIfReachable(scene, obj, action, accept = top => top === obj) {
    if (!obj?.getBounds || !isShown(obj)) return false;
    const b = obj.getBounds();
    const { topClickable } = probe(scene, b.centerX, b.centerY);
    if (!topClickable || !accept(topClickable)) return false;
    action();
    return true;
}

// ── Hover outline + tooltip ──────────────────────────────────────────────────

let hover     = null;   // { scene, key, outline, follow }
let tooltipEl = null;
let tooltipTimer = null;
let lastMouse = null;

function hideTooltip() {
    clearTimeout(tooltipTimer);
    if (tooltipEl) tooltipEl.style.display = 'none';
}

function showTooltip(name) {
    if (!tooltipEl) {
        tooltipEl = document.createElement('div');
        tooltipEl.style.cssText = `
            position:fixed;z-index:1001;pointer-events:none;display:none;
            font:12px/1.35 'Arial Black',Arial,sans-serif;color:#f4d35e;
            background:rgba(10,10,26,.92);border:1px solid #f4d35e;border-radius:4px;
            padding:4px 8px;white-space:nowrap;box-shadow:0 2px 8px rgba(0,0,0,.5);
        `;
        document.body.appendChild(tooltipEl);
    }
    tooltipEl.innerHTML = '';
    const title = document.createElement('div');
    title.textContent = name;
    const hint = document.createElement('div');
    hint.textContent = 'Right-click for details';
    hint.style.cssText = 'font:10px Arial,sans-serif;color:#9ddcff;';
    tooltipEl.append(title, hint);
    positionTooltip();
    tooltipEl.style.display = 'block';
}

function positionTooltip() {
    if (!tooltipEl || !lastMouse) return;
    const x = Math.min(lastMouse.x + 16, window.innerWidth - tooltipEl.offsetWidth - 8);
    const y = Math.min(lastMouse.y + 18, window.innerHeight - tooltipEl.offsetHeight - 8);
    tooltipEl.style.left = `${x}px`;
    tooltipEl.style.top  = `${y}px`;
}

function clearHover() {
    if (!hover) return;
    hover.scene.events?.off('postupdate', hover.follow);
    hover.outline?.destroy();
    hover = null;
    hideTooltip();
}

function setHover(target) {
    const key = target ? (target.obj || target.cardData) : null;
    if (hover && target && hover.key === key && hover.scene === target.scene) {
        positionTooltip();
        return;
    }
    clearHover();
    if (!target) return;

    const { scene } = target;
    scene.onCardHover?.(target.cardData);   // e.g. the duel's card detail panel
    const outline = scene.add.rectangle(0, 0, 10, 10).setStrokeStyle(2, 0xf4d35e, 1).setDepth(150);
    // Follow the card every frame (hand cards lift and rotate on hover)
    const follow = () => {
        if (target.obj) {
            if (!target.obj.active) { clearHover(); return; }
            const m = target.obj.getWorldTransformMatrix();
            outline.setPosition(m.tx, m.ty).setRotation(m.rotation)
                .setSize(target.obj.width * m.scaleX + 4, target.obj.height * m.scaleY + 4);
        } else {
            const b = target.bounds;
            outline.setRotation(0).setPosition(b.centerX, b.centerY).setSize(b.width + 4, b.height + 4);
        }
    };
    follow();
    scene.events.on('postupdate', follow);
    hover = { scene, key, outline, follow };

    tooltipTimer = setTimeout(() => {
        if (hover?.key === key) showTooltip(target.cardData.name || 'Card');
    }, TOOLTIP_DELAY_MS);
}

function onMouseMove(e) {
    lastMouse = { x: e.clientX, y: e.clientY };
    if (e.target !== canvas || e.buttons || isCardZoomOpen()) { clearHover(); return; }
    setHover(cardUnder(e.clientX, e.clientY));
}

// ── Right-click ──────────────────────────────────────────────────────────────

function onRightButton(e) {
    if (e.button !== 2 || e.target !== canvas) return;
    // Keep right-clicks away from Phaser: scenes treat any button as a tap
    e.stopPropagation();
    e.preventDefault();
    if (e.type !== 'pointerdown') return;   // (cancelling pointerdown suppresses the mouse events)

    if (closeCardZoom()) return;
    const target = cardUnder(e.clientX, e.clientY);
    if (!target) return;
    clearHover();
    showCardZoom(target.scene, target.cardData);
}

// ── Keyboard ─────────────────────────────────────────────────────────────────

function typingInField(e) {
    const t = e.target;
    return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
}

function onKeyDown(e) {
    if (typingInField(e)) return;
    const scene = topScene();
    const key   = scene?.scene.key;
    const duel  = DUEL_SCENES.has(key) ? scene : null;

    if (e.code === 'Escape') {
        e.preventDefault();
        if (closeCardZoom()) return;
        if (key === 'SettingsScene') scene.close();
        else if (SETTINGS_FROM.has(key)) { clearHover(); openSettings(scene); }
        return;
    }
    if (e.code === 'Tab') {
        e.preventDefault();   // no browser focus cycling
        if (duel && !e.repeat) duel._showZoneSummary?.(true);
        return;
    }
    if (!duel || isCardZoomOpen() || e.repeat) return;

    if (e.code === 'Space' || e.code === 'Enter' || e.code === 'NumpadEnter') {
        e.preventDefault();
        const nextBg = duel._nextBtn?.list?.[0];
        pressIfReachable(duel, nextBg, () => nextBg.emit('pointerup'));
        return;
    }
    const digit = /^(?:Digit|Numpad)([1-9])$/.exec(e.code);
    if (digit) {
        const card = duel._handCards?.[Number(digit[1]) - 1];
        if (!card) return;
        // Hand cards overlap in the fan, so another hand card on top still counts as reachable
        pressIfReachable(duel, card._frame, () => duel._onHandCardTapped(card),
            top => top.cardObject?.mode === 'hand');
    }
}

function onKeyUp(e) {
    if (e.code !== 'Tab') return;
    for (const s of game.scene.getScenes(false)) {
        if (DUEL_SCENES.has(s.scene.key)) s._showZoneSummary?.(false);
    }
}

// ── Cursor ───────────────────────────────────────────────────────────────────

function svgCursor(fill) {
    const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'>` +
        `<path d='M3 2 L3 19 L7.5 14.5 L10.5 21 L13.5 19.7 L10.6 13.3 L17 13.3 Z' ` +
        `fill='${fill}' stroke='#0d0d1a' stroke-width='1.6' stroke-linejoin='round'/></svg>`;
    return `url("data:image/svg+xml,${encodeURIComponent(svg)}") 3 2`;
}

function installCursor() {
    const manager = game.input;
    const arrow   = `${svgCursor('#f4d35e')}, default`;   // gold
    const hand    = `${svgCursor('#4cc9f0')}, pointer`;   // cyan over anything clickable
    manager.setDefaultCursor(arrow);
    const setCursor = manager.setCursor.bind(manager);
    manager.setCursor = (io) => {
        if (io?.cursor === 'pointer') canvas.style.cursor = hand;
        else setCursor(io);
    };
}

// ── Install ──────────────────────────────────────────────────────────────────

export function installDesktopInput(g) {
    game   = g;
    canvas = g.canvas;
    installCursor();
    for (const type of ['mousedown', 'mouseup', 'pointerdown', 'pointerup']) {
        window.addEventListener(type, onRightButton, true);
    }
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', () => { clearHover(); onKeyUp({ code: 'Tab' }); });
    canvas.addEventListener('mouseleave', clearHover);
}
