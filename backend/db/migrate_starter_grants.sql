-- Which clans' starter decks each player has been given (routes/onboarding.js), so none is given twice.
-- Until the launch wipe every player gets every clan's starter (GIVE_ALL_STARTERS); the clan a player
-- picked at the start counts as given.
CREATE TABLE IF NOT EXISTS player_starter_grants (
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    clan        TEXT        NOT NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, clan)
);

INSERT INTO player_starter_grants (player_id, clan)
SELECT id, chosen_clan FROM players WHERE chosen_clan IS NOT NULL
ON CONFLICT DO NOTHING;
