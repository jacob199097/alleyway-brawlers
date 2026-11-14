'use strict';

/**
 * PHONE NOTIFICATIONS (Firebase Cloud Messaging, Android).
 *
 * The game registers each phone's token with its clock's offset from UTC (routes/push.js, push_tokens).
 * What it sends, each as an Android notification channel (the game names them; players can turn any off
 * in the phone's settings, or all of them in the game):
 *   invites  a friend's challenge or Turf Defense invite while the game isn't open on their screen, at once
 *            (socket/onlineMatch.js, socket/coopMatch.js);
 *   daily    the daily reward, when it hasn't been claimed, from 6 pm on the phone's clock;
 *   results  a finished turf map week with Karat to claim, a finished ranked season with rewards to claim;
 *   updates  a new game version (its first patch note), new cards (announce(), scripts/sync_cards.mjs).
 * All but invites go out between 9 am and 10 pm on the phone's clock (tick(), every 15 minutes), each once.
 *
 * FCM_SERVICE_ACCOUNT in .env is the path to the Firebase project's service account key (JSON, never in git).
 * Without it nothing is sent, and the rest of the game is unaffected.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const { pool } = require('../db/pool');

const DAY_STARTS = 9, DAY_ENDS = 22;   // the phone's hours pushes (other than invites) may go out in
const DAILY_HOUR = 18;
const TICK_MS = 15 * 60 * 1000;
const KINDS = ['invites', 'daily', 'results', 'updates'];

let account;   // the service account (undefined: not read yet; null: none)
let access = { token: '', until: 0 };

function credentials() {
    if (account !== undefined) return account;
    try {
        const a = JSON.parse(fs.readFileSync(process.env.FCM_SERVICE_ACCOUNT || '', 'utf8'));
        account = a.client_email && a.private_key && a.project_id ? a : null;
    } catch {
        account = null;
    }
    return account;
}

const enabled = () => !!credentials();

/** POST to an https URL → {status, body}. (https, not fetch: any Node version) */
function post(url, body, headers) {
    return new Promise((resolve) => {
        const u = new URL(url);
        const req = https.request({ method: 'POST', hostname: u.hostname, path: u.pathname + u.search, headers, timeout: 15000 }, (res) => {
            let data = '';
            res.on('data', (c) => { data += c; });
            res.on('end', () => {
                let json = null;
                try { json = JSON.parse(data); } catch { /* not JSON */ }
                resolve({ status: res.statusCode, body: json });
            });
        });
        req.on('error', () => resolve({ status: 0, body: null }));
        req.on('timeout', () => req.destroy());
        req.end(body);
    });
}

/** An OAuth access token for FCM from the service account (a signed JWT exchanged at Google), kept for its hour. */
async function accessToken(send = post) {
    if (access.token && Date.now() < access.until - 60_000) return access.token;
    const a = credentials();
    if (!a) return '';
    const now = Math.floor(Date.now() / 1000);
    const aud = a.token_uri || 'https://oauth2.googleapis.com/token';
    const part = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${part({ alg: 'RS256', typ: 'JWT' })}.${part({ iss: a.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud, iat: now, exp: now + 3600 })}`;
    const sig = crypto.sign('RSA-SHA256', Buffer.from(unsigned), a.private_key).toString('base64url');
    const r = await send(aud, new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${sig}` }).toString(),
        { 'Content-Type': 'application/x-www-form-urlencoded' });
    if (r.status !== 200 || !r.body?.access_token) {
        console.error('[Push] No access token from Google:', r.status);
        return '';
    }
    access = { token: r.body.access_token, until: Date.now() + (Number(r.body.expires_in) || 3600) * 1000 };
    return access.token;
}

/** The FCM message for one phone. */
function message(token, { kind, title, body }) {
    return {
        message: {
            token,
            notification: { title: String(title).slice(0, 100), body: String(body).slice(0, 240) },
            android: { priority: kind === 'invites' ? 'high' : 'normal', notification: { channel_id: kind, tag: kind } },
            data: { kind },
        },
    };
}

/** Sends to one phone → 'ok', 'dead' (the token no longer works: forget it) or 'error'. */
async function sendTo(token, msg, send = post) {
    const a = credentials();
    const bearer = await accessToken(send);
    if (!a || !bearer) return 'error';
    const r = await send(`https://fcm.googleapis.com/v1/projects/${a.project_id}/messages:send`, JSON.stringify(message(token, msg)),
        { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` });
    if (r.status === 200) return 'ok';
    const code = r.body?.error?.details?.find?.((d) => d.errorCode)?.errorCode || r.body?.error?.status;
    if (r.status === 404 || code === 'UNREGISTERED' || (r.status === 400 && code === 'INVALID_ARGUMENT')) return 'dead';
    console.error('[Push] FCM refused a message:', r.status, code || '');
    return 'error';
}

/** Sends to every phone a player is signed in on (dead tokens are forgotten). → how many got it */
async function toPlayer(playerId, msg) {
    if (!enabled()) return 0;
    const { rows } = await pool.query('SELECT token FROM push_tokens WHERE player_id = $1', [playerId]);
    let sent = 0;
    for (const { token } of rows) {
        const r = await sendTo(token, msg);
        if (r === 'ok') sent += 1;
        else if (r === 'dead') await pool.query('DELETE FROM push_tokens WHERE token = $1', [token]);
    }
    return sent;
}

/** Whether a player has any phone to send to. */
async function hasPhone(playerId) {
    if (!enabled()) return false;
    const { rows } = await pool.query('SELECT 1 FROM push_tokens WHERE player_id = $1 LIMIT 1', [playerId]);
    return rows.length > 0;
}

/** An invite or challenge, at once. (Never throws: the caller is a socket handler.) */
function invite(playerId, title, body) {
    toPlayer(playerId, { kind: 'invites', title, body }).catch((err) => console.error('[Push] Invite failed:', err.message));
}

/** A phone's token for a player (moved to them if another account had it). */
async function register(playerId, token, platform = 'android', tzMinutes = 0) {
    await pool.query(
        `INSERT INTO push_tokens (token, player_id, platform, tz_minutes) VALUES ($1, $2, $3, $4)
         ON CONFLICT (token) DO UPDATE SET player_id = $2, platform = $3, tz_minutes = $4, updated_at = NOW()`,
        [token, playerId, platform, tzMinutes]);
}

async function unregister(playerId, token) {
    await pool.query('DELETE FROM push_tokens WHERE token = $1 AND player_id = $2', [token, playerId]);
}

/** News for every phone (sent over the next two days, in each one's daytime). */
async function announce(title, body) {
    await pool.query('INSERT INTO push_outbox (title, body) VALUES ($1, $2)', [title, body]);
}

/** Records a push as sent → true the first time (so each goes out once). */
async function once(key) {
    const { rowCount } = await pool.query('INSERT INTO push_sent (key) VALUES ($1) ON CONFLICT DO NOTHING', [key]);
    return rowCount === 1;
}

/** The hour on a phone's clock (0-23). */
function localHour(now, tzMinutes) {
    const m = ((now.getUTCHours() * 60 + now.getUTCMinutes() + Number(tzMinutes || 0)) % 1440 + 1440) % 1440;
    return Math.floor(m / 60);
}

/** What a daily reward gives, in words: "150 Karat", "a free pack and 300 Karat". */
function rewardText(r = {}) {
    const parts = [];
    if (r.free_packs) parts.push(r.free_packs === 1 ? 'a free pack' : `${r.free_packs} free packs`);
    if (r.karat) parts.push(`${r.karat} Karat`);
    if (r.dust) parts.push(`${r.dust} Dust`);
    return parts.join(' and ') || 'a reward';
}

/** The pushes due for one player now (not checked against what was already sent). */
async function dueFor(playerId, hour, now, { daily, territory, seasons, outbox }) {
    const due = [];
    if (hour < DAY_STARTS || hour >= DAY_ENDS) return due;
    const day = now.toISOString().slice(0, 10);
    if (hour >= DAILY_HOUR) {
        const s = await daily.status(playerId);
        if (s && !s.claimed) {
            due.push({ key: `daily:${playerId}:${day}`, kind: 'daily', title: 'Your daily reward is ready',
                body: `Day ${s.day} of 7: ${rewardText(s.rewards[s.day - 1])}. Keep the streak going!` });
        }
    }
    const weeks = await territory.unclaimed(playerId, now);
    if (weeks.length) {
        const karat = weeks.reduce((n, w) => n + (Number(w.karat) || 0), 0);
        due.push({ key: `turf:${weeks[0].week}:${playerId}`, kind: 'results', title: 'The turf map week is over',
            body: `${karat} Karat is waiting for you on the turf map. Come and claim it.` });
    }
    for (const s of await seasons.unclaimed(playerId)) {
        due.push({ key: `season:${s.season}:${playerId}`, kind: 'results', title: `${s.name} is over`,
            body: `You reached ${s.peak_tier_name}. Your season rewards are waiting.` });
    }
    for (const o of outbox) due.push({ key: `out:${o.id}:${playerId}`, kind: 'updates', title: o.title, body: o.body });
    return due;
}

/** Every 15 minutes: the reminders and news due on each phone, each once. */
async function tick(now = new Date()) {
    if (!enabled()) return;
    const economy = {
        daily: require('../economy/daily'), territory: require('../economy/territory'), seasons: require('../economy/seasons'),
        outbox: (await pool.query(`SELECT id, title, body FROM push_outbox WHERE created_at > NOW() - INTERVAL '2 days' ORDER BY id`)).rows,
    };
    const { rows } = await pool.query(
        'SELECT DISTINCT ON (player_id) player_id, tz_minutes FROM push_tokens ORDER BY player_id, updated_at DESC');
    for (const p of rows) {
        try {
            for (const d of await dueFor(p.player_id, localHour(now, p.tz_minutes), now, economy)) {
                if (await once(d.key)) await toPlayer(p.player_id, d);
            }
        } catch (err) {
            console.error('[Push] Reminders failed for a player:', err.message);
        }
    }
    await pool.query(`DELETE FROM push_sent WHERE at < NOW() - INTERVAL '60 days'`);
    await pool.query(`DELETE FROM push_outbox WHERE created_at < NOW() - INTERVAL '7 days'`);
}

/** A new game version (shared/game_version.json "latest") is news once: its first patch note. */
async function announceVersion() {
    const root = path.join(__dirname, '../..');
    const latest = JSON.parse(fs.readFileSync(path.join(root, 'shared/game_version.json'), 'utf8')).latest;
    if (!latest || !(await once(`version:${latest}`))) return;
    let note = '';
    try {
        const notes = JSON.parse(fs.readFileSync(path.join(root, 'godot/data/patch_notes.json'), 'utf8'));
        note = String((notes.find((n) => n.version === latest)?.notes || [])[0] || '');
    } catch { /* no notes */ }
    await announce(`Alleyway Brawlers ${latest} is out`, note || 'A new version of the game is ready. Open it to update.');
}

/** Starts the reminders (server.js). */
function start() {
    if (!enabled()) {
        console.log('[Push] No FCM_SERVICE_ACCOUNT: phone notifications are off.');
        return;
    }
    console.log('[Push] Phone notifications are on.');
    const run = () => announceVersion().then(() => tick()).catch((err) => console.error('[Push]', err.message));
    setTimeout(run, 30_000).unref();
    setInterval(run, TICK_MS).unref();
}

module.exports = { start, tick, dueFor, invite, hasPhone, register, unregister, announce, toPlayer, sendTo, message, accessToken,
    localHour, rewardText, enabled, KINDS, _reset: (a) => { account = a; access = { token: '', until: 0 }; } };
