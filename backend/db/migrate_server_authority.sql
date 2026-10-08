-- ============================================================
-- Server-authority migration
--   * solo_matches     — server-issued sessions for AI matches, so rewards
--                        can only be claimed once per real match
--   * payment_grants   — one row per Stripe PaymentIntent already redeemed,
--                        so a single payment can't be replayed
--   * player_packs     — unique (player_id, pack_type) so buyPack can upsert
-- Safe to re-run.
-- ============================================================

CREATE TABLE IF NOT EXISTS solo_matches (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    ranked          BOOLEAN     NOT NULL DEFAULT FALSE,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    outcome         TEXT        CHECK (outcome IN ('win', 'loss', 'draw', 'abandoned')),
    rewarded        BOOLEAN     NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_solo_matches_player ON solo_matches (player_id, started_at DESC);

CREATE TABLE IF NOT EXISTS payment_grants (
    payment_intent_id TEXT        PRIMARY KEY,
    player_id         UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    bundle_id         TEXT        NOT NULL,
    contraband        INTEGER     NOT NULL CHECK (contraband > 0),
    granted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Collapse any duplicate pack rows before adding the unique constraint
CREATE TEMP TABLE _pack_merge AS
    SELECT player_id, pack_type, SUM(quantity) AS qty, MIN(id::text)::uuid AS keep_id
    FROM   player_packs
    GROUP  BY player_id, pack_type
    HAVING COUNT(*) > 1;

UPDATE player_packs pp SET quantity = m.qty
FROM   _pack_merge m WHERE pp.id = m.keep_id;

DELETE FROM player_packs pp
USING  _pack_merge m
WHERE  pp.player_id = m.player_id AND pp.pack_type = m.pack_type AND pp.id <> m.keep_id;

DROP TABLE _pack_merge;

CREATE UNIQUE INDEX IF NOT EXISTS player_packs_player_pack_key
    ON player_packs (player_id, pack_type);
