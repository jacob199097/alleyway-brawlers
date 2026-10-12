/**
 * CARD CATALOG
 * Rules data for every card, keyed by game ID (also the art key: assets/cards/<id>.png).
 * Shared by the client (solo duels, deck loading) and the server (online matches).
 * Every card comes from the Card Forge (shared/cards_forge.js, written by tools/import_forge.mjs).
 */

import { FORGE_CARDS } from './cards_forge.js';

export const CARD_CATALOG = { ...FORGE_CARDS };

// Every card names its clan for the game's screens (shared/clans.js): the name and colour set in
// the Forge
for (const c of Object.values(CARD_CATALOG)) {
    if (!c.clanName) c.clanName = String(c.clan || '').replace(/_/g, ' ').replace(/\b\w/g, ch => ch.toUpperCase());
    if (!c.clanColor) c.clanColor = '#b388ff';
}
