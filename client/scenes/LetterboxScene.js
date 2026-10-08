/**
 * LETTERBOX SCENE (desktop only)
 * Fills the bands above and below the 844×390 area that unconverted scenes draw in
 * (see utils/Layout.js) with dimmed alley art instead of flat bars. Sits behind every
 * other scene and never takes input. The centre band is left untouched so scenes look
 * exactly as before.
 */

import { isDesktop } from '../utils/Platform.js';
import { W, H, BASE_H, EXTRA_H } from '../utils/Layout.js';

export class LetterboxScene extends Phaser.Scene {
    constructor() {
        super({ key: 'LetterboxScene', active: isDesktop });
        this.fullLayout = true;
    }

    preload() {
        this.load.image('letterbox_art', 'assets/menu_background.png');
    }

    create() {
        this.scene.sendToBack();
        if (!EXTRA_H) return;

        const band = EXTRA_H / 2;
        const tex  = this.textures.get('letterbox_art').getSourceImage();
        const sy   = tex.height / H;   // source px per world px when stretched over the whole world

        // Top and bottom slices of the art, each cropped to its band
        for (const [y, cropY] of [[0, 0], [band + BASE_H, (band + BASE_H) * sy]]) {
            this.add.image(0, y, 'letterbox_art')
                .setOrigin(0, 0)
                .setCrop(0, cropY, tex.width, band * sy)
                .setDisplaySize(W, H)
                .setY(y - cropY / sy);
        }
        // Dim the art so it reads as a frame, not content
        this.add.rectangle(0, 0, W, band, 0x0d0d1a, 0.72).setOrigin(0, 0);
        this.add.rectangle(0, band + BASE_H, W, band, 0x0d0d1a, 0.72).setOrigin(0, 0);
        // Thin accent edges where the game area starts and ends
        this.add.rectangle(0, band - 1, W, 1, 0x4cc9f0, 0.35).setOrigin(0, 0);
        this.add.rectangle(0, band + BASE_H, W, 1, 0x4cc9f0, 0.35).setOrigin(0, 0);
    }

    update() {
        // Other scenes call sendToBack() too (the menu video does) — stay underneath all of them
        if (this.scene.getIndex() !== 0) this.scene.sendToBack();
    }
}
