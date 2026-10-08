/**
 * CardZoom — fullscreen card-detail overlay.
 * showCardZoom(scene, cardData)  → shows overlay, returns dismiss fn
 * attachHoldZoom(scene, obj, cardData, holdMs)  → wires hold-to-zoom on any interactive object
 */
import { sceneH, BASE_H } from './Layout.js';

const ZOOM_W = 240;
const ZOOM_H = 336;   // 5:7 portrait — bigger art, narrower stats panel
const DEPTH  = 200;

const RARITY_LABEL = { 1: 'Common', 2: 'Rare', 3: 'Epic', 4: 'Legendary', 5: 'Mythic' };
const RARITY_COLOR = { 1: '#9aa0a6', 2: '#2196f3', 3: '#f4d35e', 4: '#9c27b0', 5: '#ff9800' };

const FACTION_LABEL = {
    lion_pride:    'Lions',
    viper_clan:    'Vipers',
};

const CLAN_TAG_LABEL = {
    lion:  'Lions',
    viper: 'Vipers',
};

const CARD_TYPE_LABEL = {
    gang_member: 'Gang Member',
    hustle:      'Hustle',
    ambush:      'Ambush',
    leader:      'Leader',
};

function _capitalize(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }

function _formatCardNumber(cardData) {
    // Prefer an explicit cardNumber if present; otherwise hash the id into 4 digits
    if (cardData.cardNumber) return String(cardData.cardNumber).padStart(4, '0');
    const src = cardData.id || cardData.cardId || cardData.name || '';
    let h = 0;
    for (let i = 0; i < src.length; i++) h = ((h * 31) + src.charCodeAt(i)) >>> 0;
    return String(h % 10000).padStart(4, '0');
}

/** Normalise card data so snake_case (DB rows) and camelCase (in-game catalog)
 * fields all resolve. */
function _normalize(data) {
    const d = { ...data };
    if (d.cardType   == null && d.card_type    != null) d.cardType   = d.card_type;
    if (d.effectText == null && d.effect_text  != null) d.effectText = d.effect_text;
    if (d.flavourText== null && d.flavour_text != null) d.flavourText= d.flavour_text;
    if (d.flavourText== null && d.flavor_text  != null) d.flavourText= d.flavor_text;
    if (d.art_url    == null && d.artUrl       != null) d.art_url    = d.artUrl;
    if (d.cardId     == null && d.card_id      != null) d.cardId     = d.card_id;
    return d;
}

export function showCardZoom(scene, rawCardData) {
    const cardData = _normalize(rawCardData);
    const W  = 844;
    const H  = sceneH(scene);
    const oy = (H - BASE_H) / 2;   // content keeps its 390-tall design, centred in taller scenes
    const cy = H / 2;

    // Three-column layout: stats panel (left) | card (middle) | keyword (right)
    const panelX = 10;
    const panelY = 14 + oy;
    const panelW = 200;
    const panelH = BASE_H - 28;
    const cardX  = W / 2;   // card art centered on screen

    const objs    = [];
    const reg     = o => { objs.push(o); return o; };
    const dismiss = () => objs.forEach(o => o?.destroy());

    // Backdrop — blocks input beneath, dismiss on tap
    reg(scene.add.rectangle(W / 2, cy, W, H, 0x000000)
        .setAlpha(0.6).setDepth(DEPTH).setInteractive())
        .on('pointerdown', dismiss);

    // ── Stats panel (left) ───────────────────────────────────────────────────
    reg(scene.add.rectangle(panelX + panelW / 2, panelY + panelH / 2, panelW, panelH, 0x0d1020, 0.95)
        .setStrokeStyle(2, 0xf4d35e, 0.9).setDepth(DEPTH + 1));

    const rarity = cardData.rarity ?? 1;
    const rarityColor = RARITY_COLOR[rarity] || '#aaaaaa';
    const rarityLbl   = RARITY_LABEL[rarity] || 'Common';
    const factionLbl  = CLAN_TAG_LABEL[cardData.clanTag]
                     || FACTION_LABEL[cardData.clan]
                     || _capitalize(cardData.clan || '');
    // Hide the redundant "Gang Member" tag — the subtype + level conveys it.
    const cardTypeRaw = cardData.cardType === 'gang_member' ? '' : cardData.cardType;
    const typeLbl     = CARD_TYPE_LABEL[cardTypeRaw] || _capitalize(cardTypeRaw || '');
    // Leaders display "Leader" only — subtype is irrelevant for them.
    const subtypeLbl  = (cardData.cardType === 'leader')
        ? '' : (cardData.subtype ? _capitalize(cardData.subtype) : '');
    // Level is only meaningful for Strivers (their promotion chain).
    const levelLbl    = (cardData.subtype === 'striver' && cardData.level)
        ? `Lv.${cardData.level}` : '';
    const cardNumber  = _formatCardNumber(cardData);

    let ty = panelY + 12;
    const innerX = panelX + 14;
    const innerW = panelW - 28;

    // Name
    const nameTxt = reg(scene.add.text(innerX, ty, cardData.name || 'Unknown', {
        fontSize: '16px', fontFamily: 'Arial Black', color: '#ffffff',
        wordWrap: { width: innerW },
    }).setDepth(DEPTH + 2));
    ty += nameTxt.height + 4;

    // Type / subtype / level inline
    const subline = [typeLbl, subtypeLbl, levelLbl].filter(Boolean).join(' • ');
    if (subline) {
        const subTxt = reg(scene.add.text(innerX, ty, subline, {
            fontSize: '10px', color: '#aaccff', fontStyle: 'italic',
            wordWrap: { width: innerW },
        }).setDepth(DEPTH + 2));
        ty += subTxt.height + 6;
    }

    // Faction + rarity row
    if (factionLbl) {
        const facTxt = reg(scene.add.text(innerX, ty, factionLbl.toUpperCase(), {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setDepth(DEPTH + 2));
        const rarTxt = reg(scene.add.text(panelX + panelW - 14, ty, rarityLbl.toUpperCase(), {
            fontSize: '9px', fontFamily: 'Arial Black', color: rarityColor,
        }).setOrigin(1, 0).setDepth(DEPTH + 2));
        ty += Math.max(facTxt.height, rarTxt.height) + 6;
    }

    // Divider
    reg(scene.add.rectangle(innerX, ty, innerW, 1, 0x334466, 0.9)
        .setOrigin(0, 0).setDepth(DEPTH + 2));
    ty += 6;

    // Stat row (Authority / ATK / DEF)
    const statY = ty;
    const stat = (x, label, value, color) => {
        if (value == null) return;
        reg(scene.add.text(x, statY, label, {
            fontSize: '8px', color: '#aaaacc',
        }).setDepth(DEPTH + 2));
        reg(scene.add.text(x, statY + 9, String(value), {
            fontSize: '13px', fontFamily: 'Arial Black', color,
        }).setDepth(DEPTH + 2));
    };
    const colW = innerW / 3;
    stat(innerX,                'AUTHORITY', cardData.authority ?? '—', '#ffd166');
    if (cardData.attack != null) stat(innerX + colW,         'ATK', cardData.attack, '#e63946');
    if (cardData.defense != null) stat(innerX + colW * 2,    'DEF', cardData.defense, '#4cc9f0');
    ty += 32;

    // Effect heading + body
    if (cardData.effectText) {
        reg(scene.add.text(innerX, ty, 'EFFECT', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setDepth(DEPTH + 2));
        ty += 12;
        const effTxt = reg(scene.add.text(innerX, ty, cardData.effectText, {
            fontSize: '10px', color: '#e6e6f0',
            wordWrap: { width: innerW }, lineSpacing: 2,
        }).setDepth(DEPTH + 2));
        ty += effTxt.height + 8;
    }

    // Flavour text
    if (cardData.flavourText) {
        const flvTxt = reg(scene.add.text(innerX, ty, `"${cardData.flavourText}"`, {
            fontSize: '9px', color: '#888899', fontStyle: 'italic',
            wordWrap: { width: innerW }, lineSpacing: 2,
        }).setDepth(DEPTH + 2));
        ty += flvTxt.height + 6;
    }

    // Card number — bottom-left of the panel
    reg(scene.add.text(innerX, panelY + panelH - 14, `#${cardNumber}`, {
        fontSize: '8px', color: '#666677',
    }).setDepth(DEPTH + 2));

    // ── Card image (right) ───────────────────────────────────────────────────
    const artKey = [cardData.art_url, cardData.id, cardData.cardId]
        .find(k => k && scene.textures.exists(k));

    if (artKey) {
        const img = scene.add.image(cardX, cy, artKey)
            .setDisplaySize(ZOOM_W, ZOOM_H)
            .setDepth(DEPTH + 2);
        img.texture?.setFilter?.(1);  // LINEAR — keep upscale smooth
        reg(img);
    } else {
        // Fallback only when texture isn't loaded
        reg(scene.add.rectangle(cardX, cy, ZOOM_W, ZOOM_H, 0x0d1020)
            .setStrokeStyle(3, 0xf4d35e, 0.9).setDepth(DEPTH + 2));
        reg(scene.add.text(cardX, cy, cardData.name || 'Unknown', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#ffffff',
            wordWrap: { width: ZOOM_W - 30 }, align: 'center',
        }).setOrigin(0.5).setDepth(DEPTH + 3));
    }

    // Dismiss hint
    reg(scene.add.text(cardX, cy + ZOOM_H / 2 + 12, 'tap to close', {
        fontSize: '8px', color: '#888888',
    }).setOrigin(0.5, 0.5).setDepth(DEPTH + 4));

    // ── Keyword reference (right) ────────────────────────────────────────────
    const effectText = cardData.effectText || '';
    const keywords   = [];
    if (/PROMOT/i.test(effectText)) keywords.push({ key: 'kw_promote', label: 'PROMOTE' });
    if (/\bDown(ed|s)?\b/i.test(effectText)) keywords.push({ key: 'kw_downed', label: 'DOWNED' });

    if (keywords.length > 0) {
        const KW_X = cardX + ZOOM_W / 2 + 10;          // left edge of keyword column
        const KW_W = Math.min(220, W - KW_X - 14);     // keep inside canvas
        keywords.forEach((kw, i) => {
            const hasTex = scene.textures.exists(kw.key);
            const KW_H = hasTex
                ? (() => { const f = scene.textures.getFrame(kw.key); return f ? Math.round(KW_W * f.realHeight / f.realWidth) : 56; })()
                : 56;
            const stackTop = cy - ((keywords.length * (KW_H + 10)) - 10) / 2;
            const ky = stackTop + i * (KW_H + 10) + KW_H / 2;

            if (hasTex) {
                reg(scene.add.image(KW_X + KW_W / 2, ky, kw.key)
                    .setDisplaySize(KW_W, KW_H).setDepth(DEPTH + 3));
            } else {
                reg(scene.add.rectangle(KW_X + KW_W / 2, ky, KW_W, KW_H, 0x1a1a2e)
                    .setStrokeStyle(1, 0xf4d35e, 0.8).setDepth(DEPTH + 3));
                reg(scene.add.text(KW_X + KW_W / 2, ky, kw.label, {
                    fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
                }).setOrigin(0.5).setDepth(DEPTH + 4));
            }
        });
    }

    return dismiss;
}

/**
 * Wires a hold-to-zoom gesture onto any Phaser interactive game object.
 * Cancels automatically if the pointer moves more than 8px or is released early.
 */
export function attachHoldZoom(scene, gameObject, cardData, holdMs = 600) {
    let timer  = null;
    let startX = 0;
    let startY = 0;

    const cancel = () => { if (timer) { timer.remove(false); timer = null; } };

    gameObject.on('pointerdown', (ptr) => {
        cancel();
        startX = ptr.worldX;
        startY = ptr.worldY;
        timer  = scene.time.delayedCall(holdMs, () => {
            timer = null;
            showCardZoom(scene, cardData);
        });
    });

    gameObject.on('pointermove', (ptr) => {
        if (Math.abs(ptr.worldX - startX) > 8 || Math.abs(ptr.worldY - startY) > 8) cancel();
    });

    gameObject.on('pointerup',  cancel);
    gameObject.on('pointerout', cancel);
}
