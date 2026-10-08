/**
 * SOCIAL CLUB SCENE
 * Friends list, pending requests, online status, VS challenge, chat.
 */

import { SocketClient } from '../network/SocketClient.js';
import { apiFetch } from '../utils/Platform.js';
import { VIEW_H } from '../utils/Layout.js';

const W = 844;
const H = 390;

export class SocialScene extends Phaser.Scene {
    constructor() {
        super('SocialScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.6);

        this.add.text(W / 2, 36, 'SOCIAL CLUB', {
            fontSize: '22px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);

        this._buildAddFriendInput();
        this._buildFriendsList();

        this._makeBtn(W / 2, H - 45, '← BACK', () => this.scene.start('MainMenuScene'), 0x333355);

        // Listen for incoming challenges while on this screen
        SocketClient.on('challenge:received', ({ fromPlayerId, fromUsername }) => {
            this._showChallengePopup(fromPlayerId, fromUsername);
        });

        // Listen for incoming chat messages
        SocketClient.on('chat:message', (msg) => {
            if (this._activeChatId === msg.fromPlayerId) {
                this._appendChatMessage(msg.body, false);
            }
        });
    }

    _buildAddFriendInput() {
        const inputDom = this.add.dom(W / 2, 80).createFromHTML(
            `<input type="text" placeholder="Search username to add..." style="
                width:240px;padding:8px;border-radius:6px;border:none;
                font-size:13px;background:#1a1a2e;color:#fff;border:1px solid #4cc9f0;
            ">`
        );

        this._makeBtn(340, 80, '+', () => {
            const username = inputDom.node.querySelector('input').value.trim();
            if (!username) return;
            apiFetch('/api/social/friends/request', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify({ targetUsername: username }),
            })
            .then(r => r.json())
            .then(d => {
                this._toast(d.success ? 'Friend request sent!' : d.error);
            });
        }, 0x2d6a4f);
    }

    _buildFriendsList() {
        apiFetch('/api/social/friends')
        .then(r => r.json())
        .then(friends => this._renderFriends(friends));
    }

    _renderFriends(friends) {
        this.add.text(14, 110, 'FRIENDS', {
            fontSize: '10px', color: '#888888',
        });

        if (!friends.length) {
            this.add.text(W / 2, 160, 'No friends yet. Add some!', {
                fontSize: '12px', color: '#555555',
            }).setOrigin(0.5);
            return;
        }

        friends.forEach((f, i) => {
            const y = 135 + i * 68;
            const isPending = f.status === 'pending';

            // Row background
            this.add.rectangle(W / 2, y, W - 20, 58, 0x1a1a2e)
                .setStrokeStyle(1, isPending ? 0xf4d35e : 0x333355);

            // Online indicator
            this.add.circle(28, y - 10, 5, f.is_online ? 0x2d6a4f : 0x555555);

            // Name + level
            this.add.text(42, y - 14, f.friend_username, {
                fontSize: '13px', fontFamily: 'Arial Black', color: '#ffffff',
            });
            this.add.text(42, y + 4, isPending ? '(Pending)' : `Lv.${f.level}`, {
                fontSize: '10px', color: isPending ? '#f4d35e' : '#888888',
            });

            // Action buttons
            if (isPending) {
                this._makeBtn(330, y, '✓', () => {
                    apiFetch(`/api/social/friends/${f.friendship_id}/accept`, {
                        method: 'PATCH',
                    }).then(() => this.scene.restart());
                }, 0x2d6a4f);
            } else {
                // VS Challenge
                this._makeBtn(300, y - 10, '⚔', () => {
                    SocketClient.emit('challenge:send', { targetPlayerId: f.friend_id });
                    this._toast(`Challenge sent to ${f.friend_username}!`);
                }, 0xe63946);

                // Chat
                this._makeBtn(345, y - 10, '💬', () => {
                    this._openChat(f.friend_id, f.friend_username);
                }, 0x457b9d);
            }
        });
    }

    _showChallengePopup(fromPlayerId, fromUsername) {
        const overlay = this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000)
            .setAlpha(0.75).setDepth(90).setInteractive();

        this.add.text(W / 2, H / 2 - 60, `⚔ CHALLENGE from\n${fromUsername}`, {
            fontSize: '18px', fontFamily: 'Arial Black', color: '#f4d35e',
            align: 'center',
        }).setOrigin(0.5).setDepth(91);

        this._makeBtn(W / 2 - 60, H / 2 + 40, 'ACCEPT', () => {
            overlay.destroy();
            SocketClient.emit('challenge:accept', { fromPlayerId });
        }, 0x2d6a4f);

        this._makeBtn(W / 2 + 60, H / 2 + 40, 'DECLINE', () => {
            overlay.destroy();
        }, 0xe63946);
    }

    _openChat(friendId, friendName) {
        this._activeChatId = friendId;

        // Fetch history
        apiFetch(`/api/social/messages/${friendId}`)
        .then(r => r.json())
        .then(msgs => this._buildChatUI(friendId, friendName, msgs));
    }

    _buildChatUI(friendId, friendName, history) {
        // Slide-up chat panel
        const panel = this.add.container(0, H).setDepth(95);

        const bg = this.add.rectangle(W / 2, -H / 2, W, VIEW_H, 0x111122)
            .setStrokeStyle(2, 0x4cc9f0);
        panel.add(bg);

        this.add.text(W / 2, -H + 40, `Chat — ${friendName}`, {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5);

        this._chatLines = [];
        this._chatPanel = panel;

        // History
        history.forEach(m => this._appendChatMessage(m.body, m.sender_id !== friendId));

        // Input
        const inputDom = this.add.dom(W / 2, -45).createFromHTML(
            `<input type="text" placeholder="Message..." style="
                width:260px;padding:8px;background:#1a1a2e;color:#fff;
                border:1px solid #4cc9f0;border-radius:6px;font-size:13px;
            ">`
        );
        panel.add(inputDom);

        this._makeBtn(350, -45, '▶', () => {
            const body = inputDom.getChildByType('input').value.trim();
            if (!body) return;
            SocketClient.emit('chat:message', { toPlayerId: friendId, body });
            this._appendChatMessage(body, true);
            inputDom.getChildByType('input').value = '';
        }, 0x4cc9f0);

        this._makeBtn(30, -H + 40, '✕', () => {
            panel.destroy();
            this._activeChatId = null;
        }, 0x333355);

        this.tweens.add({ targets: panel, y: 0, duration: 350, ease: 'Power3' });
    }

    _appendChatMessage(body, isMine) {
        const y = -H + 90 + this._chatLines.length * 28;
        const x = isMine ? W - 20 : 20;
        const t = this.add.text(x, y, body, {
            fontSize: '11px', color: isMine ? '#4cc9f0' : '#ffffff',
            wordWrap: { width: 240 },
            align:    isMine ? 'right' : 'left',
        }).setOrigin(isMine ? 1 : 0, 0);
        this._chatPanel?.add(t);
        this._chatLines.push(t);
    }

    _toast(msg, color = '#4cc9f0') {
        const t = this.add.text(W / 2, H - 80, msg, {
            fontSize: '12px', color, backgroundColor: '#000',
            padding: { x: 8, y: 5 },
        }).setOrigin(0.5).setDepth(50);
        this.tweens.add({ targets: t, alpha: 0, delay: 2000, duration: 400,
            onComplete: () => t.destroy() });
    }

    _makeBtn(x, y, label, cb, color) {
        const w   = label.length > 2 ? 100 : 36;
        const btn = this.add.rectangle(x, y, w, 32, color)
            .setStrokeStyle(1, 0xffffff).setInteractive().setOrigin(0.5);
        this.add.text(x, y, label, {
            fontSize: '11px', fontFamily: 'Arial Black', color: '#fff',
        }).setOrigin(0.5);
        btn.on('pointerup', cb);
    }

    shutdown() {
        SocketClient.off('challenge:received');
        SocketClient.off('chat:message');
        this._activeChatId = null;
    }
}
