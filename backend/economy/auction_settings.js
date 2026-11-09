'use strict';

/**
 * AUCTION HOUSE SETTINGS — every number the auction house uses (economy/auction.js). Change them here.
 *
 * Most of it is there to stop one person moving cards or Karat between their own accounts: a fresh
 * account farmed to level 5 for its free packs mustn't be able to hand its pulls to a main account for 1
 * Karat, or buy the main's junk for a fortune. Prices have a floor and a ceiling per rarity, auctions run a
 * fixed time in public (anyone can outbid a cheap listing), every sale pays a fee, and accounts need some
 * history before they can trade at all.
 *
 * A pack is 200 Karat for 3 cards and a win pays 40 (routes/shop.js, economy/postMatch.js). On average a
 * pack gives about 0.14 Legendaries and 0.46 Epics (economy/packOpener.js), so a Legendary "costs" about
 * 1400 Karat in packs: the prices below sit around that.
 */

module.exports = {
    // ── Who can use it ──
    MIN_LEVEL: 5,
    MIN_ACCOUNT_DAYS: 7,
    REQUIRE_VERIFIED: true,     // a confirmed email address, or an account made with Steam
    REQUIRE_STEAM: false,       // at the Steam launch: true = only accounts linked to Steam (docs/LAUNCH_CHECKLIST.md)

    // ── Auctions ──
    DURATION_HOURS: 24,
    SNIPE_SECONDS: 120,         // a bid in the last 2 minutes pushes the end back to 2 minutes after it
    MIN_RAISE_PCT: 5,           // a new bid beats the top bid by at least 5%...
    MIN_RAISE: 5,               // ...and at least 5 Karat

    // ── Prices, in Karat, by rarity (1 Common … 5 Legendary): the lowest starting price and the highest bid ──
    PRICES: {
        1: { min: 10, max: 150 },
        2: { min: 20, max: 300 },
        3: { min: 50, max: 600 },
        4: { min: 150, max: 1500 },
        5: { min: 500, max: 5000 },
    },

    // ── Fees (they leave the game: an auction house needs a Karat sink) ──
    LISTING_FEE_PCT: 5,         // of the starting price, paid when listing, not refunded...
    LISTING_FEE_MIN: 5,         // ...and at least this
    SALE_FEE_PCT: 10,           // of the final price, taken from what the seller gets

    // ── Limits. "Newer" = below level NEWER_LEVEL or an account younger than NEWER_DAYS days ──
    NEWER_LEVEL: 10,
    NEWER_DAYS: 30,
    LIMITS: {
        newer: { active: 3, perDay: 3 },     // auctions running at once / auctions started in the last 24 hours
        regular: { active: 5, perDay: 5 },
    },
    MAX_LEADING_BIDS: 10,       // auctions you can be the top bidder on at once (each one holds your Karat)

    // ── Watching for one person playing several accounts (flags for a person to look at, never automatic) ──
    REPEAT_PAIR_SALES: 3,       // this many sales between the same two players in REPEAT_PAIR_DAYS days...
    REPEAT_PAIR_DAYS: 30,       // ...flags the sale
    KEEP_DAYS: 90,              // finished auctions (and their bids) are deleted this long after they end
};
