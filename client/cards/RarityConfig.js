/**
 * RARITY CONFIG — single source of truth for the 5-tier rarity system.
 * Import this wherever rarity labels or colours are needed.
 */

export const RARITY = {
    COMMON:     1,
    RARE:       2,
    EPIC:       3,
    LEGENDARY:  4,
    MYTHIC:     5,
};

export const RARITY_LABEL = {
    1: 'Common',
    2: 'Rare',
    3: 'Epic',
    4: 'Legendary',
    5: 'Mythic',
};

/** Hex colour per rarity, used for card borders, text, and UI accents. */
export const RARITY_COLOR = {
    1: '#aaaaaa',   // Common    — grey
    2: '#4cc9f0',   // Rare      — blue
    3: '#f4d35e',   // Epic      — gold
    4: '#c77dff',   // Legendary — purple
    5: '#ff6b35',   // Mythic    — fiery orange
};

/** Glow/shadow intensity multiplier per rarity (for card shine effects). */
export const RARITY_GLOW = {
    1: 0,
    2: 0.3,
    3: 0.6,
    4: 0.85,
    5: 1.0,
};
