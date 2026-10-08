import { SettingsManager } from '../utils/SettingsManager.js';
import { W, H } from '../utils/Layout.js';

export class VideoBackgroundScene extends Phaser.Scene {
    constructor() {
        super('VideoBackgroundScene');
        this.fullLayout = true;   // fills the whole 16:9 world on desktop (utils/Layout.js)
    }

    create() {
        // Low quality: static art instead of decoding video behind every menu
        if (!SettingsManager.videoBackground && this.textures.exists('menu_background')) {
            this.add.image(W / 2, H / 2, 'menu_background').setDisplaySize(W, H);
            return;
        }
        const vid = this.add.video(W / 2, H / 2, 'menu_background_video');
        vid.on('created', () => vid.setDisplaySize(W, H));
        vid.play(true); // loop forever
    }
}
