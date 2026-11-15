// Run: node backend/socket/contracts.test.cjs
// Contracts in matches (onlineMatch.js with economy/contracts.js): an eligible match (CPU on Normal) shows the
// player their contract at the start; done during the match, it's paid then and the player's update carries a
// "contract" event; not done, the match counts as one of its matches; an Easy CPU match leaves it alone.
const path = require('path');
const { createOnlineService } = require(path.join(__dirname, 'onlineMatch.js'));
const { GOALS } = require(path.join(__dirname, '../economy/contract_settings.js'));

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
    // Two goals for the test: one done by the opening hand, one that can't be done in a conceded match
    GOALS.test_draw = { text: 'Draw a card', price: 10, payout: 25, need: 1, count: (ev, me) => ev.type === 'draw' && ev.side === me };
    GOALS.test_never = { text: 'Never', price: 10, payout: 25, need: 99, count: () => false };
    const contract = { goal: 'test_draw' };
    const paid = [], played = [];
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 10, avatar_url: 'profile_001' }),
        resolveMatch: async () => ({}),
        resolveCpuMatch: async () => ({}),
        botMoveMs: 0, botEventMs: 0,
        activeContract: async () => ({ id: 7, goal: contract.goal, text: GOALS[contract.goal].text, price: 10, payout: 25, matches_left: 3, win: false }),
        completeContract: async (playerId, id) => { paid.push([playerId, id]); return { payout: 25, karat: 125 }; },
        contractMatchPlayed: async (playerId, id) => { played.push([playerId, id]); return { status: 'active', matches_left: 2 }; },
    });
    let bad = 0;
    const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };
    const join = (id) => { const s = fakeSocket(); svc.register(s, { playerId: id, username: id }); return s; };

    // 1. Done by the opening hand: shown at the start, paid, and a "contract" event in the update
    const p = join('pia');
    await p.handlers['mp:cpu']({ difficulty: 'normal' });
    check(await until(() => last(p, 'mp:start')), 'the CPU match starts');
    const start = last(p, 'mp:start');
    check(start.contract && start.contract.text === 'Draw a card' && start.contract.payout === 25 && start.contract.matches_left === 3, 'the contract is shown at the start');
    check(await until(() => paid.length === 1), 'done: paid');
    check(paid[0][0] === 'pia' && paid[0][1] === 7, 'the right contract, to the right player');
    const told = p.got.filter(([e, d]) => e === 'mp:update' && (d.events || []).some(ev => ev.type === 'contract' && ev.status === 'done'));
    check(told.length === 1, 'the player is told once, in their update');
    p.handlers['mp:concede']({ matchId: start.matchId });
    check(await until(() => last(p, 'mp:over')), 'the match is over');
    check(last(p, 'mp:over').contract?.status === 'done' && played.length === 0, 'a done contract uses up no match');
    check(paid.length === 1, 'and is never paid twice');

    // 2. Not done: the match counts as one of its matches
    contract.goal = 'test_never';
    const q = join('quin');
    await q.handlers['mp:cpu']({ difficulty: 'hard' });
    check(await until(() => last(q, 'mp:start')), 'a Hard CPU match starts');
    check(!!last(q, 'mp:start').contract, 'with the contract');
    q.handlers['mp:concede']({ matchId: last(q, 'mp:start').matchId });
    check(await until(() => last(q, 'mp:over')), 'it is over');
    check(played.length === 1 && played[0][1] === 7, 'one of its matches is used up');
    check(last(q, 'mp:over').contract?.matches_left === 2, 'the player sees how many are left');

    // 3. An Easy CPU match doesn't count
    const r = join('rob');
    await r.handlers['mp:cpu']({ difficulty: 'easy' });
    check(await until(() => last(r, 'mp:start')), 'an Easy CPU match starts');
    check(last(r, 'mp:start').contract === null, 'no contract in it');
    r.handlers['mp:concede']({ matchId: last(r, 'mp:start').matchId });
    check(await until(() => last(r, 'mp:over')), 'it is over');
    check(played.length === 1 && last(r, 'mp:over').contract === null, 'and the contract is left alone');

    console.log(bad ? `${bad} FAILED` : 'contracts in matches: all passed');
    process.exit(bad ? 1 : 0);
})();
