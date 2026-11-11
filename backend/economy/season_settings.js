'use strict';

/**
 * RANKED SEASONS: every number (economy/seasons.js uses them). Decided 2026-11-11: rewards go by the
 * highest rank a player reached in the season, and a new season drops everyone back two ranks.
 */

// What a season pays, by the highest rank reached in it (only players who played Ranked that season).
// A pack is worth 200 Karat (routes/shop.js). Legend also gets the season's prize card (shared/seasons.js).
const REWARDS = {
    rookie:       { karat: 100, free_packs: 0 },
    street_tough: { karat: 250, free_packs: 1 },
    enforcer:     { karat: 400, free_packs: 2 },
    underboss:    { karat: 600, free_packs: 3 },
    kingpin:      { karat: 800, free_packs: 4 },
    legend:       { karat: 1000, free_packs: 5, prize: true },
};

// How many ranks everyone drops at the start of a new season (Legend → Underboss, Enforcer → Rookie):
// they start at the bottom of that rank.
const SOFT_RESET_TIERS = 2;

// A new season's planned length when none is given (backend/scripts/season.mjs end --weeks N)
const DEFAULT_WEEKS = 13;

module.exports = { REWARDS, SOFT_RESET_TIERS, DEFAULT_WEEKS };
