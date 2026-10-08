import { apiFetch } from '../utils/Platform.js';
import { VIEW_H } from '../utils/Layout.js';
/**
 * Mailbox — system messages, rewards, news.
 * Two-pane layout: list on the left, full message on the right.
 */

const W = 844;
const H = 390;

export class MailboxScene extends Phaser.Scene {
    constructor() {
        super('MailboxScene');
        this.fullLayout = 'center';   // 390-tall design centred in the 16:9 view (utils/Layout.js)
    }

    create() {
        this.add.rectangle(W / 2, H / 2, W, VIEW_H, 0x000000).setAlpha(0.7);

        this.add.text(W / 2, 22, 'MAILBOX', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#f4d35e',
        }).setOrigin(0.5);

        // Left column — message list
        const listX  = 12;
        const listY  = 50;
        const listW  = 320;
        const listH  = H - listY - 60;
        this.add.rectangle(listX + listW / 2, listY + listH / 2, listW, listH, 0x101030, 0.95)
            .setStrokeStyle(2, 0x4cc9f0, 0.6);

        // Right column — message body
        const bodyX  = listX + listW + 12;
        const bodyY  = listY;
        const bodyW  = W - bodyX - 12;
        const bodyH  = listH;
        this.add.rectangle(bodyX + bodyW / 2, bodyY + bodyH / 2, bodyW, bodyH, 0x101030, 0.95)
            .setStrokeStyle(2, 0x4cc9f0, 0.6);

        this._listX = listX; this._listY = listY; this._listW = listW; this._listH = listH;
        this._bodyX = bodyX; this._bodyY = bodyY; this._bodyW = bodyW; this._bodyH = bodyH;

        this._listObjs = [];
        this._bodyObjs = [];
        this._messages = [];

        this._buildBackButton();
        this._buildReadAllButton();
        this._loadMessages();
    }

    _buildBackButton() {
        const btn = this.add.rectangle(40, H - 22, 72, 28, 0x333355)
            .setStrokeStyle(1, 0xffffff).setInteractive({ useHandCursor: true });
        this.add.text(40, H - 22, '← BACK', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5).setDepth(1);
        btn.on('pointerup', () => this.scene.start('MainMenuScene'));
    }

    _buildReadAllButton() {
        const x = W - 80, y = H - 22;
        const btn = this.add.rectangle(x, y, 130, 28, 0x1a3a4a)
            .setStrokeStyle(1, 0x4cc9f0).setInteractive({ useHandCursor: true });
        this.add.text(x, y, 'MARK ALL READ', {
            fontSize: '9px', fontFamily: 'Arial Black', color: '#9ddcff',
        }).setOrigin(0.5).setDepth(1);
        btn.on('pointerup', () => {
            apiFetch('/api/mail/read-all', {
                method: 'POST',
            }).then(() => this._loadMessages()).catch(() => {});
        });
    }

    _loadMessages() {
        apiFetch('/api/mail')
            .then(r => r.json())
            .then(data => {
                this._messages = data.messages || [];
                this._renderList();
                if (this._messages.length) this._openMessage(this._messages[0]);
                else this._renderEmptyBody();
            })
            .catch(() => this._renderEmptyBody('Could not load mailbox.'));
    }

    _renderList() {
        this._listObjs.forEach(o => o?.destroy?.());
        this._listObjs = [];

        if (!this._messages.length) {
            const t = this.add.text(this._listX + this._listW / 2, this._listY + 20,
                'No messages.', { fontSize: '11px', color: '#888888' }).setOrigin(0.5);
            this._listObjs.push(t);
            return;
        }

        const rowH = 56;
        let y = this._listY + 6;
        this._messages.forEach(m => {
            const isUnread = !m.read_at;
            const fill = isUnread ? 0x1d2742 : 0x14141e;
            const stroke = isUnread ? 0x4cc9f0 : 0x334466;

            const bg = this.add.rectangle(this._listX + this._listW / 2, y + rowH / 2,
                this._listW - 12, rowH - 4, fill).setStrokeStyle(1, stroke)
                .setInteractive({ useHandCursor: true });

            const dot = isUnread
                ? this.add.circle(this._listX + 12, y + rowH / 2, 4, 0x4cc9f0)
                : null;

            const senderTxt = this.add.text(this._listX + 22, y + 8, m.sender || 'System', {
                fontSize: '9px', fontFamily: 'Arial Black', color: '#aaccff',
            });

            const subjTxt = this.add.text(this._listX + 22, y + 22, m.subject || '(no subject)', {
                fontSize: '11px', fontFamily: 'Arial Black',
                color: isUnread ? '#ffffff' : '#cccccc',
                wordWrap: { width: this._listW - 40 },
            });

            const dateTxt = this.add.text(this._listX + this._listW - 14, y + 8,
                this._fmtDate(m.created_at), {
                    fontSize: '8px', color: '#888899',
                }).setOrigin(1, 0);

            bg.on('pointerup', () => this._openMessage(m));
            this._listObjs.push(bg, senderTxt, subjTxt, dateTxt);
            if (dot) this._listObjs.push(dot);

            y += rowH;
        });
    }

    _openMessage(msg) {
        // Mark read on the server (idempotent) and locally
        if (!msg.read_at) {
            msg.read_at = new Date().toISOString();
            apiFetch(`/api/mail/${msg.id}/read`, {
                method: 'POST',
            }).catch(() => {});
            this._renderList();
        }

        this._bodyObjs.forEach(o => o?.destroy?.());
        this._bodyObjs = [];

        const bx = this._bodyX + 12, by = this._bodyY + 12;
        const bw = this._bodyW - 24;

        const subj = this.add.text(bx, by, msg.subject || '(no subject)', {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#f4d35e',
            wordWrap: { width: bw },
        });
        const subjBottom = by + subj.height + 4;
        const meta = this.add.text(bx, subjBottom,
            `From ${msg.sender || 'System'}  ·  ${this._fmtDate(msg.created_at, true)}`, {
                fontSize: '9px', color: '#888899',
            });

        const sep = this.add.rectangle(bx, subjBottom + meta.height + 6, bw, 1, 0x334466)
            .setOrigin(0, 0.5);

        const body = this.add.text(bx, subjBottom + meta.height + 14, msg.body || '', {
            fontSize: '11px', color: '#dddddd',
            wordWrap: { width: bw }, lineSpacing: 3,
        });

        // Delete button
        const delX = this._bodyX + this._bodyW - 60;
        const delY = this._bodyY + this._bodyH - 22;
        const delBg = this.add.rectangle(delX, delY, 100, 26, 0x3a1010)
            .setStrokeStyle(1, 0xe63946).setInteractive({ useHandCursor: true });
        const delTxt = this.add.text(delX, delY, 'DELETE', {
            fontSize: '10px', fontFamily: 'Arial Black', color: '#ffa7b0',
        }).setOrigin(0.5);
        delBg.on('pointerup', () => this._deleteMessage(msg));

        this._bodyObjs.push(subj, meta, sep, body, delBg, delTxt);
    }

    _renderEmptyBody(msg = 'Inbox empty.') {
        this._bodyObjs.forEach(o => o?.destroy?.());
        this._bodyObjs = [];
        const t = this.add.text(this._bodyX + this._bodyW / 2,
            this._bodyY + this._bodyH / 2, msg, {
                fontSize: '13px', color: '#888888', fontStyle: 'italic',
            }).setOrigin(0.5);
        this._bodyObjs.push(t);
    }

    _deleteMessage(msg) {
        apiFetch(`/api/mail/${msg.id}`, {
            method: 'DELETE',
        })
        .then(() => {
            this._messages = this._messages.filter(m => m.id !== msg.id);
            this._renderList();
            if (this._messages.length) this._openMessage(this._messages[0]);
            else this._renderEmptyBody();
        })
        .catch(() => {});
    }

    _fmtDate(iso, full = false) {
        if (!iso) return '';
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return '';
        if (full) return d.toLocaleString();
        const today = new Date();
        const sameDay = d.toDateString() === today.toDateString();
        if (sameDay) return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        return d.toLocaleDateString();
    }
}
