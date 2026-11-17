-- The profile showcase (economy/showcase.js): up to three cards a player picks to show off (game card ids, in
-- order), shown on their profile and in the match intro. Only cards they own count (checked on save and read).
ALTER TABLE players ADD COLUMN IF NOT EXISTS showcase TEXT[] NOT NULL DEFAULT '{}';
