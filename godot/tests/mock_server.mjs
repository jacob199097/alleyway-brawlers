// A fake game server for testing the Godot menus without the real backend or a database.
// Same routes and response shapes as backend/routes/*; state lives in memory only.
//   node godot/tests/mock_server.mjs [port]      (default 3999)
// Then set Settings → Server → http://127.0.0.1:3999 and log in with any email/password
// (each email is its own account). Online matches run on the real backend/socket/onlineMatch.js.
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { CARD_CATALOG } from '../../shared/cards.js';
import { pickableClans, starterRecipe } from '../../shared/clans.js';

const port = Number(process.argv[2] || 3999);

const cards = Object.values(CARD_CATALOG).map(c => ({
    id: randomUUID(), name: c.name, clan: c.clan, clan_tag: c.clanTag, card_type: c.cardType,
    subtype: c.subtype ?? null, level: c.level ?? 1, authority: c.authority ?? 0,
    attack: c.attack ?? null, defense: c.defense ?? null, rarity: c.rarity ?? 1,
    art_url: c.id, effect_text: c.effectText ?? '', flavour_text: c.flavourText ?? null,
}));
const byId = new Map(cards.map(c => [c.id, c]));
const inventory = new Map(cards.map(c => [c.id, 3]));
cards.filter(c => c.rarity <= 2).slice(0, 4).forEach(c => inventory.set(c.id, 5));   // a few extras to scrap

// Crafting and achievements use the real definitions (backend/economy/*.js; nothing there connects to a database)
const _require = createRequire(import.meta.url);
const { VALUES: CRAFT_VALUES } = _require('../../backend/economy/crafting.js');
const achievementDefs = await _require('../../backend/economy/achievements.js').definitions();
const unlocked = new Map(achievementDefs.filter((a, i) => i % 3 === 0).map((a, i) => [a.id, new Date(Date.now() - i * 86400e3).toISOString()]));
const craftSummary = (p) => {
    let extras = 0, extrasDust = 0;
    for (const c of cards) {
        const n = Math.max(0, (inventory.get(c.id) || 0) - (c.card_type === 'leader' ? 1 : 3));
        extras += n; extrasDust += n * CRAFT_VALUES[c.rarity].scrap;
    }
    return { dust: p.dust, values: CRAFT_VALUES, maxCopies: 3, extras, extrasDust };
};
const looks = () => {
    const got = achievementDefs.filter(a => unlocked.has(a.id));
    return { avatars: ['profile_001', 'profile_002', ...got.map(a => a.reward.avatar).filter(v => v && v !== 'portraits')],
        portraits: got.some(a => a.reward.avatar === 'portraits'),
        titles: got.filter(a => a.reward.title).map(a => ({ id: a.id, text: a.reward.title })),
        backs: ['default', ...got.map(a => a.reward.back).filter(Boolean)] };
};

// One account per email; the token names the account. `player` is whoever made the request.
const players = new Map();   // token → player
function loginAs(email) {
    const token = `mock-token:${email}`;
    if (!players.has(token)) {
        const name = email.split('@')[0];
        players.set(token, {
            id: randomUUID(), username: name.charAt(0).toUpperCase() + name.slice(1), email, karat: 1200,
            contraband: 300, level: 6, xp: 3300, rank: 'enforcer', rank_points: 240, wins: 12, losses: 7, draws: 0,
            avatar_url: 'profile_001', profile_bio: 'Running these streets.', chosen_clan: pickableClans()[0]?.id ?? null,
            created_at: new Date().toISOString(), collection_pct: 100, token, dust: 1850, title: null, title_id: null, card_back: null,
        });
    }
    return players.get(token);
}
let player = loginAs('test@example.com');
const byPlayerId = (id) => [...players.values()].find(p => p.id === id);

// Starter deck: Lv.1 characters and effects, up to 40 cards, King Roan as leader
const deckCards = new Map();
let total = 0;
for (const c of cards) {
    if (c.card_type === 'leader' || (c.card_type === 'gang_member' && c.level > 1)) continue;
    const n = Math.min(2, 40 - total);
    if (n > 0) { deckCards.set(c.id, n); total += n; }
}
const leader = cards.find(c => c.card_type === 'leader');
const decks = [
    { id: randomUUID(), name: 'Lion Pride', is_active: true, leader_card_id: leader.id, cards: deckCards, updated_at: new Date().toISOString() },
    { id: randomUUID(), name: 'Half Built', is_active: false, leader_card_id: null, cards: new Map([...deckCards].slice(0, 6)), updated_at: new Date().toISOString() },
];

const mail = [
    { id: randomUUID(), sender: 'System', subject: 'Welcome to the Lions', body: 'Your starter inventory and a 40-card Lions deck have been added to your account.\n\nOpen the Deck Editor to customise it.', read_at: null, created_at: new Date().toISOString() },
    { id: randomUUID(), sender: 'Daily Quests', subject: 'Reward delivered', body: '+50 Karat for winning a match today.', read_at: new Date().toISOString(), created_at: new Date(Date.now() - 86400e3).toISOString() },
];
const friends = [
    { friendship_id: randomUUID(), status: 'accepted', friend_id: randomUUID(), friend_username: 'AlleyCat', friend_avatar: 'profile_002', is_online: true, level: 9 },
    { friendship_id: randomUUID(), status: 'accepted', friend_id: randomUUID(), friend_username: 'Brickhouse', friend_avatar: 'profile_001', is_online: false, level: 3 },
    { friendship_id: randomUUID(), status: 'pending', friend_id: randomUUID(), friend_username: 'NewKid', friend_avatar: 'profile_001', is_online: false, level: 1 },
];
const quests = {
    daily: [
        { id: 'daily_win_1', label: 'Win 1 Match', target: 1, rewardKarat: 50, rewardContraband: 0, progress: 1, claimed: false },
        { id: 'daily_win_3', label: 'Win 3 Matches', target: 3, rewardKarat: 150, rewardContraband: 0, progress: 1, claimed: false },
        { id: 'daily_play_10', label: 'Play 10 Cards', target: 10, rewardKarat: 50, rewardContraband: 0, progress: 6, claimed: false },
        { id: 'daily_pack', label: 'Open a Crew Pack', target: 1, rewardKarat: 0, rewardContraband: 15, progress: 0, claimed: false },
    ],
    main: [
        { id: 'wins_10', label: 'Win 10 Matches', target: 10, rewardKarat: 200, progress: 10, claimed: false },
        { id: 'wins_50', label: 'Win 50 Matches', target: 50, rewardKarat: 500, progress: 12, claimed: false },
        { id: 'reach_lv10', label: 'Reach Level 10', target: 10, rewardKarat: 300, progress: 6, claimed: false },
    ],
};
const matches = new Map();

function deckSummary(d) {
    return { id: d.id, name: d.name, is_active: d.is_active, updated_at: d.updated_at,
        card_count: [...d.cards.values()].reduce((s, n) => s + n, 0) };
}

const routes = {
    'GET /health': () => [200, { status: 'ok' }],
    'POST /api/auth/login': (b) => {
        if (!b.email || !b.password) return [400, { error: 'email and password are required.' }];
        const p = loginAs(String(b.email).toLowerCase());
        return [200, { token: p.token, player: p }];
    },
    'POST /api/auth/register': () => [201, { pending: true, message: 'Account created.' }],
    'POST /api/auth/forgot-password': () => [200, { success: true }],
    'GET /api/profile/me': () => [200, player],
    'PATCH /api/profile/me': (b) => { if (b.avatarUrl) player.avatar_url = b.avatarUrl; return [200, { success: true }]; },
    'GET /api/craft': () => [200, craftSummary(player)],
    'POST /api/craft/scrap': (b) => {
        const c = cards.find(x => x.art_url === b.card);
        if (!c || !inventory.get(c.id)) return [400, { error: "You don't own that card." }];
        inventory.set(c.id, inventory.get(c.id) - 1);
        player.dust += CRAFT_VALUES[c.rarity].scrap;
        return [200, { dust: player.dust, quantity: inventory.get(c.id), gained: CRAFT_VALUES[c.rarity].scrap }];
    },
    'POST /api/craft/make': (b) => {
        const c = cards.find(x => x.art_url === b.card);
        if (!c) return [400, { error: "That card can't be crafted." }];
        const cost = CRAFT_VALUES[c.rarity].craft;
        if ((inventory.get(c.id) || 0) >= (c.card_type === 'leader' ? 1 : 3)) return [400, { error: 'You already have all a deck can use.' }];
        if (player.dust < cost) return [400, { error: `You need ${cost} Dust to craft ${c.name}.` }];
        player.dust -= cost;
        inventory.set(c.id, (inventory.get(c.id) || 0) + 1);
        return [200, { dust: player.dust, quantity: inventory.get(c.id), spent: cost }];
    },
    'POST /api/craft/extras': () => {
        const { extras, extrasDust } = craftSummary(player);
        for (const c of cards) inventory.set(c.id, Math.min(inventory.get(c.id) || 0, c.card_type === 'leader' ? 1 : 3));
        player.dust += extrasDust;
        return [200, { dust: player.dust, gained: extrasDust, scrapped: extras }];
    },
    'GET /api/achievements': () => [200, {
        achievements: achievementDefs.map(a => ({ id: a.id, name: a.name, desc: a.desc, reward: a.reward, clan: a.clan || null,
            target: a.target, progress: unlocked.has(a.id) ? a.target : Math.floor(a.target * 0.6),
            unlocked: unlocked.has(a.id), unlockedAt: unlocked.get(a.id) || null })),
        cosmetics: looks(),
        equipped: { avatar: player.avatar_url, title: player.title_id, back: player.card_back },
    }],
    'POST /api/achievements/equip': (b) => {
        if (b.avatar !== undefined) player.avatar_url = b.avatar;
        if (b.title !== undefined) { player.title_id = b.title; player.title = looks().titles.find(t => t.id === b.title)?.text ?? null; }
        if (b.back !== undefined) player.card_back = b.back;
        return [200, { ok: true }];
    },
    'GET /api/profile/inventory': () => [200, cards.map(c => ({ ...c, quantity: inventory.get(c.id) })).filter(c => c.quantity > 0)
        .sort((a, b) => b.rarity - a.rarity || a.name.localeCompare(b.name))],
    'GET /api/deck': () => [200, decks.map(deckSummary)],
    'POST /api/deck': (b) => {
        const d = { id: randomUUID(), name: b.name || 'New Deck', is_active: false, leader_card_id: null, cards: new Map(), updated_at: new Date().toISOString() };
        decks.push(d);
        return [201, { id: d.id, name: d.name, is_active: false }];
    },
    'GET /api/deck/:id': (_b, id) => {
        const d = decks.find(x => x.id === id);
        if (!d) return [404, { error: 'Deck not found.' }];
        return [200, { ...deckSummary(d), cards: [...d.cards].map(([cid, copies]) => ({ ...byId.get(cid), copies })),
            leader: d.leader_card_id ? byId.get(d.leader_card_id) : null }];
    },
    'PUT /api/deck/:id/cards': (b, id) => {
        const d = decks.find(x => x.id === id);
        const n = (b.cards || []).reduce((s, c) => s + c.copies, 0);
        if (n !== 40) return [400, { error: `Deck must be exactly 40 cards (currently ${n}).` }];
        d.cards = new Map(b.cards.map(c => [c.cardId, c.copies]));
        if (b.leaderCardId !== undefined) d.leader_card_id = b.leaderCardId;
        return [200, { success: true, totalCopies: n }];
    },
    'PATCH /api/deck/:id/activate': (_b, id) => { decks.forEach(d => d.is_active = d.id === id); return [200, { success: true }]; },
    'POST /api/shop/open': (b) => {
        const cost = b.currency === 'contraband' ? 100 : 200;
        const field = b.currency === 'contraband' ? 'contraband' : 'karat';
        if (player[field] < cost) return [400, { error: `Not enough ${field}.` }];
        player[field] -= cost;
        const pool = cards.filter(c => c.card_type !== 'leader');
        const got = [0, 1, 2].map(() => pool[Math.floor(Math.random() * pool.length)]);
        got[2] = pool.filter(c => c.rarity >= 3)[Math.floor(Math.random() * 5)] || got[2];
        got.forEach(c => inventory.set(c.id, inventory.get(c.id) + 1));
        quests.daily[3].progress = 1;
        return [200, { cardsReceived: got.map(c => ({ ...c, cardId: c.art_url, cardType: c.card_type, clanTag: c.clan_tag })),
            newKarat: player.karat, newContraband: player.contraband }];
    },
    'POST /api/shop/contraband/purchase': (b) => {
        const amounts = { cb_500: 500, cb_1200: 1200, cb_2500: 2500, cb_7000: 7000, cb_15000: 15000 };
        if (!amounts[b.bundleId]) return [400, { error: 'Invalid bundle.' }];
        player.contraband += amounts[b.bundleId];
        return [200, { success: true, contrabandGranted: amounts[b.bundleId], newContraband: player.contraband }];
    },
    'GET /api/quests': () => [200, quests],
    'POST /api/quests/claim/:id': (_b, id) => {
        const q = [...quests.daily, ...quests.main].find(x => x.id === id);
        if (!q || q.claimed || q.progress < q.target) return [400, { error: 'Quest not complete.' }];
        q.claimed = true;
        player.karat += q.rewardKarat || 0;
        player.contraband += q.rewardContraband || 0;
        return [200, { success: true, karat: player.karat, contraband: player.contraband }];
    },
    'GET /api/mail': () => [200, { messages: mail, unread: mail.filter(m => !m.read_at).length }],
    'POST /api/mail/read-all': () => { mail.forEach(m => m.read_at ??= new Date().toISOString()); return [200, { success: true }]; },
    'POST /api/mail/:id/read': (_b, id) => { const m = mail.find(x => x.id === id); if (m) m.read_at ??= new Date().toISOString(); return [200, { success: true }]; },
    'DELETE /api/mail/:id': (_b, id) => { const i = mail.findIndex(x => x.id === id); if (i >= 0) mail.splice(i, 1); return [200, { success: true }]; },
    // Every other account that has logged in is a friend too, so challenges can be tested
    'GET /api/social/friends': () => [200, [
        ...[...players.values()].filter(p => p.id !== player.id).map(p => ({
            friendship_id: `f-${p.id}`, status: 'accepted', friend_id: p.id, friend_username: p.username,
            friend_avatar: p.avatar_url, is_online: online.has(p.id), level: p.level,
            in_match: online.has(p.id) && service.isInMatch(p.id), incoming: false,
        })),
        ...friends,
    ]],
    'POST /api/social/friends/request': (b) => b.targetUsername === 'nobody' ? [404, { error: 'Player not found.' }] : [200, { success: true }],
    'PATCH /api/social/friends/:id/accept': (_b, id) => { const f = friends.find(x => x.friendship_id === id); if (f) f.status = 'accepted'; return [200, { success: true }]; },
    'GET /api/social/messages/:id': (_b, id) => [200, [
        { sender_id: id, body: 'You up for a brawl later?' }, { sender_id: player.id, body: 'Always. Bring your best deck.' }]],
    'GET /api/onboarding/clans': () => [200, pickableClans().map(c => ({ ...c, leader: starterRecipe(c.id).leader }))],
    'POST /api/onboarding/start-clan': (b) => { player.chosen_clan = b.clan; return [200, { success: true, clan: b.clan }]; },
    'POST /api/match/start': () => { const id = randomUUID(); matches.set(id, Date.now()); return [200, { matchId: id }]; },
    'POST /api/match/complete': (b) => {
        if (!matches.has(b.matchId)) return [404, { error: 'Match not found.' }];
        matches.delete(b.matchId);
        const win = b.result === 'win';
        const xp = win ? 60 : 25;
        player.xp += xp; player.karat += win ? 40 : 10; player[win ? 'wins' : 'losses']++;
        return [200, { ok: true, rewards: { outcome: b.result, karatEarned: win ? 40 : 10, xpEarned: xp, firstWinBonus: win,
            newKarat: player.karat, newXp: player.xp, newLevel: player.level, leveledUp: false,
            newRank: player.rank, rankChanged: false, rankPointDelta: win ? 15 : -5 } }];
    },
};

function route(method, path) {
    for (const [key, fn] of Object.entries(routes)) {
        const [m, pattern] = key.split(' ');
        if (m !== method) continue;
        const re = new RegExp('^' + pattern.replace(/:id/g, '([^/]+)') + '$');
        const hit = re.exec(path);
        if (hit) return (body) => fn(body, ...hit.slice(1));
    }
    return null;
}

let contentApp = null;   // the real backend/routes/content.js (card data and art downloads)
const server = http.createServer((req, res) => {
    if (req.url.startsWith('/api/content/')) {
        if (!contentApp) {
            contentApp = require('../../backend/node_modules/express')();
            contentApp.use('/api/content', require('../../backend/routes/content.js'));
        }
        console.log(req.method, req.url.split('?')[0]);
        return contentApp(req, res);
    }
    let raw = '';
    req.on('data', d => raw += d);
    req.on('end', () => {
        const path = req.url.split('?')[0];
        const handler = route(req.method, path);
        let body = {};
        try { body = raw ? JSON.parse(raw) : {}; } catch { /* ignore */ }
        const me = players.get(String(req.headers.authorization || '').replace(/^Bearer /, ''));
        if (me) player = me;
        const authed = path.startsWith('/api/auth') || path === '/health' || !!me;
        const [code, data] = !handler ? [404, { error: 'Not found.' }] : !authed ? [401, { error: 'Unauthorized.' }] : handler(body);
        res.writeHead(code, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
        console.log(req.method, path, code);
    });
});

// ── Realtime: the real online-match service, with in-memory data instead of Postgres ──
const require = createRequire(import.meta.url);
const { Server } = require('../../backend/node_modules/socket.io');
const { createOnlineService } = require('../../backend/socket/onlineMatch.js');
const { nextForm } = await import('../../shared/duel/DuelState.js');

const io = new Server(server, { cors: { origin: '*' } });
const online = new Set();   // player ids with a socket
io.use((socket, next) => {
    const p = players.get(socket.handshake.auth?.token);
    if (!p) return next(new Error('Invalid or expired token.'));
    socket.playerData = { playerId: p.id, username: p.username };
    next();
});

const spec = (c) => ({ id: c.art_url, name: c.name, authority: c.authority, attack: c.attack ?? 0, defense: c.defense ?? 0, rarity: c.rarity });
const service = createOnlineService(io, {
    onAction(match, seat, action, ok) {
        const st = match.state;
        console.log(`ACT t${st.turn} ${seat} ${JSON.stringify(action)} ${ok ? 'ok' : 'REFUSED'} morale ${st.sides.player.morale}/${st.sides.opponent.morale}`);
    },
    async loadSetup() {
        const d = decks.find(x => x.is_active) || decks[0];
        const deck = [];
        for (const [cid, copies] of d.cards) for (let i = 0; i < copies; i++) deck.push(spec(byId.get(cid)));
        if (deck.length !== 40) return { error: 'You need a complete 40-card deck to play online.' };
        const hideout = [];
        const seen = new Set();
        for (const [cid] of d.cards) {
            let next = nextForm(byId.get(cid).art_url);
            while (next && !seen.has(next)) {
                seen.add(next);
                const owned = cards.find(c => c.art_url === next);
                if (owned) for (let i = 0; i < 3; i++) hideout.push(spec(owned));
                next = nextForm(next);
            }
        }
        return { deck, hideout, leader: d.leader_card_id ? byId.get(d.leader_card_id).art_url : '' };
    },
    async loadProfile(playerId) {
        const p = byPlayerId(playerId);
        return { username: p.username, level: p.level, avatar_url: p.avatar_url, title: p.title, card_back: p.card_back };
    },
    async resolveMatch({ winnerId, p1Id, p2Id }) {
        const out = {};
        for (const id of [p1Id, p2Id]) {
            const p = byPlayerId(id);
            const win = id === winnerId;
            p.xp += win ? 100 : 20; p.karat += win ? 50 : 10; p[win ? 'wins' : 'losses']++;
            out[id] = { outcome: win ? 'win' : 'loss', karatEarned: win ? 50 : 10, xpEarned: win ? 100 : 20,
                firstWinBonus: false, newKarat: p.karat, newXp: p.xp, newLevel: p.level, leveledUp: false,
                newRank: p.rank, rankChanged: false, rankPointDelta: 0 };
        }
        console.log('MATCH OVER winner', byPlayerId(winnerId)?.username ?? 'none');
        return out;
    },
    async resolveCpuMatch({ playerId, outcome, ranked }) {
        const p = byPlayerId(playerId);
        const win = outcome === 'win';
        p.xp += win ? 100 : 20; p.karat += win ? 50 : 10; p[win ? 'wins' : 'losses']++;
        console.log(`CPU MATCH OVER ${p.username} ${outcome}${ranked ? ' (ranked)' : ''}`);
        return { outcome, karatEarned: win ? 50 : 10, xpEarned: win ? 100 : 20, firstWinBonus: false,
            newKarat: p.karat, newXp: p.xp, newLevel: p.level, leveledUp: false, newRank: p.rank,
            rankChanged: false, rankPointDelta: ranked ? (win ? 25 : -10) : 0 };
    },
});
io.on('connection', (socket) => {
    const { playerId, username } = socket.playerData;
    online.add(playerId);
    console.log('socket connected', username);
    service.register(socket, socket.playerData);
    socket.on('chat:message', ({ toPlayerId, body } = {}) => {
        for (const s of io.sockets.sockets.values()) {
            if (s.playerData.playerId === toPlayerId) s.emit('chat:message', { fromPlayerId: playerId, fromUsername: username, body });
        }
    });
    socket.on('disconnect', () => {
        if (![...io.sockets.sockets.values()].some(s => s.playerData.playerId === playerId)) online.delete(playerId);
    });
});

server.listen(port, () => console.log(`Mock server on http://127.0.0.1:${port}`));
