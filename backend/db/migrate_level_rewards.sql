-- Level rewards: every level gained is a free pack the player picks in the shop
-- (economy/postMatch.js grants them, economy/packOpener.js spends them). Safe to run again.
ALTER TABLE players ADD COLUMN IF NOT EXISTS free_packs INTEGER NOT NULL DEFAULT 0 CHECK (free_packs >= 0);
