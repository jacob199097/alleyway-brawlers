-- The daily reward (economy/daily.js): how many days in a row the player has claimed it, and the
-- last (UTC) day they did. Missing a day starts the streak again from day 1.
ALTER TABLE players ADD COLUMN IF NOT EXISTS daily_streak INT NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS daily_claimed_on DATE;
