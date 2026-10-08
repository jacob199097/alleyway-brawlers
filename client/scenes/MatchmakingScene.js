import { SocketClient } from '../network/SocketClient.js';

const W = 844;
const H = 390;

export class MatchmakingScene extends Phaser.Scene {
    constructor() { super('MatchmakingScene'); }

    create() {
        this.add.rectangle(W / 2, H / 2, W, H, 0x000000).setAlpha(0.6);

        this._statusText = this.add.text(W / 2, H / 2 - 50, 'Connecting...', {
            fontSize: '22px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5);

        this._subText = this.add.text(W / 2, H / 2 + 4, '', {
            fontSize: '13px', color: '#888888',
        }).setOrigin(0.5);

        this._dots = 0;
        this.time.addEvent({ delay: 500, loop: true, callback: () => {
            this._dots = (this._dots + 1) % 4;
            this._subText.setText('Searching' + '.'.repeat(this._dots));
        }});

        this._makeBtn(W / 2 - 110, H / 2 + 80, 'CANCEL', () => {
            SocketClient.emit('queue:leave');
            this.scene.start('MainMenuScene');
        }, 0x333355);

        this._makeBtn(W / 2 + 110, H / 2 + 80, '🤖 VS CPU', () => {
            this.scene.start('DuelScene', {});
        }, 0x444466);

        const token = this.registry.get('token');
        SocketClient.connect(token);
        SocketClient.on('queue:joined', ({ position }) => {
            this._statusText.setText('In Queue');
            this._subText.setText(`Position: ${position} — Searching...`);
        });
        SocketClient.on('queue:error', ({ message }) => this._statusText.setText(message));
        SocketClient.on('match:found', data => this._onMatchFound(data));
        SocketClient.emit('queue:join');
    }

    _onMatchFound(matchData) {
        this._statusText.setText('MATCH FOUND!');
        this._subText.setText(`vs ${matchData.opponentName}`);

        this.time.delayedCall(1200, () => {
            const token = this.registry.get('token');
            fetch('/api/deck?active=true', { headers: { Authorization: `Bearer ${token}` } })
                .then(r => r.json())
                .then(decks => {
                    const active = decks.find(d => d.is_active) || decks[0];
                    if (active) return fetch(`/api/deck/${active.id}`, { headers: { Authorization: `Bearer ${token}` } }).then(r => r.json());
                    return null;
                })
                .then(deckData => {
                    const cards = deckData?.cards
                        ? Phaser.Utils.Array.Shuffle(deckData.cards.flatMap(c => Array(c.copies).fill(c)))
                        : [];
                    this.scene.start('MultiplayerDuelScene', { ...matchData, playerDeck: cards });
                });
        });
    }

    _makeBtn(x, y, label, cb, color = 0xe63946) {
        const btn = this.add.rectangle(x, y, 180, 42, color)
            .setStrokeStyle(1, 0xffffff).setInteractive().setOrigin(0.5);
        this.add.text(x, y, label, {
            fontSize: '13px', fontFamily: 'Arial Black', color: '#fff',
        }).setOrigin(0.5);
        btn.on('pointerup', cb);
        return btn;
    }

    shutdown() {
        SocketClient.off('queue:joined');
        SocketClient.off('queue:error');
        SocketClient.off('match:found');
    }
}
