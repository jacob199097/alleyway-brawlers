'use strict';

/**
 * NEWS EMAILS: a new season and new cards, to the players who asked for them (players.news_emails, Settings →
 * Account in the game; off unless turned on). Every one carries an unsubscribe link (/news/unsubscribe, a link
 * signed for that player, so it works without signing in) and the one-click unsubscribe headers mail programs
 * show as their own "Unsubscribe" button.
 *
 *   season(ended)  scripts/season.mjs end --apply: the season that ended and the one that starts
 *   cards(names)   scripts/sync_cards.mjs: new cards; waits CARDS_WAIT_H so a week of imports is one email
 *   tick()         every 15 minutes: sends what's due, at most NEWS_DAILY_MAX emails a day (.env, default 250:
 *                  the email provider's daily limit), oldest news first; the rest go in the next day's batch
 *
 * Nothing is sent without SMTP_HOST (the server's email settings).
 */

const crypto = require('crypto');
const { pool } = require('../db/pool');

const TICK_MS = 15 * 60 * 1000;
const CARDS_WAIT_H = 12;
const NAMES_SHOWN = 12;

const base = () => (process.env.APP_BASE_URL || 'http://localhost:3000').replace(/\/+$/, '');
const site = () => (process.env.SITE_URL ?? 'https://alleywaybrawlers.com').trim().replace(/\/+$/, '') || 'https://alleywaybrawlers.com';
const dailyMax = () => Math.max(0, parseInt(process.env.NEWS_DAILY_MAX || '250', 10) || 0);

/** The unsubscribe link's signature: only the server can make one for a player. */
function token(playerId) {
    return crypto.createHmac('sha256', String(process.env.JWT_SECRET || '')).update(`news-unsub:${playerId}`).digest('base64url').slice(0, 32);
}

function checkToken(playerId, t) {
    const want = Buffer.from(token(playerId));
    const got = Buffer.from(String(t || ''));
    return want.length === got.length && crypto.timingSafeEqual(want, got);
}

const unsubscribeLink = (playerId) => `${base()}/news/unsubscribe?u=${encodeURIComponent(playerId)}&t=${token(playerId)}`;

/** A list of names in words: "A, B and C" (and "and 4 more" past NAMES_SHOWN). */
function nameList(names) {
    const shown = names.slice(0, NAMES_SHOWN);
    const more = names.length - shown.length;
    if (more > 0) return `${shown.join(', ')} and ${more} more`;
    return shown.length > 1 ? `${shown.slice(0, -1).join(', ')} and ${shown[shown.length - 1]}` : (shown[0] || '');
}

/** The email for one news item, for one player. */
function mailFor(item, playerId) {
    const { emails } = require('./mailer');
    const names = Array.isArray(item.names) ? item.names : [];
    const lines = [...(Array.isArray(item.lines) ? item.lines : [])];
    if (item.kind === 'cards') lines.unshift(names.length === 1
        ? `A new card is on the streets: ${names[0]}. Open the game and it downloads itself, no update needed.`
        : `${names.length} new cards are on the streets: ${nameList(names)}. Open the game and they download themselves, no update needed.`);
    return emails.news({
        subject: item.kind === 'cards' && names.length === 1 ? `New card: ${names[0]}` : item.subject,
        heading: item.heading,
        lines,
        button: item.kind === 'cards' ? { text: 'See the cards', href: `${site()}/cards` } : { text: 'Play now', href: `${site()}/` },
    }, unsubscribeLink(playerId));
}

/** New cards: added to the cards email that hasn't started going out yet, or a new one. */
async function cards(names, db = pool) {
    names = [...new Set(names.filter(Boolean).map(String))];
    if (!names.length) return;
    const { rows: [open] } = await db.query(
        `SELECT id, names FROM news_outbox o WHERE kind = 'cards' AND done_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM news_sent s WHERE s.news_id = o.id) ORDER BY id DESC LIMIT 1`);
    if (open) {
        const all = [...new Set([...(open.names || []), ...names])];
        await db.query('UPDATE news_outbox SET names = $2 WHERE id = $1', [open.id, JSON.stringify(all)]);
        return;
    }
    await db.query(
        `INSERT INTO news_outbox (kind, subject, heading, names, send_after)
         VALUES ('cards', 'New cards on the streets', 'Fresh blood', $1, NOW() + make_interval(hours => $2))`,
        [JSON.stringify(names), CARDS_WAIT_H]);
}

/** A season ended (seasons.endSeason's result) and the next began. */
async function season(r, db = pool) {
    const next = r.next || {};
    const lines = [
        `${r.season.name} is over. Your reward goes by the highest rank you reached: claim it in the game, on the Seasons screen.`,
        `${next.name || 'The next season'} starts now${next.subtitle ? `: ${next.subtitle}` : ''}. Every rank has dropped back, so the climb is on again.`,
    ];
    if (next.ends_at) lines.push(`It runs until ${new Date(next.ends_at).toISOString().slice(0, 10)}.`);
    await db.query(
        `INSERT INTO news_outbox (kind, subject, heading, lines) VALUES ('season', $1, $2, $3)`,
        [`${next.name || 'A new season'} has started`, `${next.name || 'New season'}`, JSON.stringify(lines)]);
}

/** Sends what's due, up to today's limit. → how many went out. */
async function tick(send = null) {
    if (!send) {
        if (!process.env.SMTP_HOST) return 0;
        send = require('./mailer').send;
    }
    const { rows: [{ n: today }] } = await pool.query(`SELECT COUNT(*)::int AS n FROM news_sent WHERE at > NOW() - INTERVAL '1 day'`);
    let left = dailyMax() - today;
    let sent = 0;
    const { rows: due } = await pool.query(
        `SELECT * FROM news_outbox WHERE done_at IS NULL AND send_after <= NOW() ORDER BY id`);
    for (const item of due) {
        if (left <= 0) break;
        const { rows: to } = await pool.query(
            `SELECT p.id, p.email FROM players p
             WHERE p.news_emails AND p.email IS NOT NULL AND p.email_verified
               AND NOT EXISTS (SELECT 1 FROM news_sent s WHERE s.news_id = $1 AND s.player_id = p.id)
             ORDER BY p.id LIMIT $2`, [item.id, left]);
        for (const p of to) {
            const link = unsubscribeLink(p.id);
            try {
                await send(p.email, mailFor(item, p.id), {
                    'List-Unsubscribe': `<${link}>`,
                    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
                });
            } catch (err) {
                console.error('[News]', item.id, err.message);
                return sent;   // (the email service is down or refusing: try again next tick)
            }
            await pool.query('INSERT INTO news_sent (news_id, player_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [item.id, p.id]);
            sent += 1;
            left -= 1;
        }
        if (to.length === 0 || left > 0) await pool.query('UPDATE news_outbox SET done_at = NOW() WHERE id = $1', [item.id]);
    }
    await pool.query(`DELETE FROM news_outbox WHERE done_at < NOW() - INTERVAL '60 days'`);
    return sent;
}

async function setWanted(playerId, on) {
    const { rowCount } = await pool.query('UPDATE players SET news_emails = $2 WHERE id = $1', [playerId, !!on]);
    return rowCount > 0;
}

async function wanted(playerId) {
    const { rows: [p] } = await pool.query('SELECT news_emails, email, email_verified FROM players WHERE id = $1', [playerId]);
    return p ? { on: !!p.news_emails, email: !!p.email } : null;
}

function start() {
    if (!process.env.SMTP_HOST) {
        console.log('[News] No SMTP_HOST: news emails are off.');
        return;
    }
    const run = () => tick().then((n) => { if (n) console.log(`[News] ${n} sent`); }).catch((err) => console.error('[News]', err.message));
    setTimeout(run, 60 * 1000);
    setInterval(run, TICK_MS).unref();
}

module.exports = { start, tick, cards, season, setWanted, wanted, token, checkToken, unsubscribeLink, mailFor, nameList };
