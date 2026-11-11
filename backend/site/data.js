'use strict';

/**
 * WHAT THE WEBSITE SHOWS
 *
 * Everything on the website comes from the game's own files, read once when the server starts
 * (restart after `git pull`, as for the card catalogue), so the site can't drift from the game:
 *
 *   cards, clans, Striver lines     shared/cards.js, shared/clans.js
 *   How to Play and the card terms  godot/scripts/ui/how_to_play.gd (SECTIONS, TERMS)
 *   keywords and their colours      godot/scripts/keywords.gd (LIST, PHRASES, ALIASES, ENDINGS, STATUS_HELP)
 *   rarity names and colours        godot/scripts/ui/ui.gd (RARITY_LABEL, RARITY_COLOR)
 *   patch notes                     godot/data/patch_notes.json
 *   screenshots                     website/shots/shots.json (written by tools/site_shots.mjs)
 *
 *   load()   → { cards, byId, clans, clanById, lines, howto, keywords, rarities, news, shots, groups, markup, total }
 *
 * The keyword colouring is the game's (keywords.gd _tag / markup), written again for HTML.
 */

const fs   = require('fs');
const path = require('path');
const { gdConst } = require('./gd');

const ROOT = path.join(__dirname, '../..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const slug = (s) => String(s).toLowerCase().replace(/&/g, 'and').replace(/'/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// The kinds of card, in the order the site lists them: [group, plural, singular]
const GROUPS = [
    ['leader', 'Leaders', 'Leader'], ['striver', 'Strivers', 'Striver'], ['brawler', 'Brawlers', 'Brawler'],
    ['heavy', 'Heavies', 'Heavy'], ['hustle', 'Hustles', 'Hustle'], ['ambush', 'Ambushes', 'Ambush'],
];
const ORDER = Object.fromEntries(GROUPS.map(([g], i) => [g, i]));

/** A colour made readable as text on the dark page (Underworld's purple is nearly black). */
function ink(hex) {
    const n = parseInt(String(hex).replace('#', ''), 16);
    let rgb = [n >> 16, (n >> 8) & 255, n & 255];
    const light = () => 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
    for (let i = 0; i < 12 && light() < 125; i++) rgb = rgb.map((v) => Math.round(v + (255 - v) * 0.16));
    return '#' + rgb.map((v) => v.toString(16).padStart(2, '0')).join('');
}

// ── Keywords (godot/scripts/keywords.gd) ─────────────────────────────────────────────────────────
function keywordTools(src, clanInk) {
    const LIST = gdConst(src, 'LIST');             // KEYWORD → [colour, what it does]
    const PHRASES = gdConst(src, 'PHRASES');       // LOADED → [DICE]
    const PHRASE_ONLY = gdConst(src, 'PHRASE_ONLY');
    const STATUS = gdConst(src, 'STATUS_HELP');
    const ALIASES = gdConst(src, 'ALIASES');
    const ENDINGS = gdConst(src, 'ENDINGS');

    /** The keyword a word belongs to ("STUNNED" → "STUN"), or "". */
    const lookup = (word) => {
        const w = word.toUpperCase().replace(/'S$/, '');
        if (LIST[w]) return w;
        if (ALIASES[w]) return ALIASES[w];
        for (const [end, add] of ENDINGS) {
            if (!w.endsWith(end)) continue;
            const base = w.slice(0, w.length - end.length) + add;
            if (LIST[base]) return base;
        }
        return '';
    };
    const find = (word) => {
        const k = lookup(word);
        return PHRASE_ONLY.includes(k) ? '' : k;
    };

    /** The words of a text and the keyword each belongs to: a keyword starts with a capital, and every
     *  word of a multi-word one ("LOADED DICE") is tagged with it. */
    const tag = (text) => {
        const words = [...text.matchAll(/[A-Za-z']+/g)];
        const tags = words.map(() => '');
        let i = 0;
        while (i < words.length) {
            const word = words[i][0];
            const up = word.toUpperCase();
            const capital = word[0] === up[0];
            if (capital && PHRASES[up]) {
                const rest = PHRASES[up];
                const whole = rest.every((r, k) => {
                    const j = i + 1 + k;
                    return j < words.length && words[j][0].toUpperCase() === r
                        && text.slice(words[j - 1].index + words[j - 1][0].length, words[j].index).trim() === '';
                });
                if (whole) {
                    for (let k = 0; k <= rest.length; k++) tags[i + k] = up;
                    i += rest.length + 1;
                    continue;
                }
            }
            if (capital) tags[i] = find(word);
            i++;
        }
        return [words, tags];
    };

    /** The keywords in a text, each once, in order. */
    const found = (text) => [...new Set(tag(String(text || ''))[1].filter(Boolean))];

    /** Text as HTML with every keyword in its colour (the pop-up comes from site.js), and clan names in
     *  capitals in their clan's colour. */
    const markup = (text) => {
        text = String(text || '');
        const [words, tags] = tag(text);
        let out = '';
        let at = 0;
        words.forEach((m, i) => {
            const word = m[0];
            out += esc(text.slice(at, m.index));
            if (tags[i]) out += `<b class="kw" style="color:${ink(LIST[tags[i]][0])}" data-kw="${tags[i]}">${esc(word)}</b>`;
            else if (word === word.toUpperCase() && clanInk[word]) out += `<b style="color:${clanInk[word]}">${esc(word)}</b>`;
            else out += esc(word);
            at = m.index + word.length;
        });
        return out + esc(text.slice(at));
    };

    const fullName = (kw) => kw + (PHRASES[kw] ? ' ' + PHRASES[kw].join(' ') : '');

    return { LIST, STATUS, found, markup, fullName };
}

/** The game's BBCode text ([b] only, \n for line breaks) as HTML paragraphs, keywords coloured. */
function bbcode(text, markup) {
    const inline = String(text).split(/(\[\/?b\])/).map((part) => part === '[b]' ? '<b>' : part === '[/b]' ? '</b>' : markup(part)).join('');
    return inline.split(/\n{2,}/).map((p) => `<p>${p.replace(/\n/g, '<br>')}</p>`).join('');
}

// ── Cards ────────────────────────────────────────────────────────────────────────────────────────
function cardView(c, rarities) {
    const character = c.cardType === 'gang_member' || c.cardType === 'leader';
    const group = c.cardType === 'leader' ? 'leader' : c.cardType === 'gang_member' ? (ORDER[c.subtype] != null ? c.subtype : 'brawler') : c.cardType;
    const level = Number(c.level || 1);
    const kind = [];
    if (c.cardType === 'leader') kind.push('Leader');
    else if (c.cardType === 'gang_member') kind.push('Character', GROUPS[ORDER[group]][2]);
    else kind.push(GROUPS[ORDER[group]][2], ...(c.subtype ? [c.subtype[0].toUpperCase() + c.subtype.slice(1)] : []));
    if (group === 'striver') kind.push(`Level ${level}`);
    if (c.token) kind.push('Token');
    const rarity = Number(c.rarity || 1);
    return {
        id: c.id,
        name: String(c.name || '').trim(),
        clan: c.clan,
        clanName: c.clanName || c.clan,
        group,
        kind,
        character,
        level,
        authority: Number(c.authority || 0),
        attack: character ? Number(c.attack || 0) : null,
        defense: character ? Number(c.defense || 0) : null,
        influence: c.cardType === 'leader' ? Number(c.influence || 0) : null,
        sacrifice: group === 'heavy' ? Number(c.tributeCost || 0) : 0,
        rarity,
        rarityName: (rarities[rarity] || rarities[1]).name,
        text: String(c.effectText || '').trim(),
        flavour: String(c.flavourText || '').trim(),
        code: c.code || '',
        token: !!c.token,
        promotesTo: c.promotesTo || null,
        line: null,       // a Striver: its line (below)
        promote: '',      // ... and what promotes it to the next level (its own text's PROMOTE lines)
        raw: c,           // the catalogue entry (effects, for the How to Play examples)
    };
}

// ── How to Play (godot/scripts/ui/how_to_play.gd), with the game's rules for its example cards ───
// (The game shows your own clan's cards first; the site takes the clans in turn, page by page.)
const effects = (c) => (Array.isArray(c.raw.effects) ? c.raw.effects : []);
const does = (c, ...dos) => effects(c).some((e) => dos.includes(String(e.do || '')));

/** Real cards for a section: [{card, caption, turned, dim}]. */
function sectionCards(tab, pool) {
    const unit = (c) => c.raw.cardType === 'gang_member' && c.level === 1;
    const find = (ok) => pool.find(ok);
    const picks = [];
    const add = (card, caption, turned = false, dim = false) => card && picks.push({ card, caption, turned, dim });
    if (tab === 'THE GOAL' || tab === 'LEADERS') {
        pool.filter((c) => c.group === 'leader').slice(0, 2).forEach((c) => add(c, `Leader · ${c.clanName}`));
    } else if (tab === 'A TURN') {
        [1, 4, 7].forEach((want) => add(find((c) => unit(c) && c.authority === want), `Authority ${want}`));
    } else if (tab === 'CHARACTERS') {
        ['striver', 'brawler', 'heavy'].forEach((role) => add(find((c) => unit(c) && c.group === role), GROUPS[ORDER[role]][2]));
    } else if (tab === 'BRAWLS') {
        const a = find((c) => unit(c) && c.attack >= 2000);
        const d = find((c) => unit(c) && c.defense >= 2000 && c !== a);
        if (a) add(a, `In ATK · ATK ${a.attack}`);
        if (d) add(d, `In DEF · DEF ${d.defense}`, true);
    } else if (tab === 'DOWNED & KO') {
        add(find(unit), 'Downed: sideways, effects off', true, true);
    } else if (tab === 'HUSTLES & AMBUSHES') {
        add(find((c) => c.raw.cardType === 'hustle' && !c.raw.subtype), 'Hustle');
        add(find((c) => c.raw.cardType === 'ambush' && !c.raw.subtype), 'Ambush');
        add(find((c) => c.raw.subtype === 'continuous'), 'Continuous');
    } else if (tab === 'ABILITIES') {
        pool.filter((c) => effects(c).some((e) => e.when === 'activate')).slice(0, 2).forEach((c) => add(c, 'Activate'));
    }
    return picks;
}

/** Whether a card shows a card term ({do: [...]} or {on: ...}). */
function termFits(c, t) {
    switch (String(t.on || '')) {
    case 'leader': return c.group === 'leader';
    case 'heavy': return c.group === 'heavy';
    case 'striver': return c.group === 'striver' && c.level === 2;
    case 'neutral': return c.clan === 'neutral';
    case 'activate': return effects(c).some((e) => e.when === 'activate');
    case 'gutter': return effects(c).some((e) => e.when === 'gutter');
    case 'luck': return effects(c).some((e) => e.luck != null);
    case 'text': return new RegExp(String(t.re).replace(/^\(\?i\)/, ''), 'i').test(c.text);
    default: return does(c, ...(t.do || []));
    }
}

/** Up to three cards for a keyword's or term's page: the ones that do it first, then ones that only
 *  mention it; a token only when no other card has it, and one level of a Striver. fits(card): 2, 1 or 0. */
function exampleCards(pool, fits) {
    const ranked = [];
    pool.forEach((c, i) => {
        const score = fits(c);
        if (score > 0) ranked.push([score - (c.token ? 1.5 : 0), i, c]);
    });
    const names = new Set();
    return ranked.sort((a, b) => b[0] - a[0] || a[1] - b[1]).map((r) => r[2])
        .filter((c) => !names.has(c.name) && names.add(c.name)).slice(0, 3);
}

function howTo(cards, kw, markup) {
    const src = read('godot/scripts/ui/how_to_play.gd');
    // Every card by id, the clans in turn: page n starts with the n-th clan (tokens only on keyword and term pages)
    const clans = [...new Set(cards.map((c) => c.clan))].sort();
    let page = 0;
    const turn = (tokens) => {
        const first = page++ % clans.length;
        const rank = (c) => (clans.indexOf(c.clan) - first + clans.length) % clans.length;
        return cards.filter((c) => tokens || !c.token).sort((a, b) => rank(a) - rank(b) || (a.id < b.id ? -1 : 1));
    };

    const sections = gdConst(src, 'SECTIONS').map(([title, text]) => ({
        slug: slug(title), title, html: bbcode(text, markup), examples: sectionCards(title, turn(false)),
    }));

    const keywords = [];
    const seen = new Set();
    for (const [key, [color, text]] of Object.entries(kw.LIST)) {
        if (seen.has(text)) continue;   // (EXILES is EXILE)
        seen.add(text);
        const name = kw.fullName(key);
        const low = key.toLowerCase();
        keywords.push({
            key, slug: slug(name), name, color: ink(color),
            html: bbcode(text.startsWith(name) ? `[b]${name}[/b]${text.slice(name.length)}` : `[b]${name}[/b]: ${text}`, markup),
            // Its own effect (do "stasis", "give_undead") or type (Continuous, Equip), or failing that its name
            // in the card's text, not counting being immune to it
            examples: exampleCards(turn(true), (c) => (c.raw.subtype === low || does(c, low, 'give_' + low)) ? 2
                : kw.found(c.text).includes(key) && !c.text.toLowerCase().includes('immune to') ? 1 : 0),
        });
    }
    const status = (name, key, text, fits) => keywords.push({
        key, slug: slug(name), name, color: ink(kw.STATUS[key][0]), html: bbcode(text, markup), examples: exampleCards(turn(true), fits),
    });
    status('DOWNED', 'DOWNED', kw.STATUS.DOWNED[1].replace(/^DOWNED/, '[b]DOWNED[/b]'), (c) => does(c, 'down') ? 2 : 0);
    status('ZZZ', 'RESTING', '[b]ZZZ[/b]: ' + kw.STATUS.RESTING[1].replace(/^CAN'T ATTACK YET: /, ''), (c) => c.group === 'striver' && c.level === 2 ? 2 : 0);

    const terms = gdConst(src, 'TERMS').map((t) => ({
        slug: slug(t.name), name: t.name, color: ink(t.color), on: t.on || '', text: t.text,
        html: bbcode(t.text, markup), examples: exampleCards(turn(true), (c) => termFits(c, t) ? 2 : 0),
    }));

    return { sections, keywords, terms };
}

// ── Everything ───────────────────────────────────────────────────────────────────────────────────
async function build() {
    const { CARD_CATALOG } = await import('../../shared/cards.js');
    const { clanList, clanBlurb, NEUTRAL } = await import('../../shared/clans.js');

    const ui = read('godot/scripts/ui/ui.gd');
    const names = gdConst(ui, 'RARITY_LABEL');
    const colors = gdConst(ui, 'RARITY_COLOR');
    const rarities = {};   // 1..5 → {name, color}
    for (const r of Object.keys(names)) rarities[r] = { name: names[r], color: colors[r] };

    const cards = Object.values(CARD_CATALOG).filter((c) => c && c.id && c.clan).map((c) => cardView(c, rarities));
    const byId = new Map(cards.map((c) => [c.id, c]));

    // Striver lines: level 1 → 2 → 3 (promotesTo), each level knowing its line
    const lines = [];
    const later = new Set(cards.map((c) => c.promotesTo).filter(Boolean));
    for (const first of cards) {
        if (first.group !== 'striver' || later.has(first.id)) continue;
        const levels = [];
        for (let c = first; c && !levels.includes(c); c = byId.get(c.promotesTo)) levels.push(c);
        const line = { id: first.id, name: first.name, clan: first.clan, levels };
        levels.forEach((c) => {
            c.line = line;
            if (c.promotesTo) c.promote = c.text.split('\n').filter((t) => t.includes('PROMOTE this card')).join('\n');
        });
        lines.push(line);
    }

    // Listed by kind, then cost: a Striver's levels stay together
    const key = (c) => [ORDER[c.group], c.line ? c.line.levels[0].authority : c.authority, c.line ? c.line.name : c.name, c.line ? c.line.id : c.id, c.level];
    cards.sort((a, b) => {
        const [ka, kb] = [key(a), key(b)];
        for (let i = 0; i < ka.length; i++) {
            if (ka[i] !== kb[i]) return typeof ka[i] === 'number' ? ka[i] - kb[i] : String(ka[i]).localeCompare(String(kb[i]));
        }
        return 0;
    });
    lines.sort((a, b) => cards.indexOf(a.levels[0]) - cards.indexOf(b.levels[0]));

    const list = clanList();
    const clanInk = {};   // CLAN NAME → the colour its name is written in
    for (const c of list) clanInk[String(c.name).toUpperCase()] = ink(c.color);
    const kw = keywordTools(read('godot/scripts/keywords.gd'), clanInk);
    const howto = howTo(cards, kw, kw.markup);

    const clanView = (id, name, color, blurb) => {
        const own = cards.filter((c) => c.clan === id);
        const counts = {};
        for (const c of own) if (!c.token) counts[c.group] = (counts[c.group] || 0) + 1;
        return {
            id, name, color, ink: ink(color), blurb, neutral: id === NEUTRAL,
            cards: own, counts, total: own.filter((c) => !c.token).length,
            // (a clan can have more than one leader: the first made is the one its starter deck gets)
            leaders: own.filter((c) => c.group === 'leader').sort((a, b) => a.id.localeCompare(b.id)),
            get leader() { return this.leaders[0] || null; },
            lines: lines.filter((l) => l.clan === id),
        };
    };
    const clans = list.map((c) => clanView(c.id, c.name, c.color, clanBlurb(c.id)));
    const neutral = cards.find((c) => c.clan === NEUTRAL);
    if (neutral) {
        const term = howto.terms.find((t) => t.on === 'neutral');
        clans.push(clanView(NEUTRAL, neutral.clanName, neutral.raw.clanColor || '#9aa4b1', term ? term.text.replace(/\[\/?b\]/g, '') : ''));
    }
    const clanById = new Map(clans.map((c) => [c.id, c]));

    let news = [];
    try {
        news = JSON.parse(read('godot/data/patch_notes.json')).filter((n) => n && n.version && Array.isArray(n.notes));
    } catch { /* no notes: the page says so */ }

    let shots = [];
    try {
        shots = JSON.parse(read('website/shots/shots.json'));
    } catch { /* no screenshots yet (tools/site_shots.mjs makes them) */ }

    return {
        cards, byId, clans, clanById, lines, howto, rarities, news, groups: GROUPS,
        keywords: kw, markup: kw.markup,
        shots: new Map(shots.map((s) => [s.name, s])),
        total: cards.filter((c) => !c.token).length,
    };
}

let loaded = null;
/** The site's data (built on first use, then kept). */
const load = () => (loaded ||= build().catch((err) => {
    loaded = null;
    throw err;
}));

module.exports = { load, esc, slug, ink, bbcode, GROUPS };
