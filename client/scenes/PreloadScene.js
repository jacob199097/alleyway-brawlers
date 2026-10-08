import { SettingsManager } from '../utils/SettingsManager.js';
import { VIEW_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

export class PreloadScene extends Phaser.Scene {
    constructor() {
        super('PreloadScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    preload() {
        this._buildProgressBar();

        this.load.image('menu_background',  'assets/menu_background.png');
        this.load.video('menu_background_video', 'assets/menu_new_loop.mp4', true);
        this.load.image('fight_menu',       'assets/fight_menu.png');
        this.load.image('deck_editor',      'assets/deck_editor.png');
        this.load.image('main_menu_bar',    'assets/main_menu_bar.png');
        this.load.image('profile_001',      'assets/profile_001.png');
        this.load.image('profile_002',      'assets/profile_002.png');
        this.load.image('shop_menu',        'assets/shop_menu.png');
        this.load.image('profile_menu',     'assets/profile_menu.png');
        this.load.image('social_menu',      'assets/social_menu.png');
        this.load.image('contraband_499',   'assets/contraband_4.99.png');
        this.load.image('contraband_999',   'assets/contraband_9.99.png');
        this.load.image('contraband_1999',  'assets/contraband_19.99.png');
        this.load.image('contraband_4999',  'assets/contraband_49.99.png');
        this.load.image('contraband_9999',  'assets/contraband_99.99.png');
        this.load.image('quests',           'assets/quests.png');
        this.load.image('duel_background',  'assets/duel_background.png');
        this.load.image('victory_screen', 'assets/victory.png');
        this.load.image('defeat_screen',  'assets/defeat.png');
        this.load.image('card_frame',       'assets/Cropped_Frame.png');
        this.load.image('eric_lv1',         'assets/cards/eric_lv1.png');
        this.load.image('eric_lv2',         'assets/cards/eric_lv2.png');
        this.load.image('eric_lv3',         'assets/cards/eric_lv3.png');
        this.load.image('king_roan',        'assets/cards/king_roan.png');
        this.load.image('maya_lv1',         'assets/cards/maya_lv1.png');
        this.load.image('maya_lv2',         'assets/cards/maya_lv2.png');
        this.load.image('maya_lv3',         'assets/cards/maya_lv3.png');
        this.load.image('pride_runner',     'assets/cards/pride_runner.png');
        this.load.image('lion_grunt',       'assets/cards/lion_grunt.png');
        this.load.image('block_enforcer',   'assets/cards/block_enforcer.png');
        this.load.image('goldfang',         'assets/cards/goldfang.png');
        this.load.image('pride_lieutenant', 'assets/cards/pride_lieutenant.png');
        this.load.image('pride_mentor',     'assets/cards/pride_mentor.png');
        this.load.image('brutus',           'assets/cards/brutus.png');
        this.load.image('lion_ambush',      'assets/cards/lion_ambush.png');
        this.load.image('no_witnesses',     'assets/cards/no_witnesses.png');
        this.load.image('kings_test',       'assets/cards/kings_test.png');
        this.load.image('corner_deal',      'assets/cards/corner_deal.png');
        this.load.image('blood_scent',      'assets/cards/blood_scent.png');
        this.load.image('lion_rescue',      'assets/cards/lion_rescue.png');
        this.load.image('hunter_lv1',      'assets/cards/hunter_lv1.png');
        this.load.image('hunter_lv2',      'assets/cards/hunter_lv2.png');
        this.load.image('hunter_lv3',      'assets/cards/hunter_lv3.png');
        this.load.image('viper_lv1',       'assets/cards/viper_lv1.png');
        this.load.image('viper_lv2',       'assets/cards/viper_lv2.png');
        this.load.image('viper_lv3',       'assets/cards/viper_lv3.png');
        this.load.image('debt_collector',  'assets/cards/debt_collector.png');
        this.load.image('bulwark',         'assets/cards/bulwark.png');
        this.load.image('mauler',          'assets/cards/mauler.png');
        this.load.image('kingpin',         'assets/cards/kingpin.png');
        this.load.image('sovereign',       'assets/cards/sovereign.png');

        // Keyword reference images (shown on card zoom when relevant keywords appear)
        this.load.image('kw_promote',  'assets/keywords/promote_keyword.png');
        this.load.image('kw_downed',   'assets/keywords/downed_keyword.png');

        this.load.on('loaderror', () => {});
        this.load.image('card_back',    'assets/card_back.png');
        this.load.image('lion_booster',  'assets/Lion_booster.png');
        this.load.image('viper_booster', 'assets/Viper_booster.png');
        this.load.image('lions_deck',    'assets/lions_deck.png');
        this.load.image('vipers_deck',   'assets/vipers_deck.png');

        // Rank badge images
        this.load.image('rank_rookie',      'assets/ranks/rookie.png');
        this.load.image('rank_runner',      'assets/ranks/runner.png');
        this.load.image('rank_enforcer',    'assets/ranks/enforcer.png');
        this.load.image('rank_brawler',     'assets/ranks/brawler.png');
        this.load.image('rank_striver',     'assets/ranks/striver.png');
        this.load.image('rank_shot_caller', 'assets/ranks/shot_caller.png');
        this.load.image('rank_lieutenant',  'assets/ranks/lieutenant.png');
        this.load.image('rank_kingpin',     'assets/ranks/kingpin.png');
        this.load.image('rank_sovereign',   'assets/ranks/Sovereign.png');
        this.load.image('rank_undisputed',  'assets/ranks/undisputed.png');
        this.load.image('title_alleyway', 'assets/title_alleyway.png');
        this.load.spritesheet('fx_attack',  'assets/fx/attack.png',  { frameWidth: 128, frameHeight: 128 });
        this.load.spritesheet('fx_destroy', 'assets/fx/destroy.png', { frameWidth: 128, frameHeight: 128 });
        this.load.spritesheet('fx_ambush',  'assets/fx/ambush.png',  { frameWidth: 128, frameHeight: 128 });
        this.load.spritesheet('fx_direct',  'assets/fx/direct.png',  { frameWidth: 256, frameHeight: 128 });
        this.load.audio('sfx_card_play', 'assets/audio/card_play.mp3');
        this.load.audio('sfx_attack',    'assets/audio/attack.mp3');
        this.load.audio('sfx_destroy',   'assets/audio/destroy.mp3');
        this.load.audio('sfx_victory',   'assets/audio/victory.mp3');
        this.load.audio('sfx_defeat',    'assets/audio/defeat.mp3');
        this.load.audio('bgm_duel',      'assets/audio/bgm_duel.mp3');
        this.load.audio('bgm_menu',      'assets/audio/bgm_menu.mp3');
        this.load.audio('bgm_main_menu', 'assets/main_menu_theme_loop.mp3');
        this.load.audio('bgm_duel_theme', 'assets/duel_theme.mp3');
    }

    create() {
        this._defineAnimations();
        if (!this.scene.isActive('VideoBackgroundScene')) {
            this.scene.launch('VideoBackgroundScene');
            this.scene.sendToBack('VideoBackgroundScene');
        }
        // First-time players pick their starting clan before reaching the menu
        const player = this.registry.get('player');
        if (player && !player.chosen_clan) {
            // Force default render quality to 'high' for a brand-new account so
            // a previous tester's "low" choice in localStorage doesn't carry over.
            SettingsManager.quality = 'high';
            this.scene.start('ClanSelectScene');
        } else {
            this.scene.start('MainMenuScene');
        }
    }

    _buildProgressBar() {
        const barW = W * 0.5;
        const barH = 16;
        const x    = W / 2;
        const y    = H / 2;

        // Background — use menu background if already cached, else dark fallback
        if (this.textures.exists('menu_background')) {
            this.add.image(x, y, 'menu_background').setDisplaySize(W, VIEW_H).setOrigin(0.5);
        } else {
            this.add.rectangle(x, y, W, VIEW_H, 0x04060c).setOrigin(0.5);
        }

        // Dark overlay so the progress bar / title stay readable
        this.add.rectangle(x, y, W, VIEW_H, 0x000000, 0.55).setOrigin(0.5);

        if (this.textures.exists('title_alleyway')) {
            this.add.image(x, y - 90, 'title_alleyway').setDisplaySize(300, 163).setOrigin(0.5);
        }

        this.add.rectangle(x, y, barW, barH, 0x333333).setOrigin(0.5);
        const bar = this.add.rectangle(x - barW / 2, y, 0, barH, 0xe63946).setOrigin(0, 0.5);

        this.load.on('progress', v => { bar.width = barW * v; });

        this._buildTipPanel(x, y);
    }

    _buildTipPanel(centerX, barY) {
        const TIPS = [
            // Combat & Mechanics
            ['STREET TACTICS', "Reduce your opponent's Morale from 6000 to 0 to win the brawl. Protect your turf."],
            ['DIRECT HITS',    "If your opponent's Front Row is empty, your Characters can attack their Morale directly."],
            ['ATK vs ATK',     "When two Characters battle in Attack Position, the loser is sent to The Gutter and any excess damage is subtracted from the loser's Morale."],
            ['HOLD THE LINE',  "Placing a Character in Defense Position (sideways) protects your Morale — even if destroyed, you take no excess damage."],
            ['PROMOTE SICKNESS',"Newly Promoted Strivers cannot attack the turn they promote. Plan ahead!"],

            // Promote mechanic
            ['EVOLVE',         "Strivers start weak, but Promoted versions are pulled instantly from your Hideout when they score a kill."],
            ['GEAR SURVIVES',  "If a Striver has Hardware equipped when they Promote, the gear stays attached to their evolved form — it doesn't get sent to The Gutter."],

            // Resources
            ['AUTHORITY CURVE',"You gain 1 max Authority per turn, capping at 15. Save your Heavies for when you have the resources to back them up."],
            ['MULLIGAN',       "Use the Mulligan at the start to toss expensive Heavies and dig for low-cost Brawlers and Strivers."],

            // Support cards
            ['AMBUSH',         "Ambushes trigger during your opponent's turn. A well-placed Ambush can completely ruin their Brawl Phase."],
            ['HUSTLE',         "Hustles play directly from your hand for an immediate effect, then go straight to The Gutter."],
            ['BACK ROW',       "You only have 3 Back Row slots for Ambushes and Hardware. Manage your space wisely."],

            // Flavour / world-building
            ['THE GUTTER',     "Every fallen Character, used Hustle, and broken piece of Hardware ends up in The Gutter. Watch it to track what your opponent has burned."],
            ['THE HIDEOUT',    "Your LV2, LV3, and LV4 fighters wait in The Hideout — they never clog your main deck draws."],
            ['DOWNED STATE',   "Characters are Downed instead of destroyed in battle. Downed units can't attack or use effects, but recover at the start of your turn. Attack a Downed unit again to send it to The Gutter for good."],
            ['THE KINGPIN',    "Your Leader starts Dormant — their passive effect applies immediately, but they can't attack. Fulfill their Awaken condition to enter them into the Brawl."],
        ];

        const tipY = barY + 70;
        const panelW = 620, panelH = 78;

        // Slim panel behind the tip
        this.add.rectangle(centerX, tipY, panelW, panelH, 0x04060c, 0.82)
            .setStrokeStyle(1, 0xf4d35e, 0.8).setOrigin(0.5);

        // "TIP" badge in the top-left corner
        this.add.rectangle(centerX - panelW / 2 + 38, tipY - panelH / 2 + 12, 60, 16,
            0xf4d35e, 0.95).setOrigin(0.5);
        this.add.text(centerX - panelW / 2 + 38, tipY - panelH / 2 + 12, 'TIP',
            { fontSize: '10px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
              fontStyle: 'bold', color: '#1a1a2e', letterSpacing: 2 }
        ).setOrigin(0.5);

        // Title (rotates with the tip)
        const titleText = this.add.text(centerX, tipY - panelH / 2 + 12, '', {
            fontSize: '11px', fontFamily: 'Impact, "Arial Narrow", sans-serif',
            fontStyle: 'bold', color: '#ffd86b', letterSpacing: 1,
            stroke: '#000', strokeThickness: 2,
        }).setOrigin(0.5);

        // Body
        const bodyText = this.add.text(centerX, tipY + 8, '', {
            fontSize: '8px', fontFamily: 'Verdana, sans-serif',
            color: '#dcdcec', wordWrap: { width: panelW - 40 }, align: 'center',
        }).setOrigin(0.5);

        let idx = Math.floor(Math.random() * TIPS.length);
        const showTip = (i) => {
            const [title, body] = TIPS[i];
            titleText.setText(title);
            bodyText.setText(body);
        };
        showTip(idx);

        this._tipTimer = this.time.addEvent({
            delay: 4500, loop: true,
            callback: () => {
                idx = (idx + 1) % TIPS.length;
                showTip(idx);
            },
        });
    }

    _defineAnimations() {
        const defs = [
            { key: 'anim_attack',  texture: 'fx_attack',  end: 7,  frameRate: 18 },
            { key: 'anim_destroy', texture: 'fx_destroy', end: 11, frameRate: 20 },
            { key: 'anim_ambush',  texture: 'fx_ambush',  end: 9,  frameRate: 16 },
            { key: 'anim_direct',  texture: 'fx_direct',  end: 7,  frameRate: 18 },
        ];
        for (const d of defs) {
            if (!this.textures.exists(d.texture)) continue;
            this.anims.create({
                key:       d.key,
                frames:    this.anims.generateFrameNumbers(d.texture, { start: 0, end: d.end }),
                frameRate: d.frameRate,
                repeat:    0,
            });
        }
    }
}
