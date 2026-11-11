// Ranked seasons: the prize card each season gives everyone who reaches Legend in it (the server's
// side is backend/economy/seasons.js). Like the Turf Defense bosses' prizes, a season's prize is never
// in packs, never crafted, scrapped or sold: reaching Legend that season is the only way to get it.
// Set a season's prize to the card's game ID once the card is in the game ('' = none yet); a Striver
// comes with its higher levels.

import { CARD_CATALOG } from './cards.js';

export const SEASON_PRIZES = {
    0: '',
};

/** A prize and the levels it promotes into. */
function line(id) {
    const out = [];
    for (let cur = id; cur && CARD_CATALOG[cur] && !out.includes(cur); cur = CARD_CATALOG[cur].promotesTo || '') out.push(cur);
    return out;
}

/** The cards a season's Legend prize gives (its levels too), or [] (none set, or not in the game yet). */
export const seasonPrize = (season) => line(SEASON_PRIZES[season] || '');

/** Every season prize card and its levels. */
export function seasonPrizeCardIds() {
    return new Set(Object.keys(SEASON_PRIZES).flatMap((s) => seasonPrize(s)));
}
