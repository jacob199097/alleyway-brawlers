-- Account deletion (routes/account.js): deleting a player removes everything that is theirs
-- (ON DELETE CASCADE elsewhere). Two tables keep their rows without the player in them:
--   matches        — the other player's match history stays, with the deleted side left empty
--   payment_grants — a payment stays marked as already redeemed, so it can't be claimed again
-- Safe to run every start: the foreign keys are only changed when they aren't SET NULL yet.

ALTER TABLE matches ALTER COLUMN player_one_id DROP NOT NULL;
ALTER TABLE matches ALTER COLUMN player_two_id DROP NOT NULL;
ALTER TABLE payment_grants ALTER COLUMN player_id DROP NOT NULL;

DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT c.conname, t.relname AS tbl, a.attname AS col
        FROM   pg_constraint c
        JOIN   pg_class t ON t.oid = c.conrelid
        JOIN   pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE  c.contype = 'f'
          AND  c.confrelid = 'players'::regclass
          AND  ((t.relname = 'matches' AND a.attname IN ('player_one_id', 'player_two_id', 'winner_id'))
             OR (t.relname = 'payment_grants' AND a.attname = 'player_id'))
          AND  c.confdeltype <> 'n'
    LOOP
        EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', fk.tbl, fk.conname);
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES players(id) ON DELETE SET NULL',
                       fk.tbl, fk.conname, fk.col);
    END LOOP;
END $$;
