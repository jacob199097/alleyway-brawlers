-- ============================================================
-- TURF WAR TACTICS — PostgreSQL Schema
-- ============================================================

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";   -- case-insensitive text for usernames

-- ============================================================
-- ENUMERATIONS
-- ============================================================

CREATE TYPE card_type   AS ENUM ('gang_member', 'hustle', 'ambush');
CREATE TYPE rank_tier   AS ENUM (
    'rookie', 'street_tough', 'enforcer', 'underboss', 'kingpin', 'legend'
);
CREATE TYPE match_result AS ENUM ('win', 'loss', 'draw');
CREATE TYPE friend_status AS ENUM ('pending', 'accepted', 'blocked');
CREATE TYPE pack_type    AS ENUM ('iron_saints', 'neon_serpents', 'dust_devils', 'lion_pride', 'viper_clan');

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
    socket_id       TEXT                                  -- current socket.io connection
);

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
    name            TEXT        NOT NULL UNIQUE,
    clan            pack_type   NOT NULL,                 -- which clan this card belongs to
    card_type       card_type   NOT NULL,

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
    art_url         TEXT,
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
-- SAMPLE SEED DATA (cards)
-- ============================================================

-- Rarity scale: 1=Common  2=Uncommon  3=Rare  4=Epic  5=Legendary
INSERT INTO cards (name, clan, card_type, authority, attack, defense, tribute_cost, rarity, effect_text, flavour_text)
VALUES
    -- Lions (Iron Saints)
    ('Eric',        'iron_saints', 'gang_member', 2, 1400, 300, 0, 1,
     '[Lion Synergy] +300 ATK with 2+ Lions face-up. Promote: Destroy 1 opposing Character by battle.',
     '"He moves before you finish thinking."'),
    ('Eric Lv.2',   'iron_saints', 'gang_member', 5, 2200, 600, 0, 2,
     '[Lion Synergy] +300 ATK with 2+ Lions face-up. Promote: Destroy 2 opposing Characters by battle.',
     '"The second form is where the real damage starts."'),
    ('Eric Lv.3',   'iron_saints', 'gang_member', 8, 2900, 800, 0, 3,
     'On Promote to LV3: Send all non-Lion Characters with ATK lower than this card''s ATK to The Gutter.',
     '"Nobody left standing."'),

    ('Randy',       'iron_saints', 'gang_member', 1, 1200, 900, 0, 1,
     'Promote: Destroy 1 opposing Character by battle.',
     '"You can''t put him down."'),
    ('Randy Lv.2',  'iron_saints', 'gang_member', 4, 2000, 1300, 0, 2,
     'Promote: Destroy 1 opposing Character by battle.',
     '"Getting harder to kill with every hit."'),
    ('Randy Lv.3',  'iron_saints', 'gang_member', 7, 2600, 2000, 0, 3,
     'While face-up, opposing Characters cannot target your LV1 Lion Strivers for attacks.',
     '"Step to me. I''m right here."');
