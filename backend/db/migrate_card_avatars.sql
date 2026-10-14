-- Profile pictures are crops of card art now: the old Lions / Viper pictures are gone, so whoever
-- wore one gets the default (none chosen: the game shows the first leader's art). Safe to re-run.
UPDATE players SET avatar_url = NULL WHERE avatar_url IN ('profile_001', 'profile_002');
ALTER TABLE players ALTER COLUMN avatar_url DROP DEFAULT;
