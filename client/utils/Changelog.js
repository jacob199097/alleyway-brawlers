/**
 * Changelog modal — shown once per build version.
 *
 * Bump CURRENT_VERSION when releasing a new version. The modal will pop on
 * the first MainMenuScene create() after the version string changes.
 */

import { sceneH } from './Layout.js';

const CURRENT_VERSION = '0.4.0';
const STORAGE_KEY     = 'twt_seen_changelog_v';

const ENTRIES = [
    {
        version: '0.4.0',
        title:   'May 2026 Update',
        bullets: [
            'New: Lions & Vipers clan-pick onboarding flow',
            'New: Deck editor search bar + faction/type filters',
            'New: Persistent toast notifications, in-game changelog',
            'New: LOG OUT button in settings, password show/hide on login',
            'Fix: Email verification link now uses LAN address',
            'Fix: Victory/defeat screen uses blurred match snapshot',
        ],
    },
];

const W = 844;

export function maybeShowChangelog(scene) {
    if (!scene) return;
    const H = sceneH(scene);
    let seen = '';
    try { seen = localStorage.getItem(STORAGE_KEY) || ''; } catch {}
    if (seen === CURRENT_VERSION) return;

    const entry = ENTRIES.find(e => e.version === CURRENT_VERSION) || ENTRIES[0];
    if (!entry) return;

    const objs = [];
    const reg  = o => { objs.push(o); return o; };

    reg(scene.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.78).setDepth(8000).setInteractive());

    const PNL_W = 460, PNL_H = 280;
    reg(scene.add.rectangle(W / 2, H / 2, PNL_W, PNL_H, 0x101030, 0.98)
        .setStrokeStyle(2, 0xf4d35e).setDepth(8001));

    reg(scene.add.text(W / 2, H / 2 - PNL_H / 2 + 18, `${entry.title}  •  v${entry.version}`, {
        fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
    }).setOrigin(0.5).setDepth(8002));

    reg(scene.add.rectangle(W / 2, H / 2 - PNL_H / 2 + 32, PNL_W - 32, 1, 0xf4d35e, 0.4)
        .setDepth(8002));

    const body = entry.bullets.map(b => '• ' + b).join('\n');
    reg(scene.add.text(W / 2, H / 2 - 8, body, {
        fontSize: '11px', fontFamily: 'Arial', color: '#dddde8',
        align: 'left', lineSpacing: 6, wordWrap: { width: PNL_W - 40 },
    }).setOrigin(0.5).setDepth(8002));

    const bx = W / 2, by = H / 2 + PNL_H / 2 - 28;
    const btn = reg(scene.add.rectangle(bx, by, 140, 32, 0x2d6a4f)
        .setStrokeStyle(2, 0xa7e8c1).setDepth(8002).setInteractive({ useHandCursor: true }));
    reg(scene.add.text(bx, by, "GOT IT", {
        fontSize: '12px', fontFamily: 'Arial Black', color: '#ffffff',
    }).setOrigin(0.5).setDepth(8003));

    btn.on('pointerdown', () => btn.setAlpha(0.7));
    btn.on('pointerout',  () => btn.setAlpha(1));
    btn.on('pointerup',   () => {
        try { localStorage.setItem(STORAGE_KEY, CURRENT_VERSION); } catch {}
        objs.forEach(o => o?.destroy?.());
    });
}
