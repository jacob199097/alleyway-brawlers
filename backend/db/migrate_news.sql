-- News emails (utils/news.js): a new season, new cards. Only to players who asked for them (Settings → Account
-- in the game: news_emails, off unless they turn it on), with an unsubscribe link in every one.
ALTER TABLE players ADD COLUMN IF NOT EXISTS news_emails BOOLEAN NOT NULL DEFAULT FALSE;

-- One email for everyone who asked: sent from send_after, a batch at a time (the provider's daily limit), until
-- done_at. kind 'cards' waits a while so a week of imports goes out as one email (names, merged in).
CREATE TABLE IF NOT EXISTS news_outbox (
    id          BIGSERIAL   PRIMARY KEY,
    kind        TEXT        NOT NULL,
    subject     TEXT        NOT NULL,
    heading     TEXT        NOT NULL,
    lines       JSONB       NOT NULL DEFAULT '[]',
    names       JSONB       NOT NULL DEFAULT '[]',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    send_after  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    done_at     TIMESTAMPTZ
);

-- Who each one has gone to (so a restart carries on where it stopped, and nobody gets it twice)
CREATE TABLE IF NOT EXISTS news_sent (
    news_id     BIGINT      NOT NULL REFERENCES news_outbox(id) ON DELETE CASCADE,
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (news_id, player_id)
);
CREATE INDEX IF NOT EXISTS news_sent_at ON news_sent (at);
