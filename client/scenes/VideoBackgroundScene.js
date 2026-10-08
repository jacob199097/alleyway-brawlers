const W = 844;
const H = 390;

export class VideoBackgroundScene extends Phaser.Scene {
    constructor() { super('VideoBackgroundScene'); }

    create() {
        const vid = this.add.video(W / 2, H / 2, 'menu_background_video');
        vid.on('created', () => vid.setDisplaySize(W, H));
        vid.play(true); // loop forever
    }
}
