import { apiFetch } from '../utils/Platform.js';
const W = 844;
const H = 390;

export class LoginScene extends Phaser.Scene {
    constructor() { super('LoginScene'); }

    preload() {
        this.load.image('menu_background', 'assets/menu_background.png');
        this.load.video('menu_background_video', 'assets/menu_new_loop.mp4', true);
    }

    create() {
        this._mode = 'login';

        if (!this.scene.isActive('VideoBackgroundScene')) {
            this.scene.launch('VideoBackgroundScene');
            this.scene.sendToBack('VideoBackgroundScene');
        }

        // Dark panel (right-side form area)
        this.add.rectangle(W * 0.65, H / 2, W * 0.46, H, 0x0d0d1a).setAlpha(0.85);

        // ── Left: Title logo ──────────────────────────────────────────────────
        if (this.textures.exists('title_alleyway')) {
            this.add.image(W * 0.22, H / 2 - 10, 'title_alleyway').setDisplaySize(260, 142).setOrigin(0.5);
        }

        // ── Right: Form ───────────────────────────────────────────────────────
        const formX = W * 0.65;

        const emailDom = this._makeInput(formX, H / 2 - 100, 'email',    'Email',                    'email',            '#4cc9f0');
        const passDom  = this._makeInput(formX, H / 2 - 52,  'password', 'Password',                 'current-password', '#4cc9f0');
        const userDom  = this._makeInput(formX, H / 2 + 0,   'text',     'Username (register only)', 'username',         '#555577');
        this._emailEl = emailDom.node;  this._emailDom = emailDom;
        this._passEl  = passDom.node;   this._passDom  = passDom;
        this._userEl  = userDom.node;   this._userDom  = userDom;
        this._userEl.disabled    = true;
        this._userDom.setVisible(false);

        // Prefill with the last email that successfully reached the login form
        try {
            const remembered = localStorage.getItem('twt_last_email');
            if (remembered) this._emailEl.value = remembered;
        } catch {}

        // Show/hide password toggle (small "eye" icon overlaid on the password input)
        this._eyeBtn = this.add.text(formX + 110, H / 2 - 52, '👁', {
            fontSize: '14px', color: '#9ddcff',
        }).setOrigin(0.5).setDepth(5).setInteractive({ useHandCursor: true });
        this._eyeBtn.on('pointerup', () => {
            const showing = this._passEl.type === 'text';
            this._passEl.type = showing ? 'password' : 'text';
            this._eyeBtn.setAlpha(showing ? 1 : 0.6);
        });

        // Submit on Enter from any input field
        const onKey = (e) => { if (e.key === 'Enter') this._submit(); };
        this._emailEl.addEventListener('keydown', onKey);
        this._passEl.addEventListener('keydown',  onKey);
        this._userEl.addEventListener('keydown',  onKey);

        this._errText = this.add.text(formX, H / 2 + 36, '', {
            fontSize: '11px', fontFamily: 'Arial', color: '#e63946',
        }).setOrigin(0.5);

        this._actionBtn     = this._makeBtn(formX, H / 2 + 66, 'LOGIN', 0xe63946, () => this._submit());
        this._toggleText    = this.add.text(formX, H / 2 + 100, "No account?  REGISTER", {
            fontSize: '11px', fontFamily: 'Arial', color: '#4cc9f0',
        }).setOrigin(0.5).setInteractive({ useHandCursor: true });
        this._toggleText.on('pointerdown', () => this._toggleMode());
    }

    _toggleMode() {
        this._mode = this._mode === 'login' ? 'register' : 'login';
        this._errText.setText('');
        this._updateMode();
    }

    _updateMode() {
        const isReg = this._mode === 'register';
        this._userEl.disabled          = !isReg;
        this._userEl.style.borderColor = isReg ? '#4cc9f0' : '#555577';
        // Username is only needed to register — hide it entirely on the login form
        this._userDom.setVisible(isReg);
        if (this._actionBtnText) this._actionBtnText.setText(isReg ? 'REGISTER' : 'LOGIN');
        this._toggleText.setText(isReg ? 'Have an account?  LOGIN' : 'No account?  REGISTER');
    }

    _makeInput(x, y, type, placeholder, autocomplete, borderColor) {
        const el = document.createElement('input');
        el.type         = type;
        el.placeholder  = placeholder;
        el.autocomplete = autocomplete;
        el.style.cssText = `
            width:240px;padding:8px 10px;border-radius:6px;font-size:13px;
            background:#1a1a2e;color:#fff;border:1px solid ${borderColor};
            outline:none;box-sizing:border-box;
        `;
        return this.add.dom(x, y, el);
    }

    _makeBtn(x, y, label, color, cb) {
        const btn = this.add.rectangle(x, y, 240, 40, color)
            .setStrokeStyle(2, 0xffffff)
            .setInteractive({ useHandCursor: true })
            .setOrigin(0.5);

        this._actionBtnText = this.add.text(x, y, label, {
            fontSize: '14px', fontFamily: 'Arial Black', color: '#ffffff',
        }).setOrigin(0.5);

        btn.on('pointerdown', () => btn.setFillStyle(0xffffff));
        btn.on('pointerup',   () => { btn.setFillStyle(color); cb(); });
        btn.on('pointerout',  () => btn.setFillStyle(color));
        return btn;
    }

    _submit() {
        const email    = this._emailEl.value.trim();
        const password = this._passEl.value;
        const username = this._userEl.value.trim();

        if (!email || !password) { this._errText.setText('Email and password required.'); return; }

        const isReg    = this._mode === 'register';
        const endpoint = isReg ? '/api/auth/register' : '/api/auth/login';
        const body     = isReg ? { email, password, username } : { email, password };

        this._errText.setText('');
        this._actionBtnText?.setText('...');

        apiFetch(endpoint, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        })
        .then(r => r.json().then(d => ({ ok: r.ok, data: d })))
        .then(({ ok, data }) => {
            if (!ok) { this._errText.setText(data.error || 'Error'); this._updateMode(); return; }
            if (isReg && data.pending) {
                // Server sent a verification email — switch to the login form
                // now (email kept, password cleared) and show the notice on top.
                try { localStorage.setItem('twt_last_email', email); } catch {}
                this._mode = 'login';
                this._passEl.value = '';
                this._userEl.value = '';
                this._updateMode();
                this._showVerificationSent();
                return;
            }
            try { localStorage.setItem('twt_last_email', email); } catch {}
            localStorage.setItem('twt_token', data.token);
            this.registry.set('player', data.player);
            this.registry.set('token',  data.token);
            this.scene.start('PreloadScene');
        })
        .catch(() => { this._errText.setText('Network error.'); this._updateMode(); });
    }

    _showVerificationSent() {
        const W = 844, H = 390;
        const objs = [];
        const reg  = o => { objs.push(o); return o; };
        // Hide the HTML input fields while the modal is up — Phaser's DOM
        // layer sits above the canvas, so we have to hide the DOMElement
        // game objects themselves (and the toggle text), not just style them.
        const domWrappers = [this._emailDom, this._passDom, this._userDom].filter(Boolean);
        domWrappers.forEach(d => d.setVisible(false));
        const prevToggleVisible = this._toggleText?.visible;
        this._toggleText?.setVisible(false);
        const close = () => {
            objs.forEach(o => o?.destroy?.());
            domWrappers.forEach(d => d.setVisible(true));
            if (prevToggleVisible !== undefined) this._toggleText?.setVisible(prevToggleVisible);
            this._updateMode();   // re-hides the username box when on the login form
        };

        // Backdrop blocks all input below
        reg(this.add.rectangle(W / 2, H / 2, W, H, 0x000000, 0.78)
            .setDepth(900).setInteractive());

        reg(this.add.rectangle(W / 2, H / 2, 480, 200, 0x101030, 0.98)
            .setStrokeStyle(2, 0x4cc9f0).setDepth(901));

        reg(this.add.text(W / 2, H / 2 - 56, 'EMAIL VERIFICATION SENT', {
            fontSize: '16px', fontFamily: 'Arial Black', color: '#4cc9f0',
        }).setOrigin(0.5).setDepth(902));

        reg(this.add.text(W / 2, H / 2 - 12,
            'Please check your inbox to confirm your account.\nYou won\'t be able to log in until your email is verified.',
            { fontSize: '11px', color: '#cccccc', align: 'center', wordWrap: { width: 440 } }
        ).setOrigin(0.5).setDepth(902));

        const bx = W / 2, by = H / 2 + 56;
        const btn = reg(this.add.rectangle(bx, by, 140, 32, 0x222244)
            .setStrokeStyle(2, 0x4cc9f0).setDepth(902).setInteractive({ useHandCursor: true }));
        reg(this.add.text(bx, by, 'CLOSE', {
            fontSize: '12px', fontFamily: 'Arial Black', color: '#9ddcff',
        }).setOrigin(0.5).setDepth(903));

        btn.on('pointerdown', () => btn.setAlpha(0.7));
        btn.on('pointerout',  () => btn.setAlpha(1));
        btn.on('pointerup',   () => { btn.setAlpha(1); close(); });
    }
}
