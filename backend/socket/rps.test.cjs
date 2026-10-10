// Run: node backend/socket/rps.test.cjs
// Scissors Paper Rock before matches against players (onlineMatch.js): a draw replays the round,
// the winner's "go second" choice is honoured, and a player leaving mid-way requeues the other.
const path = require('path');
const { createOnlineService } = require(path.join(__dirname, 'onlineMatch.js'));

function fakeSocket() {
    const handlers = {}, got = [];
    return { handlers, got, connected: true, on: (ev, fn) => { handlers[ev] = fn; },
        emit: (ev, data) => got.push([ev, JSON.parse(JSON.stringify(data))]) };
}
const wait = (ms) => new Promise(r => setTimeout(r, ms));
async function until(fn, ms = 8000) {
    const t = Date.now();
    while (!fn()) { if (Date.now() - t > ms) return false; await wait(20); }
    return true;
}
const last = (s, ev) => [...s.got].reverse().find(([e]) => e === ev)?.[1];

(async () => {
    const { cpuSetup } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelAI.js').replace(/\\/g, '/'));
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        resolveMatch: async () => ({}),
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

    // 1. Queue two players: draw, then alice wins and chooses to go second
    const a = fakeSocket(), b = fakeSocket();
    svc.register(a, { playerId: 'alice' });
    svc.register(b, { playerId: 'bob' });
    await a.handlers['mp:queue']();
    await b.handlers['mp:queue']();
    check(await until(() => last(a, 'mp:rps') && last(b, 'mp:rps')), 'both players get mp:rps');
    let id = last(a, 'mp:rps').rpsId;
    check(last(a, 'mp:rps').opponent.username === 'bob', 'alice sees bob as the opponent');
    a.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
    b.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
    check(last(a, 'mp:rps_result')?.outcome === 'draw', 'same throw is a draw');
    check(await until(() => last(a, 'mp:rps')?.round === 2), 'a draw starts round 2');
    a.handlers['mp:rps_pick']({ rpsId: id, pick: 'paper' });
    b.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
    check(last(a, 'mp:rps_result')?.outcome === 'win' && last(b, 'mp:rps_result')?.outcome === 'loss', 'paper beats rock');
    check(await until(() => last(a, 'mp:rps_choose')), 'the winner is asked first or second');
    check(!last(b, 'mp:rps_choose'), 'the loser is not asked');
    a.handlers['mp:rps_first']({ rpsId: id, goFirst: false });
    check(last(a, 'mp:rps_decided')?.first === 'opponent' && last(b, 'mp:rps_decided')?.first === 'you', 'alice went second, bob first');
    check(await until(() => last(a, 'mp:start') && last(b, 'mp:start')), 'the match starts');
    const viewA = last(a, 'mp:start').view;
    check(viewA.active === 'opponent', 'in the match bob (alice\'s opponent) is first');

    // 2. Friend challenge, then one leaves during Scissors Paper Rock
    const c = fakeSocket(), d = fakeSocket();
    svc.register(c, { playerId: 'carol' });
    svc.register(d, { playerId: 'dave' });
    svc.register(fakeSocket(), { playerId: 'erin' });
    c.handlers['mp:challenge']({ targetPlayerId: 'dave' });
    await d.handlers['mp:accept']({ fromPlayerId: 'carol' });
    check(await until(() => last(c, 'mp:rps') && last(d, 'mp:rps')), 'a friend challenge starts with Scissors Paper Rock');
    check(last(c, 'mp:rps').mode === 'friendly', 'mode is friendly');
    d.handlers['disconnect']();
    check(last(c, 'mp:rps_cancel') && last(c, 'mp:rps_cancel').requeued === false, 'the other player is told the match is off');
    check(!svc.isInMatch('carol'), 'carol is free again');

    console.log(bad ? `${bad} problem(s)` : 'all good');
    process.exit(bad ? 1 : 0);
})();
