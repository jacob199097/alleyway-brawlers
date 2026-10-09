// A fake game server for testing the Godot menus without the real backend or a database.
// Same routes and response shapes as backend/routes/*; state lives in memory only.
//   node godot/tests/mock_server.mjs [port]      (default 3999)
// Then set Settings → Server → http://127.0.0.1:3999 and log in with any email/password.
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { CARD_CATALOG } from '../../shared/cards.js';

const port = Number(process.argv[2] || 3999);

const cards = Object.values(CARD_CATALOG).map(c => ({
    id: randomUUID(), name: c.name, clan: 'lion_pride', clan_tag: c.clanTag, card_type: c.cardType,
    subtype: c.subtype ?? null, level: c.level ?? 1, authority: c.authority ?? 0,
    attack: c.attack ?? null, defense: c.defense ?? null, rarity: c.rarity ?? 1,
    art_url: c.id, effect_text: c.effectText ?? '', flavour_text: c.flavourText ?? null,
}));
const byId = new Map(cards.map(c => [c.id, c]));
const inventory = new Map(cards.map(c => [c.id, 3]));

const player = {
    id: randomUUID(), username: 'Tester', email: 'test@example.com', karat: 1200, contraband: 300,
    level: 6, xp: 3300, rank: 'enforcer', rank_points: 240, wins: 12, losses: 7, draws: 0,
    avatar_url: 'profile_001', profile_bio: 'Running these streets.', chosen_clan: 'lion_pride',
    created_at: new Date().toISOString(), collection_pct: 100,
};

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
    'POST /api/auth/login': (b) => b.email && b.password ? [200, { token: 'mock-token', player }] : [400, { error: 'email and password are required.' }],
    'POST /api/auth/register': () => [201, { pending: true, message: 'Account created.' }],
    'POST /api/auth/forgot-password': () => [200, { success: true }],
    'GET /api/profile/me': () => [200, player],
    'PATCH /api/profile/me': (b) => { if (b.avatarUrl) player.avatar_url = b.avatarUrl; return [200, { success: true }]; },
    'GET /api/profile/inventory': () => [200, cards.map(c => ({ ...c, quantity: inventory.get(c.id) }))
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
    'GET /api/social/friends': () => [200, friends],
    'POST /api/social/friends/request': (b) => b.targetUsername === 'nobody' ? [404, { error: 'Player not found.' }] : [200, { success: true }],
    'PATCH /api/social/friends/:id/accept': (_b, id) => { const f = friends.find(x => x.friendship_id === id); if (f) f.status = 'accepted'; return [200, { success: true }]; },
    'GET /api/social/messages/:id': (_b, id) => [200, [
        { sender_id: id, body: 'You up for a brawl later?' }, { sender_id: player.id, body: 'Always. Bring your best deck.' }]],
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

http.createServer((req, res) => {
    let raw = '';
    req.on('data', d => raw += d);
    req.on('end', () => {
        const path = req.url.split('?')[0];
        const handler = route(req.method, path);
        let body = {};
        try { body = raw ? JSON.parse(raw) : {}; } catch { /* ignore */ }
        const authed = path.startsWith('/api/auth') || path === '/health' || req.headers.authorization === 'Bearer mock-token';
        const [code, data] = !handler ? [404, { error: 'Not found.' }] : !authed ? [401, { error: 'Unauthorized.' }] : handler(body);
        res.writeHead(code, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
        console.log(req.method, path, code);
    });
}).listen(port, () => console.log(`Mock server on http://127.0.0.1:${port}`));
