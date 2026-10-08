import { RARITY_COLOR, RARITY_LABEL } from '../cards/RarityConfig.js';
import { showCardZoom }               from '../utils/CardZoom.js';

const W = 844;
const H = 390;

// ── Layout constants ──────────────────────────────────────────────────────────
const HEADER_H    = 38;   // title row
const FILTER_H    = 30;   // filter tab row
const GRID_Y      = HEADER_H + FILTER_H;   // 68
const GRID_H      = H - GRID_Y;            // 322
const GRID_X      = 8;
const GRID_W      = W - GRID_X * 2;

// Card cell
const CARD_W      = 68;
const CARD_H      = 90;
const CARD_GAP    = 8;
const COLS        = Math.floor((GRID_W + CARD_GAP) / (CARD_W + CARD_GAP));  // 10

// Clan / type values that appear in collection items
const CLAN_FILTERS = ['LION', 'STRIVER', 'HEAVY', 'BRAWLER'];
const RARITY_FILTERS = [
    { label: 'COMMON',    rarity: 1 },
    { label: 'RARE',      rarity: 2 },
    { label: 'EPIC',      rarity: 3 },
    { label: 'LEGENDARY', rarity: 4 },
    { label: 'MYTHIC',    rarity: 5 },
];

export class CardLibraryScene extends Phaser.Scene {
    constructor() { super('CardLibraryScene'); }

    // ── create ────────────────────────────────────────────────────────────────

    create() {
        this._collection    = [];   // raw data from API
        this._filtered      = [];   // after applying active filters
        this._scrollY       = 0;    // current scroll offset (≤0)
        this._contentH      = 0;    // total grid height
        this._activeClan    = new Set();    // e.g. {'LION'}
        this._activeRarity  = new Set();   // e.g. {1, 3}
        this._newBadges     = [];   // {cardId, badgeGroup} — kept for mark-seen
        this._cardHits      = [];   // [{lx, ly, cardData}] in container-local space
        this._isDragging    = false;
        this._dragStartY    = 0;
        this._scrollBase    = 0;

        // Background
        this.add.rectangle(W / 2, H / 2, W, H, 0x04060c);

        this._buildHeader();
        this._buildFilterBar();
        this._buildGridContainer();
        this._buildScrollInput();
        this._showSpinner();
        this._fetchCollection();
    }

    // ── Header row ────────────────────────────────────────────────────────────

    _buildHeader() {
        // Dark header strip
        this.add.rectangle(W / 2, HEADER_H / 2, W, HEADER_H, 0x090d16);
        this.add.rectangle(W / 2, HEADER_H - 0.5, W, 1, 0x223355);

        // Title
        this.add.text(W / 2, HEADER_H / 2, 'CARD LIBRARY', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);

        // Total count (updated after fetch)
        this._totalTxt = this.add.text(W / 2 + 120, HEADER_H / 2, '', {
            fontSize: '9px', color: '#aaaaaa',
        }).setOrigin(0, 0.5);

        // Back button
        this._makeBtn(38, HEADER_H / 2, '← BACK', () => this.scene.start('MainMenuScene'), 0x1a1a33, 62, 24);

        // Mark All Seen button
        this._markSeenBtn = this._makeBtn(W - 68, HEADER_H / 2, 'MARK ALL SEEN',
            () => this._markAllSeen(), 0x1a3322, 106, 24);
    }

    // ── Filter bar ────────────────────────────────────────────────────────────

    _buildFilterBar() {
        const barY = HEADER_H + FILTER_H / 2;
        this.add.rectangle(W / 2, HEADER_H + FILTER_H / 2, W, FILTER_H, 0x0c1020);
        this.add.rectangle(W / 2, HEADER_H + FILTER_H - 0.5, W, 1, 0x223355);

        this._filterBtns = [];

        // ALL button (special — clears all filters)
        const allBtn = this._makeFilterBtn(14, barY, 'ALL', () => this._clearFilters());
        this._allBtn = allBtn;
        this._filterBtns.push(allBtn);

        // Clan filter tabs
        let curX = 52;
        for (const clan of CLAN_FILTERS) {
            const btn = this._makeFilterBtn(curX, barY, clan, () => this._toggleClan(clan));
            btn._filterKey  = clan;
            btn._filterType = 'clan';
            this._filterBtns.push(btn);
            curX += this._tabWidth(clan) + 4;
        }

        // Separator pip
        this.add.rectangle(curX + 2, barY, 2, 16, 0x334466);
        curX += 8;

        // Rarity filter tabs
        for (const { label, rarity } of RARITY_FILTERS) {
            const colorNum = this._hexToNum(RARITY_COLOR[rarity]);
            const btn = this._makeFilterBtn(curX, barY, label,
                () => this._toggleRarity(rarity), colorNum);
            btn._filterKey  = rarity;
            btn._filterType = 'rarity';
            this._filterBtns.push(btn);
            curX += this._tabWidth(label) + 4;
        }
    }

    _tabWidth(label) {
        return Math.max(36, label.length * 6 + 14);
    }

    _makeFilterBtn(x, y, label, cb, activeColor = 0x334466) {
        const w    = this._tabWidth(label);
        const rect = this.add.rectangle(x + w / 2, y, w, 22, 0x141820)
            .setStrokeStyle(1, 0x334466)
            .setInteractive({ useHandCursor: true });
        const txt  = this.add.text(x + w / 2, y, label, {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#888888',
        }).setOrigin(0.5);

        rect._label      = txt;
        rect._activeColor = activeColor;
        rect._active     = false;
        rect._cb         = cb;

        rect.on('pointerup', () => {
            rect._cb();
        });
        rect.on('pointerdown', () => rect.setAlpha(0.7));
        rect.on('pointerout',  () => rect.setAlpha(1));
        rect.on('pointerup',   () => rect.setAlpha(1));

        return rect;
    }

    _setFilterBtnActive(btn, active) {
        btn._active = active;
        if (active) {
            btn.setStrokeStyle(2, btn._activeColor || 0x4cc9f0);
            btn.setFillStyle(0x1e2a3a);
            btn._label.setColor('#ffffff');
        } else {
            btn.setStrokeStyle(1, 0x334466);
            btn.setFillStyle(0x141820);
            btn._label.setColor('#888888');
        }
    }

    _clearFilters() {
        this._activeClan.clear();
        this._activeRarity.clear();
        this._syncFilterBtnStates();
        this._applyFilters();
    }

    _toggleClan(clan) {
        if (this._activeClan.has(clan)) this._activeClan.delete(clan);
        else                             this._activeClan.add(clan);
        this._syncFilterBtnStates();
        this._applyFilters();
    }

    _toggleRarity(rarity) {
        if (this._activeRarity.has(rarity)) this._activeRarity.delete(rarity);
        else                                 this._activeRarity.add(rarity);
        this._syncFilterBtnStates();
        this._applyFilters();
    }

    _syncFilterBtnStates() {
        const noFilters = this._activeClan.size === 0 && this._activeRarity.size === 0;
        this._setFilterBtnActive(this._allBtn, noFilters);

        for (const btn of this._filterBtns) {
            if (btn === this._allBtn) continue;
            if (btn._filterType === 'clan') {
                this._setFilterBtnActive(btn, this._activeClan.has(btn._filterKey));
            } else if (btn._filterType === 'rarity') {
                this._setFilterBtnActive(btn, this._activeRarity.has(btn._filterKey));
            }
        }
    }

    _applyFilters() {
        const noClan   = this._activeClan.size   === 0;
        const noRarity = this._activeRarity.size === 0;

        this._filtered = this._collection.filter(card => {
            const clanOk   = noClan   || this._activeClan.has((card.clan   || '').toUpperCase());
            const rarityOk = noRarity || this._activeRarity.has(card.rarity);
            return clanOk && rarityOk;
        });

        this._scrollY = 0;
        this._gridContainer.y = GRID_Y;
        this._renderGrid();
    }

    // ── Grid container + mask ─────────────────────────────────────────────────

    _buildGridContainer() {
        this._gridContainer = this.add.container(0, GRID_Y);

        // Geometry mask — clips the scrolling grid to the grid area
        const maskGfx = this.add.graphics();
        maskGfx.fillStyle(0xffffff);
        maskGfx.fillRect(0, GRID_Y, W, GRID_H);
        this._gridContainer.setMask(maskGfx.createGeometryMask());

        // Empty-state text (hidden by default)
        this._emptyTxt = this.add.text(W / 2, GRID_Y + GRID_H / 2, 'No cards match filters', {
            fontSize: '13px', fontFamily: 'Arial Black', color: '#445566',
        }).setOrigin(0.5).setVisible(false).setDepth(5);
    }

    // ── Scroll input ──────────────────────────────────────────────────────────

    _buildScrollInput() {
        // Transparent overlay rectangle that captures drag events for the grid
        const overlay = this.add.rectangle(W / 2, GRID_Y + GRID_H / 2, W, GRID_H, 0x000000, 0)
            .setInteractive({ useHandCursor: false })
            .setDepth(10);

        overlay.on('pointerdown', (ptr) => {
            this._isDragging  = true;
            this._dragStartY  = ptr.y;
            this._scrollBase  = this._scrollY;
        });

        overlay.on('pointermove', (ptr) => {
            if (!this._isDragging) return;
            const dy     = ptr.y - this._dragStartY;
            const maxScroll = Math.max(0, this._contentH - GRID_H);
            this._scrollY           = Phaser.Math.Clamp(this._scrollBase + dy, -maxScroll, 0);
            this._gridContainer.y   = GRID_Y + this._scrollY;
        });

        overlay.on('pointerup', (ptr) => {
            if (this._isDragging) {
                const dx = Math.abs(ptr.x - (ptr.downX ?? ptr.x));
                const dy = Math.abs(ptr.y - this._dragStartY);
                // If movement was minimal it's a tap — handle card tap
                if (dx < 6 && dy < 6) {
                    this._handleGridTap(ptr.x, ptr.y);
                }
            }
            this._isDragging = false;
        });

        overlay.on('pointerupoutside', () => { this._isDragging = false; });
    }

    _handleGridTap(wx, wy) {
        // Convert world Y to container-local Y
        const ly = wy - this._gridContainer.y;
        for (const hit of this._cardHits) {
            if (Math.abs(wx - hit.lx) <= CARD_W / 2 &&
                Math.abs(ly - hit.ly) <= CARD_H / 2) {
                showCardZoom(this, hit.cardData);
                return;
            }
        }
    }

    // ── Loading spinner ───────────────────────────────────────────────────────

    _showSpinner() {
        const cx = W / 2;
        const cy = GRID_Y + GRID_H / 2;

        this._spinnerGroup = this.add.container(cx, cy);

        const rect = this.add.rectangle(0, 0, 24, 6, 0x4cc9f0).setDepth(20);
        this._spinnerGroup.add(rect);
        this._spinnerGroup.setDepth(20);

        this._spinnerTween = this.tweens.add({
            targets:  this._spinnerGroup,
            angle:    360,
            duration: 800,
            repeat:   -1,
            ease:     'Linear',
        });
    }

    _hideSpinner() {
        if (this._spinnerTween) { this._spinnerTween.stop(); this._spinnerTween = null; }
        if (this._spinnerGroup) { this._spinnerGroup.destroy(); this._spinnerGroup = null; }
    }

    // ── Data fetch ────────────────────────────────────────────────────────────

    _fetchCollection() {
        const token = this.registry.get('token');
        fetch('/api/collection/my', {
            headers: { Authorization: `Bearer ${token}` },
        })
        .then(r => {
            if (!r.ok) throw new Error(`HTTP ${r.status}`);
            return r.json();
        })
        .then(data => {
            this._hideSpinner();
            this._collection = Array.isArray(data) ? data : [];
            this._filtered   = [...this._collection];
            this._totalTxt.setText(`${this._collection.length} cards`);
            // Start with ALL active
            this._setFilterBtnActive(this._allBtn, true);
            this._renderGrid();
        })
        .catch(() => {
            this._hideSpinner();
            this._toast('Failed to load collection');
        });
    }

    // ── Grid rendering ────────────────────────────────────────────────────────

    _renderGrid() {
        this._gridContainer.removeAll(true);
        this._cardHits  = [];
        this._newBadges = [];

        if (this._filtered.length === 0) {
            this._emptyTxt.setVisible(true);
            this._contentH = 0;
            return;
        }
        this._emptyTxt.setVisible(false);

        const stepX = CARD_W + CARD_GAP;
        const stepY = CARD_H + CARD_GAP;
        const PAD   = 8;

        this._filtered.forEach((card, i) => {
            const col = i % COLS;
            const row = Math.floor(i / COLS);
            const lx  = PAD + col * stepX + CARD_W / 2;
            const ly  = PAD + row * stepY + CARD_H / 2;

            const borderColor = this._hexToNum(RARITY_COLOR[card.rarity] || '#aaaaaa');

            // Background + border
            const bg = this.add.rectangle(lx, ly, CARD_W, CARD_H, 0x0d1020)
                .setStrokeStyle(2, borderColor);
            this._gridContainer.add(bg);

            // Card art image
            const texKey = card.cardId;
            if (texKey && this.textures.exists(texKey)) {
                const img = this.add.image(lx, ly - 6, texKey)
                    .setDisplaySize(CARD_W - 4, CARD_H - 18);
                this._gridContainer.add(img);
            } else {
                // Fallback dark rectangle
                const fallback = this.add.rectangle(lx, ly - 6, CARD_W - 4, CARD_H - 18, 0x161824)
                    .setStrokeStyle(1, 0x223344);
                this._gridContainer.add(fallback);
            }

            // Card name at bottom
            const nameTxt = this.add.text(lx, ly + CARD_H / 2 - 2, card.name || card.cardId, {
                fontSize: '6px', fontFamily: 'Arial Black', color: '#dddddd',
                wordWrap: { width: CARD_W - 6 }, align: 'center',
            }).setOrigin(0.5, 1);
            this._gridContainer.add(nameTxt);

            // Count badge bottom-left (if count > 1)
            if ((card.count || 1) > 1) {
                const badgeBg = this.add.rectangle(
                    lx - CARD_W / 2 + 10, ly + CARD_H / 2 - 10,
                    20, 13, 0x000000, 0.85
                ).setStrokeStyle(1, 0x4cc9f0);
                const badgeTxt = this.add.text(
                    lx - CARD_W / 2 + 10, ly + CARD_H / 2 - 10,
                    `×${card.count}`, {
                        fontSize: '6px', fontFamily: 'Arial Black', color: '#4cc9f0',
                    }
                ).setOrigin(0.5);
                this._gridContainer.add(badgeBg);
                this._gridContainer.add(badgeTxt);
            }

            // NEW badge top-right
            if (card.isNew) {
                const badgeX = lx + CARD_W / 2 - 12;
                const badgeY = ly - CARD_H / 2 + 9;

                const newBg = this.add.rectangle(badgeX, badgeY, 22, 12, 0xd4a017)
                    .setStrokeStyle(1, 0xffd700);
                const newTxt = this.add.text(badgeX, badgeY, 'NEW', {
                    fontSize: '5px', fontFamily: 'Arial Black', color: '#000000',
                }).setOrigin(0.5);

                this._gridContainer.add(newBg);
                this._gridContainer.add(newTxt);
                this._newBadges.push({ cardId: card.cardId, objects: [newBg, newTxt] });
            }

            // Hit record (container-local coords)
            this._cardHits.push({ lx, ly, cardData: this._buildCardData(card) });
        });

        // Compute total scrollable content height
        const rows = Math.ceil(this._filtered.length / COLS);
        this._contentH = PAD * 2 + rows * stepY;
    }

    /** Build a minimal cardData object compatible with showCardZoom */
    _buildCardData(item) {
        return {
            id:         item.cardId,
            cardId:     item.cardId,
            art_url:    item.cardId,
            name:       item.name       || item.cardId,
            rarity:     item.rarity,
            clan:       item.clan,
            cardType:   item.cardType,
            subtype:    item.subtype,
            effectText: item.effectText || '',
        };
    }

    // ── Mark All Seen ─────────────────────────────────────────────────────────

    _markAllSeen() {
        const token = this.registry.get('token');
        fetch('/api/collection/mark-seen', {
            method:  'POST',
            headers: { Authorization: `Bearer ${token}` },
        }).catch(() => {}); // ignore errors per spec

        // Remove all NEW badges from the grid
        for (const badge of this._newBadges) {
            for (const obj of badge.objects) {
                obj.destroy();
            }
        }
        this._newBadges = [];

        // Clear isNew on collection data so re-renders don't show them
        this._collection.forEach(c => { c.isNew = false; });
        this._filtered.forEach(c => { c.isNew = false; });

        this._toast('All cards marked as seen', '#4cc9f0');
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    _hexToNum(hex) {
        return parseInt((hex || '#888888').replace('#', ''), 16);
    }

    _makeBtn(x, y, label, cb, color = 0x222244, w = 90, h = 26) {
        const btn = this.add.rectangle(x, y, w, h, color)
            .setStrokeStyle(1, 0x445577)
            .setInteractive({ useHandCursor: true })
            .setOrigin(0.5);
        this.add.text(x, y, label, {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5);
        btn.on('pointerup',   cb);
        btn.on('pointerdown', () => btn.setAlpha(0.7));
        btn.on('pointerout',  () => btn.setAlpha(1));
        btn.on('pointerup',   () => btn.setAlpha(1));
        return btn;
    }

    _toast(msg, color = '#e63946') {
        const t = this.add.text(W / 2, H - 22, msg, {
            fontSize: '11px', color,
            backgroundColor: '#000000',
            padding: { x: 10, y: 5 },
        }).setOrigin(0.5).setDepth(50);
        this.tweens.add({
            targets: t, alpha: 0, delay: 2400, duration: 400,
            onComplete: () => t.destroy(),
        });
    }

    shutdown() {
        this._hideSpinner();
    }
}
