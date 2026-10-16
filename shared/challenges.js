/**
 * The weekly challenge: one rules twist a week (the list goes round in order), played against
 * the server CPU (socket/onlineMatch.js, mp:cpu {challenge: true}). The first win each week pays
 * REWARD (backend/economy/challenge.js). Both rules engines apply a twist's rules
 * (DuelState.js / duel_state.gd: start_authority, start_morale, opening_hand, pierce).
 */

export const TWISTS = [
    { id: 'war_chest', name: 'War Chest', text: 'Both players start with 3 Authority.', rules: { start_authority: 3 } },
    { id: 'short_fuse', name: 'Short Fuse', text: 'Both players start with 3000 Morale.', rules: { start_morale: 3000 } },
    { id: 'full_hands', name: 'Full Hands', text: 'Opening hands have 7 cards.', rules: { opening_hand: 7 } },
    { id: 'armour_piercing', name: 'Armour Piercing', text: 'Every attack has PIERCE: beating a DEF character costs its owner Morale too.', rules: { pierce: true } },
];

/** What the first win of the week pays. */
export const REWARD = { karat: 300, free_packs: 1 };

const WEEK_MS = 7 * 24 * 3600 * 1000;
// Weeks start on Monday 00:00 UTC (1970-01-05 was a Monday)
const EPOCH = Date.UTC(1970, 0, 5);

/** This week's challenge: {week, id, name, text, rules, ends_at}. */
export function weeklyChallenge(now = Date.now()) {
    const week = Math.floor((now - EPOCH) / WEEK_MS);
    const twist = TWISTS[((week % TWISTS.length) + TWISTS.length) % TWISTS.length];
    return { week, ...twist, rules: { ...twist.rules }, ends_at: new Date(EPOCH + (week + 1) * WEEK_MS).toISOString() };
}
