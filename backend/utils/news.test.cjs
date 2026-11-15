// Run: node backend/utils/news.test.cjs
// News emails (utils/news.js) without a database or an email service: the signed unsubscribe link, the email
// itself, and what tick() sends (only to players who asked, at most the daily limit, the unsubscribe headers).
process.env.JWT_SECRET = 'test-secret';
process.env.APP_BASE_URL = 'https://play.example.com';
process.env.NEWS_DAILY_MAX = '3';
const { pool } = require('../db/pool');
const news = require('./news');

let bad = 0;
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

(async () => {
    // The unsubscribe link: signed for that player, so nobody can unsubscribe someone else
    const id = '6f1c2b0e-0000-4000-8000-000000000001';
    const t = news.token(id);
    check(news.checkToken(id, t), 'the signature for that player checks out');
    check(!news.checkToken('6f1c2b0e-0000-4000-8000-000000000002', t), "not for another player");
    check(!news.checkToken(id, ''), 'nor an empty one');
    check(news.unsubscribeLink(id) === `https://play.example.com/news/unsubscribe?u=${id}&t=${t}`, 'the link');

    // The email: what's new, a button, the unsubscribe link in the footer and the text version
    check(news.nameList(['A', 'B', 'C']) === 'A, B and C', 'names in words');
    check(news.nameList(Array.from({ length: 14 }, (_, i) => `C${i}`)).endsWith('and 2 more'), 'a long list is cut short');
    const m = news.mailFor({ kind: 'cards', subject: 'New cards on the streets', heading: 'Fresh blood', lines: [], names: ['Marty', 'Flicker'] }, id);
    check(m.subject === 'New cards on the streets' && m.html.includes('Marty and Flicker'), 'the cards email names the cards');
    check(m.html.includes(news.unsubscribeLink(id).replace(/&/g, '&amp;')) && m.text.includes(news.unsubscribeLink(id)), 'with the unsubscribe link (HTML and text)');
    check(news.mailFor({ kind: 'cards', subject: 'x', heading: 'y', lines: [], names: ['Marty'] }, id).subject === 'New card: Marty', 'one card: its name in the subject');

    // tick(): due news to the players who asked, up to the daily limit, with the one-click unsubscribe headers
    const sentRows = [];
    let done = null;
    const players = [{ id: 'p1', email: 'a@x.com' }, { id: 'p2', email: 'b@x.com' }, { id: 'p3', email: 'c@x.com' }, { id: 'p4', email: 'd@x.com' }];
    pool.query = async (sql, params = []) => {
        if (sql.includes('COUNT(*)::int AS n FROM news_sent')) return { rows: [{ n: 0 }] };
        if (sql.includes('FROM news_outbox WHERE done_at IS NULL')) return { rows: [{ id: 7, kind: 'season', subject: 'Season 1 has started', heading: 'Season 1', lines: ['Season 0 is over.'], names: [] }] };
        if (sql.includes('FROM players p')) {
            check(sql.includes('p.news_emails') && sql.includes('p.email_verified'), 'only players who asked, with a confirmed address');
            return { rows: players.filter((p) => !sentRows.some((s) => s.player === p.id)).slice(0, params[1]) };
        }
        if (sql.startsWith('INSERT INTO news_sent')) { sentRows.push({ news: params[0], player: params[1] }); return { rowCount: 1 }; }
        if (sql.startsWith('UPDATE news_outbox SET done_at')) { done = params[0]; return { rowCount: 1 }; }
        return { rows: [], rowCount: 0 };
    };
    const mails = [];
    const n = await news.tick(async (to, mail, headers) => mails.push({ to, mail, headers }));
    check(n === 3 && mails.length === 3, 'three sent: the daily limit');
    check(done === null, "the fourth player waits for tomorrow, so it isn't done");
    check(mails[0].headers['List-Unsubscribe'] === `<${news.unsubscribeLink('p1')}>`, 'the List-Unsubscribe header has their link');
    check(mails[0].headers['List-Unsubscribe-Post'] === 'List-Unsubscribe=One-Click', 'one-click unsubscribe');
    check(mails[0].mail.subject === 'Season 1 has started', 'the season email');
    process.env.NEWS_DAILY_MAX = '10';
    await news.tick(async (to, mail, headers) => mails.push({ to, mail, headers }));
    check(mails.length === 4 && mails[3].to === 'd@x.com', 'the next day: the last player');
    check(done === 7, 'and then it is done');

    // The email service refusing: stop, try again next tick, nobody marked as sent
    sentRows.length = 0; done = null;
    const before = mails.length;
    const n2 = await news.tick(async () => { throw new Error('SMTP down'); });
    check(n2 === 0 && sentRows.length === 0 && done === null && mails.length === before, 'nothing marked sent when the email service fails');

    console.log(bad ? `\n${bad} FAILED` : '\nnews: ok');
    process.exit(bad ? 1 : 0);
})();
