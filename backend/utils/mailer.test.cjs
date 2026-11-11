'use strict';
// The account emails (utils/mailer.js): the link in both the HTML and the text, pictures only from the
// website and over HTTPS, nothing that tracks the reader, the contact address, and small enough that
// Gmail shows the whole email (it cuts off emails over 102 KB).
//   node backend/utils/mailer.test.cjs   (no mail is sent)
process.env.CONTACT_EMAIL = 'support@example.com';
process.env.SITE_URL = 'https://alleywaybrawlers.com';
const assert = require('assert');
const { emails } = require('./mailer');

const link = 'https://play.alleywaybrawlers.com/api/auth/verify-email?token=abc123';
for (const [name, mail] of Object.entries({ verification: emails.verification(link), passwordReset: emails.passwordReset(link) })) {
    assert.ok(mail.subject.includes('AlleyWay Brawlers'), `${name}: the subject names the game`);
    assert.ok(mail.html.includes(`href="${link}"`), `${name}: the button links to the page`);
    assert.ok(mail.text.includes(link), `${name}: the plain-text version has the link`);
    const imgs = [...mail.html.matchAll(/<img\b[^>]*\bsrc="([^"]+)"/g)].map((m) => m[1]);
    assert.deepEqual(imgs, ['https://alleywaybrawlers.com/site/img/email-banner.jpg'], `${name}: one picture, the banner, from the website`);
    assert.ok(/<img\b[^>]*\balt="AlleyWay Brawlers"/.test(mail.html), `${name}: the banner says what it is when pictures are blocked`);
    for (const m of mail.html.matchAll(/\bhref="([^"]+)"/g)) {
        assert.ok(/^(https:\/\/(alleywaybrawlers\.com|play\.alleywaybrawlers\.com)\/|mailto:)/.test(m[1]), `${name}: link ${m[1]} goes to the game's own addresses`);
    }
    assert.ok(mail.html.includes('mailto:support@example.com') && mail.text.includes('support@example.com'), `${name}: the contact address`);
    assert.ok(Buffer.byteLength(mail.html) < 102 * 1024, `${name}: under Gmail's 102 KB`);
    assert.ok(!/undefined|NaN|\[object Object\]/.test(mail.html + mail.text), `${name}: nothing unfilled`);
}
// A link can't break out of its attribute
assert.ok(!emails.passwordReset('https://x.test/?a="><script>').html.includes('"><script>'), 'the link is escaped');
console.log('mailer: ok');
