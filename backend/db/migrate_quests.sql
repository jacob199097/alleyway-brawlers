-- Quest tracking tables for AlleyWay Brawlers

CREATE TABLE IF NOT EXISTS player_daily_quests (
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_id    TEXT NOT NULL,
    quest_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    progress    INTEGER NOT NULL DEFAULT 0,
    claimed     BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (player_id, quest_id, quest_date)
);

CREATE TABLE IF NOT EXISTS player_quest_claims (
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_id    TEXT NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, quest_id)
);
