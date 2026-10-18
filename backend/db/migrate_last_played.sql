-- When each player last finished a match (online, CPU or free-for-all): shown on profiles.
-- Set by economy/achievements.js recordMatch; filled in once from the older match records.
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_played_at TIMESTAMPTZ;

UPDATE players p SET last_played_at = x.at
FROM (
    SELECT pid, MAX(at) AS at FROM (
        SELECT player_one_id AS pid, played_at AS at FROM matches
        UNION ALL SELECT player_two_id, played_at FROM matches
        UNION ALL SELECT player_id, completed_at FROM solo_matches WHERE completed_at IS NOT NULL
    ) m GROUP BY pid
) x
WHERE p.id = x.pid AND p.last_played_at IS NULL;
