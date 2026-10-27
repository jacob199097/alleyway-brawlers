-- Profile pictures given to one player by hand (backend/scripts/give_avatar.js), e.g. the art of a card
-- that was based on them. They count as unlocked (economy/achievements.js cosmetics). Safe to re-run.
CREATE TABLE IF NOT EXISTS player_avatar_gifts (
    player_id  UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    avatar     TEXT        NOT NULL,   -- 'card:<game card id>', like players.avatar_url
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, avatar)
);
