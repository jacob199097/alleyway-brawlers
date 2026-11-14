'use strict';

/**
 * Away, not gone: the same rule for every kind of match (onlineMatch.js, ffaMatch.js, coopMatch.js).
 *
 * A phone freezes the game while it's minimized, so its connection doesn't close: it stops answering and
 * times out ("ping timeout"). Such a player keeps their seat and their moves are played for them, as for
 * anyone who isn't acting (the away rule decides when they're out), and they come back into the match when
 * they open the game again. A game that closed its connection (quit or closed, on a phone too: swiping it
 * away ends it at once, crashed) gets the usual minute to come back, with nothing played for it meanwhile.
 */
function awayNotGone(reason) {
    return reason === 'ping timeout';
}

module.exports = { awayNotGone };
