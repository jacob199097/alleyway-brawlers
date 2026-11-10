// AlleyWay Brawlers: what the website does in the browser (the pages come from backend/site/pages.js).
// Every page works without this file. It adds the card zoom, the screenshot viewer, the keyword
// pop-ups, the search on /cards that answers as you type, the kind chips on a clan's page, and a mark
// on the download for the visitor's own device. It stores nothing and talks to nothing but this site.
(() => {
    'use strict';

    const root = document.documentElement;
    const V = new URL(document.currentScript.src).search;   // (?v=…: the stamp the page's other files carry)
    root.classList.add('js');

    // ── The visitor's device: its download first ─────────────────────────────────────────────────
    function platform() {
        const ua = navigator.userAgent;
        if (/Android/i.test(ua)) return 'android';
        if (/iPhone|iPad|iPod/i.test(ua)) return '';
        if (/Mac/i.test(ua)) return navigator.maxTouchPoints > 1 ? '' : 'macos';   // (an iPad says it's a Mac)
        return /Win/i.test(ua) ? 'windows' : '';
    }

    const os = platform();
    for (const el of os ? document.querySelectorAll(`[data-os="${os}"]`) : []) {
        el.classList.add('mine');
        const cta = el.closest('.cta');
        if (cta && !el.classList.contains('off')) cta.classList.add('picked');
    }

    // ── A full-screen <dialog> with close / previous / next ──────────────────────────────────────
    /** `what` is "card" or "screenshot"; `step(-1 | 1)` moves. Null where the browser has no <dialog>. */
    function makeDialog(cls, what, step) {
        const dlg = document.createElement('dialog');
        if (typeof dlg.showModal !== 'function') return null;
        dlg.className = cls;
        dlg.setAttribute('aria-label', what[0].toUpperCase() + what.slice(1));
        const button = (name, text, says) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = `dlg-btn ${name}`;
            b.textContent = text;
            b.setAttribute('aria-label', says);
            dlg.append(b);
            return b;
        };
        const ui = { dlg, x: button('x', '×', 'Close'), prev: button('prev', '‹', `Previous ${what}`), next: button('next', '›', `Next ${what}`) };
        ui.x.addEventListener('click', () => dlg.close());
        ui.prev.addEventListener('click', () => step(-1));
        ui.next.addEventListener('click', () => step(1));
        dlg.addEventListener('click', (e) => e.target === dlg && dlg.close());   // (a click outside what's shown)
        dlg.addEventListener('close', () => root.classList.remove('modal'));
        dlg.addEventListener('keydown', (e) => {
            if (e.key === 'ArrowLeft') step(-1);
            if (e.key === 'ArrowRight') step(1);
        });
        document.body.append(dlg);
        return ui;
    }

    function show(ui) {
        if (ui.dlg.open) return;
        ui.dlg.showModal();
        root.classList.add('modal');
    }

    // ── The card zoom: a card in full, over the page ─────────────────────────────────────────────
    const fragments = new Map();   // card id → its HTML, being fetched or here
    let zoom = null;
    let ids = [];                  // the cards previous / next walk through
    let at = 0;

    function fragment(id) {
        if (!fragments.has(id)) {
            fragments.set(id, fetch(`/cards/${encodeURIComponent(id)}?fragment=1`).then((r) => {
                if (!r.ok) throw new Error(String(r.status));
                return r.text();
            }));
        }
        return fragments.get(id);
    }

    function showCard() {
        const id = ids[at];
        zoom.prev.disabled = at <= 0;
        zoom.next.disabled = at >= ids.length - 1;
        zoom.box.classList.add('loading');
        fragment(id).then((html) => {
            if (ids[at] !== id) return;   // (they've moved on)
            zoom.box.innerHTML = `${html}<p class="page-link"><a href="/cards/${encodeURIComponent(id)}">This card's own page</a></p>`;
            zoom.box.classList.remove('loading');
            zoom.box.scrollTop = 0;
            if (ids[at + 1]) fragment(ids[at + 1]).catch(() => {});   // (the next one, ready)
        }).catch(() => {
            fragments.delete(id);
            location.href = `/cards/${encodeURIComponent(id)}`;   // (the zoom can't get it: its page, then)
        });
    }

    function stepCard(by) {
        if (!ids[at + by]) return;
        at += by;
        showCard();
    }

    function openCard(link, e) {
        if (!zoom) {
            zoom = makeDialog('zoom', 'card', stepCard);
            if (!zoom) return;   // (the link goes to the card's page)
            zoom.box = document.createElement('div');
            zoom.box.className = 'zoom-box';
            zoom.dlg.append(zoom.box);
        }
        e.preventDefault();
        const id = link.dataset.card;
        // Previous / next walk the cards shown around the one clicked (a card in the zoom's own
        // Striver line moves within the list when it's in it)
        if (!zoom.dlg.contains(link) || !ids.includes(id)) {
            const around = link.closest('#cards, .grid, .levels, .mini-line, .word-cards, .egs') || link.parentNode;
            const seen = [...around.querySelectorAll('a.card[data-card]')].filter((a) => a.getClientRects().length);
            ids = [...new Set(seen.map((a) => a.dataset.card))];
        }
        at = Math.max(0, ids.indexOf(id));
        show(zoom);
        showCard();
    }

    // ── The screenshot viewer ────────────────────────────────────────────────────────────────────
    let viewer = null;
    let shots = [];
    let shotAt = 0;

    function showShot() {
        const a = shots[shotAt];
        const small = a.querySelector('img');
        viewer.img.src = a.href;
        viewer.img.alt = small ? small.alt : '';
        viewer.cap.textContent = a.dataset.caption || '';
        viewer.prev.disabled = shotAt <= 0;
        viewer.next.disabled = shotAt >= shots.length - 1;
    }

    function stepShot(by) {
        if (!shots[shotAt + by]) return;
        shotAt += by;
        showShot();
    }

    function openShot(link, e) {
        if (!viewer) {
            viewer = makeDialog('viewer', 'screenshot', stepShot);
            if (!viewer) return;   // (the link opens the picture itself)
            const figure = document.createElement('figure');
            viewer.img = document.createElement('img');
            viewer.cap = document.createElement('figcaption');
            figure.append(viewer.img, viewer.cap);
            viewer.dlg.append(figure);
        }
        e.preventDefault();
        // (every screenshot on the page, each once)
        const byHref = new Map([...document.querySelectorAll('a[data-shot]')].reverse().map((a) => [a.href, a]));
        shots = [...byHref.values()].reverse();
        shotAt = Math.max(0, shots.findIndex((a) => a.href === link.href));
        show(viewer);
        showShot();
    }

    // ── Keyword pop-ups: what a coloured word on a card means ────────────────────────────────────
    let words = null;     // /site/keywords.json, once it's been asked for
    let tip = null;
    let tipFor = null;

    /** The keyword under `target`, or null (not where the meaning is already written beside it). */
    function keywordAt(target) {
        const el = target.closest ? target.closest('.kw[data-kw]') : null;
        return el && !el.closest('.word, .words') ? el : null;
    }

    function showTip(el) {
        if (tipFor === el) return;
        tipFor = el;
        words = words || fetch(`/site/keywords.json${V}`).then((r) => r.json()).catch(() => ({}));
        words.then((all) => {
            const word = all[el.dataset.kw];
            if (!word || tipFor !== el) return;
            if (!tip) {
                tip = document.createElement('div');
                tip.className = 'tip';
                tip.setAttribute('role', 'tooltip');
            }
            const name = document.createElement('b');
            name.textContent = word.name;
            name.style.color = el.style.color;
            tip.replaceChildren(name, word.text);   // (the text starts " X: …" or ": …", as it follows the name)
            (document.querySelector('dialog[open]') || document.body).append(tip);   // (over the zoom, when it's open)
            // Over the word (the rest of the sentence stays readable), or under it when there's no room; never off the side
            const r = el.getBoundingClientRect();
            const t = tip.getBoundingClientRect();
            const left = Math.min(Math.max(8, r.left + r.width / 2 - t.width / 2), root.clientWidth - t.width - 8);
            const top = r.top - t.height - 8 < 8 ? r.bottom + 8 : r.top - t.height - 8;
            tip.style.left = `${Math.max(8, left)}px`;
            tip.style.top = `${Math.max(8, top)}px`;
        });
    }

    function hideTip() {
        tipFor = null;
        if (tip) tip.remove();
    }

    document.addEventListener('mouseover', (e) => {
        const el = keywordAt(e.target);
        if (el) showTip(el);
    });
    document.addEventListener('mouseout', (e) => keywordAt(e.target) && hideTip());
    addEventListener('scroll', hideTip, { passive: true, capture: true });

    // ── Clicks: a card, a screenshot, a keyword (a tap, on a phone) ──────────────────────────────
    document.addEventListener('click', (e) => {
        const word = keywordAt(e.target);
        if (word) showTip(word);
        else hideTip();
        if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;   // (a new tab, say)
        const card = e.target.closest('a.card[data-card]');
        if (card) return openCard(card, e);
        const shot = e.target.closest('a[data-shot]');
        if (shot) openShot(shot, e);
    });

    // ── /cards: the cards change as you type (the same test as passes() in pages.js) ─────────────
    const form = document.getElementById('filters');
    const grid = document.getElementById('grid');
    if (form && grid) {
        const tiles = [...grid.querySelectorAll('a.card')];
        const tally = document.getElementById('tally');
        const empty = document.getElementById('empty');
        const fields = ['q', 'clan', 'kind', 'rarity'];
        const apply = () => {
            const f = Object.fromEntries(fields.map((name) => [name, form.elements[name].value.trim()]));
            const wanted = f.q.toLowerCase().split(/\s+/).filter(Boolean);
            let shown = 0;
            let tokens = 0;   // (of those shown: "52 cards and 1 token" or "1 token", as cardCount() in pages.js says it)
            for (const a of tiles) {
                const d = a.dataset;
                const ok = (!f.clan || d.clan === f.clan) && (!f.kind || d.kind === f.kind) && (!f.rarity || d.rarity === f.rarity)
                    && wanted.every((w) => d.q.includes(w));
                a.hidden = !ok;
                if (ok) shown++;
                if (ok && 'token' in d) tokens++;
            }
            const says = (n, one) => `${n} ${n === 1 ? one : `${one}s`}`;
            tally.textContent = [shown > tokens || !tokens ? says(shown - tokens, 'card') : '', tokens ? says(tokens, 'token') : ''].filter(Boolean).join(' and ');
            empty.hidden = shown > 0;
            // (the address keeps up, so a search can be sent to someone or come back to)
            const query = new URLSearchParams(fields.filter((name) => f[name]).map((name) => [name, f[name]])).toString();
            history.replaceState(null, '', location.pathname + (query ? `?${query}` : ''));
        };
        form.addEventListener('input', apply);
        form.addEventListener('submit', (e) => {
            e.preventDefault();
            apply();
        });
    }

    // ── A clan's page: the chips show one kind of card at a time ─────────────────────────────────
    for (const bar of document.querySelectorAll('.chipbar')) {
        bar.addEventListener('click', (e) => {
            const chip = e.target.closest('a[data-filter]');
            if (!chip) return;
            e.preventDefault();
            const want = chip.dataset.filter;
            const groups = [...document.querySelectorAll('section.group[data-group]')];
            for (const g of groups) g.hidden = !!want && g.dataset.group !== want;
            for (const a of bar.querySelectorAll('a')) a.classList.toggle('on', a === chip);
            // (a chip half off the side of a phone's screen comes in)
            const box = bar.getBoundingClientRect();
            const at = chip.getBoundingClientRect();
            bar.scrollLeft += Math.min(0, at.left - box.left - 16) + Math.max(0, at.right - box.right + 16);
            // (the page just got shorter: keep the cards in view, under the bar)
            const first = groups.find((g) => !g.hidden);
            if (first && first.getBoundingClientRect().top < bar.getBoundingClientRect().bottom) first.scrollIntoView({ block: 'start' });
        });
    }

    // ── How to play: the contents list shows where you are ───────────────────────────────────────
    const toc = document.querySelector('.toc');
    if (toc && 'IntersectionObserver' in window) {
        const links = new Map([...toc.querySelectorAll('a[href^="#"]')].map((a) => [a.hash.slice(1), a]));
        const watch = new IntersectionObserver((entries) => {
            for (const entry of entries) {
                if (!entry.isIntersecting) continue;
                for (const a of links.values()) a.classList.toggle('on', a === links.get(entry.target.id));
            }
        }, { rootMargin: '-20% 0px -70% 0px' });   // (the part crossing a band near the top of the screen)
        for (const id of links.keys()) {
            const part = document.getElementById(id);
            if (part) watch.observe(part);
        }
    }
})();
