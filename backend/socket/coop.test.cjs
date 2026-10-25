// Run: node backend/socket/coop.test.cjs
// Turf Defense (socket/coopMatch.js): quick match pairs two players waiting for the same boss level
// (locked levels refused, the others online told someone's looking), each player's view from their
// own seat (player / ally / boss, hands hidden, the boss's Morale), a whole match to the end with both
// players paid together, partner emotes, and a player who goes out watching their partner fight on.
const path = require('path');
const { createCoopService, namesFor } = require(path.join(__dirname, 'coopMatch.js'));
const { rename } = require(path.join(__dirname, 'ffaMatch.js'));

function fakeSocket() {
    const handlers = {}, got = [];
    return { handlers, got, connected: true, on: (ev, fn) => { handlers[ev] = fn; },
        emit: (ev, data) => got.push([ev, JSON.parse(JSON.stringify(data))]) };
}
const wait = (ms) => new Promise(r => setTimeout(r, ms));
async function until(fn, ms = 20000) {
    const t = Date.now();
    while (!fn()) { if (Date.now() - t > ms) return false; await wait(20); }
    return true;
}
const last = (s, ev) => [...s.got].reverse().find(([e]) => e === ev)?.[1];

(async () => {
    const { cpuSetup, choose } = await import('file:///' + path.join(__dirname, '../../shared/duel/DuelAI.js').replace(/\\/g, '/'));
    const paid = [];
    const clears = { ann: {}, ben: {}, cat: {}, dan: { archon: { 1: { clears: 1 } } } };
    const svc = createCoopService(null, {
        loadSetup: async () => cpuSetup('militia'),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        loadClears: async (id) => clears[id] || {},
        resolveTurf: async (r) => { paid.push(r); return { won: r.won, first: true, karatEarned: r.won ? 300 : 15, prize: r.won && r.level === 1 ? 'card_nebu_048' : null }; },
        turnSecs: 5, awaySecs: 1, botMoveMs: 1, botEventMs: 0,
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };
    const join = (id) => {
        const s = fakeSocket();
        svc.register(s, { playerId: id, username: id });
        return s;
    };
    const [a, b, c, d] = ['ann', 'ben', 'cat', 'dan'].map(join);

    // 1. Locked levels are refused; a level that's open puts you in the queue and tells the others
    await a.handlers['coop:queue']({ boss: 'archon', level: 2 });
    check(/first/.test(last(a, 'coop:error')?.message || ''), 'level 2 is locked until level 1 is beaten');
    await a.handlers['coop:queue']({ boss: 'nobody', level: 1 });
    check(!!last(a, 'coop:error'), 'an unknown boss is refused');
    await a.handlers['coop:queue']({ boss: 'archon', level: 1 });
    check(last(a, 'coop:queue')?.boss === 'archon', 'queued for the Archon, Street');
    check(last(b, 'coop:looking')?.username === 'ann' && last(b, 'coop:looking').boss === 'archon', 'the others hear ann is looking');
    check(!last(a, 'coop:looking'), "ann doesn't hear about herself");
    check(svc.waiting()['archon:1'] === 1, 'one waiting for archon:1');
    await d.handlers['coop:queue']({ boss: 'archon', level: 2 });
    check(last(d, 'coop:queue')?.level === 2, 'dan beat level 1, so level 2 is open to him');
    d.handlers['coop:leave']();
    check(!svc.waiting()['archon:2'], 'leaving the queue takes you out');

    // 2. A second player for the same boss level: the match starts for both
    await b.handlers['coop:queue']({ boss: 'archon', level: 1 });
    check(await until(() => last(a, 'coop:start') && last(b, 'coop:start')), 'paired: the match starts for both');
    check(!svc.waiting()['archon:1'], 'nobody left waiting');
    const st = last(a, 'coop:start');
    check(st.mode === 'coop' && st.boss.id === 'archon' && st.boss.morale === 9000 && st.boss.lines?.intro?.length, 'the boss info (Morale, lines) comes with it');
    check(Object.keys(st.players).sort().join() === 'ally,boss,player', 'players: you, your ally, the boss');
    check(st.players.boss.boss && st.players.ally.username === 'ben', 'ben is ann\'s ally');
    check(!/"p[12]"/.test(JSON.stringify([st.view, st.players])), 'no server seat names reach the client');
    check(Object.keys(st.view.sides).sort().join() === 'ally,boss,player' && st.view.seats.length === 3, 'every board and the turn order');
    check(st.view.sides.boss.max_morale === 9000 && st.view.sides.player.max_morale === 6000, "each side's most Morale");
    check(st.view.teams.player === st.view.teams.ally && st.view.teams.boss !== st.view.teams.player, 'the teams');
    check(st.view.sides.ally.hand.every(x => Object.keys(x).join() === 'uid'), "your ally's hand is hidden");
    check(st.view.sides.player.hand.every(x => x.id), 'your own hand is shown');

    // 3. Partner emotes: only to your partner, only from the list
    const match = [...svc._matches.values()][0];
    a.handlers['coop:emote']({ matchId: match.id, key: 'boss' });
    check(last(b, 'coop:emote')?.key === 'boss' && !last(a, 'coop:emote'), 'an emote reaches the partner');
    b.handlers['coop:emote']({ matchId: match.id, key: 'free text!' });
    check(!last(a, 'coop:emote'), 'only listed emotes');

    // 4. Play it out: the players' moves (the CPU's choice on the real state) in their own names
    const sockOf = { ann: a, ben: b };
    let moves = 0;
    while (!match.over && moves < 12000) {
        const state = match.state;
        const seat = state.pending.side || state.active;
        const s = match.seats[seat];
        if (s.bot) {
            await wait(2);
            continue;
        }
        let action = choose(state, seat, 'normal');
        if (!Object.keys(action).length) action = { kind: 'next' };
        sockOf[s.playerId].handlers['coop:action']({ matchId: match.id, action: rename(action, namesFor(seat)) });
        moves += 1;
        await wait(0);
    }
    check(match.over, `the match ends (${moves} moves, ${match.state.winner === 'boss' ? 'the boss' : 'the crew'} won)`);
    check(await until(() => last(a, 'coop:over') && last(b, 'coop:over')), 'both hear the result');
    const over = last(a, 'coop:over');
    check(over.won === last(b, 'coop:over').won && over.won === (match.state.winner !== 'boss'), 'they win or lose together');
    check(paid.length === 2 && paid.every(r => r.bossId === 'archon' && r.level === 1 && r.won === over.won), 'both are paid, for the right boss level');
    check(over.rewards?.karatEarned > 0 && over.boss.id === 'archon', 'the result has the rewards');
    check(!svc.isBusy('ann') && !svc.isBusy('ben'), 'both are free again');

    // 5. One player goes out: the other fights on; the result comes to both at the end
    await c.handlers['coop:queue']({ boss: 'veyr', level: 1 });
    await a.handlers['coop:queue']({ boss: 'veyr', level: 1 });
    check(await until(() => last(c, 'coop:start')?.boss.id === 'veyr'), 'a second match (Veyr)');
    const m2 = [...svc._matches.values()][0];
    const seatC = Object.keys(m2.seats).find(s => m2.seats[s].playerId === 'cat');
    c.handlers['coop:concede']({ matchId: m2.id });
    check(m2.state.sides[seatC].out && !m2.over, 'cat gives up: the match goes on for ann');
    a.handlers['coop:concede']({ matchId: m2.id });
    check(await until(() => m2.over), 'both out: the boss wins');
    check(await until(() => last(c, 'coop:over')?.won === false && last(a, 'coop:over')?.won === false), 'both hear they lost');

    console.log(bad ? `\n${bad} check(s) FAILED` : '\ncoop: all ok');
    process.exit(bad ? 1 : 0);
})().catch(err => { console.error(err); process.exit(1); });
