import { getPlayerTitle } from '../utils/PlayerTitle.js';
import { apiFetch } from '../utils/Platform.js';
import { W, H, BASE_H, EXTRA_H, midY } from '../utils/Layout.js';

const BAR_H = Math.round(W * 260 / 2400); // 91px — matches main_menu_bar.png aspect ratio
const BAR_Y = BAR_H / 2;                  // vertical centre of bar

// XP within the current level, using the same exponential curve as the backend
function xpProgress(player) {
    const lvl = Math.min(player.level || 1, 50);
    let atLevel = 0;
    for (let i = 1; i < lvl; i++) atLevel += Math.floor(100 * Math.pow(i, 1.5));
    const needed  = Math.floor(100 * Math.pow(lvl, 1.5));
    const current = Math.max(0, (player.xp || 0) - atLevel);
    if (lvl >= 50) return { current: needed, needed, pct: 1 };
    return { current: Math.min(current, needed), needed, pct: needed > 0 ? Math.min(1, current / needed) : 1 };
}

export class MainMenuScene extends Phaser.Scene {
    constructor() {
        super('MainMenuScene');
        this.fullLayout = true;   // lays out against Layout.H (see utils/Layout.js)
    }

    create() {
        const token = this.registry.get('token');
        if (!token) { this.scene.start('LoginScene'); return; }

        this._buildBackground();
        this._playBGM();

        // Always fetch fresh player data so post-match rewards show immediately
        apiFetch('/api/profile/me')
            .then(r => r.ok ? r.json() : null)
            .then(player => {
                if (!player) { this.scene.start('LoginScene'); return; }
                this.registry.set('player', player);
                this._buildTopBar(player);
                this._buildCenterButtons();
                this._buildRightButtons();
                this._loadAndBuildQuests(player);
                import('../utils/Changelog.js').then(m => m.maybeShowChangelog(this));
            })
            .catch(() => {
                // Fall back to cached data if the fetch fails
                const player = this.registry.get('player');
                if (!player) { this.scene.start('LoginScene'); return; }
                this._buildTopBar(player);
                this._buildCenterButtons();
                this._buildRightButtons();
                this._loadAndBuildQuests(player);
            });
    }

    _buildBackground() {
        this.add.rectangle(W / 2, H / 2, W, H, 0x000000).setAlpha(0.35);
    }

    // ── Top info bar ──────────────────────────────────────────────────────────

    _buildTopBar(player) {
        this.add.image(W / 2, BAR_Y, 'main_menu_bar').setDisplaySize(W, BAR_H);

        // ── Profile avatar (square) ───────────────────────────────────────
        const iconX = 64;
        const iconR = 33;
        const iconKey = (player.avatar_url && this.textures.exists(player.avatar_url))
            ? player.avatar_url : 'profile_001';

        const icon = this.add.image(iconX, BAR_Y, iconKey)
            .setDisplaySize(iconR * 2, iconR * 2)
            .setInteractive({ useHandCursor: true });

        icon.on('pointerdown', () => icon.setAlpha(0.7));
        icon.on('pointerout',  () => icon.setAlpha(1));
        icon.on('pointerup',   () => { icon.setAlpha(1); this.scene.start('ProfileScene'); });

        // ── Stats — top row: username (PLAYER NAME field) + level (LVL field) ──
        this.add.text(245, BAR_Y - 14, player.username.toUpperCase(), {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5, 0.5);

        this.add.text(410, BAR_Y - 14, `${player.level}`, {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5, 0.5);

        // ── Stats — bottom row: title (TITLE field) + XP bar ──────────────
        this.add.text(185, BAR_Y + 12, getPlayerTitle(player.level), {
            fontSize: '8px', fontFamily: 'Arial Black', color: '#e63946',
        }).setOrigin(0.5, 0.5);

        const xp     = xpProgress(player);
        const xpBarX = 345;
        const xpBarY = BAR_Y + 20;
        const xpBarW = 95;
        const xpBarH = 4;
        this.add.text(xpBarX + xpBarW / 2, xpBarY - 10, `${xp.current} / ${xp.needed}`, {
            fontSize: '7px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5, 0.5);
        this.add.rectangle(xpBarX, xpBarY, xpBarW, xpBarH, 0x1a1a3a).setOrigin(0, 0.5);
        this.add.rectangle(xpBarX, xpBarY, xpBarW * xp.pct, xpBarH, 0x4cc9f0).setOrigin(0, 0.5);

        // ── Contraband value — overlays the gold amount field on the bar ──
        this._contrabandText = this.add.text(706, BAR_Y - 10, `${player.contraband ?? 0}`, {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#e040fb',
        }).setOrigin(0.5, 0.5);

        // ── Karat value — overlays the contraband field on the bar ──────
        this._karatText = this.add.text(762, BAR_Y - 10, `${player.karat ?? 0}`, {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5, 0.5);

        // ── Invisible click zones over bar's native icons ──────────────────
        // Settings gear (leftmost, before mail)
        this._makeBarZone(500, BAR_Y, 30, () => {
            this.scene.pause();
            this.scene.launch('SettingsScene');
        });
        // Mail icon
        this._makeBarZone(545, BAR_Y, 28, () => this.scene.start('MailboxScene'));
        // Chat / social icon
        this._makeBarZone(572, BAR_Y, 28, () => this.scene.start('SocialScene'));
        // Briefcase / shop icon
        this._makeBarZone(628, BAR_Y, 36, () => this.scene.start('ShopScene'));
    }

    // ── Centre: fight + deck editor ───────────────────────────────────────────

    _buildCenterButtons() {
        const cx = W / 2;
        // Fight + deck editor + library column. The 16:9 desktop world has room to centre the
        // whole column under the bar; the 390-tall layout keeps its original spacing.
        const columnH = 131 + 10 + 131 + 12 + 26;
        const top = EXTRA_H ? BAR_H + (H - BAR_H - columnH) / 2 : BAR_H + 14;
        const y1  = top + 65;          // 170 at 390 tall
        const y2  = y1 + 131 + 10;     // 311 at 390 tall

        this._makeImageBtn(cx, y1, 'fight_menu',  240, 131, () => this.scene.start('FightModeScene'));
        this._makeImageBtn(cx, y2, 'deck_editor', 240, 131, () => this.scene.start('DeckBuilderScene'));

        // Card Library button — compact, below deck editor
        this._buildCardLibraryBtn(cx, y2 + 65 + 12 + 13);
    }

    _buildCardLibraryBtn(cx, btnY) {
        const btnW = 130, btnH = 26;
        const bg = this.add.rectangle(cx, btnY, btnW, btnH, 0x000a1a)
            .setStrokeStyle(1, 0x4cc9f0, 0.9).setInteractive({ useHandCursor: true });
        this.add.text(cx, btnY, '📖 CARD LIBRARY', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5).setDepth(1);
        bg.on('pointerdown', () => bg.setAlpha(0.6));
        bg.on('pointerout',  () => bg.setAlpha(1));
        bg.on('pointerup',   () => { bg.setAlpha(1); this.scene.start('CardLibraryScene'); });
    }

    // ── Right panel: shop · profile · social ─────────────────────────────────

    _buildRightButtons() {
        const rx = W - 110;
        // Available height below bar: 299px
        // Three buttons at 178×97 + 4px gaps = 299px → no extra padding needed
        // (centred in the extra height on desktop)
        const y1 = midY(BAR_H + 49);   // 140 at 390 tall
        const y2 = y1 + 97 + 5;        // 242
        const y3 = y2 + 97 + 5;        // 344

        // Images are 2400×1309 (ratio ~1.834:1); at width=178 → height=97
        this._makeImageBtn(rx, y1, 'shop_menu',    178, 97, () => this.scene.start('ShopScene'));
        this._makeImageBtn(rx, y2, 'profile_menu', 178, 97, () => this.scene.start('ProfileScene'));
        this._makeImageBtn(rx, y3, 'social_menu',  178, 97, () => this.scene.start('SocialScene'));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _makeBarZone(x, y, size, cb) {
        const zone = this.add.zone(x, y, size, size).setInteractive({ useHandCursor: true });
        zone.on('pointerup', cb);
    }

    _makeImageBtn(x, y, key, w, h, cb) {
        const img = this.add.image(x, y, key).setDisplaySize(w, h)
            .setInteractive({ useHandCursor: true });
        img.on('pointerdown', () => img.setAlpha(0.7));
        img.on('pointerup',   () => { img.setAlpha(1); cb(); });
        img.on('pointerout',  () => img.setAlpha(1));
    }

    _toast(msg, color = '#4cc9f0') {
        const t = this.add.text(W / 2, H - 20, msg, {
            fontSize: '12px', color, backgroundColor: '#000',
            padding: { x: 8, y: 5 },
        }).setOrigin(0.5).setDepth(50);
        this.tweens.add({ targets: t, alpha: 0, delay: 2000, duration: 400,
            onComplete: () => t.destroy() });
    }

    _playBGM() {
        try {
            const key = this.cache.audio.exists('bgm_main_menu') ? 'bgm_main_menu' : 'bgm_menu';
            // If the menu BGM is already playing, leave it alone — navigating between
            // menu sub-scenes (shop, profile, etc.) should not restart the track.
            const alreadyPlaying = this.sound.sounds?.some(s => s.key === key && s.isPlaying);
            if (alreadyPlaying) return;

            // Stop duel music only (not menu music that may be continuing from a previous visit)
            ['bgm_duel_theme', 'bgm_duel'].forEach(k => {
                this.sound.sounds?.filter(s => s.key === k && s.isPlaying).forEach(s => s.stop());
            });

            if (this.cache.audio.exists(key)) {
                this.sound.add(key, { loop: true, volume: 0.35 }).play();
            }
        } catch (_) {}
    }

    // ── Quest panel ───────────────────────────────────────────────────────────

    async _loadAndBuildQuests(player) {
        let questData = { daily: [], main: [] };
        try {
            const r = await apiFetch('/api/quests');
            if (r.ok) questData = await r.json();
        } catch (_) {}

        if (!this.scene.isActive('MainMenuScene')) return;
        this._buildQuestsPanel(player, questData);
    }

    _buildQuestsPanel(player, { daily, main }) {
        // Pinned to the far-left; enlarged (depth -1 so the fight button stays on top
        // if any right-edge pixels bleed into its area).
        // Panel keeps its 390-tall design, centred in any extra height (desktop)
        const oy  = EXTRA_H / 2;
        const PW  = 500;
        const PH  = BASE_H + -90;
        this.add.image(0, BASE_H / 2 + oy, 'quests').setOrigin(0.2, 0.4).setDisplaySize(PW, PH).setDepth(-1);

        // Content must still stay left of the fight button (left edge x≈302)
        const CONTENT_W = 300;           // safe content zone width
        const CX    = CONTENT_W / 2;     // centre of content zone
        const TOP   = BAR_H + oy;        // y ≈ 91 at 390 tall
        const MID   = BAR_H + (BASE_H - BAR_H) / 2 + oy;  // y ≈ 240 at 390 tall
        const ROW_W = CONTENT_W - 60;

        // ── Main quests section (top half) ──────────────────────────────────
        const mainVisible = (main.length ? main : [])
            .filter(q => !q.claimed)
            .sort((a, b) => (b.progress / b.target) - (a.progress / a.target))
            .slice(0, 3);

        let ry = TOP + 48;
        for (const q of mainVisible) {
            this._renderQuestRow(CX, ry, ROW_W, q, false);
            ry += 25;
        }

        // ── Daily quests section (bottom half) ──────────────────────────────
        ry = MID + -20;
        for (const q of (daily || [])) {
            this._renderQuestRow(CX, ry, ROW_W, q, true);
            ry += 25;
        }
    }

    _renderQuestRow(cx, y, rowW, quest, isDaily) {
        const done    = quest.progress >= quest.target;
        const claimed = quest.claimed;
        const pct     = Math.min(1, quest.progress / quest.target);
        const barW    = rowW * 0.68;
        const barH    = 4;

        const nameCol = claimed ? '#666666' : done ? '#4caf50' : '#ffffff';

        this.add.text(cx, y, quest.label, {
            fontSize: '7px', fontFamily: 'Arial Black', color: nameCol,
        }).setOrigin(0.5, 0).setDepth(2);

        // Progress bar
        const bx = cx - barW / 2;
        this.add.rectangle(cx, y + 12, barW, barH, 0x111133).setOrigin(0.5, 0.5).setDepth(2);
        if (pct > 0) {
            this.add.rectangle(bx, y + 12, barW * pct, barH, done ? 0x4caf50 : 0x4cc9f0)
                .setOrigin(0, 0.5).setDepth(2);
        }

        if (done && !claimed) {
            // Interactive CLAIM label
            const reward = quest.rewardKarat
                ? `+${quest.rewardKarat}K`
                : `+${quest.rewardContraband}C`;
            const btn = this.add.text(cx, y + 19, `CLAIM ${reward}`, {
                fontSize: '6px', fontFamily: 'Arial Black', color: '#000000',
                backgroundColor: '#4caf50', padding: { x: 3, y: 1 },
            }).setOrigin(0.5, 0).setDepth(3).setInteractive({ useHandCursor: true });

            btn.on('pointerdown', () => btn.setAlpha(0.7));
            btn.on('pointerout',  () => btn.setAlpha(1));
            btn.on('pointerup',   () => {
                btn.setAlpha(1);
                this._claimQuest(quest.id, btn);
            });
        } else {
            this.add.text(cx, y + 19, `${quest.progress} / ${quest.target}`, {
                fontSize: '6px', fontFamily: 'Arial', color: claimed ? '#555555' : '#aaaaaa',
            }).setOrigin(0.5, 0).setDepth(2);
        }
    }

    _claimQuest(questId, btn) {
        btn.setText('...').disableInteractive();

        apiFetch(`/api/quests/claim/${questId}`, {
            method: 'POST',
        })
        .then(r => r.json().then(d => ({ ok: r.ok, data: d })))
        .then(({ ok, data }) => {
            if (!ok) { btn.setText('ERR'); return; }

            btn.destroy();

            // Update player currency in registry + refresh on-screen totals
            const p = this.registry.get('player');
            if (p) {
                p.karat      = data.karat;
                p.contraband = data.contraband;
                this.registry.set('player', p);
            }
            this._karatText?.setText(`${data.karat ?? 0}`);
            this._contrabandText?.setText(`${data.contraband ?? 0}`);

            this._toast('Quest reward claimed!', '#4caf50');
        })
        .catch(() => btn.setText('ERR'));
    }
}
