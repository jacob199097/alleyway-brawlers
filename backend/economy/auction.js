'use strict';

/**
 * AUCTION HOUSE
 * Players sell cards to each other for Karat. The numbers are in economy/auction_settings.js.
 *
 *   List a card:  it leaves your collection at once (copies your saved decks use can't be listed, nor a
 *                 boss's prize), you pay the listing fee, and the auction runs DURATION_HOURS.
 *   Bid:          the bid's Karat is held from your balance; when someone outbids you it comes back and
 *                 the mailbox says so. A bid in the last SNIPE_SECONDS pushes the end back.
 *   The end:      settleDue() (every 30 s from server.js) gives the card to the top bidder and the price,
 *                 less the sale fee, to the seller. No bids: the card goes back to the seller.
 *   Cancel:       only before the first bid (the listing fee isn't refunded).
 *
 * Against one person moving cards or Karat between their own accounts: price floors and ceilings by
 * rarity, public auctions of a fixed length, fees, account requirements and limits. Sales between accounts
 * that share a (scrambled) IP address, or between the same two players again and again, are flagged for a
 * person to look at (backend/scripts/auction_report.mjs); nothing is blocked automatically.
 */

const { pool } = require('../db/pool');
const S = require('./auction_settings');
const { copiesInDecks } = require('./crafting');

class AuctionError extends Error {}

const DAY_MS = 24 * 3600 * 1000;

const priceRange = (rarity) => S.PRICES[rarity] || S.PRICES[1];
const listingFee = (start) => Math.max(S.LISTING_FEE_MIN, Math.ceil(start * S.LISTING_FEE_PCT / 100));
const saleFee = (price) => Math.ceil(price * S.SALE_FEE_PCT / 100);

/** The lowest bid that beats `a` now (null: it's at its highest price already). */
function minBid(a) {
    const { max } = priceRange(a.rarity);
    if (a.high_bid == null) return a.start_price;
    if (a.high_bid >= max) return null;
    return Math.min(max, a.high_bid + Math.max(S.MIN_RAISE, Math.ceil(a.high_bid * S.MIN_RAISE_PCT / 100)));
}

/** Whether a player may list and bid: { ok, reasons: [why not], newer, limits }. */
async function eligibility(playerId, client = pool) {
    const { rows: [p] } = await client.query(
        'SELECT level, created_at, email_verified, steam_id FROM players WHERE id = $1', [playerId]);
    if (!p) throw new AuctionError('Player not found.');
    const reasons = [];
    if (p.level < S.MIN_LEVEL) reasons.push(`Reach level ${S.MIN_LEVEL} (you're level ${p.level}).`);
    const ageDays = (Date.now() - new Date(p.created_at).getTime()) / DAY_MS;
    if (ageDays < S.MIN_ACCOUNT_DAYS) {
        const left = Math.ceil(S.MIN_ACCOUNT_DAYS - ageDays);
        reasons.push(`Your account needs to be ${S.MIN_ACCOUNT_DAYS} days old (${left} more day${left === 1 ? '' : 's'}).`);
    }
    if (S.REQUIRE_VERIFIED && !p.email_verified && !p.steam_id) reasons.push('Confirm your email address.');
    if (S.REQUIRE_STEAM && !p.steam_id) reasons.push('Link your Steam account (Settings → Account).');
    const newer = p.level < S.NEWER_LEVEL || ageDays < S.NEWER_DAYS;
    return { ok: reasons.length === 0, reasons, newer, limits: newer ? S.LIMITS.newer : S.LIMITS.regular };
}

async function requireEligible(playerId, client) {
    const e = await eligibility(playerId, client);
    if (!e.ok) throw new AuctionError('You can\'t use the auction house yet: ' + e.reasons.join(' '));
    return e;
}

const SELECT = `SELECT a.*, c.art_url AS game_id, c.name AS card_name, s.username AS seller_name
                FROM auctions a JOIN cards c ON c.id = a.card_id LEFT JOIN players s ON s.id = a.seller_id`;

/** An auction as the game shows it to `playerId` (the top bidder's name isn't shown). */
function view(a, playerId) {
    return {
        id: Number(a.id), card: a.game_id, name: a.card_name, rarity: a.rarity,
        seller: a.seller_name || null, mine: a.seller_id === playerId,
        startPrice: a.start_price, highBid: a.high_bid, bids: a.bids, minBid: a.status === 'active' ? minBid(a) : null,
        maxPrice: priceRange(a.rarity).max, leading: a.high_bidder != null && a.high_bidder === playerId,
        status: a.status, endsAt: a.ends_at, settledAt: a.settled_at, saleFee: a.sale_fee,
    };
}

/** What the auction house screen needs besides the auctions: the rules, your Karat, whether you can trade. */
async function overview(playerId) {
    const e = await eligibility(playerId);
    const { rows: [p] } = await pool.query('SELECT karat FROM players WHERE id = $1', [playerId]);
    const { rows: [n] } = await pool.query(
        `SELECT COUNT(*) FILTER (WHERE status = 'active')::int AS active,
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day')::int AS today
         FROM auctions WHERE seller_id = $1`, [playerId]);
    return {
        eligible: e.ok, reasons: e.reasons, karat: p.karat,
        limits: { ...e.limits, activeUsed: n.active, todayUsed: n.today, leadingBids: S.MAX_LEADING_BIDS },
        rules: {
            minLevel: S.MIN_LEVEL, minAccountDays: S.MIN_ACCOUNT_DAYS, durationHours: S.DURATION_HOURS,
            snipeSeconds: S.SNIPE_SECONDS, prices: S.PRICES, listingFeePct: S.LISTING_FEE_PCT,
            listingFeeMin: S.LISTING_FEE_MIN, saleFeePct: S.SALE_FEE_PCT,
        },
    };
}

/** Running auctions, soonest to end first. filter: { rarity, clan, search } */
async function browse(playerId, filter = {}) {
    await settleDue();
    const where = [`a.status = 'active'`];
    const params = [];
    if (filter.rarity) { params.push(Number(filter.rarity)); where.push(`a.rarity = $${params.length}`); }
    if (filter.clan) { params.push(String(filter.clan)); where.push(`c.clan::text = $${params.length}`); }
    if (filter.search) { params.push('%' + String(filter.search).slice(0, 40) + '%'); where.push(`c.name ILIKE $${params.length}`); }
    const { rows } = await pool.query(`${SELECT} WHERE ${where.join(' AND ')} ORDER BY a.ends_at LIMIT 200`, params);
    return rows.map(a => view(a, playerId));
}

/** Your auctions and bids: running ones, and those finished in the last 7 days. */
async function mine(playerId) {
    await settleDue();
    const { rows: selling } = await pool.query(
        `${SELECT} WHERE a.seller_id = $1 AND (a.status = 'active' OR a.settled_at > NOW() - INTERVAL '7 days')
         ORDER BY a.status <> 'active', a.ends_at DESC LIMIT 100`, [playerId]);
    const { rows: bidding } = await pool.query(
        `${SELECT} WHERE a.id IN (SELECT auction_id FROM auction_bids WHERE bidder_id = $1)
           AND (a.status = 'active' OR a.settled_at > NOW() - INTERVAL '7 days')
         ORDER BY a.status <> 'active', a.ends_at DESC LIMIT 100`, [playerId]);
    return {
        selling: selling.map(a => view(a, playerId)),
        bidding: bidding.map(a => ({ ...view(a, playerId), won: a.status === 'sold' && a.high_bidder === playerId })),
    };
}

/** Put one copy of a card up for auction. → { auction, karat } */
async function list(playerId, gameId, startPrice, ip = null) {
    if (!Number.isInteger(startPrice)) throw new AuctionError('Choose a starting price.');
    if ((await import('../../shared/turf.js')).prizeCardIds().has(gameId)) {
        throw new AuctionError("A boss's prize can't be sold.");
    }
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query('SELECT id FROM players WHERE id = $1 FOR UPDATE', [playerId]);   // (one listing at a time per player: the limits hold)
        const e = await requireEligible(playerId, client);
        const { rows: [n] } = await client.query(
            `SELECT COUNT(*) FILTER (WHERE status = 'active')::int AS active,
                    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day')::int AS today
             FROM auctions WHERE seller_id = $1`, [playerId]);
        if (n.active >= e.limits.active) throw new AuctionError(`You can have ${e.limits.active} auctions running at once.`);
        if (n.today >= e.limits.perDay) throw new AuctionError(`You can start ${e.limits.perDay} auctions a day. Try again tomorrow.`);
        const { rows: [row] } = await client.query(
            `SELECT c.id, c.name, c.rarity, pi.quantity FROM player_inventory pi JOIN cards c ON c.id = pi.card_id
             WHERE pi.player_id = $1 AND c.art_url = $2 FOR UPDATE OF pi`, [playerId, gameId]);
        if (!row) throw new AuctionError("You don't own that card.");
        const needed = (await copiesInDecks(client, playerId)).get(row.id) || 0;
        if (row.quantity - 1 < needed) {
            throw new AuctionError(`Your decks use ${needed === 1 ? 'your copy' : `all ${needed} copies`} of ${row.name}. Take it out of a deck to sell it.`);
        }
        const { min, max } = priceRange(row.rarity);
        if (startPrice < min || startPrice > max) {
            throw new AuctionError(`${row.name} can start between ${min} and ${max} Karat.`);
        }
        const fee = listingFee(startPrice);
        const { rows: [p] } = await client.query(
            'UPDATE players SET karat = karat - $1 WHERE id = $2 AND karat >= $1 RETURNING karat', [fee, playerId]);
        if (!p) throw new AuctionError(`Listing it costs ${fee} Karat.`);
        if (row.quantity > 1) {
            await client.query('UPDATE player_inventory SET quantity = quantity - 1 WHERE player_id = $1 AND card_id = $2', [playerId, row.id]);
        } else {
            await client.query('DELETE FROM player_inventory WHERE player_id = $1 AND card_id = $2', [playerId, row.id]);
        }
        const { rows: [a] } = await client.query(
            `INSERT INTO auctions (seller_id, card_id, rarity, start_price, listing_fee, seller_ip, ends_at)
             VALUES ($1, $2, $3, $4, $5, $6, NOW() + make_interval(hours => $7)) RETURNING id`,
            [playerId, row.id, row.rarity, startPrice, fee, ip, S.DURATION_HOURS]);
        await client.query('COMMIT');
        const { rows: [full] } = await pool.query(`${SELECT} WHERE a.id = $1`, [a.id]);
        return { auction: view(full, playerId), karat: p.karat };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/** Bid `amount` Karat. → { auction, karat } */
async function bid(playerId, auctionId, amount, ip = null) {
    if (!Number.isInteger(amount) || amount < 1) throw new AuctionError('Enter a bid.');
    const mail = [];
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [a] } = await client.query(`${SELECT} WHERE a.id = $1 FOR UPDATE OF a`, [auctionId]);
        if (!a || a.status !== 'active' || new Date(a.ends_at) <= new Date()) throw new AuctionError('That auction has ended.');
        if (a.seller_id === playerId) throw new AuctionError("You can't bid on your own auction.");
        if (a.high_bidder === playerId) throw new AuctionError("You're already the top bidder.");
        await requireEligible(playerId, client);
        const least = minBid(a);
        if (least == null) throw new AuctionError(`${a.card_name} has reached its highest price.`);
        if (amount < least) throw new AuctionError(`Bid at least ${least} Karat.`);
        const { max } = priceRange(a.rarity);
        if (amount > max) throw new AuctionError(`${a.card_name} sells for at most ${max} Karat.`);
        const { rows: [lead] } = await client.query(
            `SELECT COUNT(*)::int AS n FROM auctions WHERE status = 'active' AND high_bidder = $1`, [playerId]);
        if (lead.n >= S.MAX_LEADING_BIDS) throw new AuctionError(`You can be the top bidder on ${S.MAX_LEADING_BIDS} auctions at once.`);
        const { rows: [p] } = await client.query(
            'UPDATE players SET karat = karat - $1 WHERE id = $2 AND karat >= $1 RETURNING karat', [amount, playerId]);
        if (!p) throw new AuctionError(`You need ${amount} Karat to bid that.`);
        if (a.high_bidder) {   // the bid it beats: its Karat goes back
            await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2', [a.high_bid, a.high_bidder]);
            mail.push([a.high_bidder, `Outbid: ${a.card_name}`,
                `Someone bid ${amount} Karat on ${a.card_name}, beating your ${a.high_bid}. Your ${a.high_bid} Karat is back in your balance.\n\nThe auction house is in the Shop.`]);
        }
        await client.query(
            `UPDATE auctions SET high_bid = $1, high_bidder = $2, bids = bids + 1,
                    ends_at = GREATEST(ends_at, NOW() + make_interval(secs => $3)) WHERE id = $4`,
            [amount, playerId, S.SNIPE_SECONDS, a.id]);
        await client.query('INSERT INTO auction_bids (auction_id, bidder_id, amount, ip) VALUES ($1, $2, $3, $4)', [a.id, playerId, amount, ip]);
        await client.query('COMMIT');
        await sendAll(mail);
        const { rows: [full] } = await pool.query(`${SELECT} WHERE a.id = $1`, [a.id]);
        return { auction: view(full, playerId), karat: p.karat };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

/** Take a listing down before anyone bids: the card comes back (not the listing fee). */
async function cancel(playerId, auctionId) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const { rows: [a] } = await client.query('SELECT * FROM auctions WHERE id = $1 FOR UPDATE', [auctionId]);
        if (!a || a.seller_id !== playerId) throw new AuctionError('That auction isn\'t yours.');
        if (a.status !== 'active') throw new AuctionError('That auction has ended.');
        if (a.high_bidder || a.bids > 0) throw new AuctionError('Someone has bid on it: it runs to the end.');
        await giveCard(client, playerId, a.card_id);
        await client.query(`UPDATE auctions SET status = 'cancelled', settled_at = NOW() WHERE id = $1`, [a.id]);
        await client.query('COMMIT');
        return { ok: true };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function giveCard(client, playerId, cardId) {
    await client.query(
        `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, 1)
         ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = player_inventory.quantity + 1`, [playerId, cardId]);
}

async function sendAll(mail) {
    for (const [playerId, subject, body] of mail) {
        await pool.query(`INSERT INTO player_mail (player_id, sender, subject, body) VALUES ($1, 'Auction House', $2, $3)`,
            [playerId, subject, body]).catch(err => console.error('[Auction] mail:', err.message));
    }
}

/** Why a sale looks like one person trading with themselves: same_ip, repeat_pair. */
async function flagsFor(client, a) {
    const flags = [];
    const ips = async (id, extra) => {
        const { rows } = await client.query(
            `SELECT signup_ip AS ip FROM players WHERE id = $1
             UNION SELECT ip FROM auction_bids WHERE bidder_id = $1 AND created_at > NOW() - make_interval(days => $2)
             UNION SELECT seller_ip FROM auctions WHERE seller_id = $1 AND created_at > NOW() - make_interval(days => $2)`,
            [id, S.REPEAT_PAIR_DAYS]);
        return new Set([...rows.map(r => r.ip), extra].filter(Boolean));
    };
    const seller = await ips(a.seller_id, a.seller_ip);
    const buyer = await ips(a.high_bidder);
    if ([...buyer].some(ip => seller.has(ip))) flags.push('same_ip');
    const { rows: [pair] } = await client.query(
        `SELECT COUNT(*)::int AS n FROM auctions WHERE status = 'sold' AND settled_at > NOW() - make_interval(days => $3)
           AND ((seller_id = $1 AND high_bidder = $2) OR (seller_id = $2 AND high_bidder = $1))`,
        [a.seller_id, a.high_bidder, S.REPEAT_PAIR_DAYS]);
    if (pair.n + 1 >= S.REPEAT_PAIR_SALES) flags.push('repeat_pair');
    return flags;
}

/** Finish the auctions whose time is up. → how many it finished */
async function settleDue() {
    let done = 0;
    for (;;) {
        const mail = [];
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            const { rows: [a] } = await client.query(
                `${SELECT} WHERE a.status = 'active' AND a.ends_at <= NOW() ORDER BY a.ends_at LIMIT 1 FOR UPDATE OF a SKIP LOCKED`);
            if (!a) {
                await client.query('COMMIT');
                return done;
            }
            if (a.high_bidder) {
                const fee = saleFee(a.high_bid);
                const flags = a.seller_id ? await flagsFor(client, a) : [];
                await giveCard(client, a.high_bidder, a.card_id);
                if (a.seller_id) await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2', [a.high_bid - fee, a.seller_id]);
                await client.query(
                    `UPDATE auctions SET status = 'sold', sale_fee = $1, flags = $2, settled_at = NOW() WHERE id = $3`, [fee, flags, a.id]);
                mail.push([a.high_bidder, `You won ${a.card_name}`,
                    `Your bid of ${a.high_bid} Karat won the auction: ${a.card_name} is in your collection.`]);
                if (a.seller_id) {
                    mail.push([a.seller_id, `Sold: ${a.card_name}`,
                        `${a.card_name} sold for ${a.high_bid} Karat. After the ${S.SALE_FEE_PCT}% fee (${fee}), ${a.high_bid - fee} Karat is in your balance.`]);
                }
            } else {
                if (a.seller_id) await giveCard(client, a.seller_id, a.card_id);
                await client.query(`UPDATE auctions SET status = 'unsold', settled_at = NOW() WHERE id = $1`, [a.id]);
                if (a.seller_id) {
                    mail.push([a.seller_id, `No bids: ${a.card_name}`,
                        `Nobody bid on ${a.card_name}, so it's back in your collection.`]);
                }
            }
            await client.query('COMMIT');
            done++;
            await sendAll(mail);
        } catch (err) {
            await client.query('ROLLBACK').catch(() => {});
            throw err;
        } finally {
            client.release();
        }
    }
}

/** Deleting an account (routes/account.js), inside its transaction: bids on its auctions are refunded, and
 *  where it was the top bidder the auction carries on without that bid (its Karat goes with the account). */
async function forgetPlayer(client, playerId) {
    const { rows: theirs } = await client.query(
        `SELECT a.id, a.high_bid, a.high_bidder, c.name FROM auctions a JOIN cards c ON c.id = a.card_id
         WHERE a.seller_id = $1 AND a.status = 'active' FOR UPDATE OF a`, [playerId]);
    for (const a of theirs) {
        if (a.high_bidder && a.high_bidder !== playerId) {
            await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2', [a.high_bid, a.high_bidder]);
            await client.query(`INSERT INTO player_mail (player_id, sender, subject, body) VALUES ($1, 'Auction House', $2, $3)`,
                [a.high_bidder, `Auction cancelled: ${a.name}`, `The seller left the game, so the auction for ${a.name} is off. Your ${a.high_bid} Karat is back in your balance.`]);
        }
        await client.query(`UPDATE auctions SET status = 'cancelled', settled_at = NOW() WHERE id = $1`, [a.id]);
    }
    await client.query(
        `UPDATE auctions SET high_bid = NULL, high_bidder = NULL WHERE status = 'active' AND high_bidder = $1`, [playerId]);
}

/** Delete finished auctions (and their bids) KEEP_DAYS after they end. */
async function cleanup() {
    const { rowCount } = await pool.query(
        `DELETE FROM auctions WHERE status <> 'active' AND settled_at < NOW() - make_interval(days => $1)`, [S.KEEP_DAYS]);
    return rowCount;
}

/** Flagged sales and the pairs of players who trade most (backend/scripts/auction_report.mjs). */
async function report(days = 30) {
    const { rows: flagged } = await pool.query(
        `SELECT a.id, a.settled_at, a.high_bid, a.flags, c.name AS card, s.username AS seller, b.username AS buyer
         FROM auctions a JOIN cards c ON c.id = a.card_id
         LEFT JOIN players s ON s.id = a.seller_id LEFT JOIN players b ON b.id = a.high_bidder
         WHERE a.status = 'sold' AND cardinality(a.flags) > 0 AND a.settled_at > NOW() - make_interval(days => $1)
         ORDER BY a.settled_at DESC`, [days]);
    const { rows: pairs } = await pool.query(
        `SELECT LEAST(s.username, b.username) AS a, GREATEST(s.username, b.username) AS b, COUNT(*)::int AS sales,
                SUM(x.high_bid)::int AS karat
         FROM auctions x JOIN players s ON s.id = x.seller_id JOIN players b ON b.id = x.high_bidder
         WHERE x.status = 'sold' AND x.settled_at > NOW() - make_interval(days => $1)
         GROUP BY 1, 2 HAVING COUNT(*) >= 2 ORDER BY sales DESC LIMIT 50`, [days]);
    const { rows: shared } = await pool.query(
        `SELECT signup_ip, array_agg(username ORDER BY created_at) AS players FROM players
         WHERE signup_ip IS NOT NULL GROUP BY signup_ip HAVING COUNT(*) > 1`);
    return { flagged, pairs, sharedSignups: shared.map(r => r.players) };
}

module.exports = {
    eligibility, overview, browse, mine, list, bid, cancel, settleDue, forgetPlayer, cleanup, report,
    minBid, listingFee, saleFee, AuctionError, SETTINGS: S,
};
