-- Turf Defense (economy/turf.js): each player's attempts and clears of each boss level
CREATE TABLE IF NOT EXISTS boss_clears (
    player_id        UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    boss_id          TEXT        NOT NULL,              -- godot/data/bosses.json
    level            SMALLINT    NOT NULL,
    clears           INTEGER     NOT NULL DEFAULT 0,
    attempts         INTEGER     NOT NULL DEFAULT 0,
    best_turns       INTEGER,                           -- the fewest turns a clear took
    first_cleared_at TIMESTAMPTZ,
    PRIMARY KEY (player_id, boss_id, level)
);
