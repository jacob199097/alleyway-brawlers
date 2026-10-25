'use strict';

/**
 * LEGAL PAGES (public, no sign-in; linked from the game and needed for app stores)
 *
 *   GET /privacy          the privacy policy
 *   GET /terms            the terms of service
 *   GET /delete-account   how to delete an account, with a form (POST /api/account/delete)
 *
 * Contact address: CONTACT_EMAIL in .env, else the address game emails come from (SMTP_USER).
 * Change UPDATED when the wording changes, and keep the policy true to what the server stores.
 */

const router = require('express').Router();

const GAME = 'AlleyWay Brawlers';
const UPDATED = '25 October 2026';

const contact = () => process.env.CONTACT_EMAIL || process.env.SMTP_USER || '';
const contactLink = () => contact()
    ? `<a href="mailto:${contact()}">${contact()}</a>`
    : 'the contact address on our website';

function page(title, body) {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${title} · ${GAME}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 :root{color-scheme:dark}
 body{margin:0;background:#0d0d1a;color:#dcdcea;font:16px/1.65 Arial,Helvetica,sans-serif}
 main{max-width:760px;margin:0 auto;padding:40px 20px 64px}
 nav{display:flex;gap:18px;flex-wrap:wrap;font-size:14px;margin-bottom:28px}
 nav a{color:#4cc9f0;text-decoration:none} nav a:hover{text-decoration:underline}
 h1{color:#f4d35e;font-size:30px;margin:0 0 4px;letter-spacing:.5px}
 .date{color:#8e8ea8;font-size:14px;margin:0 0 28px}
 h2{color:#f4d35e;font-size:19px;margin:34px 0 8px}
 a{color:#4cc9f0}
 ul{padding-left:22px} li{margin:4px 0}
 .box{background:#101030;border:1px solid #2c2c5a;border-radius:10px;padding:18px 20px;margin:18px 0}
 label{display:block;font-size:13px;color:#a8a8c0;margin:14px 0 6px}
 input{width:100%;box-sizing:border-box;padding:12px;border-radius:6px;border:2px solid #4cc9f0;background:#1a1a2e;color:#fff;font-size:16px}
 button{margin-top:20px;padding:13px 22px;border:0;border-radius:6px;background:#e63946;color:#fff;font-weight:bold;font-size:16px;cursor:pointer}
 button:disabled{opacity:.5;cursor:default}
 #msg{margin-top:16px;min-height:1.4em}
</style></head><body><main>
<nav><a href="/privacy">Privacy policy</a><a href="/terms">Terms of service</a><a href="/delete-account">Delete your account</a></nav>
${body}
</main></body></html>`;
}

function privacy() {
    return page('Privacy policy', `
<h1>Privacy policy</h1>
<p class="date">Last updated ${UPDATED}</p>
<p>${GAME} is an online trading-card fighting game made and run by a small independent team ("we", "us").
This policy explains what we collect when you play, why, who can see it, and how to delete it.
Questions: ${contactLink()}.</p>

<h2>What we collect</h2>
<ul>
 <li><b>Your account:</b> your email address, the username you choose, and your password. We never store the
  password itself, only a one-way scrambled version (a bcrypt hash) that can check it but not reveal it. We also keep
  whether your email is confirmed and, for a short time, the links in activation and password-reset emails.</li>
 <li><b>Your game:</b> your cards and packs, decks, Karat, Contraband and Dust, level and XP, rank, wins and losses,
  achievements, quests, daily rewards, clan mastery, your chosen clan, title, profile picture and card back, and
  when you last played.</li>
 <li><b>Friends and messages:</b> your friends list and friend requests, the direct messages you send and receive,
  and the messages in your in-game mailbox.</li>
 <li><b>Matches:</b> the result of each online match, and recordings of your 30 most recent matches (the decks,
  the moves made and the players' names and profile pictures) so you can watch them back. We also keep match
  statistics that are not linked to any account (which clan and cards were in each deck, which were played, who
  won) to balance the cards.</li>
 <li><b>Purchases:</b> if you buy Contraband, the payment is handled by Stripe. We never see or store your card
  details. We keep the payment reference, the bundle you bought and the Contraband it gave you.</li>
 <li><b>Error reports:</b> when the game hits an error, it sends us the game version, your operating system, the
  error message and where it happened, and your account id, so we can fix it. These are deleted after 30 days.</li>
 <li><b>Connection details:</b> our server sees the IP address your game connects from. We use it to keep the
  service running and safe (for example, to limit repeated password guesses), and it can appear in our server's
  logs.</li>
 <li><b>On your device:</b> the game saves your settings and your sign-in session in its own folder on your
  computer. This stays on your device.</li>
</ul>
<p>We don't use advertising, ad trackers or third-party analytics, and we don't collect your real name, address,
phone number, contacts or location.</p>

<h2>How we use it</h2>
<ul>
 <li>To run the game: sign you in, save your progress, match you with other players, and run matches and rewards
  on our server.</li>
 <li>To email you about your account: activation and password resets. We will only send news or offers if you
  have chosen to receive them.</li>
 <li>To fix bugs, balance cards, and stop cheating, abuse and attacks on the service.</li>
</ul>

<h2>What other players can see</h2>
<p>Your username, profile picture, title, level, rank and win record (on the leaderboard and your profile), the
cards you play in a match, and replays of matches you played against them. Direct messages are seen only by the
person you send them to.</p>

<h2>Who we share it with</h2>
<p>We don't sell or rent your information. We only share what's needed with the services that help run the game:</p>
<ul>
 <li><b>Stripe</b>, to take payments for Contraband (their privacy policy covers your payment details);</li>
 <li><b>our email provider</b>, to deliver activation and password-reset emails;</li>
 <li><b>DuckDNS</b>, which points our web address at our server (it doesn't receive your game data).</li>
</ul>
<p>We may also share information if the law requires it, or to protect players and the service from fraud or abuse.</p>

<h2>How long we keep it</h2>
<p>We keep your account and game data for as long as your account exists. Error reports are deleted after 30 days,
and only your 30 most recent match recordings are kept. When you delete your account, everything listed above
that belongs to it is deleted straight away. The anonymous match statistics are kept, and other players' match
history keeps the match without your account in it.</p>

<h2>Deleting your account and your other choices</h2>
<ul>
 <li><b>Delete your account</b> in the game (Settings → Account → Delete account) or on the
  <a href="/delete-account">delete your account</a> page. This can't be undone.</li>
 <li>You can ask us for a copy of your data, or to correct it, by emailing ${contactLink()}.</li>
 <li>Depending on where you live (for example in the UK, the EU or California), you may have further rights, such
  as to object to how we use your data or to complain to your local data protection authority. Contact us and we'll
  help.</li>
</ul>

<h2>Children</h2>
<p>${GAME} isn't made for children under 13, and they shouldn't create an account. If you're under the age where
you can agree to this policy yourself where you live, ask a parent or guardian first. If you think a child under 13
has made an account, contact us and we'll delete it.</p>

<h2>Keeping it safe</h2>
<p>Passwords are stored only as hashes, the game talks to our server over an encrypted (HTTPS) connection, and
access to the server is restricted. No system is perfectly secure, so use a password you don't use anywhere else.</p>

<h2>Where it's stored</h2>
<p>Your data is stored on a server run by us. It may be in a different country from yours.</p>

<h2>Changes to this policy</h2>
<p>If we change this policy, we'll update the date above. If the change is significant, we'll tell you in the game
before it applies.</p>`);
}

function terms() {
    return page('Terms of service', `
<h1>Terms of service</h1>
<p class="date">Last updated ${UPDATED}</p>
<p>These terms are the agreement between you and the team that makes and runs ${GAME} ("we", "us"). By creating an
account or playing, you agree to them and to our <a href="/privacy">privacy policy</a>. If you don't agree, please
don't play. Questions: ${contactLink()}.</p>

<h2>1. Your account</h2>
<ul>
 <li>You must be at least 13 to make an account. If you're under the age where you can agree to these terms where
  you live, a parent or guardian must agree to them for you.</li>
 <li>Use an email address you own, keep your password secret, and don't share, sell or trade your account. You're
  responsible for what happens on it.</li>
 <li>Pick a username that isn't offensive, hateful or pretending to be someone else. We may change or remove one
  that is.</li>
</ul>

<h2>2. The game</h2>
<p>We give you a personal, non-commercial, non-transferable licence to download and play ${GAME}. The game is in
active development: cards, rules, balance, rewards and features will change, and we may need to reset or adjust
progress to fix bugs or exploits. We'll try to keep the game online, but it may sometimes be unavailable, and we
may end the service; if we do, we'll give notice in the game first.</p>

<h2>3. Cards, currencies and purchases</h2>
<ul>
 <li>Karat, Contraband, Dust, cards, packs and other in-game items are a licence to use them in the game. They
  aren't your property, have no value in real money, can't be exchanged for money, and can't be sold, traded or
  moved outside the game.</li>
 <li>We may change, rebalance or retire cards and items (for example to keep the game fair).</li>
 <li>Contraband bought with real money is delivered to your account straight away, and payments are handled by
  Stripe. Purchases are final and aren't refundable once delivered, except where the law where you live gives you a
  right to a refund. If something goes wrong with a purchase, contact us.</li>
</ul>

<h2>4. Playing fair</h2>
<p>Don't:</p>
<ul>
 <li>cheat, use bots or scripts, or modify, reverse-engineer or tamper with the game or its traffic to get an
  advantage;</li>
 <li>exploit bugs (please report them to us instead);</li>
 <li>harass, threaten, abuse or spam other players, or send hateful, sexual or illegal content in messages or
  usernames;</li>
 <li>attack, overload or try to break into our servers or other players' accounts;</li>
 <li>buy, sell or trade accounts, cards or currencies for real money.</li>
</ul>
<p>If you break these terms we may remove items or currency gained unfairly, or suspend or delete your account.</p>

<h2>5. Our content</h2>
<p>The game, its code, art, cards, music and names belong to us or to those who license them to us. You're welcome
to stream, record and share videos and screenshots of yourself playing, as long as you don't suggest they're
official.</p>

<h2>6. Ending</h2>
<p>You can stop playing and <a href="/delete-account">delete your account</a> at any time. We may suspend or end
your access if you seriously or repeatedly break these terms, or if we have to by law.</p>

<h2>7. Liability</h2>
<p>The game is provided "as is". As far as the law allows, we aren't responsible for indirect losses or for losing
in-game items or progress, and our total responsibility to you is limited to what you paid us in the 12 months
before the problem. Nothing in these terms takes away rights you have as a consumer under the law where you live.</p>

<h2>8. Changes to these terms</h2>
<p>We may update these terms as the game changes. We'll update the date above, and for significant changes we'll
tell you in the game before they apply. Playing after that means you accept the new terms.</p>`);
}

function deletePage() {
    return page('Delete your account', `
<h1>Delete your account</h1>
<p class="date">${GAME}</p>
<p>Deleting your account removes it for good: your cards and packs, decks, Karat, Contraband and Dust, progress,
achievements, friends, messages, mail and match recordings. Contraband you bought is lost and isn't refunded. This
can't be undone. See the <a href="/privacy">privacy policy</a> for what's kept.</p>

<h2>In the game</h2>
<p>Open <b>Settings → Account → Delete account</b>, enter your password and confirm.</p>

<h2>Here</h2>
<div class="box">
<form id="f">
 <label for="e">Email</label>
 <input id="e" type="email" autocomplete="email" required>
 <label for="p">Password</label>
 <input id="p" type="password" autocomplete="current-password" required>
 <label><input id="c" type="checkbox" style="width:auto;margin-right:8px">I understand my account and everything in it will be deleted for good.</label>
 <button id="b" type="submit">Delete my account</button>
</form>
<div id="msg"></div>
</div>
<p>Forgotten your password? Use "Forgot password?" on the game's login screen first, or email ${contactLink()} from
the address on the account.</p>
<script>
const f = document.getElementById('f'), msg = document.getElementById('msg'), b = document.getElementById('b');
const say = (t, ok) => { msg.textContent = t; msg.style.color = ok ? '#4caf50' : '#e63946'; };
f.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!document.getElementById('c').checked) return say('Tick the box to confirm.');
  b.disabled = true;
  try {
    const r = await fetch('/api/account/delete', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: document.getElementById('e').value, password: document.getElementById('p').value }) });
    const d = await r.json().catch(() => ({}));
    if (r.ok) { f.remove(); say('Your account has been deleted.', true); }
    else { b.disabled = false; say(d.error || 'That did not work. Try again.'); }
  } catch { b.disabled = false; say("Can't reach the server. Try again."); }
});
</script>`);
}

router.get('/privacy', (_req, res) => res.send(privacy()));
router.get('/terms', (_req, res) => res.send(terms()));
router.get('/delete-account', (_req, res) => res.send(deletePage()));

module.exports = router;
