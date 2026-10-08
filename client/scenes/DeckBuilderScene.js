import { RARITY_COLOR }            from '../cards/RarityConfig.js';
import { showCardZoom }            from '../utils/CardZoom.js';
import { apiFetch } from '../utils/Platform.js';
import { VIEW_BOTTOM, VIEW_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

// ── Layout ────────────────────────────────────────────────────────────────────
const DIVIDER_X  = 418;
const HEADER_H   = 56;         // two rows of controls
const CONTENT_Y  = HEADER_H;
const CONTENT_H  = H - HEADER_H;

// Collection grid (left panel)
const COLL_COLS  = 4;
const CARD_W     = 70;
const CARD_H     = 92;
const CARD_GAP   = 6;
const CARD_PAD   = 8;

// Deck list (right panel)
const DECK_X     = DIVIDER_X + 4;
const DECK_PNL_W = W - DECK_X;
const DECK_ROW_H = 30;
const DECK_ROW_G = 4;

// Leader slot lives at the top of the deck panel (fixed, doesn't scroll).
const LEADER_PANE_H = 76;
const DECK_TOP      = HEADER_H + LEADER_PANE_H;

// Drag thresholds
const DRAG_DIST  = 14;   // px before drag mode activates
const HOLD_MS    = 450; // ms for hold-to-zoom

export class DeckBuilderScene extends Phaser.Scene {
    constructor() {
        super('DeckBuilderScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this._inventory      = [];
        this._deckCards      = [];   // [{cardId, name, rarity}] – flat, one entry per copy
        this._activeDeckId   = null;
        this._allDecks       = [];
        this._deckIdx        = 0;

        this._collScroll     = 0;    // current Y offset (≤0)
        this._deckScroll     = 0;
        this._collContentH   = 0;
        this._deckContentH   = 0;

        // Pointer state machine: idle → pending → scrolling|dragging
        this._pState         = 'idle';
        this._pStart         = null;
        this._pScrollBase    = 0;
        this._pressHit       = null;
        this._drag           = null;   // {source, item, ghost, label}
        this._holdTimer      = null;

        this._collHits       = [];    // [{lx,ly,w,h,item}] local-space hit areas
        this._deckHits       = [];

        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.65);
        this._buildHeader();
        this._buildPanelBg();
        this._buildContainers();
        this._loadData();
        this._setupPointer();
    }

    // ── Header ────────────────────────────────────────────────────────────────

    _buildHeader() {
        // Row 1 (y≈18)
        this._makeBtn(44, 18, '← BACK',  () => this._attemptExit(), 0x333355, 76, 26);
        this.add.text(W / 2, 18, 'DECK BUILDER', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);
        this._makeBtn(W - 44, 18, 'SAVE', () => this._saveDeck(), 0x2d6a4f, 68, 26);
        this._countText = this.add.text(W - 84, 18, '0/40', {
            fontSize: '10px', color: '#e63946',
        }).setOrigin(1, 0.5);

        // Row 1 divider
        this.add.rectangle(W / 2, 36, W, 1, 0x334466, 1);

        // Row 2 (y≈47): search + filters | deck selector
        this._filterText    = '';
        this._filterFaction = 'all'; // 'all' | 'lion_pride' | 'viper_clan'
        this._filterType    = 'all'; // 'all' | 'gang_member' | 'effect' (= non-gang_member)
        this._buildFilterBar(47);

        // Deck selector: ◀ name ▶  [★ ACTIVE]  [+ NEW]
        this._makeBtn(DIVIDER_X + 18, 47, '◀', () => this._cycleDeck(-1), 0x222244, 22, 20);
        this._deckNameTxt = this.add.text(DIVIDER_X + 110, 47, '—', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5);
        this._makeBtn(DIVIDER_X + 202, 47, '▶', () => this._cycleDeck(1), 0x222244, 22, 20);
        this._makeBtn(DIVIDER_X + 268, 47, '★ SET ACTIVE', () => this._setActive(), 0x4a4a00, 98, 20);
        this._makeBtn(W - 36, 47, '+ NEW', () => this._createDeck(), 0x1d3d1d, 58, 20);

        // Row 2 divider
        this.add.rectangle(W / 2, HEADER_H - 1, W, 1, 0x334466, 1);
    }

    _buildFilterBar(y) {
        // Search input (HTML DOM, narrow)
        const input = document.createElement('input');
        input.type        = 'search';
        input.placeholder = 'Search…';
        input.style.cssText = `
            width:120px;padding:3px 6px;border-radius:4px;font-size:10px;
            background:#1a1a2e;color:#fff;border:1px solid #4cc9f0;
            outline:none;box-sizing:border-box;
        `;
        const dom = this.add.dom(70, y, input);
        dom.setDepth(5);
        input.addEventListener('input', () => {
            this._filterText = input.value.trim().toLowerCase();
            this._collScroll = 0;
            this._renderCollection();
        });
        this._searchDom = dom;

        // Faction chips
        const chipFn = (x, label, onClick, isActive) => {
            const fill = isActive() ? 0x4cc9f0 : 0x222244;
            const txtCol = isActive() ? '#04060c' : '#cccccc';
            const r = this.add.rectangle(x, y, 36, 16, fill)
                .setStrokeStyle(1, 0x4cc9f0).setInteractive({ useHandCursor: true });
            const t = this.add.text(x, y, label, {
                fontSize: '8px', fontFamily: 'Arial Black', color: txtCol,
            }).setOrigin(0.5);
            r.on('pointerup', () => { onClick(); this._refreshFilterChips(); this._collScroll = 0; this._renderCollection(); });
            return { r, t, label, onClick, isActive };
        };

        this._chips = [];
        let cx = 148;
        const factions = [
            ['ALL',    () => this._filterFaction = 'all',         () => this._filterFaction === 'all'],
            ['LIONS',  () => this._filterFaction = 'lion_pride',  () => this._filterFaction === 'lion_pride'],
            ['VIPERS', () => this._filterFaction = 'viper_clan',  () => this._filterFaction === 'viper_clan'],
        ];
        factions.forEach(([lbl, on, isAct]) => { this._chips.push(chipFn(cx, lbl, on, isAct)); cx += 40; });

        cx += 8;
        const types = [
            ['UNITS',  () => this._filterType = 'gang_member', () => this._filterType === 'gang_member'],
            ['EFFECT', () => this._filterType = 'effect',      () => this._filterType === 'effect'],
            ['ANY',    () => this._filterType = 'all',         () => this._filterType === 'all'],
        ];
        types.forEach(([lbl, on, isAct]) => { this._chips.push(chipFn(cx, lbl, on, isAct)); cx += 40; });
    }

    _refreshFilterChips() {
        this._chips.forEach(c => {
            const active = c.isActive();
            c.r.setFillStyle(active ? 0x4cc9f0 : 0x222244);
            c.t.setColor(active ? '#04060c' : '#cccccc');
        });
    }

    _matchesFilters(item) {
        if (this._filterFaction !== 'all' && item.clan !== this._filterFaction) return false;
        if (this._filterType === 'gang_member' && item.card_type !== 'gang_member') return false;
        if (this._filterType === 'effect'      && item.card_type === 'gang_member') return false;
        if (this._filterText) {
            const hay = `${item.name || ''} ${item.subtype || ''} ${item.card_type || ''}`.toLowerCase();
            if (!hay.includes(this._filterText)) return false;
        }
        return true;
    }

    // ── Panel chrome ──────────────────────────────────────────────────────────

    _buildPanelBg() {
        this.add.rectangle(DIVIDER_X / 2, CONTENT_Y + CONTENT_H / 2,
            DIVIDER_X, CONTENT_H, 0x080810, 1).setAlpha(0.4);
        this.add.rectangle(DECK_X + DECK_PNL_W / 2, CONTENT_Y + CONTENT_H / 2,
            DECK_PNL_W, CONTENT_H, 0x080810, 1).setAlpha(0.4);
        this.add.rectangle(DIVIDER_X, CONTENT_Y + CONTENT_H / 2, 2, CONTENT_H, 0x334466);
    }

    _buildContainers() {
        this._collCont = this.add.container(0, CONTENT_Y);
        this._deckCont = this.add.container(DECK_X, DECK_TOP);

        const cg = this.make.graphics({ add: false });
        cg.fillRect(0, CONTENT_Y, DIVIDER_X, CONTENT_H);
        this._collCont.setMask(cg.createGeometryMask());

        const dg = this.make.graphics({ add: false });
        dg.fillRect(DECK_X, DECK_TOP, DECK_PNL_W, VIEW_BOTTOM - DECK_TOP);
        this._deckCont.setMask(dg.createGeometryMask());
    }

    // ── Data ──────────────────────────────────────────────────────────────────

    _loadData() {

        Promise.all([
            apiFetch('/api/profile/inventory').then(r => r.json()),
            apiFetch('/api/deck').then(r => r.json()),
        ]).then(([inv, decks]) => {
            this._inventory = inv;
            this._allDecks  = Array.isArray(decks) ? decks : [];
            if (this._allDecks.length) {
                this._deckIdx = Math.max(0, this._allDecks.findIndex(d => d.is_active));
                this._loadDeck();
            } else {
                this._renderCollection();
                this._renderDeck();
            }
        }).catch(() => this._toast('Failed to load data'));
    }

    _loadDeck() {
        const deck = this._allDecks[this._deckIdx];
        if (!deck) { this._renderCollection(); this._renderDeck(); return; }
        this._activeDeckId = deck.id;
        this._deckNameTxt.setText(this._truncate(deck.name || `Deck ${deck.id}`, 16));

        apiFetch(`/api/deck/${deck.id}`)
            .then(r => r.json())
            .then(data => {
                this._deckCards = (data.cards || []).flatMap(c =>
                    Array(c.copies).fill({ cardId: c.id, name: c.name, rarity: c.rarity })
                );
                this._leaderCard = data.leader || null;
                this._dirty = false;
                this._deckScroll = 0;
                this._deckCont.y = DECK_TOP;
                this._renderDeck();
                this._renderCollection();
                this._renderLeaderSlot();
            })
            .catch(() => this._toast('Failed to load deck'));
    }

    _cycleDeck(dir) {
        if (!this._allDecks.length) return;
        this._deckIdx = (this._deckIdx + dir + this._allDecks.length) % this._allDecks.length;
        this._loadDeck();
    }

    // ── Rendering ─────────────────────────────────────────────────────────────

    _renderCollection() {
        this._collCont.removeAll(true);
        this._collHits = [];

        const stepX  = CARD_W + CARD_GAP;
        const stepY  = CARD_H + CARD_GAP;
        const inDeck = {};
        this._deckCards.forEach(c => { inDeck[c.cardId] = (inDeck[c.cardId] || 0) + 1; });

        // Leaders never appear in the main collection grid — they belong in
        // the dedicated leader slot on the deck panel.
        const items = this._inventory
            .filter(it => it.card_type !== 'leader')
            .filter(it => this._matchesFilters(it));

        items.forEach((item, i) => {
            const col = i % COLL_COLS;
            const row = Math.floor(i / COLL_COLS);
            const lx  = CARD_PAD + col * stepX + CARD_W / 2;
            const ly  = CARD_PAD + row * stepY + CARD_H / 2;

            const col6 = this._colorNum(RARITY_COLOR[item.rarity]);
            const used = inDeck[item.id] || 0;
            const avail = (item.quantity || 0) - used;
            const dimmed = avail <= 0;

            const bg = this.add.rectangle(lx, ly, CARD_W, CARD_H, dimmed ? 0x111118 : 0x1a1a2e)
                .setStrokeStyle(1, dimmed ? 0x333333 : col6)
                .setAlpha(dimmed ? 0.5 : 1);

            const toAdd = [bg];

            // Card artwork — added after bg so it renders on top
            const texKey = item.art_url || item.image_key || item.id;
            if (texKey && this.textures.exists(texKey)) {
                const img = this.add.image(lx, ly - 8, texKey)
                    .setDisplaySize(CARD_W - 4, CARD_H - 18)
                    .setAlpha(dimmed ? 0.4 : 1);
                toAdd.push(img);
            }

            const nameTxt = this.add.text(lx, ly + CARD_H / 2 - 9, item.name, {
                fontSize: '6px', fontFamily: 'Arial Black', color: dimmed ? '#555555' : '#ffffff',
                wordWrap: { width: CARD_W - 4 }, align: 'center',
            }).setOrigin(0.5, 1);

            // Quantity badge (top-right): used/max copies
            const badgeBg  = this.add.rectangle(lx + CARD_W / 2 - 9, ly - CARD_H / 2 + 8, 18, 13, 0x000000, 0.85);
            const badgeTxt = this.add.text(lx + CARD_W / 2 - 9, ly - CARD_H / 2 + 8,
                `${used}/${Math.min(3, item.quantity || 0)}`, {
                    fontSize: '6px', fontFamily: 'Arial Black',
                    color: used >= 3 ? '#e63946' : '#f4d35e',
                }).setOrigin(0.5);

            toAdd.push(nameTxt, badgeBg, badgeTxt);
            this._collCont.add(toAdd);
            this._collHits.push({ lx, ly, w: CARD_W, h: CARD_H, item });
        });

        const rows = Math.ceil(items.length / COLL_COLS);
        this._collContentH = CARD_PAD * 2 + rows * stepY;
    }

    _renderDeck() {
        this._deckCont.removeAll(true);
        this._deckHits = [];

        // Group by cardId
        const grouped = {};
        this._deckCards.forEach(c => {
            if (!grouped[c.cardId]) grouped[c.cardId] = { ...c, count: 0 };
            grouped[c.cardId].count++;
        });
        const entries = Object.values(grouped);

        entries.forEach((item, i) => {
            const ly = CARD_PAD / 2 + i * (DECK_ROW_H + DECK_ROW_G) + DECK_ROW_H / 2;
            const col6 = this._colorNum(RARITY_COLOR[item.rarity]);

            const bg = this.add.rectangle(DECK_PNL_W / 2, ly, DECK_PNL_W - 6, DECK_ROW_H, 0x14141e)
                .setStrokeStyle(1, col6);

            const nameTxt = this.add.text(8, ly, item.name, {
                fontSize: '8px', color: '#cccccc', wordWrap: { width: DECK_PNL_W - 70 },
            }).setOrigin(0, 0.5);

            const cntTxt = this.add.text(DECK_PNL_W - 20, ly, `×${item.count}`, {
                fontSize: '11px', fontFamily: 'Arial Black', color: '#f4d35e',
            }).setOrigin(1, 0.5);

            // Visual tap hint (no setInteractive — handled by scene pointer)
            const rmHint = this.add.text(DECK_PNL_W - 6, ly, '−', {
                fontSize: '13px', fontFamily: 'Arial Black', color: '#e63946',
            }).setOrigin(1, 0.5);

            this._deckCont.add([bg, nameTxt, cntTxt, rmHint]);
            this._deckHits.push({ lx: DECK_PNL_W / 2, ly, w: DECK_PNL_W - 6, h: DECK_ROW_H, item });
        });

        const total = this._deckCards.length;
        this._countText.setText(`${total}/40`);
        this._countText.setColor(total === 40 ? '#4cc9f0' : '#e63946');

        this._deckContentH = CARD_PAD + entries.length * (DECK_ROW_H + DECK_ROW_G);
    }

    // ── Pointer input ─────────────────────────────────────────────────────────

    _setupPointer() {
        this.input.on('pointerdown', p => this._pDown(p));
        this.input.on('pointermove', p => this._pMove(p));
        this.input.on('pointerup',   p => this._pUp(p));
        this.input.on('pointerupoutside', p => this._pUp(p));
    }

    _pDown(ptr) {
        if (this._pState !== 'idle') return;
        if (ptr.worldY < CONTENT_Y) return;   // header buttons use their own handlers

        this._pState        = 'pending';
        this._pStart        = { x: ptr.worldX, y: ptr.worldY };
        this._collScrollBase = this._collScroll;
        this._deckScrollBase = this._deckScroll;
        this._pressHit      = this._hitCard(ptr.worldX, ptr.worldY);

        // Hold-to-zoom timer
        if (this._pressHit) {
            this._holdTimer = this.time.delayedCall(HOLD_MS, () => {
                if (this._pState === 'pending') {
                    showCardZoom(this, this._pressHit.item);
                    this._pState = 'idle';
                    this._pressHit = null;
                }
            });
        }
    }

    _pMove(ptr) {
        if (this._pState === 'idle') return;

        const dx   = ptr.worldX - this._pStart.x;
        const dy   = ptr.worldY - this._pStart.y;
        const dist = Math.hypot(dx, dy);

        if (this._pState === 'pending' && dist > 8) {
            this._cancelHold();
            // Horizontal movement from a card hit → drag; else scroll
            const isHoriz = Math.abs(dx) > Math.abs(dy) * 0.7 && Math.abs(dx) > 10;
            if (this._pressHit && isHoriz && dist >= DRAG_DIST) {
                this._pState = 'dragging';
                this._startDrag(this._pressHit, ptr);
            } else {
                this._pState = 'scrolling';
            }
        }

        if (this._pState === 'scrolling') {
            if (this._pStart.x < DIVIDER_X) {
                const maxS = Math.max(0, this._collContentH - CONTENT_H);
                this._collScroll = Phaser.Math.Clamp(this._collScrollBase + dy, -maxS, 0);
                this._collCont.y = CONTENT_Y + this._collScroll;
            } else {
                const maxS = Math.max(0, this._deckContentH - (H - DECK_TOP));
                this._deckScroll = Phaser.Math.Clamp(this._deckScrollBase + dy, -maxS, 0);
                this._deckCont.y = DECK_TOP + this._deckScroll;
            }
        }

        if (this._pState === 'dragging' && this._drag) {
            this._drag.ghost.setPosition(ptr.worldX, ptr.worldY);
            this._drag.label.setPosition(ptr.worldX, ptr.worldY);
            // Highlight drop zone
            const overDeck = ptr.worldX >= DIVIDER_X;
            const validDrop = (this._drag.source === 'collection' && overDeck) ||
                              (this._drag.source === 'deck'       && !overDeck);
            this._drag.ghost.setFillStyle(validDrop ? 0x4cc9f0 : 0xe63946, 0.8);
        }
    }

    _pUp(ptr) {
        this._cancelHold();

        if (this._pState === 'pending' && this._pressHit) {
            this._handleTap(this._pressHit);
        } else if (this._pState === 'dragging') {
            this._endDrag(ptr);
        }

        this._pState    = 'idle';
        this._pressHit  = null;
    }

    _cancelHold() {
        if (this._holdTimer) { this._holdTimer.remove(); this._holdTimer = null; }
    }

    // ── Hit testing ───────────────────────────────────────────────────────────

    _hitCard(wx, wy) {
        if (wy < CONTENT_Y) return null;

        if (wx < DIVIDER_X) {
            const ly = wy - this._collCont.y;
            for (const h of this._collHits) {
                if (Math.abs(h.lx - wx)       <= h.w / 2 &&
                    Math.abs(h.ly - ly)        <= h.h / 2) {
                    return { source: 'collection', item: h.item };
                }
            }
        } else {
            const ly = wy  - this._deckCont.y;
            const lx = wx  - DECK_X;
            for (const h of this._deckHits) {
                if (Math.abs(h.lx - lx) <= h.w / 2 &&
                    Math.abs(h.ly - ly) <= h.h / 2) {
                    return { source: 'deck', item: h.item };
                }
            }
        }
        return null;
    }

    _handleTap(hit) {
        if (hit.source === 'collection') this._addToDeck(hit.item);
        else                             this._removeFromDeck(hit.item.cardId);
    }

    // ── Drag ─────────────────────────────────────────────────────────────────

    _startDrag(hit, ptr) {
        const ghost = this.add.rectangle(ptr.worldX, ptr.worldY, CARD_W, CARD_H, 0x4cc9f0, 0.82)
            .setDepth(100).setStrokeStyle(2, 0xffffff);
        const label = this.add.text(ptr.worldX, ptr.worldY, hit.item.name, {
            fontSize: '7px', fontFamily: 'Arial Black',
            color: '#ffffff', align: 'center',
            wordWrap: { width: CARD_W - 8 },
        }).setOrigin(0.5).setDepth(101);
        this._drag = { source: hit.source, item: hit.item, ghost, label };
    }

    _endDrag(ptr) {
        if (!this._drag) return;
        const { source, item, ghost, label } = this._drag;
        ghost.destroy();
        label.destroy();
        this._drag = null;

        const overDeck = ptr.worldX >= DIVIDER_X;
        if (source === 'collection' && overDeck)  this._addToDeck(item);
        else if (source === 'deck'  && !overDeck) this._removeFromDeck(item.cardId);
    }

    // ── Deck mutations ────────────────────────────────────────────────────────

    _addToDeck(item) {
        const copies = this._deckCards.filter(c => c.cardId === item.id).length;
        if (copies >= 3)             { this._toast('Max 3 copies per card'); return; }
        if (this._deckCards.length >= 40) { this._toast('Deck full (40 cards)'); return; }
        this._deckCards.push({ cardId: item.id, name: item.name, rarity: item.rarity });
        this._dirty = true;
        this._renderDeck();
        this._renderCollection();
    }

    _removeFromDeck(cardId) {
        const idx = this._deckCards.findLastIndex(c => c.cardId === cardId);
        if (idx !== -1) { this._deckCards.splice(idx, 1); this._dirty = true; }
        this._renderDeck();
        this._renderCollection();
    }

    // ── Deck management ───────────────────────────────────────────────────────

    _saveDeck(onDone) {
        if (!this._activeDeckId) { this._toast('No deck selected'); onDone?.(false); return; }
        const total = this._deckCards.length;
        if (total !== 40) { this._toast(`Need 40 cards (have ${total})`, '#e63946'); onDone?.(false); return; }

        const grouped = {};
        this._deckCards.forEach(c => { grouped[c.cardId] = (grouped[c.cardId] || 0) + 1; });
        const cards = Object.entries(grouped).map(([cardId, copies]) => ({ cardId, copies }));

        const body  = { cards, leaderCardId: this._leaderCard?.id ?? null };
        apiFetch(`/api/deck/${this._activeDeckId}/cards`, {
            method:  'PUT',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify(body),
        })
        .then(r => r.json())
        .then(d => {
            const ok = !!d.success;
            if (ok) this._dirty = false;
            this._toast(ok ? 'Deck saved!' : (d.error || 'Error'),
                        ok ? '#4cc9f0' : '#e63946');
            onDone?.(ok);
        })
        .catch(() => { this._toast('Save failed'); onDone?.(false); });
    }

    _attemptExit() {
        // No unsaved changes → leave immediately
        if (!this._dirty) { this.scene.start('MainMenuScene'); return; }
        this._showExitConfirm();
    }

    _showExitConfirm() {
        if (this._exitOpen) return;
        this._exitOpen = true;

        const W = 844, H = 390;
        const objs = [];
        const reg  = o => { objs.push(o); return o; };
        const close = () => { objs.forEach(o => o?.destroy()); this._exitOpen = false; };

        reg(this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0.7)
            .setDepth(200).setInteractive());

        const px = W / 2, py = H / 2;
        reg(this.add.rectangle(px, py, 460, 180, 0x101030, 0.98)
            .setStrokeStyle(2, 0xf4d35e).setDepth(201));

        reg(this.add.text(px, py - 56, 'UNSAVED CHANGES', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(202));

        const total = this._deckCards.length;
        const subline = total === 40
            ? 'Save your changes before leaving the deck editor?'
            : `Your deck has ${total} cards — must be 40 to save. Quit without saving?`;
        reg(this.add.text(px, py - 22, subline, {
            fontSize: '11px', color: '#cccccc', wordWrap: { width: 420 }, align: 'center',
        }).setOrigin(0.5).setDepth(202));

        const mkBtn = (x, label, fill, stroke, color, onClick) => {
            const w = 130, h = 32;
            const bg = reg(this.add.rectangle(x, py + 36, w, h, fill)
                .setStrokeStyle(2, stroke).setDepth(202).setInteractive({ useHandCursor: true }));
            reg(this.add.text(x, py + 36, label, {
                fontSize: '11px', fontFamily: 'Arial Black', color,
            }).setOrigin(0.5).setDepth(203));
            bg.on('pointerdown', () => bg.setAlpha(0.6));
            bg.on('pointerout',  () => bg.setAlpha(1));
            bg.on('pointerup',   () => { bg.setAlpha(1); onClick(); });
        };

        // Save & Exit (only meaningful when deck = 40)
        mkBtn(px - 150, 'SAVE & EXIT', 0x1a3a1a, 0x4caf50, '#a5d6a7', () => {
            this._saveDeck((ok) => {
                if (ok) { close(); this.scene.start('MainMenuScene'); }
            });
        });
        // Quit without saving
        mkBtn(px,       'QUIT',        0x3a1010, 0xe63946, '#ffa7b0', () => {
            close();
            this.scene.start('MainMenuScene');
        });
        // Cancel
        mkBtn(px + 150, 'CANCEL',      0x222244, 0x8888aa, '#cccccc', close);
    }

    _setActive() {
        if (!this._activeDeckId) return;
        apiFetch(`/api/deck/${this._activeDeckId}/activate`, {
            method: 'PATCH',
        })
        .then(r => r.json())
        .then(d => {
            if (d.success) {
                this._allDecks.forEach(dk => dk.is_active = dk.id === this._activeDeckId);
                this._toast('Set as active deck', '#4cc9f0');
            }
        })
        .catch(() => this._toast('Failed to set active'));
    }

    _createDeck() {
        const name = window.prompt('New deck name:');
        if (!name) return;
        apiFetch('/api/deck', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ name }),
        })
        .then(r => r.json())
        .then(d => {
            if (d.id) {
                this._allDecks.push(d);
                this._deckIdx  = this._allDecks.length - 1;
                this._deckCards = [];
                this._activeDeckId = d.id;
                this._deckNameTxt.setText(this._truncate(d.name, 16));
                this._renderDeck();
                this._toast(`Created "${d.name}"`, '#4cc9f0');
            }
        })
        .catch(() => this._toast('Create failed'));
    }

    // ── Leader slot ───────────────────────────────────────────────────────────

    _renderLeaderSlot() {
        // Tear down any previous slot graphics
        this._leaderSlotObjs?.forEach(o => o?.destroy?.());
        this._leaderSlotObjs = [];

        const px = DECK_X + 6;
        const py = HEADER_H + 4;
        const pw = DECK_PNL_W - 12;
        const ph = LEADER_PANE_H - 8;

        // Section background
        const bg = this.add.rectangle(px + pw / 2, py + ph / 2, pw, ph, 0x14101e)
            .setStrokeStyle(2, 0xf4d35e, 0.85);
        this._leaderSlotObjs.push(bg);

        const heading = this.add.text(px + 6, py + 4, 'LEADER', {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#f4d35e',
        });
        this._leaderSlotObjs.push(heading);

        // Portrait area (left)
        const pSize = ph - 16;
        const pcx = px + pSize / 2 + 6;
        const pcy = py + ph / 2 + 4;
        const portraitBg = this.add.rectangle(pcx, pcy, pSize, pSize, 0x0a0a14)
            .setStrokeStyle(1, 0x556688);
        this._leaderSlotObjs.push(portraitBg);

        if (this._leaderCard) {
            const tex = this._leaderCard.art_url || this._leaderCard.id;
            if (tex && this.textures.exists(tex)) {
                const img = this.add.image(pcx, pcy, tex).setDisplaySize(pSize - 4, pSize - 4);
                this._leaderSlotObjs.push(img);
            }
            const nameTxt = this.add.text(pcx + pSize / 2 + 8, py + ph / 2 - 4,
                this._leaderCard.name, {
                    fontSize: '11px', fontFamily: 'Arial Black', color: '#ffffff',
                    wordWrap: { width: pw - pSize - 28 },
                }).setOrigin(0, 1);
            this._leaderSlotObjs.push(nameTxt);
            const subTxt = this.add.text(pcx + pSize / 2 + 8, py + ph / 2 + 2,
                `Authority ${this._leaderCard.authority ?? '—'}`, {
                    fontSize: '9px', color: '#aaccff',
                }).setOrigin(0, 0);
            this._leaderSlotObjs.push(subTxt);
        } else {
            const placeholder = this.add.text(pcx, pcy, '?', {
                fontSize: '20px', fontFamily: 'Arial Black', color: '#444466',
            }).setOrigin(0.5);
            this._leaderSlotObjs.push(placeholder);
            const noneTxt = this.add.text(pcx + pSize / 2 + 8, py + ph / 2,
                'No leader chosen', {
                    fontSize: '10px', color: '#888899', fontStyle: 'italic',
                }).setOrigin(0, 0.5);
            this._leaderSlotObjs.push(noneTxt);
        }

        // CHOOSE button at the right edge of the slot
        const btnX = px + pw - 36;
        const btnY = py + ph / 2;
        const btn = this.add.rectangle(btnX, btnY, 60, 22, 0x222244)
            .setStrokeStyle(1, 0xf4d35e).setInteractive({ useHandCursor: true });
        const btnTxt = this.add.text(btnX, btnY,
            this._leaderCard ? 'CHANGE' : 'CHOOSE', {
                fontSize: '9px', fontFamily: 'Arial Black', color: '#f4d35e',
            }).setOrigin(0.5);
        btn.on('pointerup', () => this._showLeaderPicker());
        this._leaderSlotObjs.push(btn, btnTxt);
    }

    _showLeaderPicker() {
        if (this._leaderPickerOpen) return;
        this._leaderPickerOpen = true;

        const objs = [];
        const reg  = o => { objs.push(o); return o; };
        const close = () => { objs.forEach(o => o?.destroy?.()); this._leaderPickerOpen = false; };

        reg(this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000, 0.75)
            .setDepth(200).setInteractive())
            .on('pointerdown', close);

        const pw = 540, ph = 240;
        reg(this.add.rectangle(W / 2, H / 2, pw, ph, 0x101030, 0.98)
            .setStrokeStyle(2, 0xf4d35e).setDepth(201).setInteractive());

        reg(this.add.text(W / 2, H / 2 - ph / 2 + 14, 'CHOOSE A LEADER', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5).setDepth(202));

        const leaders = (this._inventory || []).filter(it => it.card_type === 'leader');
        if (!leaders.length) {
            reg(this.add.text(W / 2, H / 2, 'No leader cards in your collection.', {
                fontSize: '11px', color: '#cccccc',
            }).setOrigin(0.5).setDepth(202));
        } else {
            const tileW = 80, tileH = 110;
            const gap   = 14;
            const totalW = leaders.length * tileW + (leaders.length - 1) * gap;
            let lx = W / 2 - totalW / 2 + tileW / 2;
            const ly = H / 2 - 6;

            leaders.forEach(lc => {
                const isCurrent = this._leaderCard?.id === lc.id;
                const stroke    = isCurrent ? 0xffd700 : 0x556688;
                const tile = reg(this.add.rectangle(lx, ly, tileW, tileH, 0x14141e)
                    .setStrokeStyle(2, stroke).setDepth(202)
                    .setInteractive({ useHandCursor: true }));
                if (lc.art_url && this.textures.exists(lc.art_url)) {
                    reg(this.add.image(lx, ly - 8, lc.art_url)
                        .setDisplaySize(tileW - 6, tileH - 24).setDepth(203));
                }
                reg(this.add.text(lx, ly + tileH / 2 - 8, lc.name, {
                    fontSize: '8px', fontFamily: 'Arial Black', color: '#ffffff',
                    wordWrap: { width: tileW - 4 }, align: 'center',
                }).setOrigin(0.5, 1).setDepth(203));
                tile.on('pointerup', () => {
                    this._leaderCard = lc;
                    this._dirty      = true;
                    this._renderLeaderSlot();
                    close();
                });
                lx += tileW + gap;
            });
        }

        // Clear leader + cancel
        const mk = (x, label, fill, stroke, color, onTap) => {
            const bg = reg(this.add.rectangle(x, H / 2 + ph / 2 - 22, 130, 26, fill)
                .setStrokeStyle(1, stroke).setDepth(202).setInteractive({ useHandCursor: true }));
            reg(this.add.text(x, H / 2 + ph / 2 - 22, label, {
                fontSize: '10px', fontFamily: 'Arial Black', color,
            }).setOrigin(0.5).setDepth(203));
            bg.on('pointerup', onTap);
        };
        mk(W / 2 - 80, 'CLEAR LEADER', 0x3a1010, 0xe63946, '#ffa7b0', () => {
            this._leaderCard = null;
            this._dirty      = true;
            this._renderLeaderSlot();
            close();
        });
        mk(W / 2 + 80, 'CANCEL',       0x222244, 0x8888aa, '#cccccc', close);
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    _colorNum(hex) {
        return parseInt((hex || '#888888').replace('#', ''), 16);
    }

    _truncate(str, max) {
        return str.length > max ? str.slice(0, max - 1) + '…' : str;
    }

    _makeBtn(x, y, label, cb, color, w = 100, h = 30) {
        const btn = this.add.rectangle(x, y, w, h, color)
            .setStrokeStyle(1, 0x556688).setInteractive({ useHandCursor: true }).setOrigin(0.5);
        this.add.text(x, y, label, {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5);
        btn.on('pointerup',   cb);
        btn.on('pointerdown', () => btn.setAlpha(0.7));
        btn.on('pointerout',  () => btn.setAlpha(1));
        return btn;
    }

    _toast(msg, color = '#e63946') {
        const t = this.add.text(W / 2, H - 22, msg, {
            fontSize: '12px', color, backgroundColor: '#000',
            padding: { x: 8, y: 5 },
        }).setOrigin(0.5).setDepth(50);
        this.tweens.add({ targets: t, alpha: 0, delay: 2200, duration: 400,
            onComplete: () => t.destroy() });
    }

    shutdown() {
        this._cancelHold();
    }
}
