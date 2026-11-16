-- Animated cards (economy/animated.js): a card's animated version, owned by a player (crafted for Dust in the
-- Card Library, or bought for Contraband in the shop). Their copies of that card play its art animation
-- (the card's artFx, from the Card Forge), in their collection and in matches.
CREATE TABLE IF NOT EXISTS animated_cards (
    player_id    UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    card_id      TEXT        NOT NULL,
    source       TEXT        NOT NULL,
    acquired_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (player_id, card_id)
);
