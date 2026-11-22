-- Card mastery quests (economy/veterans.js, godot/data/veteran_quests.json): what each player's cards did in
-- their matches (KOs and Downs in its attacks, direct damage, effects used, PROMOTEs, a leader's Awakenings).
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS kos      INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS downs    INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS direct   INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS effects  INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS promotes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE card_veterans ADD COLUMN IF NOT EXISTS awakens  INTEGER NOT NULL DEFAULT 0;

-- The tier each card had earned by card XP before the quests (1 XP a match + 2 a win: 15 / 45 / 120), kept.
-- Set once, when the column is added (cards played later earn tiers by their quests only).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'card_veterans' AND column_name = 'legacy_tier') THEN
        ALTER TABLE card_veterans ADD COLUMN legacy_tier SMALLINT NOT NULL DEFAULT 0;
        UPDATE card_veterans SET legacy_tier = CASE
            WHEN plays + wins * 2 >= 120 THEN 3 WHEN plays + wins * 2 >= 45 THEN 2 WHEN plays + wins * 2 >= 15 THEN 1 ELSE 0 END;
    END IF;
END $$;
