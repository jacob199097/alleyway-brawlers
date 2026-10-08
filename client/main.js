/**
 * ALLEYWAY BRAWLERS — Phaser 3 Client Entry Point
 * Portrait-mode Android target: 390 × 844 logical pixels.
 */

import Phaser from 'phaser';

import { BootScene }       from './scenes/BootScene.js';
import { LoginScene }      from './scenes/LoginScene.js';
import { PreloadScene }    from './scenes/PreloadScene.js';
import { MainMenuScene }   from './scenes/MainMenuScene.js';
import { DuelScene }       from './scenes/DuelScene.js';
import { MultiplayerDuelScene } from './scenes/MultiplayerDuelScene.js';
import { ShopScene }       from './scenes/ShopScene.js';
import { ContrabandScene } from './scenes/ContrabandScene.js';
import { ClanSelectScene } from './scenes/ClanSelectScene.js';
import { MailboxScene }    from './scenes/MailboxScene.js';
import { ProfileScene }    from './scenes/ProfileScene.js';
import { DeckBuilderScene }from './scenes/DeckBuilderScene.js';
import { SocialScene }     from './scenes/SocialScene.js';
import { PostMatchScene }  from './scenes/PostMatchScene.js';
import { CardLibraryScene }       from './scenes/CardLibraryScene.js';
import { MatchmakingScene }       from './scenes/MatchmakingScene.js';
import { RankedMatchmakingScene } from './scenes/RankedMatchmakingScene.js';
import { FightModeScene }         from './scenes/FightModeScene.js';
import { RPSScene }               from './scenes/RPSScene.js';
import { SettingsScene }          from './scenes/SettingsScene.js';
import { VideoBackgroundScene } from './scenes/VideoBackgroundScene.js';
import { isDesktop, bindRegistry } from './utils/Platform.js';
import { SettingsManager } from './utils/SettingsManager.js';
import { W, H } from './utils/Layout.js';
import { LetterboxScene } from './scenes/LetterboxScene.js';
import { installDesktopInput } from './utils/DesktopInput.js';

// Desktop shell: drop the mobile-only page hints (home-screen app, orientation lock, touch-action)
if (isDesktop) {
    document.querySelectorAll(
        'meta[name="mobile-web-app-capable"], meta[name="apple-mobile-web-app-capable"], meta[name="screen-orientation"]'
    ).forEach(m => m.remove());
    document.documentElement.classList.add('desktop');
}

// ── Shared game config (portrait, scale to fill screen) ──────────────────────
const config = {
    type:            Phaser.AUTO,
    width:           W,
    height:          H,
    backgroundColor: '#1a1a2e',
    parent:          'game-container',

    // Smooth scaling for the baked card-art images so they don't look pixelated
    // when displayed at non-native sizes (in-hand small, zoomed large)
    pixelArt:        false,
    antialias:       true,
    // Edge anti-aliasing (WebGL MSAA) — player setting, applies on restart
    antialiasGL:     SettingsManager.antialias,
    roundPixels:     false,

    scale: {
        mode:             Phaser.Scale.FIT,
        autoCenter:       Phaser.Scale.CENTER_BOTH,
        orientation:      Phaser.Scale.LANDSCAPE,
        width:            W,
        height:           H,
    },

    // No browser context menu (desktop will use right-click for card zoom)
    disableContextMenu: true,

    // Enable multi-touch input
    input: {
        touch: { capture: true },
    },

    dom: {
        createContainer: true,
    },

    scene: [
        BootScene,
        LetterboxScene,
        LoginScene,
        PreloadScene,
        MainMenuScene,
        DuelScene,
        MultiplayerDuelScene,
        ShopScene,
        ContrabandScene,
        ClanSelectScene,
        MailboxScene,
        ProfileScene,
        DeckBuilderScene,
        SocialScene,
        CardLibraryScene,
        MatchmakingScene,
        RankedMatchmakingScene,
        FightModeScene,
        RPSScene,
        PostMatchScene,
        SettingsScene,
        VideoBackgroundScene,
    ],
};

export const game = new Phaser.Game(config);
bindRegistry(game.registry);
if (isDesktop) game.events.once('ready', () => installDesktopInput(game));

// Expose for hot-reload / debug
if (typeof window !== 'undefined') window.__TWT__ = { game, settings: SettingsManager };
