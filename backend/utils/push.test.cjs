// Run: node backend/utils/push.test.cjs
// Phone notifications (utils/push.js) without a database or Google: the message sent to FCM, the signed
// sign-in to Google, what a dead token looks like, and which reminders are due at which hour on the phone.
const crypto = require('crypto');
const push = require('./push');

let bad = 0;
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

(async () => {
    // The hour on the phone's clock, and a reward in words
    const at = new Date('2026-11-15T08:30:00Z');
    check(push.localHour(at, 600) === 18, 'UTC+10 at 08:30 UTC is 6 pm');
    check(push.localHour(at, -480) === 0, 'UTC-8 at 08:30 UTC is just after midnight');
    check(push.localHour(at, -540) === 23, 'UTC-9: the hour before');
    check(push.rewardText({ karat: 150 }) === '150 Karat', 'a reward in words');
    check(push.rewardText({ karat: 300, free_packs: 1 }) === 'a free pack and 300 Karat', 'a pack and Karat');

    // The message: an Android notification on its kind's channel; invites go out at high priority
    const m = push.message('tok123', { kind: 'invites', title: 'Ana wants to brawl', body: 'Open the game.' });
    check(m.message.token === 'tok123' && m.message.notification.title === 'Ana wants to brawl', 'the token, title and text');
    check(m.message.android.notification.channel_id === 'invites' && m.message.android.priority === 'high', 'on the invites channel, high priority');
    check(push.message('t', { kind: 'daily', title: 'x', body: 'y' }).message.android.priority === 'normal', 'reminders at normal priority');

    // Signing in to Google with the service account: a JWT signed with its key, exchanged for an access token
    const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    push._reset({ client_email: 'push@test.iam.gserviceaccount.com', project_id: 'alleyway-test',
        private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
    const calls = [];
    let fcmReply = { status: 200, body: { name: 'projects/x/messages/1' } };
    const fake = async (url, body, headers) => {
        calls.push({ url, body, headers });
        if (url.includes('oauth2')) return { status: 200, body: { access_token: 'ya29.test', expires_in: 3600 } };
        return fcmReply;
    };
    check(await push.sendTo('tok123', { kind: 'daily', title: 'Your daily reward is ready', body: 'Day 2' }, fake) === 'ok', 'a message goes out');
    const jwt = new URLSearchParams(calls[0].body).get('assertion');
    const [h, c, s] = jwt.split('.');
    const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
    check(crypto.verify('RSA-SHA256', Buffer.from(`${h}.${c}`), publicKey, Buffer.from(s, 'base64url')), 'the JWT is signed with the service account key');
    check(claims.iss === 'push@test.iam.gserviceaccount.com' && claims.scope.includes('firebase.messaging'), 'for the FCM scope');
    check(calls[1].url === 'https://fcm.googleapis.com/v1/projects/alleyway-test/messages:send', "to the project's FCM address");
    check(calls[1].headers.Authorization === 'Bearer ya29.test', 'with the access token');
    check(JSON.parse(calls[1].body).message.token === 'tok123', 'for that phone');
    await push.sendTo('tok456', { kind: 'daily', title: 'x', body: 'y' }, fake);
    check(calls.filter((x) => x.url.includes('oauth2')).length === 1, 'the access token is kept for its hour');
    fcmReply = { status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } };
    check(await push.sendTo('old', { kind: 'daily', title: 'x', body: 'y' }, fake) === 'dead', 'an uninstalled phone: the token is dead');
    fcmReply = { status: 503, body: { error: { status: 'UNAVAILABLE' } } };
    check(await push.sendTo('tok', { kind: 'daily', title: 'x', body: 'y' }, fake) === 'error', 'Google busy: an error, the token kept');

    // What's due: only in the phone's daytime; the daily reward from 6 pm when unclaimed; Karat on the turf
    // map; season rewards; news
    const now = new Date('2026-11-16T09:00:00Z');
    const economy = (claimed, turf = [], seasons = [], outbox = []) => ({
        daily: { status: async () => ({ claimed, day: 3, rewards: [{}, {}, { karat: 150 }] }) },
        territory: { unclaimed: async () => turf },
        seasons: { unclaimed: async () => seasons },
        outbox,
    });
    let due = await push.dueFor('p1', 18, now, economy(false));
    check(due.length === 1 && due[0].kind === 'daily' && due[0].key === 'daily:p1:2026-11-16', 'the daily reward at 6 pm, once that day');
    check(due[0].body.startsWith('Day 3 of 7: 150 Karat'), 'saying which day and what it gives');
    check((await push.dueFor('p1', 18, now, economy(true))).length === 0, 'not when it was claimed');
    check((await push.dueFor('p1', 14, now, economy(false))).length === 0, 'not before 6 pm');
    due = await push.dueFor('p1', 3, now, economy(false, [{ week: '2026-11-09', karat: 50 }], [{ season: 0, name: 'Season 0', peak_tier_name: 'Kingpin' }],
        [{ id: 7, title: 'New cards', body: 'Flicker' }]));
    check(due.length === 0, 'nothing at 3 am');
    due = await push.dueFor('p1', 10, now, economy(true, [{ week: '2026-11-09', karat: 50 }, { week: '2026-11-02', karat: 100 }],
        [{ season: 0, name: 'Season 0', peak_tier_name: 'Kingpin' }], [{ id: 7, title: 'New cards', body: 'Flicker' }]));
    check(due.some((d) => d.key === 'turf:2026-11-09:p1' && d.body.startsWith('150 Karat')), 'the turf map: all the Karat waiting, once a week');
    check(due.some((d) => d.key === 'season:0:p1' && d.title === 'Season 0 is over' && d.body.includes('Kingpin')), 'a season over');
    check(due.some((d) => d.key === 'out:7:p1' && d.kind === 'updates'), 'news');

    console.log(bad ? `${bad} problem(s)` : 'push: all good');
    process.exit(bad ? 1 : 0);
})();
