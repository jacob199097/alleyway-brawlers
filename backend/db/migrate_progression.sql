-- Crafting and achievements. Safe to run again: backend/db/migrate.js runs it when the server starts.

-- Dust: made by scrapping cards, spent crafting them (economy/crafting.js)
ALTER TABLE players ADD COLUMN IF NOT EXISTS dust INTEGER NOT NULL DEFAULT 0 CHECK (dust >= 0);
-- Cosmetics unlocked by achievements (economy/achievements.js)
ALTER TABLE players ADD COLUMN IF NOT EXISTS title TEXT;       -- the achievement whose title is shown (NULL = level title)
ALTER TABLE players ADD COLUMN IF NOT EXISTS card_back TEXT;   -- 'default', a clan id, or NULL = the deck's clan back

-- Running totals achievements are measured against (matches played, KOs, packs opened, ...)
CREATE TABLE IF NOT EXISTS player_counters (
    player_id   UUID    NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    key         TEXT    NOT NULL,
    value       INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id, key)
);

CREATE TABLE IF NOT EXISTS player_achievements (
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    achievement_id  TEXT        NOT NULL,
    unlocked_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, achievement_id)
);
