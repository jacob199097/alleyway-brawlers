-- ============================================================
-- TURF WAR TACTICS — PostgreSQL Schema
-- Creates a fresh database with every table and column the backend uses
-- (the migrate_*.sql files are folded in). Then load the card set:
--   psql -d turf_war -f db/schema.sql
--   psql -d turf_war -f db/seed_cards.sql
-- ============================================================

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";   -- case-insensitive text for usernames

-- ============================================================
-- ENUMERATIONS
-- ============================================================

CREATE TYPE card_type   AS ENUM ('gang_member', 'hustle', 'ambush', 'leader');
CREATE TYPE rank_tier   AS ENUM (
    'rookie', 'street_tough', 'enforcer', 'underboss', 'kingpin', 'legend'
);
CREATE TYPE match_result AS ENUM ('win', 'loss', 'draw');
CREATE TYPE friend_status AS ENUM ('pending', 'accepted', 'blocked');
CREATE TYPE pack_type    AS ENUM ('lion_pride');   -- Card Forge clans are added by backend/scripts/sync_cards.mjs

-- ============================================================
-- PLAYERS
-- ============================================================

CREATE TABLE players (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        CITEXT      NOT NULL UNIQUE,
    email           CITEXT      NOT NULL UNIQUE,
    password_hash   TEXT        NOT NULL,

    -- Economy
    karat           INTEGER     NOT NULL DEFAULT 0  CHECK (karat >= 0),
    contraband      INTEGER     NOT NULL DEFAULT 0  CHECK (contraband >= 0),

    -- Progression
    level           SMALLINT    NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 50),
    xp              INTEGER     NOT NULL DEFAULT 0 CHECK (xp >= 0),

    -- Rank
    rank            rank_tier   NOT NULL DEFAULT 'rookie',
    rank_points     INTEGER     NOT NULL DEFAULT 0 CHECK (rank_points >= 0),

    -- Stats
    wins            INTEGER     NOT NULL DEFAULT 0 CHECK (wins >= 0),
    losses          INTEGER     NOT NULL DEFAULT 0 CHECK (losses >= 0),
    draws           INTEGER     NOT NULL DEFAULT 0 CHECK (draws >= 0),

    -- Daily rewards
    first_win_date  DATE,                                -- tracks first-win-of-day bonus

    -- Profile customization
    avatar_url      TEXT,
    profile_bio     TEXT        CHECK (char_length(profile_bio) <= 200),

    -- Metadata
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_online       BOOLEAN     NOT NULL DEFAULT FALSE,
    socket_id       TEXT,                                 -- current socket.io connection
    chosen_clan     TEXT,                                 -- 'lion_pride', set once at onboarding

    -- Email verification + password reset
    email_verified      BOOLEAN     NOT NULL DEFAULT FALSE,
    email_token         TEXT,
    reset_token         TEXT,
    reset_token_expires TIMESTAMPTZ
);

CREATE INDEX idx_players_email_token ON players (email_token) WHERE email_token IS NOT NULL;
CREATE INDEX idx_players_reset_token ON players (reset_token) WHERE reset_token IS NOT NULL;

-- XP thresholds per level (levels 1-50). Stored separately for easy tuning.
CREATE TABLE level_thresholds (
    level           SMALLINT    PRIMARY KEY CHECK (level BETWEEN 1 AND 50),
    xp_required     INTEGER     NOT NULL    -- total cumulative XP to reach this level
);

-- Seed level thresholds using exponential curve: XP to next level = floor(100 * level^1.5)
-- Cumulative XP to reach level N = sum of floor(100 * i^1.5) for i = 1 to N-1
INSERT INTO level_thresholds (level, xp_required)
SELECT
    lvl,
    COALESCE((
        SELECT SUM(FLOOR(100.0 * i ^ 1.5))::INTEGER
        FROM   generate_series(1, lvl - 1) AS i
    ), 0)
FROM generate_series(1, 50) AS lvl;

-- ============================================================
-- CARDS (master catalogue — not per-player)
-- ============================================================

CREATE TABLE cards (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT        NOT NULL,                 -- a Striver's levels may share a name
    clan            pack_type   NOT NULL,                 -- which clan this card belongs to
    card_type       card_type   NOT NULL,
    clan_tag        TEXT,                                 -- short clan key used by card effects ('lion')
    subtype         TEXT,                                 -- 'striver' | 'brawler' | 'heavy'
    level           SMALLINT,                             -- promotion level (1-3) for Strivers

    -- Gang Member only (NULL for hustles/ambushes)
    authority       SMALLINT    CHECK (authority BETWEEN 1 AND 12),
    attack          INTEGER     CHECK (attack >= 0),
    defense         INTEGER     CHECK (defense >= 0),
    tribute_cost    SMALLINT    NOT NULL DEFAULT 0,       -- how many gang members to retire

    -- Rarity affects pack drop weight: 1=Common,2=Uncommon,3=Rare,4=Epic,5=Legendary
    rarity          SMALLINT    NOT NULL DEFAULT 1 CHECK (rarity BETWEEN 1 AND 5),

    -- Effect description (Hustles / Ambushes)
    effect_text     TEXT,
    effect_key      TEXT,                                 -- maps to client-side effect handler

    -- Art
    art_url         TEXT        UNIQUE,                   -- the card's game ID (shared/cards.js)
    flavour_text    TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PLAYER INVENTORY
-- ============================================================

CREATE TABLE player_inventory (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    card_id         UUID        NOT NULL REFERENCES cards(id),
    quantity        SMALLINT    NOT NULL DEFAULT 1 CHECK (quantity > 0),
    acquired_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (player_id, card_id)
);

-- Index for fast "show my collection" queries
CREATE INDEX idx_inventory_player ON player_inventory(player_id);

-- ============================================================
-- DECKS
-- ============================================================

CREATE TABLE decks (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL DEFAULT 'My Deck',
    is_active       BOOLEAN     NOT NULL DEFAULT FALSE,   -- the deck selected for matchmaking
    leader_card_id  UUID        REFERENCES cards(id),     -- optional leader, kept out of the 40
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE deck_cards (
    deck_id         UUID        NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    card_id         UUID        NOT NULL REFERENCES cards(id),
    copies          SMALLINT    NOT NULL DEFAULT 1 CHECK (copies BETWEEN 1 AND 3),

    PRIMARY KEY (deck_id, card_id)
);

-- Enforce 40-60 card rule via application layer (trigger shown below)
CREATE OR REPLACE FUNCTION enforce_deck_size()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    total_cards INTEGER;
BEGIN
    SELECT COALESCE(SUM(copies), 0)
    INTO   total_cards
    FROM   deck_cards
    WHERE  deck_id = COALESCE(NEW.deck_id, OLD.deck_id);

    IF total_cards > 40 THEN
        RAISE EXCEPTION 'Deck cannot exceed 40 cards (current: %)', total_cards;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_deck_size
AFTER INSERT OR UPDATE ON deck_cards
FOR EACH ROW EXECUTE FUNCTION enforce_deck_size();

-- ============================================================
-- UNOPENED PACKS (purchased but not yet opened)
-- ============================================================

CREATE TABLE player_packs (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    pack_type       pack_type   NOT NULL,
    quantity        SMALLINT    NOT NULL DEFAULT 1 CHECK (quantity > 0),
    purchased_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- MATCH HISTORY
-- ============================================================

CREATE TABLE matches (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_one_id   UUID        NOT NULL REFERENCES players(id),
    player_two_id   UUID        NOT NULL REFERENCES players(id),
    winner_id       UUID        REFERENCES players(id),  -- NULL = draw
    p1_morale_end   INTEGER,
    p2_morale_end   INTEGER,
    turns           SMALLINT,
    duration_secs   INTEGER,
    played_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_matches_p1 ON matches(player_one_id, played_at DESC);
CREATE INDEX idx_matches_p2 ON matches(player_two_id, played_at DESC);

-- ============================================================
-- SOCIAL — FRIENDS
-- ============================================================

CREATE TABLE friendships (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    requester_id    UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    addressee_id    UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    status          friend_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (requester_id, addressee_id),
    CHECK  (requester_id <> addressee_id)
);

CREATE INDEX idx_friends_addressee ON friendships(addressee_id, status);

-- ============================================================
-- DIRECT MESSAGES
-- ============================================================

CREATE TABLE messages (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    receiver_id     UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    body            TEXT        NOT NULL CHECK (char_length(body) <= 500),
    read            BOOLEAN     NOT NULL DEFAULT FALSE,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation
    ON messages(LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id), sent_at DESC);

-- ============================================================
-- MAILBOX (system messages, quest rewards, news)
-- ============================================================

CREATE TABLE player_mail (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    sender          TEXT        NOT NULL DEFAULT 'AlleyWay Brawlers',
    subject         TEXT        NOT NULL,
    body            TEXT        NOT NULL,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mail_player ON player_mail (player_id, created_at DESC);

-- ============================================================
-- QUESTS
-- ============================================================

CREATE TABLE player_daily_quests (
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_id    TEXT NOT NULL,
    quest_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    progress    INTEGER NOT NULL DEFAULT 0,
    claimed     BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (player_id, quest_id, quest_date)
);

CREATE TABLE player_quest_claims (
    player_id   UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    quest_id    TEXT NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, quest_id)
);

-- ============================================================
-- SERVER AUTHORITY
--   solo_matches   — server-issued sessions for AI matches, so rewards can only
--                    be claimed once per real match
--   payment_grants — one row per payment already redeemed
-- ============================================================

CREATE TABLE solo_matches (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    ranked          BOOLEAN     NOT NULL DEFAULT FALSE,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    outcome         TEXT        CHECK (outcome IN ('win', 'loss', 'draw', 'abandoned')),
    rewarded        BOOLEAN     NOT NULL DEFAULT FALSE
);
CREATE INDEX idx_solo_matches_player ON solo_matches (player_id, started_at DESC);

CREATE TABLE payment_grants (
    payment_intent_id TEXT        PRIMARY KEY,
    player_id         UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    bundle_id         TEXT        NOT NULL,
    contraband        INTEGER     NOT NULL CHECK (contraband > 0),
    granted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX player_packs_player_pack_key ON player_packs (player_id, pack_type);
