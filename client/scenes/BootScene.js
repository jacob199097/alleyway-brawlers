/**
 * BOOT SCENE
 * Runs once at startup. Reads saved auth token from localStorage
 * and routes to either the login screen or the main menu.
 */

import { SettingsManager } from '../utils/SettingsManager.js';
import { apiFetch } from '../utils/Platform.js';

export class BootScene extends Phaser.Scene {
    constructor() { super('BootScene'); }

    preload() {
        this.load.image('title_alleyway', 'assets/title_alleyway.png');
    }

    create() {
        // Initialise settings first so volume is correct before any audio plays
        SettingsManager.init(this.game);
        const token = localStorage.getItem('twt_token');
        if (token) {
            // Validate token by fetching player profile
            apiFetch('/api/profile/me')
            .then(r => r.ok ? r.json() : Promise.reject())
            .then(player => {
                this.registry.set('player', player);
                this.registry.set('token', token);
                this.scene.start('PreloadScene');
            })
            .catch(() => {
                localStorage.removeItem('twt_token');
                this.scene.start('LoginScene');
            });
        } else {
            this.scene.start('LoginScene');
        }
    }
}
