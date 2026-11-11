-- Ranked seasons (economy/seasons.js). One row per season, its number as the id. The season with no
-- ended_at is the current one; ends_at is when it's planned to end (NULL: not set yet. Season 0, the
-- pre-launch season, ends at the launch wipe).
CREATE TABLE IF NOT EXISTS seasons (
    id          INT         PRIMARY KEY,
    name        TEXT        NOT NULL,
    subtitle    TEXT        NOT NULL DEFAULT '',
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at     TIMESTAMPTZ,
    ended_at    TIMESTAMPTZ
);
INSERT INTO seasons (id, name) VALUES (0, 'Season 0') ON CONFLICT (id) DO NOTHING;

-- This season: how many Ranked games the player has played, and the most Rank Points they've had
-- (rewards go by the highest rank reached, not the rank at the end). postMatch.js keeps both.
ALTER TABLE players ADD COLUMN IF NOT EXISTS season_ranked INT NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS season_peak_points INT NOT NULL DEFAULT 0;
UPDATE players SET season_peak_points = rank_points WHERE season_peak_points < rank_points;

-- A finished season, for each player who played Ranked in it: the highest rank they reached and its
-- reward ({karat, free_packs, cards: [game ids]}), claimed in the game. Kept by the launch wipe, so
-- Season 0's rewards are claimed on the new accounts.
CREATE TABLE IF NOT EXISTS player_seasons (
    player_id    UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    season       INT         NOT NULL REFERENCES seasons(id),
    ranked_games INT         NOT NULL,
    peak_points  INT         NOT NULL,
    peak_tier    TEXT        NOT NULL,
    final_points INT         NOT NULL,
    reward       JSONB       NOT NULL DEFAULT '{}',
    claimed_at   TIMESTAMPTZ,
    PRIMARY KEY (player_id, season)
);
CREATE INDEX IF NOT EXISTS idx_player_seasons_unclaimed ON player_seasons (player_id) WHERE claimed_at IS NULL;
