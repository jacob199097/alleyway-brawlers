-- Steam (routes/steam.js): players who sign in with Steam, and Steam wallet orders
ALTER TABLE players ADD COLUMN IF NOT EXISTS steam_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS players_steam_id_key ON players (steam_id) WHERE steam_id IS NOT NULL;
-- A Steam-only player has no email or password
ALTER TABLE players ALTER COLUMN email DROP NOT NULL;
ALTER TABLE players ALTER COLUMN password_hash DROP NOT NULL;

CREATE TABLE IF NOT EXISTS steam_orders (
    order_id     BIGSERIAL   PRIMARY KEY,              -- Steam's orderid (unique per app)
    player_id    UUID        REFERENCES players(id) ON DELETE SET NULL,
    steam_id     TEXT        NOT NULL,
    bundle_id    TEXT        NOT NULL,
    amount_cents INTEGER     NOT NULL,
    currency     TEXT        NOT NULL DEFAULT 'USD',
    status       TEXT        NOT NULL DEFAULT 'init',  -- init | done | failed
    trans_id     TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finalized_at TIMESTAMPTZ
);
