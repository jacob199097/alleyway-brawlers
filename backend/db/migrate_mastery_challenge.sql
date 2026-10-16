-- Per-deck records, clan mastery, the weekly challenge and match stats for the balance dashboard.
-- Safe to run again.

-- Each deck's games and wins (socket/onlineMatch.js finish → shown in the deck builder and profile)
ALTER TABLE decks ADD COLUMN IF NOT EXISTS games INTEGER NOT NULL DEFAULT 0;
ALTER TABLE decks ADD COLUMN IF NOT EXISTS wins INTEGER NOT NULL DEFAULT 0;

-- Clan mastery: experience for playing each clan (economy/mastery.js)
CREATE TABLE IF NOT EXISTS clan_mastery (
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    clan        TEXT        NOT NULL,
    xp          INTEGER     NOT NULL DEFAULT 0,
    games       INTEGER     NOT NULL DEFAULT 0,
    wins        INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id, clan)
);

-- The weekly challenge: one paid win per player per week (economy/challenge.js)
CREATE TABLE IF NOT EXISTS weekly_challenge_wins (
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    week        INTEGER     NOT NULL,
    won_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, week)
);

-- One row per finished match: each side's clan, deck, and the cards drawn and played
-- (backend/scripts/balance_dashboard.js reads them)
CREATE TABLE IF NOT EXISTS match_stats (
    id          UUID        PRIMARY KEY,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mode        TEXT        NOT NULL,
    version     TEXT,
    data        JSONB       NOT NULL
);
CREATE INDEX IF NOT EXISTS match_stats_created ON match_stats (created_at);
