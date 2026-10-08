import { apiFetch } from '../utils/Platform.js';
import { VIEW_H } from '../utils/Layout.js';
const W = 844;
const H = 390;

const BUNDLES = [
    { id: 'cb_500', amount: 500,   price: 4.99,  imageKey: 'contraband_499',  tag: '' },
    { id: 'cb_1200', amount: 1200,  price: 9.99,  imageKey: 'contraband_999',  tag: 'STARTER' },
    { id: 'cb_2500', amount: 2500,  price: 19.99, imageKey: 'contraband_1999', tag: '' },
    { id: 'cb_7000', amount: 7000,  price: 49.99, imageKey: 'contraband_4999', tag: 'BEST VALUE' },
    { id: 'cb_15000', amount: 15000, price: 99.99, imageKey: 'contraband_9999', tag: '' },
];

export class ContrabandScene extends Phaser.Scene {
    constructor() {
        super('ContrabandScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.7);

        this.add.text(W / 2, 22, 'PURCHASE CONTRABAND', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#e040fb',
        }).setOrigin(0.5);

        this._cbText = this.add.text(W / 2, 42, '', {
            fontSize: '11px', color: '#e040fb',
        }).setOrigin(0.5);
        this._refreshContrabandLabel();

        // Lay out the five bundles in a single row — artwork now dominates the card
        const cardW   = 156;
        const cardH   = 270;
        const spacing = (W - 40 - cardW) / (BUNDLES.length - 1);
        const startX  = 20 + cardW / 2;
        const cardY   = H / 2 + 18;

        // Black backdrop behind every bundle so the artwork + buttons sit on
        // a single dark slab.
        const panelPadX = 14;
        const panelPadY = 12;
        const panelW = W - 28;
        const panelH = cardH + panelPadY * 2;
        this.add.rectangle(W / 2, cardY, panelW, panelH, 0x000000, 0.92)
            .setStrokeStyle(2, 0xe040fb, 0.85);

        BUNDLES.forEach((bundle, i) => {
            const x = startX + i * spacing;
            this._buildBundleCard(bundle, x, cardY, cardW, cardH);
        });

        this._buildBackButton();
    }

    _buildBundleCard(bundle, x, y, w, h) {
        const accent = 0xe040fb;

        // Artwork takes up the whole card area (image already shows units + price)
        const imgH = Math.round(h * 0.82);
        const imgY = y - h / 2 + imgH / 2 + 4;
        if (this.textures.exists(bundle.imageKey)) {
            this.add.image(x, imgY, bundle.imageKey).setDisplaySize(w, imgH);
        } else {
            this.add.rectangle(x, imgY, w, imgH, 0x2d0040).setStrokeStyle(1, accent);
        }

        // "Purchase" button beneath the artwork
        const btnY = y + h / 2 - 12;
        const btn = this.add.rectangle(x, btnY, w - 8, 24, 0x6a0d8a)
            .setStrokeStyle(1, accent).setInteractive({ useHandCursor: true });
        this.add.text(x, btnY, 'Purchase', {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(1);

        btn.on('pointerdown', () => btn.setAlpha(0.6));
        btn.on('pointerout',  () => btn.setAlpha(1));
        btn.on('pointerup',   () => { btn.setAlpha(1); this._purchase(bundle); });
    }

    _purchase(bundle) {
        apiFetch('/api/shop/contraband/purchase', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ bundleId: bundle.id }),   // server owns price + amount
        })
        .then(r => r.json().then(d => ({ ok: r.ok, data: d })))
        .then(({ ok, data }) => {
            if (!ok) { this._showToast(data.error || 'Purchase failed', '#e63946'); return; }
            const player = this.registry.get('player');
            if (player) {
                player.contraband = data.newContraband;
                this.registry.set('player', player);
            }
            this._refreshContrabandLabel();
            this._showToast(`+${data.contrabandGranted.toLocaleString()} Contraband added!`, '#e040fb');
        })
        .catch(() => this._showToast('Network error', '#e63946'));
    }

    _refreshContrabandLabel() {
        const player = this.registry.get('player');
        const cb = player?.contraband ?? 0;
        this._cbText.setText(`Balance: ${cb.toLocaleString()} CB`);
    }

    _buildBackButton() {
        const btn = this.add.rectangle(40, H - 18, 72, 28, 0x333355)
            .setStrokeStyle(1, 0xffffff).setInteractive({ useHandCursor: true });
        this.add.text(40, H - 18, '← BACK', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(1);
        btn.on('pointerup', () => this.scene.start('ShopScene'));
    }

    _showToast(msg, color = '#e63946') {
        const t = this.add.text(W / 2, H - 20, msg, {
            fontSize: '13px', color, backgroundColor: '#000000',
            padding: { x: 10, y: 6 },
        }).setOrigin(0.5).setDepth(100);
        this.tweens.add({ targets: t, alpha: 0, delay: 2000, duration: 500,
            onComplete: () => t.destroy() });
    }
}
