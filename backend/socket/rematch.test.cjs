// Run: node backend/socket/rematch.test.cjs
// Rematches after a match against a player (both must ask; a decline or leaving tells the other),
// and the move clock for a player who has stopped playing (shorter clock, then they lose).
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
const count = (s, ev) => s.got.filter(([e]) => e === ev).length;

(async () => {
    const { cpuSetup } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelAI.js').replace(/\\/g, '/'));
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        resolveMatch: async () => ({}),
        turnSecs: 0.3, awaySecs: 0.1,
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

    // Challenge → Scissors Paper Rock → match
    async function startPair(x, y, xs, ys) {
        xs.handlers['mp:challenge']({ targetPlayerId: y });
        await ys.handlers['mp:accept']({ fromPlayerId: x });
        await playRps(xs, ys);
    }
    async function playRps(xs, ys) {
        const before = count(xs, 'mp:start');
        await until(() => last(xs, 'mp:rps') && last(ys, 'mp:rps'));
        const id = last(xs, 'mp:rps').rpsId;
        xs.handlers['mp:rps_pick']({ rpsId: id, pick: 'paper' });
        ys.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
        await until(() => last(xs, 'mp:rps_choose')?.rpsId === id);
        xs.handlers['mp:rps_first']({ rpsId: id, goFirst: true });
        return until(() => count(xs, 'mp:start') > before);
    }

    // 1. A rematch needs both players
    const a = fakeSocket(), b = fakeSocket();
    svc.register(a, { playerId: 'alice', username: 'alice' });
    svc.register(b, { playerId: 'bob', username: 'bob' });
    await startPair('alice', 'bob', a, b);
    check(!!last(a, 'mp:start'), 'the first match starts');
    check(last(a, 'mp:start').clock > 0, 'mp:start says how long the move clock is');
    a.handlers['mp:concede']({ matchId: last(a, 'mp:start').matchId });
    check(await until(() => last(a, 'mp:over') && last(b, 'mp:over')), 'alice concedes, the match ends');
    a.got.length = 0; b.got.length = 0;
    await a.handlers['mp:rematch']();
    check(!!last(a, 'mp:rematch_sent'), 'alice asks for a rematch');
    check(last(b, 'mp:rematch_offer')?.fromUsername === 'alice', 'bob is offered it');
    check(!last(a, 'mp:rps'), 'nothing starts until bob agrees');
    await b.handlers['mp:rematch']();
    check(await playRps(a, b), 'bob agrees: Scissors Paper Rock again, then the rematch starts');

    // 2. Declining: the other is told, and can't ask again
    a.handlers['mp:concede']({ matchId: last(a, 'mp:start').matchId });
    await until(() => count(b, 'mp:over') >= 2);
    a.got.length = 0; b.got.length = 0;
    await b.handlers['mp:rematch']();
    a.handlers['mp:rematch_decline']();
    check(last(b, 'mp:rematch_declined')?.message === 'Your opponent left.', 'bob hears alice left');
    await b.handlers['mp:rematch']();
    check(!last(a, 'mp:rematch_offer') || count(a, 'mp:rematch_offer') === 1, 'no new offer after the decline');
    check(/expired/.test(last(b, 'mp:rematch_declined').message), 'asking again says the offer is over');

    // 3. A player who stops playing: shorter clock once auto-played, then they lose
    const c = fakeSocket(), d = fakeSocket();
    svc.register(c, { playerId: 'carol', username: 'carol' });
    svc.register(d, { playerId: 'dave', username: 'dave' });
    await startPair('carol', 'dave', c, d);
    // carol went first; nobody acts at all
    check(await until(() => c.got.some(([e, m]) => e === 'mp:update' && m.away === true)), 'after an auto-played move the update says the player is away');
    check(await until(() => last(c, 'mp:over'), 15000), 'an idle player eventually loses');
    const over = last(c, 'mp:over');
    check(over?.reason === 'afk', `the reason is afk (got ${over?.reason})`);
    const overD = last(d, 'mp:over');
    check(overD && overD.result !== over.result, 'one wins, one loses');

    console.log(bad ? `${bad} problem(s)` : 'all good');
    process.exit(bad ? 1 : 0);
})();
