// Run: node backend/socket/ffa.test.cjs
// Free-for-all (socket/ffaMatch.js): the lobby (ready up, the timer, CPUs filling to 3, 4 ready
// starts at once), each player's view from their own seat with hands hidden, a whole game to the end
// with places and results, and conceding.
const path = require('path');
const { createFfaService, namesFor, rename } = require(path.join(__dirname, 'ffaMatch.js'));

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

(async () => {
    const { cpuSetup, choose } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelAI.js').replace(/\\/g, '/'));
    const results = [];
    const svc = createFfaService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        resolveFfa: async (r) => { results.push(r); return { place: r.place, karatEarned: r.place === 1 ? 40 : 10 }; },
        lobbySecs: 0.6, turnSecs: 5, awaySecs: 1, botMoveMs: 1, botEventMs: 0,
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };
    const join = (id) => {
        const s = fakeSocket();
        svc.register(s, { playerId: id, username: id });
        return s;
    };

    // 1. Three players: the lobby lists them; it waits for the timer (not 4 yet), then starts with 3
    const [a, b, c] = ['ann', 'ben', 'cat'].map(join);
    for (const s of [a, b, c]) await s.handlers['ffa:queue']();
    const lob = last(c, 'ffa:lobby');
    check(lob?.players.length === 3 && lob.min === 3 && lob.max === 4, 'the lobby lists all three (3-4 players)');
    check(lob.players.filter(p => p.you).length === 1 && lob.players.find(p => p.you).username === 'cat', 'each sees which one is them');
    for (const s of [a, b, c]) s.handlers['ffa:ready']({ ready: true });
    check(!last(a, 'ffa:start'), "three ready doesn't start early (a fourth could still join)");
    check(await until(() => last(a, 'ffa:start') && last(b, 'ffa:start') && last(c, 'ffa:start')), 'the timer runs out: the match starts');
    const st = last(a, 'ffa:start');
    check(Object.keys(st.players).sort().join() === 'foe1,foe2,player', 'players: you and foe1, foe2');
    check(!Object.values(st.players).some(p => p.cpu), 'no CPUs needed with 3 people');
    check(!/"p[1-4]"/.test(JSON.stringify([st.view, st.players])), 'no server seat names reach the client');
    check(Object.keys(st.view.sides).sort().join() === 'foe1,foe2,player' && st.view.seats.length === 3, 'the view has every board and the turn order');
    check(st.view.sides.foe1.hand.every(x => Object.keys(x).join() === 'uid'), "the others' hands are hidden");
    check(st.view.sides.player.hand.every(x => x.id), 'your own hand is shown');

    // 2. Play it out: each player's moves (chosen by the CPU on the real state) sent in their own names
    const match = [...svc._matches.values()][0];
    const sockOf = { ann: a, ben: b, cat: c };
    let moves = 0;
    while (!match.over && moves < 8000) {
        const state = match.state;
        const seat = state.pending.side || state.active;
        const s = match.seats[seat];
        let action = choose(state, seat, 'normal');
        if (!Object.keys(action).length) action = { kind: 'next' };
        const mine = rename(action, namesFor(state.seats, seat));
        sockOf[s.playerId].handlers['ffa:action']({ matchId: match.id, action: mine });
        moves += 1;
        await wait(0);
    }
    check(match.over, `the game ends (${moves} moves)`);
    check(await until(() => [a, b, c].every(s => last(s, 'ffa:over'))), 'everyone hears the result');
    const places = [a, b, c].map(s => last(s, 'ffa:over').place).sort();
    check(places.join() === '1,2,3', `places 1, 2 and 3 (got ${places})`);
    const out = [a, b, c].filter(s => last(s, 'ffa:out'));
    // (the last one out goes out on the final blow: they hear the result with everyone else)
    check(out.length === 1 && last(out[0], 'ffa:out').place === 3, 'the first one out (3rd) heard it straight away (ffa:out)');
    check(out.every(s => last(s, 'ffa:out').place === last(s, 'ffa:over').place), "and their place didn't change");
    check(results.length === 3 && results.every(r => r.humans === 3), 'everyone is rewarded once, as a 3-person game');
    const win = [a, b, c].find(s => last(s, 'ffa:over').place === 1);
    check(last(win, 'ffa:over').places.player === 1, 'the winner sees themself in 1st');
    check(!/"p[1-4]"/.test(JSON.stringify(a.got.filter(([e]) => e.startsWith('ffa:')))), 'no seat names in any message to a player');

    // 3. On your own: CPUs fill the seats up to 3; someone not ready drops out
    const d = join('dan'), e = join('eve');
    await d.handlers['ffa:queue']();
    await e.handlers['ffa:queue']();
    d.handlers['ffa:ready']({ ready: true });
    check(await until(() => last(d, 'ffa:start')), 'dan starts after the timer');
    check(last(e, 'ffa:left')?.reason?.includes('ready'), "eve wasn't ready: she's told and left out");
    const ds = last(d, 'ffa:start');
    check(Object.values(ds.players).filter(p => p.cpu).length === 2, 'two CPUs fill the empty seats');
    const solo = [...svc._matches.values()].find(m => m.seats.p1?.playerId === 'dan' || Object.values(m.seats).some(x => x.playerId === 'dan'));
    check(solo.humans === 1, 'a game with one person in it');
    d.handlers['ffa:concede']({ matchId: ds.matchId });
    check(await until(() => last(d, 'ffa:out')), 'conceding puts dan out');
    check(await until(() => solo.over, 20000), 'the CPUs play on to the end');
    check(await until(() => last(d, 'ffa:over')), 'dan, still watching, hears the end');

    // 4. Four ready: it starts at once
    const four = ['f1', 'f2', 'f3', 'f4'].map(join);
    for (const s of four) await s.handlers['ffa:queue']();
    for (const s of four) s.handlers['ffa:ready']({ ready: true });
    check(await until(() => four.every(s => last(s, 'ffa:start')), 300), 'four ready: no waiting for the timer');
    check(Object.keys(last(four[0], 'ffa:start').players).length === 4, 'a 4-player game');
    // Busy players can't queue again
    await four[0].handlers['ffa:queue']();
    check(/already/.test(last(four[0], 'ffa:error')?.message || ''), "a player in a match can't queue again");
    // Quitting after going out: no more updates
    const m4 = [...svc._matches.values()].find(m => Object.keys(m.seats).length === 4);
    four[0].handlers['ffa:quit']();
    const before = four[0].got.length;
    await wait(200);
    check(m4.state.sides[Object.keys(m4.seats).find(k => m4.seats[k].playerId === 'f1')].out > 0, 'quitting a game you are in puts you out');
    check(four[0].got.filter(([ev]) => ev === 'ffa:update').length === four[0].got.slice(0, before).filter(([ev]) => ev === 'ffa:update').length, 'and the updates stop');

    console.log(bad ? `${bad} problem(s)` : 'all good');
    process.exit(bad ? 1 : 0);
})();
