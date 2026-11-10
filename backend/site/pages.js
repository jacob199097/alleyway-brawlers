'use strict';

/**
 * THE WEBSITE'S PAGES
 *
 * One function per page, each returning the whole page as HTML (routes/site.js sends it). What they
 * show comes from data.js, i.e. from the game's own files; the wording around it lives here.
 * Card text is never trusted: it goes through esc() or the keyword markup (which escapes it).
 *
 *   ctx = { d        the site's data (data.js load())
 *           v        the stamp on /site/ files (they change address when they change)
 *           base     'https://<host>', for the addresses link previews need
 *           canonical  true when SITE_URL names the site's one real address
 *           latest   the game's version, e.g. '0.9.139'
 *           builds   { windows, macos, android }: each {file, version, size} or null }
 *
 *   home, clans, clan, cards, card, cardFragment, howToPlay, news, notFound, keywordsJson, sitemap
 *
 * The look is website/site.css; what happens on a click (the card zoom, the screenshot viewer, the
 * filters, the keyword pop-ups) is website/site.js. Every page works without it.
 */

const { esc, GROUPS } = require('./data');
const images = require('./images');

const GAME = 'AlleyWay Brawlers';
const TAGLINE = 'Pick a clan. Build a deck. Take the city.';
const ABOUT = 'A card game of street clans for Windows, Mac and Android. Deploy your crew, set Ambushes, '
    + 'promote your Strivers mid-fight and bring the other side\'s Morale to zero.';
// Pre-launch: docs/LAUNCH_CHECKLIST.md wipes every account at launch. Empty this then ('' = no note).
const PRELAUNCH = 'The game is in pre-launch testing: accounts and progress will be reset when it launches.';

const NAV = [['/clans', 'Clans'], ['/cards', 'Cards'], ['/how-to-play', 'How to play'], ['/news', 'News']];

// The downloads: [platform, name, address, what it runs on, how to install]
const PLATFORMS = [
    ['windows', 'Windows', '/download/windows', '64-bit Windows', [
        'Unzip the download anywhere you like.',
        'Run <b>AlleywayBrawlers.exe</b>. If Windows says it "protected your PC", choose <b>More info</b>, then <b>Run anyway</b>: the game isn\'t code-signed yet.',
    ]],
    ['macos', 'Mac', '/download/mac', 'macOS 10.13 or later, Intel and Apple Silicon', [
        'Unzip the download and drag <b>Alleyway Brawlers</b> into Applications.',
        'The first time, right-click it and choose <b>Open</b>, then <b>Open</b> again: the app isn\'t notarised by Apple yet.',
        'If macOS says it is "damaged", run <code>xattr -cr "/Applications/Alleyway Brawlers.app"</code> in Terminal and open it again.',
    ]],
    ['android', 'Android', '/download/android', 'Phones and tablets', [
        'Open the downloaded file (an APK).',
        'The first time, Android asks to allow your browser to install apps ("Install unknown apps"): allow it for that browser.',
    ]],
];

// The Ranked ladder (backend/economy/postMatch.js RANK_TIERS; emblems in assets/ranks/)
const RANKS = [['rookie', 'Rookie'], ['street_tough', 'Street Tough'], ['enforcer', 'Enforcer'], ['underboss', 'Underboss'], ['kingpin', 'Kingpin'], ['legend', 'Legend']];

// The screenshot next to a How to Play section (website/shots/, tools/site_shots.mjs)
const SECTION_SHOTS = {
    'the-goal': 'duel-casino', 'a-turn': 'duel-turn', characters: 'promote', brawls: 'duel-docks',
    'downed-and-ko': 'duel-alley', 'hustles-and-ambushes': 'duel-ambush', 'game-modes': 'fight-mode',
};

const CARD_W = 360, CARD_H = 510;   // a card's shape (1054 × 1492)

const st = (ctx, file) => `/site/${file}?v=${ctx.v}`;
const count = (n, one, many) => `${n} ${n === 1 ? one : many}`;
// "52 cards", "52 cards and 1 token" or "1 token" (a token is made by a card's effect: nobody collects it)
const cardCount = (all, tokens) => [all > tokens || !tokens ? count(all - tokens, 'card', 'cards') : '', tokens ? count(tokens, 'token', 'tokens') : '']
    .filter(Boolean).join(' and ');
const mb = (bytes) => `${Math.round(bytes / 1048576)} MB`;
const clanStyle = (clan) => (clan ? ` style="--clan:${clan.color};--clan-ink:${clan.ink}"` : '');
const kindOf = (c) => [...c.kind, c.clanName].join(' · ');
// What follows a keyword's name in its meaning: " X: at the start…", " (Nebula): frozen…", ": it switches…"
const afterName = (name, text) => (text.startsWith(name) ? text.slice(name.length) : `: ${text}`);

// ── Pieces ───────────────────────────────────────────────────────────────────────────────────────
function layout(ctx, o) {
    const title = o.title ? `${o.title} · ${GAME}` : `${GAME} · the card game of street clans`;
    const url = ctx.base + o.path;
    const image = ctx.base + (o.image || st(ctx, 'img/og.jpg'));
    const nav = NAV.map(([href, name]) => `<a href="${href}"${o.path === href || o.path.startsWith(href + '/') ? ' aria-current="page"' : ''}>${name}</a>`).join('');
    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(o.description)}">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0b0b16">
${ctx.canonical ? `<link rel="canonical" href="${esc(url)}">\n` : ''}<meta property="og:site_name" content="${GAME}">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(o.title || GAME)}">
<meta property="og:description" content="${esc(o.description)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(image)}">
<meta name="twitter:card" content="${o.image ? 'summary' : 'summary_large_image'}">
<link rel="icon" type="image/png" sizes="32x32" href="${st(ctx, 'img/icon-32.png')}">
<link rel="icon" type="image/png" sizes="192x192" href="${st(ctx, 'img/icon-192.png')}">
<link rel="apple-touch-icon" href="${st(ctx, 'img/icon-180.png')}">
<link rel="preload" href="/site/fonts/anton.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${st(ctx, 'site.css')}">
<script src="${st(ctx, 'site.js')}" defer></script>
${o.head || ''}</head>
<body${o.cls ? ` class="${o.cls}"` : ''}${clanStyle(o.clan)}>
<a class="skip" href="#main">Skip to the page</a>
<header class="top">
<div class="top-in">
<a class="brand" href="/" aria-label="${GAME}: home"><img src="${st(ctx, 'img/logo-320.webp')}" alt="${GAME}" width="320" height="174"></a>
<nav id="nav" aria-label="Site">${nav}<a class="btn small" href="/#download">Download</a></nav>
</div>
</header>
<main id="main">
${o.body}
</main>
<footer class="foot">
<div class="foot-in">
<a class="brand" href="/"><img src="${st(ctx, 'img/logo-320.webp')}" alt="${GAME}" width="320" height="174" loading="lazy"></a>
<nav aria-label="More">
<div><b>The game</b><a href="/clans">Clans</a><a href="/cards">Cards</a><a href="/how-to-play">How to play</a><a href="/news">News</a><a href="/#download">Download</a></div>
<div><b>The small print</b><a href="/privacy">Privacy policy</a><a href="/terms">Terms of service</a><a href="/delete-account">Delete your account</a>${ctx.contact ? `<a href="mailto:${esc(ctx.contact)}">Contact us</a>` : ''}</div>
</nav>
<p class="fine">© ${new Date().getFullYear()} ${GAME}. Version ${esc(ctx.latest)}. This site uses no cookies and no trackers.</p>
</div>
</footer>
</body>
</html>
`;
}

/** A card's picture as a link to its page (site.js opens the zoom instead). */
function cardLink(c, { width = 360, cls = '', attrs = '', eager = false } = {}) {
    const src = images.url('card', c.id, width);
    const pic = src
        ? `<img src="${src}" alt="${esc(c.name)} (${esc(kindOf(c))})" width="${CARD_W}" height="${CARD_H}"${eager ? '' : ' loading="lazy"'} decoding="async">`
        : `<span class="noart">${esc(c.name)}</span>`;
    return `<a class="card${cls ? ' ' + cls : ''}" href="/cards/${c.id}" data-card="${c.id}"${attrs}>${pic}</a>`;
}

/** An in-game screenshot (website/shots/), opening big on a click; '' when it hasn't been made. */
function shot(ctx, name, { cls = '', caption = true, eager = false, sizes = '(min-width: 900px) 600px, 100vw' } = {}) {
    const s = ctx.d.shots.get(name);
    if (!s) return '';
    const big = st(ctx, `shots/${s.name}.webp`);
    const small = st(ctx, `shots/${s.name}-800.webp`);
    return `<figure class="shot${cls ? ' ' + cls : ''}"><a href="${big}" data-shot data-caption="${esc(s.caption)}">`
        + `<img src="${small}" srcset="${small} 800w, ${big} ${s.w}w" sizes="${sizes}" alt="${esc(s.alt || s.caption)}" width="${s.w}" height="${s.h}"${eager ? '' : ' loading="lazy"'} decoding="async"></a>`
        + `${caption ? `<figcaption>${esc(s.caption)}</figcaption>` : ''}</figure>`;
}

function emblem(clan, width, cls = 'emblem') {
    const src = images.url('emblem', clan.id, width);
    return src ? `<img class="${cls}" src="${src}" alt="" width="${width}" height="${width}" loading="lazy" decoding="async">` : '';
}

function stats(c) {
    const rows = [['Authority', c.authority]];
    if (c.character) rows.push(['ATK', c.attack], ['DEF', c.defense]);
    if (c.influence != null) rows.push(['Influence', c.influence]);
    if (c.sacrifice) rows.push(['Sacrifice', c.sacrifice]);
    return `<dl class="stats">${rows.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join('')}</dl>`;
}

/** A card's text as paragraphs: keywords in their colours, PROMOTE in the game's colour for it. */
const textOf = (ctx, text) => String(text).split('\n').filter((l) => l.trim())
    .map((l) => `<p>${ctx.d.markup(l).replace(/\bPROMOTE[SD]?\b/g, '<b class="promo">$&</b>')}</p>`).join('');

/** What a card says about promoting. */
const promoteText = (ctx, c) => textOf(ctx, c.promote);

/** A Striver line as a timeline: level 1 → 2 → 3, what each level costs and hits for, and what
 *  takes it to the next one. */
function timeline(ctx, line, { heading = 'h3', lazy = true } = {}) {
    const levels = line.levels.map((c, i) => {
        const before = line.levels[i - 1];
        const grew = (now, was) => (before && now > was ? ` <i class="up">+${now - was}</i>` : '');
        return `<li class="level">
${cardLink(c, { eager: !lazy })}
<div class="level-info">
<p class="lvl"><b>Level ${c.level}</b><span class="stars" aria-hidden="true">${'★'.repeat(c.level)}<i>${'★'.repeat(Math.max(0, line.levels.length - c.level))}</i></span></p>
<dl class="stats small"><div><dt>Authority</dt><dd>${c.authority}</dd></div><div><dt>ATK</dt><dd>${c.attack}${grew(c.attack, before && before.attack)}</dd></div><div><dt>DEF</dt><dd>${c.defense}${grew(c.defense, before && before.defense)}</dd></div></dl>
${c.promote ? `<div class="promote">${promoteText(ctx, c)}</div>` : '<p class="promote top-level">Top level</p>'}
</div>
</li>`;
    }).join('\n');
    return `<article class="line" id="line-${line.id}">
<${heading}>${esc(line.name)}</${heading}>
<ol class="levels">
${levels}
</ol>
</article>`;
}

function clanTile(clan, { blurb = true, ctx } = {}) {
    return `<a class="clan-tile" href="/clans/${clan.id}"${clanStyle(clan)}>
${emblem(clan, 240)}
<b>${esc(clan.name)}</b>
${blurb && ctx ? `<span>${ctx.d.markup(clan.blurb)}</span>` : ''}
<small>${count(clan.total, 'card', 'cards')}${clan.lines.length ? ` · ${count(clan.lines.length, 'Striver line', 'Striver lines')}` : ''}</small>
</a>`;
}

function downloads(ctx) {
    const boxes = PLATFORMS.map(([id, name, href, needs, steps]) => {
        const build = ctx.builds[id];
        return `<div class="dl" data-os="${id}">
<h3>${name}</h3>
<p class="needs">${needs}</p>
${build ? `<a class="btn" href="${href}">Download <small>${mb(build.size)}</small></a>` : '<span class="btn off">Not available yet</span>'}
<details><summary>How to install</summary><ol>${steps.map((s) => `<li>${s}</li>`).join('')}</ol></details>
</div>`;
    }).join('\n');
    return `<section class="band" id="download">
<div class="wrap">
<h2>Download</h2>
<p class="lead">Version ${esc(ctx.latest)}. One account works on all three, and everyone plays on the same servers. The game keeps itself up to date: small updates download when you start it.</p>
<div class="dls">
${boxes}
</div>
${PRELAUNCH ? `<p class="note">${PRELAUNCH}</p>` : ''}
</div>
</section>`;
}

function update(note, heading = 'h3') {
    return `<article class="update" id="v${esc(note.version)}">
<${heading}>Version ${esc(note.version)}</${heading}>
<ul>${note.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>
</article>`;
}

// ── Home ─────────────────────────────────────────────────────────────────────────────────────────
function home(ctx) {
    const d = ctx.d;
    const clans = d.clans.filter((c) => !c.neutral);
    const line = d.lines.length ? d.lines[Math.floor(Date.now() / 86400000) % d.lines.length] : null;   // (a new line each day)
    const lineClan = line && d.clanById.get(line.clan);

    const buttons = PLATFORMS.map(([id, name, href]) => (ctx.builds[id]
        ? `<a class="btn big" data-os="${id}" href="${href}"><small>Download for</small>${name}</a>`
        : `<span class="btn big off" data-os="${id}"><small>Not available yet</small>${name}</span>`)).join('');

    const feature = (title, text, media, link) => `<section class="feature${media ? '' : ' plain'}">
<div class="feature-text">
<h2>${title}</h2>
${text}
${link ? `<p><a class="more" href="${link[0]}">${link[1]}</a></p>` : ''}
</div>
${media}
</section>`;

    const ranks = RANKS.map(([id, name]) => {
        const src = images.url('rank', id, 160);
        return src ? `<li><img src="${src}" alt="" width="160" height="160" loading="lazy" decoding="async"><b>${name}</b></li>` : '';
    }).join('');

    const gallery = [...d.shots.values()].filter((s) => (s.tags || []).includes('gallery'))
        .map((s) => shot(ctx, s.name, { caption: false, sizes: '(min-width: 900px) 380px, 50vw' })).join('\n');

    const body = `<section class="hero">
<img class="hero-bg" src="${st(ctx, 'img/hero.jpg')}" srcset="${st(ctx, 'img/hero-900.jpg')} 900w, ${st(ctx, 'img/hero.jpg')} 1920w" sizes="100vw" alt="" width="1920" height="1047" fetchpriority="high">
<div class="hero-in">
<h1><img class="logo" src="${st(ctx, 'img/logo.webp')}" alt="${GAME}" width="900" height="490" fetchpriority="high"></h1>
<p class="tagline">${TAGLINE}</p>
<p class="lead">${ABOUT}</p>
<div class="cta">${buttons}</div>
<p class="fine">Version ${esc(ctx.latest)} · <a href="#download">How to install</a> · <a href="/how-to-play">How to play</a></p>
</div>
</section>

<section class="wrap screen">
${shot(ctx, 'duel-casino', { eager: true, sizes: '(min-width: 1100px) 1060px, 100vw' })}
<ul class="facts">
<li><b>${d.total}</b> cards</li>
<li><b>${clans.length}</b> clans</li>
<li><b>${d.lines.length}</b> Striver lines</li>
<li><b>3</b> ways in: Windows, Mac, Android</li>
</ul>
</section>

<section class="wrap" id="clans">
<h2>Choose your clan</h2>
<p class="lead">Every deck follows a leader, and every leader a clan. Each clan fights its own way.</p>
<div class="clan-tiles">
${clans.map((c) => clanTile(c, { ctx })).join('\n')}
</div>
</section>

<div class="wrap features">
${feature('Brawl for the block', `<p>Deploy characters, play Hustles and set Ambushes face-down. Attack in ATK, hold the line in DEF, and bring your opponent's Morale from 6000 to 0.</p>
<p>A fighter that loses a brawl goes Down. Hit it again and it's KO'd.</p>`, shot(ctx, 'duel-docks'), ['/how-to-play', 'How to play'])}
${line ? `<section class="feature strivers"${clanStyle(lineClan)}>
<div class="feature-text">
<h2>Strivers rise mid-fight</h2>
<p>A Striver starts small. Do what its card asks and it <b class="promo">PROMOTES</b> into its next level, right there on the board: three levels, each one stronger.</p>
<p>Today's line: <b>${esc(line.name)}</b>${lineClan ? `, of ${esc(lineClan.name)}` : ''}. There are ${d.lines.length} in all.</p>
<p><a class="more" href="/clans/${line.clan}#strivers">${lineClan ? `Every ${esc(lineClan.name)} Striver line` : 'More Striver lines'}</a></p>
</div>
${timeline(ctx, line, { heading: 'h3' })}
</section>` : ''}
${feature(`${d.total} cards to collect`, `<p>Open booster packs, craft the cards you're missing with Dust, and build decks of 40 to 60 cards around your leader.</p>
<p>Cards you keep fighting with earn bronze, chrome and gold frames. Spare ones sell for Karat in the Auction House.</p>`, shot(ctx, 'pack') || shot(ctx, 'card-library'), ['/cards', 'Browse every card'])}
${feature('Fight for the city', `<p>Every match is fought in one of the city's districts, and wins influence there for your clan. When the week ends, each district goes to the clan that fought hardest for it, and everyone who fought for it is paid.</p>`, shot(ctx, 'turf-map'))}
${feature('Five ways to play', `<p><b>Casual</b> and <b>Ranked</b> one on one. <b>VS CPU</b> to practise. <b>Free-for-all</b>: four players, everyone for themselves. <b>Turf Defense</b>: you and a partner against a clan boss.</p>`, shot(ctx, 'fight-mode'), ['/how-to-play#game-modes', 'The game modes'])}
</div>

${ranks ? `<section class="band ranks">
<div class="wrap">
<h2>Climb the ladder</h2>
<p class="lead">Ranked matches win Rank Points. Six ranks stand between a Rookie and a Legend.</p>
<ol class="rank-row">${ranks}</ol>
</div>
</section>` : ''}

${gallery ? `<section class="wrap" id="screenshots">
<h2>From the game</h2>
<div class="gallery">
${gallery}
</div>
</section>` : ''}

${d.news.length ? `<section class="wrap" id="latest">
<h2>Latest update</h2>
${update(d.news[0])}
<p><a class="more" href="/news">Every update</a></p>
</section>` : ''}

${downloads(ctx)}`;

    const ld = {
        '@context': 'https://schema.org', '@type': 'VideoGame', name: GAME, description: ABOUT, genre: 'Card game',
        gamePlatform: ['Windows', 'macOS', 'Android'], url: ctx.base + '/', image: ctx.base + st(ctx, 'img/og.jpg'),
    };
    return layout(ctx, {
        path: '/', description: `${TAGLINE} ${ABOUT}`, body, cls: 'home',
        head: `<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, '\\u003c')}</script>\n`,
    });
}

// ── Clans ────────────────────────────────────────────────────────────────────────────────────────
function clans(ctx) {
    const d = ctx.d;
    const tiles = d.clans.map((c) => `<article class="clan-card"${clanStyle(c)}>
<a class="clan-card-head" href="/clans/${c.id}">
${emblem(c, 240)}
<h2>${esc(c.name)}</h2>
</a>
<p>${d.markup(c.blurb)}</p>
<ul class="chips">${GROUPS.filter(([g]) => c.counts[g]).map(([g, many, one]) => `<li><b>${c.counts[g]}</b> ${c.counts[g] === 1 ? one : many}</li>`).join('')}</ul>
${c.leader ? `<div class="clan-card-leader">${cardLink(c.leader, { width: 180 })}<p><small>Leader</small><b>${esc(c.leader.name)}</b></p></div>` : ''}
<a class="more" href="/clans/${c.id}">${c.neutral ? 'Every Neutral card' : `Every ${esc(c.name)} card`}</a>
</article>`).join('\n');
    const real = d.clans.filter((c) => !c.neutral);
    return layout(ctx, {
        path: '/clans', title: 'Clans',
        description: `The ${real.length} clans of ${GAME}: ${real.map((c) => c.name).join(', ')}. Their leaders, their Striver lines and every card they have.`,
        body: `<section class="wrap page-head">
<h1>The clans</h1>
<p class="lead">A deck holds its leader's clan and Neutral cards, nothing else. So picking a clan is picking how you fight.</p>
</section>
<section class="wrap clan-cards">
${tiles}
</section>`,
    });
}

function clan(ctx, c) {
    const d = ctx.d;
    const kit = [['back', 'Card back'], ['booster', 'Booster pack'], ['deckbox', 'Deck box']].map(([kind, name]) => {
        const src = images.url(kind, c.id, 360);
        return src ? `<figure><img src="${src}" alt="${esc(c.name)}: ${name.toLowerCase()}" width="180" loading="lazy" decoding="async"><figcaption>${name}</figcaption></figure>` : '';
    }).join('');

    const groups = GROUPS.filter(([g]) => c.cards.some((x) => x.group === g));
    const chips = groups.length > 1
        ? `<nav class="chipbar" aria-label="Kinds of card"><a href="#cards" data-filter="" class="on">All <small>${c.cards.length}</small></a>${groups.map(([g, many]) => `<a href="#g-${g}" data-filter="${g}">${many} <small>${c.cards.filter((x) => x.group === g).length}</small></a>`).join('')}</nav>`
        : '';
    const sections = groups.map(([g, many]) => `<section class="group" id="g-${g}" data-group="${g}">
<h3>${many}</h3>
<div class="grid">
${c.cards.filter((x) => x.group === g).map((x) => cardLink(x)).join('\n')}
</div>
</section>`).join('\n');

    const others = d.clans.filter((o) => o !== c).map((o) => `<a class="clan-chip" href="/clans/${o.id}"${clanStyle(o)}>${emblem(o, 96)}<b>${esc(o.name)}</b></a>`).join('');

    const body = `<section class="clan-head">
<div class="wrap clan-head-in">
${emblem(c, 480, 'emblem big')}
<div>
<p class="crumb"><a href="/clans">Clans</a></p>
<h1>${esc(c.name)}</h1>
<p class="lead">${d.markup(c.blurb)}</p>
<ul class="chips">${GROUPS.filter(([g]) => c.counts[g]).map(([g, many, one]) => `<li><b>${c.counts[g]}</b> ${c.counts[g] === 1 ? one : many}</li>`).join('')}</ul>
<nav class="jump" aria-label="On this page">${c.leader ? '<a href="#leader">Leader</a>' : ''}${c.lines.length ? '<a href="#strivers">Striver lines</a>' : ''}<a href="#cards">All ${c.total} cards</a></nav>
</div>
</div>
</section>

${c.leader ? `<section class="wrap leader" id="leader">
<h2>The leader</h2>
<div class="leader-in">
${cardLink(c.leader, { width: 760, eager: true })}
<div class="leader-text">
<h3>${esc(c.leader.name)}</h3>
${stats(c.leader)}
<div class="text">${textOf(ctx, c.leader.text)}</div>
${c.leader.flavour ? `<blockquote class="flavour">${esc(c.leader.flavour)}</blockquote>` : ''}
<p class="how">A leader starts the match Dormant and helps from the side. Meet its AWAKEN condition and it takes the field. <a href="/how-to-play#leaders">How leaders work</a></p>
${kit ? `<div class="kit">${kit}</div>` : ''}
</div>
</div>
</section>` : ''}

${c.lines.length ? `<section class="wrap" id="strivers">
<h2>Striver lines</h2>
<p class="lead">${count(c.lines.length, 'Striver', 'Strivers')}, three levels each. A Striver <b class="promo">PROMOTES</b> into its next level when it does what its card asks: the higher levels wait in your Hideout. <a href="/how-to-play#characters">How Strivers work</a></p>
<div class="lines">
${c.lines.map((l) => timeline(ctx, l)).join('\n')}
</div>
</section>` : ''}

<section class="wrap" id="cards">
<h2>${c.neutral ? 'Every Neutral card' : `Every ${esc(c.name)} card`}</h2>
<p class="lead">${cardCount(c.cards.length, c.cards.length - c.total)}. Click one for a closer look.</p>
${chips}
${sections}
</section>

<section class="wrap others">
<h2>The other clans</h2>
<nav class="clan-chips">${others}</nav>
</section>`;

    const og = c.leader && images.url('card', c.leader.id, 760, 'jpg');
    return layout(ctx, {
        path: `/clans/${c.id}`, title: c.neutral ? 'Neutral cards' : `${c.name} clan`, clan: c, cls: 'clan-page',
        description: `${c.blurb} ${c.leader ? `Leader: ${c.leader.name}. ` : ''}${count(c.total, 'card', 'cards')}${c.lines.length ? ` and ${count(c.lines.length, 'Striver line', 'Striver lines')}` : ''}.`,
        image: og || undefined, body,
    });
}

// ── Cards ────────────────────────────────────────────────────────────────────────────────────────
/** What the search box looks through: the card's name, kinds, clan, rarity and keywords, in small letters. */
function searchText(ctx, c) {
    const kw = ctx.d.keywords;
    return [c.name, ...c.kind, c.clanName, c.rarityName, ...kw.found(c.text).map((k) => kw.fullName(k))].join(' ').toLowerCase();
}

/** Whether a card passes the filters (the same test site.js does in the browser). */
function passes(ctx, c, f) {
    if (f.clan && c.clan !== f.clan) return false;
    if (f.kind && c.group !== f.kind) return false;
    if (f.rarity && String(c.rarity) !== f.rarity) return false;
    const text = searchText(ctx, c);
    return f.q.toLowerCase().split(/\s+/).filter(Boolean).every((w) => text.includes(w));
}

function cards(ctx, query = {}) {
    const d = ctx.d;
    const one = (v) => String(Array.isArray(v) ? v[0] : v ?? '').slice(0, 60);
    const f = { q: one(query.q).trim(), clan: one(query.clan), kind: one(query.kind), rarity: one(query.rarity) };
    const option = (value, name, now) => `<option value="${esc(value)}"${String(value) === now ? ' selected' : ''}>${esc(name)}</option>`;

    let shown = 0;
    let tokens = 0;   // (of those shown)
    const tiles = d.cards.map((c) => {
        const ok = passes(ctx, c, f);
        if (ok) shown++;
        if (ok && c.token) tokens++;
        return cardLink(c, { attrs: ` data-clan="${c.clan}" data-kind="${c.group}" data-rarity="${c.rarity}"${c.token ? ' data-token' : ''} data-q="${esc(searchText(ctx, c))}"${ok ? '' : ' hidden'}` });
    }).join('\n');

    const body = `<section class="wrap page-head">
<h1>Every card</h1>
<p class="lead">All ${d.total} cards in the game. Search by name or keyword, or narrow them down by clan, kind and rarity.</p>
<form class="filters" id="filters" action="/cards" method="get" role="search">
<label class="grow"><span>Search</span><input type="search" name="q" value="${esc(f.q)}" placeholder="A name or a keyword, e.g. burn" autocomplete="off"></label>
<label><span>Clan</span><select name="clan">${option('', 'All clans', f.clan)}${d.clans.map((c) => option(c.id, c.name, f.clan)).join('')}</select></label>
<label><span>Kind</span><select name="kind">${option('', 'All kinds', f.kind)}${GROUPS.map(([g, many]) => option(g, many, f.kind)).join('')}</select></label>
<label><span>Rarity</span><select name="rarity">${option('', 'All rarities', f.rarity)}${Object.entries(d.rarities).map(([r, v]) => option(r, v.name, f.rarity)).join('')}</select></label>
<button class="btn small" type="submit">Show</button>
</form>
<p class="tally" id="tally" aria-live="polite">${cardCount(shown, tokens)}</p>
</section>
<section class="wrap">
<div class="grid" id="grid">
${tiles}
</div>
<p class="empty" id="empty"${shown ? ' hidden' : ''}>No card matches that. Try fewer words.</p>
</section>`;
    return layout(ctx, {
        path: '/cards', title: 'Cards', body, cls: 'cards-page',
        description: `Every card in ${GAME}: all ${d.total}, with their art, stats and effects. Search by name or keyword and filter by clan, kind and rarity.`,
    });
}

/** A card in full: its picture, its numbers, its text with the keywords explained, and its Striver line. */
function detail(ctx, c, heading = 'h1') {
    const d = ctx.d;
    const kw = d.keywords;
    const clanOf = d.clanById.get(c.clan);
    const big = images.url('card', c.id, 760);
    const rarity = d.rarities[c.rarity] || d.rarities[1];

    const seen = new Set();
    const words = kw.found(c.text).filter((k) => !seen.has(kw.LIST[k][1]) && seen.add(kw.LIST[k][1])).map((k) => {
        const name = kw.fullName(k);
        const text = kw.LIST[k][1];
        return `<div><dt>${d.markup(name)}</dt><dd>${esc(afterName(name, text))}</dd></div>`;
    }).join('');

    // (the Skeleton token has three pictures: card_unde_002, _v2, _v3)
    const variants = [];
    for (let i = 2; i <= Number(c.raw.artVariants || 1); i++) {
        const src = images.url('card', `${c.id}_v${i}`, 180);
        if (src) variants.push(`<img src="${src}" alt="${esc(c.name)}: other art ${i}" width="${CARD_W}" height="${CARD_H}" loading="lazy" decoding="async">`);
    }

    const line = c.line && c.line.levels.length > 1
        ? `<h3>Striver line</h3>
<ol class="mini-line">${c.line.levels.map((l) => `<li${l === c ? ' class="here"' : ''}>${cardLink(l, { width: 180 })}<small>Level ${l.level}</small></li>`).join('')}</ol>
${c.promote ? `<div class="promote">${promoteText(ctx, c)}</div>` : ''}`
        : '';

    return `<article class="detail" data-id="${c.id}" data-name="${esc(c.name)}"${clanStyle(clanOf)}>
<div class="detail-pic">${big ? `<img src="${big}" alt="${esc(c.name)}" width="${CARD_W}" height="${CARD_H}" decoding="async">` : `<span class="noart">${esc(c.name)}</span>`}</div>
<div class="detail-info">
<p class="crumb">${clanOf ? `<a href="/clans/${clanOf.id}">${esc(clanOf.name)}</a> · ` : ''}${esc(c.kind.join(' · '))}</p>
<${heading} class="detail-name">${esc(c.name)}</${heading}>
<ul class="chips"><li class="rarity" style="--rarity:${rarity.color}">${esc(rarity.name)}</li>${c.code ? `<li>${esc(c.code)}</li>` : ''}</ul>
${stats(c)}
${c.text ? `<div class="text">${textOf(ctx, c.text)}</div>` : ''}
${c.flavour ? `<blockquote class="flavour">${esc(c.flavour)}</blockquote>` : ''}
${words ? `<h3>Keywords</h3>\n<dl class="words">${words}</dl>` : ''}
${line}
${variants.length ? `<h3>Other art</h3>\n<div class="variants">${variants.join('')}</div>` : ''}
${clanOf ? `<p class="detail-more"><a class="more" href="/clans/${clanOf.id}">${clanOf.neutral ? 'Every Neutral card' : `Every ${esc(clanOf.name)} card`}</a></p>` : ''}
</div>
</article>`;
}

function card(ctx, c) {
    const og = images.url('card', c.id, 760, 'jpg');
    const text = c.text.replace(/\s+/g, ' ');
    return layout(ctx, {
        path: `/cards/${c.id}`, title: c.name, clan: ctx.d.clanById.get(c.clan), cls: 'card-page', image: og || undefined,
        description: `${c.name}: ${kindOf(c)}. ${text.length > 180 ? text.slice(0, 177) + '...' : text}`,
        body: `<section class="wrap">
${detail(ctx, c)}
<p class="back"><a class="more back-link" href="/cards">Every card</a></p>
</section>`,
    });
}

/** Just the card, for the zoom (site.js). */
const cardFragment = (ctx, c) => detail(ctx, c, 'h2');

// ── How to play ──────────────────────────────────────────────────────────────────────────────────
function howToPlay(ctx) {
    const h = ctx.d.howto;
    const example = (e) => `<figure class="eg${e.turned ? ' turned' : ''}${e.dim ? ' dim' : ''}">${cardLink(e.card, { width: 180 })}<figcaption>${esc(e.caption)}</figcaption></figure>`;
    const sections = h.sections.map((s) => `<section class="rule" id="${s.slug}">
<h2>${esc(s.title)}</h2>
<div class="rule-in">
<div class="rule-text">
${s.html}
${s.examples.length ? `<div class="egs">${s.examples.map(example).join('')}</div>` : ''}
</div>
${shot(ctx, SECTION_SHOTS[s.slug] || '', { sizes: '(min-width: 1100px) 460px, 100vw' })}
</div>
</section>`).join('\n');

    const entry = (prefix, t) => `<article class="word" id="${prefix}-${t.slug}" style="--word:${t.color}">
<div class="word-text">${t.html}</div>
${t.examples.length ? `<div class="word-cards">${t.examples.map((c) => cardLink(c, { width: 180 })).join('')}</div>` : ''}
</article>`;
    const terms = h.terms.map((t) => `<article class="word" id="term-${t.slug}" style="--word:${t.color}">
<div class="word-text"><h3>${esc(t.name)}</h3>${t.html}</div>
${t.examples.length ? `<div class="word-cards">${t.examples.map((c) => cardLink(c, { width: 180 })).join('')}</div>` : ''}
</article>`).join('\n');

    const toc = [...h.sections.map((s) => [s.slug, s.title]), ['keywords', 'Keywords'], ['card-terms', 'Card terms']]
        .map(([id, name]) => `<a href="#${id}">${esc(name)}</a>`).join('');

    const body = `<section class="wrap page-head">
<h1>How to play</h1>
<p class="lead">The game's own guide, word for word, with real cards as examples. In the game it's the <b>?</b> on the main menu, and the tutorial plays you through a first match.</p>
</section>
<div class="wrap howto">
<nav class="toc" aria-label="On this page">${toc}</nav>
<div class="howto-body">
${sections}
<section class="rule" id="keywords">
<h2>Keywords</h2>
<p class="lead">Words in colour on a card are keywords. Each one always means the same thing.</p>
<div class="wordlist">
${h.keywords.map((k) => entry('kw', k)).join('\n')}
</div>
</section>
<section class="rule" id="card-terms">
<h2>Card terms</h2>
<p class="lead">The other words card text keeps coming back to.</p>
<div class="wordlist">
${terms}
</div>
</section>
</div>
</div>`;
    return layout(ctx, {
        path: '/how-to-play', title: 'How to play', body, cls: 'howto-page',
        description: `How to play ${GAME}: turns, brawls, Strivers, leaders, Hustles and Ambushes, every keyword and the game modes, with real cards as examples.`,
    });
}

// ── News ─────────────────────────────────────────────────────────────────────────────────────────
function news(ctx, open = 12) {
    const notes = ctx.d.news;
    const older = notes.slice(open);
    const body = `<section class="wrap page-head">
<h1>News</h1>
<p class="lead">Every update to the game, newest first: the same notes the game shows when it updates.</p>
</section>
<section class="wrap updates">
${notes.length ? notes.slice(0, open).map((n) => update(n, 'h2')).join('\n') : '<p>No updates yet.</p>'}
${older.length ? `<details class="older"><summary>Older updates (${older.length})</summary>
${older.map((n) => update(n, 'h2')).join('\n')}
</details>` : ''}
</section>`;
    return layout(ctx, {
        path: '/news', title: 'News', body, cls: 'news-page',
        description: `What's new in ${GAME}: the notes for every update${notes.length ? `, up to version ${notes[0].version}` : ''}.`,
    });
}

// ── The rest ─────────────────────────────────────────────────────────────────────────────────────
function notFound(ctx, path = '/') {
    return layout(ctx, {
        path, title: 'Nothing here', description: `That page isn't on the ${GAME} website.`, cls: 'lost',
        body: `<section class="wrap page-head lost-in">
<h1>Dead end</h1>
<p class="lead">Nothing down this alley. The page may have moved, or the address has a typo.</p>
<p class="cta"><a class="btn" href="/">Back to the start</a><a class="btn ghost" href="/cards">Every card</a><a class="btn ghost" href="/how-to-play">How to play</a></p>
</section>`,
    });
}

/** What each keyword means, for the pop-ups: KEY → { name, text } (the text as it follows the name). */
function keywordsJson(ctx) {
    const kw = ctx.d.keywords;
    const out = {};
    for (const [key, [, text]] of Object.entries(kw.LIST)) {
        const name = kw.fullName(key);
        out[key] = { name, text: afterName(name, text) };
    }
    return out;
}

/** Every page's address (for sitemap.xml). */
function sitemap(ctx) {
    const d = ctx.d;
    return ['/', '/clans', ...d.clans.map((c) => `/clans/${c.id}`), '/cards', '/how-to-play', '/news', ...d.cards.map((c) => `/cards/${c.id}`), '/privacy', '/terms'];
}

module.exports = { home, clans, clan, cards, card, cardFragment, howToPlay, news, notFound, keywordsJson, sitemap, GAME };
