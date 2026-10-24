-- Each deck's Hideout: the higher levels of its Strivers that the player put there in the Deck
-- Editor (a Striver can only promote to a level waiting in the Hideout). Up to 3 of each.
-- hideout_set is FALSE for decks saved before this: until they're saved again, their Hideout is
-- every higher level of their Strivers the player owns (up to 3 of each), as it used to be.
CREATE TABLE IF NOT EXISTS deck_hideout (
    deck_id  UUID     NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    card_id  UUID     NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    copies   SMALLINT NOT NULL DEFAULT 1 CHECK (copies BETWEEN 1 AND 3),
    PRIMARY KEY (deck_id, card_id)
);
ALTER TABLE decks ADD COLUMN IF NOT EXISTS hideout_set BOOLEAN NOT NULL DEFAULT FALSE;
