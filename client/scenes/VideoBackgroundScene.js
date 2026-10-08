import { SettingsManager } from '../utils/SettingsManager.js';

const W = 844;
const H = 390;

export class VideoBackgroundScene extends Phaser.Scene {
    constructor() { super('VideoBackgroundScene'); }

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
