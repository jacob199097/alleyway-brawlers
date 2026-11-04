// Run: node backend/socket/ranked.test.cjs
// Ranked Brawl is player against player only (onlineMatch.js): its own queue (never matched with
// Casual), from level 5, Rank Points in the result; the old Ranked-vs-CPU request is refused.
// A Ranked match and its rematches are a best of 3: Rank Points follow the series score, and once
// it is decided a rematch is friendly.
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
        // (Rank Points as economy/postMatch.js moves them: to what the series score is worth)
        resolveMatch: async (args) => {
            resolved.push(args);
            const s = args.matchMeta.series, out = {};
            for (const id of [args.p1Id, args.p2Id]) out[id] = { rankPointDelta: !s ? 0 : (!s.leader ? 0 : s.leader === id ? 25 : -10) - (s.applied[id] || 0) };
            return out;
        },
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
    check(await until(() => last(r1, 'mp:over')), 'the result reaches the players');
    let rp = { rhea: 0, remy: 0 };
    const series = (s) => last(s, 'mp:over')?.series;
    check(series(r1)?.game === 1 && series(r1).you === 1 && series(r2).you === 0 && !series(r1).over, 'game 1 of a best of 3: rhea leads 1-0');
    check(series(r1).rankPoints === 25 && series(r2).rankPoints === -10, 'the leader holds a win\'s Rank Points (+25 / -10)');

    // 6. The rematch is the next game of the series, still Ranked; game 2 to remy levels it (Rank Points undone)
    const nth = (s, ev) => s.got.filter(([e]) => e === ev).length;
    async function game(winner, loser, n) {
        const rpsSeen = nth(r1, 'mp:rps'), chooseSeen = nth(r1, 'mp:rps_choose'), startSeen = nth(loser, 'mp:start'), overSeen = nth(r1, 'mp:over');
        loser.handlers['mp:rematch']();
        check(last(winner, 'mp:rematch_offer')?.ranked === true && last(winner, 'mp:rematch_offer').game === n, 'game ' + n + ': the rematch offer is the next game of the series');
        winner.handlers['mp:rematch']();
        check(await until(() => nth(r1, 'mp:rps') > rpsSeen && nth(r2, 'mp:rps') > rpsSeen), 'game ' + n + ': Scissors Paper Rock again');
        check(last(r1, 'mp:rps').mode === 'ranked', 'game ' + n + ' is Ranked');
        const rid = last(r1, 'mp:rps').rpsId;
        r1.handlers['mp:rps_pick']({ rpsId: rid, pick: 'paper' });
        r2.handlers['mp:rps_pick']({ rpsId: rid, pick: 'rock' });
        await until(() => nth(r1, 'mp:rps_choose') > chooseSeen);
        r1.handlers['mp:rps_first']({ rpsId: rid, goFirst: true });
        check(await until(() => nth(loser, 'mp:start') > startSeen), 'game ' + n + ' starts');
        loser.handlers['mp:concede']({ matchId: last(loser, 'mp:start').matchId });
        check(await until(() => nth(r1, 'mp:over') > overSeen && nth(r2, 'mp:over') > overSeen), 'game ' + n + ' is over');
    }
    await game(r2, r1, 2);
    check(series(r1)?.game === 2 && series(r1).you === 1 && series(r1).them === 1 && !series(r1).over, 'game 2 to remy: 1-1, not over');
    check(series(r1).rankPoints === 0 && series(r2).rankPoints === 0, 'a level series is worth no Rank Points');
    check(resolved.at(-1).matchMeta.series?.leader === null, 'the server was told the series is level');

    // 7. Game 3 decides it; after that a rematch is friendly
    await game(r1, r2, 3);
    check(series(r1)?.game === 3 && series(r1).you === 2 && series(r1).over, 'game 3 to rhea: she wins the series 2-1');
    check(series(r1).rankPoints === 25 && series(r2).rankPoints === -10, 'one series win\'s Rank Points in all (+25 / -10)');
    const before = nth(r1, 'mp:rps');
    r2.handlers['mp:rematch']();
    check(last(r1, 'mp:rematch_offer')?.ranked === false, 'once decided, the rematch offered is friendly');
    r1.handlers['mp:rematch']();
    check(await until(() => nth(r1, 'mp:rps') > before) && last(r1, 'mp:rps').mode === 'friendly', 'and it is');

    console.log(bad ? `\n${bad} check(s) failed` : '\nRanked queue: all good');
    process.exit(bad ? 1 : 0);
})().catch((err) => { console.error(err); process.exit(1); });
