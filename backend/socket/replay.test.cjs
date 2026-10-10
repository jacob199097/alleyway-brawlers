// Run: node backend/socket/replay.test.cjs
// Plays CPU matches through the real online service (fake sockets, instant timers), then checks
// that replaySteps() rebuilds exactly what the human saw live. Also checks emotes are relayed.
const path = require('path');
const root = process.argv[2] || path.join(__dirname, "../..");
global.setTimeout = (fn) => setImmediate(fn);
global.clearTimeout = (t) => t && clearImmediate(t);
const { createOnlineService, replaySteps } = require(path.join(root, 'backend/socket/onlineMatch.js'));

function fakeSocket() {
    const handlers = {}, got = [];
    return { handlers, got, on: (ev, fn) => { handlers[ev] = fn; }, emit: (ev, data) => got.push([ev, JSON.parse(JSON.stringify(data))]) };
}
const norm = (x) => JSON.stringify(x);
function dpath(a,b,p=""){if(JSON.stringify(a)===JSON.stringify(b))return null;if(a&&b&&typeof a==="object"&&typeof b==="object"){for(const k of new Set([...Object.keys(a),...Object.keys(b)])){const d=dpath(a[k],b[k],p+"."+k);if(d)return d;}}return p+": "+JSON.stringify(a)?.slice(0,200)+"  vs  "+JSON.stringify(b)?.slice(0,200);}

(async () => {
    const { cpuSetup } = await import('file:///' + path.join(root, 'shared/duel/DuelAI.js').replace(/\\/g, '/'));
    const records = [];
    const svc = createOnlineService(null, {
        loadSetup: async () => cpuSetup(),
        loadProfile: async (id) => ({ username: id, level: 1, avatar_url: 'profile_001' }),
        resolveMatch: async () => ({}), resolveCpuMatch: async () => ({}),
        saveReplay: async (rec) => { records.push(JSON.parse(JSON.stringify(rec))); },
    });
    let bad = 0;
    for (const difficulty of ['easy', 'normal', 'hard']) {
        const sock = fakeSocket();
        svc.register(sock, { playerId: 'human-' + difficulty });
        await sock.handlers['mp:cpu']({ ranked: false, difficulty });
        for (let i = 0; i < 2000 && !sock.got.some(([e]) => e === 'mp:over'); i++) await new Promise(r => setImmediate(r));
        const live = sock.got.filter(([e]) => e === 'mp:start' || e === 'mp:update').map(([, d]) => d);
        const over = sock.got.find(([e]) => e === 'mp:over');
        const rec = records[records.length - 1];
        if (!over || !rec) { console.log(difficulty, 'no result'); bad++; continue; }
        const r = await replaySteps(rec, 'player');
        const startOk = norm(r.start.view) === norm(live[0].view);
        const liveUpdates = live.slice(1).filter(u => !u.resync);
        let firstDiff = -1;
        for (let i = 0; i < Math.max(liveUpdates.length, r.updates.length); i++) {
            const a = liveUpdates[i], b = r.updates[i];
            if (!a || !b || norm(a.events) !== norm(b.events) || norm(a.view) !== norm(b.view)) { firstDiff = i; break; }
        }
        if (firstDiff >= 0) { const a = liveUpdates[firstDiff], b = r.updates[firstDiff]; console.log("ACT", JSON.stringify(rec.actions[firstDiff - 1]), "LIVE EV", JSON.stringify(a.events.map(e => e.type)), "REPLAY EV", JSON.stringify(b.events.map(e => e.type))); console.log("DIFF", dpath(a && {e: a.events, v: a.view}, b && {e: b.events, v: b.view})); }
        const ok = startOk && firstDiff < 0 && r.complete && r.over.result === over[1].result;
        if (!ok) bad++;
        console.log(`${difficulty}: ${rec.actions.length} actions, ${liveUpdates.length} updates, result ${over[1].result}, ` +
            `replay ${ok ? 'MATCHES' : `DIFFERS (start ${startOk}, first diff ${firstDiff}, complete ${r.complete})`}`);
    }
    // Emotes between two players
    const a = fakeSocket(), b = fakeSocket();
    svc.register(a, { playerId: 'alice' });
    svc.register(b, { playerId: 'bob' });
    await a.handlers['mp:queue']();
    await b.handlers['mp:queue']();
    // Emote as soon as it starts: with instant timers nobody acting soon loses for being away
    for (let i = 0; i < 50 && !a.got.some(([e]) => e === 'mp:start'); i++) await new Promise(r => setImmediate(r));
    const start = a.got.find(([e]) => e === 'mp:start');
    if (start) {
        const id = start[1].matchId;
        a.handlers['mp:emote']({ matchId: id, key: 'gg' });
        a.handlers['mp:emote']({ matchId: id, key: 'gg' });          // too soon: dropped
        a.handlers['mp:emote']({ matchId: id, key: 'free text' });   // not on the list: dropped
        const got = b.got.filter(([e]) => e === 'mp:emote');
        console.log(`emotes: bob got ${got.length} (${got.map(([, d]) => d.key).join(',')}), expected 1 (gg)`);
        if (got.length !== 1) bad++;
    } else { console.log('emote test: no match started'); bad++; }
    console.log(bad ? `${bad} problem(s)` : 'all good');
    process.exit(bad ? 1 : 0);
})();
