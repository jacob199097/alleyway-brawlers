-- The auction house (economy/auction.js, routes/auction.js; numbers in economy/auction_settings.js).
-- IP addresses are only kept scrambled (an HMAC, utils/ipHash.js): enough to see that two accounts used
-- the same connection, not to read the address back.
ALTER TABLE players ADD COLUMN IF NOT EXISTS signup_ip TEXT;

CREATE TABLE IF NOT EXISTS auctions (
    id           BIGSERIAL   PRIMARY KEY,
    seller_id    UUID        REFERENCES players(id) ON DELETE SET NULL,
    card_id      UUID        NOT NULL REFERENCES cards(id),
    rarity       SMALLINT    NOT NULL,
    start_price  INTEGER     NOT NULL CHECK (start_price > 0),
    listing_fee  INTEGER     NOT NULL DEFAULT 0,
    high_bid     INTEGER,                                   -- the top bid (held from the bidder's Karat)
    high_bidder  UUID        REFERENCES players(id) ON DELETE SET NULL,
    bids         INTEGER     NOT NULL DEFAULT 0,
    status       TEXT        NOT NULL DEFAULT 'active',     -- active | sold | unsold | cancelled
    sale_fee     INTEGER,
    seller_ip    TEXT,
    flags        TEXT[]      NOT NULL DEFAULT '{}',         -- same_ip, repeat_pair (set when it sells)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at      TIMESTAMPTZ NOT NULL,
    settled_at   TIMESTAMPTZ
);
-- A Buy Now price (optional): anyone may buy it outright at that price until the first bid
ALTER TABLE auctions ADD COLUMN IF NOT EXISTS buy_now INTEGER;
CREATE INDEX IF NOT EXISTS auctions_active_idx ON auctions (ends_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS auctions_seller_idx ON auctions (seller_id, created_at);
CREATE INDEX IF NOT EXISTS auctions_bidder_idx ON auctions (high_bidder) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS auction_bids (
    id          BIGSERIAL   PRIMARY KEY,
    auction_id  BIGINT      NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
    bidder_id   UUID        REFERENCES players(id) ON DELETE SET NULL,
    amount      INTEGER     NOT NULL,
    ip          TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS auction_bids_auction_idx ON auction_bids (auction_id);
CREATE INDEX IF NOT EXISTS auction_bids_bidder_idx ON auction_bids (bidder_id);
