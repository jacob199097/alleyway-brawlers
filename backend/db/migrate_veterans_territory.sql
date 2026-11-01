-- Veteran cards (economy/veterans.js): each player's wins and plays with each card (played in the
-- match it counts for), which earn it scuffs, a foil edge, then a gold signature
CREATE TABLE IF NOT EXISTS card_veterans (
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    card_id     TEXT        NOT NULL,
    wins        INTEGER     NOT NULL DEFAULT 0,
    plays       INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id, card_id)
);

-- The turf map (economy/territory.js): influence each player won for their deck's clan in each
-- district (an arena, godot/data/arenas.json) during a week (its Monday, UTC)
CREATE TABLE IF NOT EXISTS territory_influence (
    week        DATE        NOT NULL,
    district    TEXT        NOT NULL,
    clan        TEXT        NOT NULL,
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    points      INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (week, district, clan, player_id)
);
CREATE INDEX IF NOT EXISTS territory_influence_player ON territory_influence (player_id, week);

-- A finished week's Karat, paid once (POST /api/territory/claim)
CREATE TABLE IF NOT EXISTS territory_claims (
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    week        DATE        NOT NULL,
    karat       INTEGER     NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, week)
);
