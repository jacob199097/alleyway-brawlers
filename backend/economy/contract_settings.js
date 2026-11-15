'use strict';

/**
 * CONTRACTS: every number in one place (economy/contracts.js uses them). A contract is bought in the shop
 * and covers the player's next MATCHES eligible matches; done in one of them, it pays its payout (paid the
 * moment it's done; a "win" one at the end of a match it was won); not done by then, its price is lost.
 *
 * Each goal: text (what the player reads), price and payout (Karat), win (only counts in a match the player
 * wins), and how it's judged from the match's events (see track / met in contracts.js):
 *   count: an event that counts toward need (event, mySeat) → true
 *   sum:   an amount that adds up toward need (event, mySeat) → number
 *   spoil: an event that rules it out for the rest of the match (event, mySeat) → true
 *   end:   checked once the match is over ({ morale, turns }) → true
 */

const MATCHES = 3;        // eligible matches a contract lasts
const OFFERS = 3;         // contracts on sale each day (the same for everyone; new ones at 00:00 UTC)
// Eligible matches: Casual, Ranked, and CPU matches on Normal or harder (not a weekly challenge's twist)
const CPU_LEVELS = ['normal', 'hard'];
const MODES = ['casual', 'ranked', 'cpu_ranked', 'cpu'];

const enemy = (ev, me) => ev.side && ev.side !== me;
const GOALS = {
    ko_3: { text: 'KO 3 enemy characters in one match', price: 100, payout: 250, need: 3,
        count: (ev, me) => ev.type === 'ko' && enemy(ev, me) && !ev.exiled },
    ko_5: { text: 'KO 5 enemy characters in one match', price: 200, payout: 500, need: 5,
        count: (ev, me) => ev.type === 'ko' && enemy(ev, me) && !ev.exiled },
    down_5: { text: 'Down 5 enemy characters in one match', price: 150, payout: 375, need: 5,
        count: (ev, me) => ev.type === 'downed' && enemy(ev, me) },
    direct_2000: { text: 'Deal 2000 Morale damage with direct attacks in one match', price: 150, payout: 375, need: 2000,
        sum: (ev, me) => (ev.type === 'clash' && ev.side === me && ev.vs === 'DIRECT' ? Number(ev.att) || 0 : 0) },
    promote_1: { text: 'PROMOTE a Striver', price: 100, payout: 250, need: 1,
        count: (ev, me) => ev.type === 'promote' && ev.side === me },
    awaken: { text: 'Awaken your leader', price: 150, payout: 375, need: 1,
        count: (ev, me) => ev.type === 'awaken' && ev.side === me },
    hustles_3: { text: 'Play 3 Hustles in one match', price: 100, payout: 250, need: 3,
        count: (ev, me) => ev.side === me && (ev.type === 'hustle' || (ev.type === 'lasting' && ev.card?.cardType === 'hustle')) },
    win_morale_3000: { text: 'Win with 3000 or more Morale left', price: 150, payout: 375, win: true,
        end: (m) => m.morale >= 3000 },
    win_leader_safe: { text: 'Win without your leader being attacked', price: 150, payout: 375, win: true,
        spoil: (ev, me) => ev.type === 'leader_hit' && ev.side === me, end: () => true },
    win_fast: { text: 'Win in 12 turns or fewer', price: 200, payout: 500, win: true,
        end: (m) => m.turns <= 12 },
    win_no_losses: { text: "Win without losing a character to a KO", price: 200, payout: 500, win: true,
        spoil: (ev, me) => ev.type === 'ko' && ev.side === me && !ev.card?.token, end: () => true },
};

module.exports = { MATCHES, OFFERS, CPU_LEVELS, MODES, GOALS };
