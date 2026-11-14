-- Phone notifications (utils/push.js): each phone's Firebase Cloud Messaging token, the account signed in on it
-- and its clock's offset from UTC in minutes (so reminders come at a sensible hour there). Removed when the game
-- signs out or turns notifications off, when Firebase says the token is dead, and with the account.
CREATE TABLE IF NOT EXISTS push_tokens (
    token       TEXT        PRIMARY KEY,
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    platform    TEXT        NOT NULL DEFAULT 'android',
    tz_minutes  INT         NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS push_tokens_player ON push_tokens (player_id);

-- News for every phone (a new game version, new cards): sent to each over the next two days, in its daytime
CREATE TABLE IF NOT EXISTS push_outbox (
    id          BIGSERIAL   PRIMARY KEY,
    title       TEXT        NOT NULL,
    body        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- What has gone out once ('daily:<player>:<day>', 'turf:<week>:<player>', 'season:<id>:<player>',
-- 'out:<outbox id>:<player>', 'version:<version>'): kept 60 days
CREATE TABLE IF NOT EXISTS push_sent (
    key         TEXT        PRIMARY KEY,
    at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
