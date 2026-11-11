-- A deck has 40 to 60 cards (routes/deck.js checks both ends). The database's own guard, from when decks
-- were exactly 40, still refused anything over 40: saving a 41-card deck failed with "Deck cannot exceed 40
-- cards". It now stops only past 60.
CREATE OR REPLACE FUNCTION enforce_deck_size()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    total_cards INTEGER;
BEGIN
    SELECT COALESCE(SUM(copies), 0)
    INTO   total_cards
    FROM   deck_cards
    WHERE  deck_id = COALESCE(NEW.deck_id, OLD.deck_id);

    IF total_cards > 60 THEN
        RAISE EXCEPTION 'A deck has at most 60 cards (this one has %)', total_cards;
    END IF;
    RETURN NEW;
END;
$$;
