-- Email verification + password-reset columns
-- Run once: psql $DATABASE_URL -f db/migrate_email_auth.sql

ALTER TABLE players
    ADD COLUMN IF NOT EXISTS email_verified      BOOLEAN     NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS email_token         TEXT,
    ADD COLUMN IF NOT EXISTS reset_token         TEXT,
    ADD COLUMN IF NOT EXISTS reset_token_expires TIMESTAMPTZ;

-- Index so token lookups are fast
CREATE INDEX IF NOT EXISTS idx_players_email_token  ON players (email_token)  WHERE email_token  IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_players_reset_token  ON players (reset_token)  WHERE reset_token  IS NOT NULL;
