// Run: node backend/socket/ranked.test.cjs
// Ranked Brawl is player against player only (onlineMatch.js): its own queue (never matched with
// Casual), from level 5, Rank Points in the result; the old Ranked-vs-CPU request is refused.
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
    const resolved = [];
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: id === 'newbie' ? 3 : 10, avatar_url: 'profile_001' }),
        resolveMatch: async (args) => { resolved.push(args); return {}; },
        resolveCpuMatch: async () => ({}),
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };
    const join = (id) => { const s = fakeSocket(); svc.register(s, { playerId: id, username: id }); return s; };

    // 1. A Ranked player and a Casual player aren't matched with each other
    const r1 = join('rhea'), c1 = join('cole');
    await r1.handlers['mp:queue']({ ranked: true });
    await c1.handlers['mp:queue']();
    check(last(r1, 'mp:queued')?.ranked === true, 'rhea is in the Ranked queue');
    check(last(c1, 'mp:queued')?.ranked === false, 'cole is in the Casual queue');
    await wait(100);
    check(!last(r1, 'mp:rps') && !last(c1, 'mp:rps'), 'Ranked and Casual players are not matched together');

    // 2. A second Ranked player is matched with the first, in a ranked match
    const r2 = join('remy');
    await r2.handlers['mp:queue']({ ranked: true });
    check(await until(() => last(r1, 'mp:rps') && last(r2, 'mp:rps')), 'two Ranked players are matched');
    check(last(r1, 'mp:rps').mode === 'ranked', 'it is a Ranked match');
    check(!last(c1, 'mp:rps'), 'the Casual player is still waiting');

    // 3. Under level 5: refused
    const n = join('newbie');
    await n.handlers['mp:queue']({ ranked: true });
    check(/level 5/.test(last(n, 'mp:error')?.message || ''), 'under level 5 can\'t queue for Ranked');
    check(!last(n, 'mp:queued'), 'and isn\'t queued');

    // 4. The old Ranked-vs-CPU request is refused (VS CPU still works)
    const o = join('olga');
    await o.handlers['mp:cpu']({ ranked: true });
    check(/other players/.test(last(o, 'mp:error')?.message || ''), 'Ranked against the CPU is refused');
    check(!last(o, 'mp:start'), 'no CPU match starts');

    // 5. Ranked match plays out: the result is rewarded as ranked (Rank Points)
    const id = last(r1, 'mp:rps').rpsId;
    r1.handlers['mp:rps_pick']({ rpsId: id, pick: 'paper' });
    r2.handlers['mp:rps_pick']({ rpsId: id, pick: 'rock' });
    check(await until(() => last(r1, 'mp:rps_choose')), 'Scissors Paper Rock decides who goes first');
    r1.handlers['mp:rps_first']({ rpsId: id, goFirst: true });
    check(await until(() => last(r1, 'mp:start') && last(r2, 'mp:start')), 'the Ranked match starts');
    check(last(r1, 'mp:start').mode === 'ranked', 'the match is Ranked');
    r2.handlers['mp:concede']({ matchId: last(r2, 'mp:start').matchId });
    check(await until(() => resolved.length > 0), 'the result is rewarded');
    check(resolved[0]?.matchMeta?.ranked === true && resolved[0]?.winnerId === 'rhea', 'as a Ranked win for rhea (Rank Points)');

    console.log(bad ? `\n${bad} check(s) failed` : '\nRanked queue: all good');
    process.exit(bad ? 1 : 0);
})().catch((err) => { console.error(err); process.exit(1); });
