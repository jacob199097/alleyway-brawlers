// Run: node backend/socket/spectate.test.cjs
// Spectators: only friends may watch, they see the match from their friend's side with both hands
// and face-down cards hidden, players are told how many are watching, and the result reaches them.
const path = require('path');
const { createOnlineService } = require(path.join(__dirname, 'onlineMatch.js'));

function fakeSocket() {
    const handlers = {}, got = [];
    return { handlers, got, connected: true, on: (ev, fn) => { handlers[ev] = fn; },
        emit: (ev, data) => got.push([ev, JSON.parse(JSON.stringify(data))]) };
}
const wait = (ms) => new Promise(r => setTimeout(r, ms));
async function until(fn, ms = 10000) {
    const t = Date.now();
    while (!fn()) { if (Date.now() - t > ms) return false; await wait(20); }
    return true;
}
const last = (s, ev) => [...s.got].reverse().find(([e]) => e === ev)?.[1];
const all = (s, ev) => s.got.filter(([e]) => e === ev).map(([, d]) => d);

/** Anything in a view that would give away a hidden card. */
function leaks(view) {
    const out = [];
    for (const seat of ['player', 'opponent']) {
        const s = view.sides[seat];
        if (s.hand.some(c => Object.keys(c).some(k => k !== 'uid'))) out.push(`${seat} hand`);
        if (s.hideout.some(c => Object.keys(c).some(k => k !== 'uid'))) out.push(`${seat} hideout`);
        if (s.field.some(c => c && c.face_down && c.name)) out.push(`${seat} face-down card`);
    }
    return out;
}

(async () => {
    const { cpuSetup } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelAI.js').split(path.sep).join('/'));
    const friends = new Set(['carol:alice', 'alice:carol']);
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        resolveMatch: async () => ({}),
        areFriends: async (a, b) => friends.has(`${a}:${b}`),
        turnSecs: 0.15, awaySecs: 0.1,
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

    const a = fakeSocket(), b = fakeSocket(), c = fakeSocket(), d = fakeSocket();
    svc.register(a, { playerId: 'alice', username: 'alice' });
    svc.register(b, { playerId: 'bob', username: 'bob' });
    svc.register(c, { playerId: 'carol', username: 'carol' });
    svc.register(d, { playerId: 'dave', username: 'dave' });

    // Not in a match yet
    await c.handlers['mp:spectate']({ targetPlayerId: 'alice' });
    check(/aren't in a match/.test(last(c, 'mp:error')?.message || ''), "can't watch someone who isn't playing");

    // alice vs bob
    a.handlers['mp:challenge']({ targetPlayerId: 'bob' });
    await b.handlers['mp:accept']({ fromPlayerId: 'alice' });
    await until(() => last(a, 'mp:rps') && last(b, 'mp:rps'));
    const id = last(a, 'mp:rps').rpsId;
    a.handlers['mp:rps_pick']({ rpsId: id, pick: 'paper' });
    b.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
    await until(() => last(a, 'mp:rps_choose'));
    a.handlers['mp:rps_first']({ rpsId: id, goFirst: true });
    check(await until(() => last(a, 'mp:start')), 'the match starts');
    const matchId = last(a, 'mp:start').matchId;

    // dave isn't alice's friend
    await d.handlers['mp:spectate']({ targetPlayerId: 'alice' });
    check(/friends/.test(last(d, 'mp:error')?.message || ''), 'only friends can watch');
    check(!last(d, 'mp:start'), 'dave gets no match');

    // carol watches alice
    await c.handlers['mp:spectate']({ targetPlayerId: 'alice' });
    const start = last(c, 'mp:start');
    check(start?.spectate === true && start.matchId === matchId, 'carol gets the match as a spectator');
    check(start?.you?.username === 'alice' && start?.opponent?.username === 'bob', "she watches from alice's side");
    check(start && leaks(start.view).length === 0, `nothing hidden shows in her view (${start && leaks(start.view).join(', ')})`);
    check(last(a, 'mp:spectators')?.count === 1 && last(b, 'mp:spectators')?.count === 1, 'both players hear 1 is watching');

    // Moves keep coming (both players are away, so the server plays for them)
    check(await until(() => all(c, 'mp:update').some(u => u.events.some(e => e.type === 'draw' && !e.opening))), 'carol gets the updates, through a turn with a draw');
    const updates = all(c, 'mp:update');
    check(updates.every(u => leaks(u.view).length === 0), 'no update view shows hidden cards');
    const draws = updates.flatMap(u => u.events).filter(e => e.type === 'draw');
    check(draws.length > 0 && draws.every(e => Object.keys(e.card).every(k => k === 'uid')), `draws stay hidden (${draws.length} seen)`);
    const prompts = updates.flatMap(u => u.events).filter(e => e.type === 'prompt');
    check(prompts.every(e => e.key === 'hidden'), 'prompts stay hidden');
    // alice is "player" for carol, as for alice herself
    const aView = all(a, 'mp:update').at(-1).view, cView = updates.at(-1).view;
    check(aView.active === cView.active && aView.sides.player.morale === cView.sides.player.morale, "carol's sides match alice's");

    // Stop watching, then watch again
    c.handlers['mp:unspectate']();
    check(last(a, 'mp:spectators')?.count === 0, 'leaving: the count drops to 0');
    const before = all(c, 'mp:update').length;
    await wait(500);
    check(all(c, 'mp:update').length === before, 'no more updates after leaving');
    await c.handlers['mp:spectate']({ targetPlayerId: 'alice' });

    // A reconnecting spectator gets the match again
    const starts = all(c, 'mp:start').length;
    c.handlers['mp:resync']();
    check(all(c, 'mp:start').length === starts + 1 && last(c, 'mp:start').spectate, 'resync sends the spectator view again');

    // The match ends: carol hears the result from alice's side
    a.handlers['mp:concede']({ matchId });
    check(await until(() => last(c, 'mp:over')), 'carol gets the result');
    check(last(c, 'mp:over')?.result === 'loss' && last(c, 'mp:over')?.spectate, 'alice conceded: a loss for the side carol watched');
    check(!svc.isInMatch('carol'), "carol was never 'in' the match");

    console.log(bad ? `${bad} problem(s)` : 'all good');
    process.exit(bad ? 1 : 0);
})();
