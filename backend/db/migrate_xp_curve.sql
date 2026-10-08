-- ============================================================
-- MIGRATION: Exponential XP curve + first_win_date column
-- Run once against an existing turf_war database.
-- ============================================================

-- 1. Add first_win_date column (safe to run multiple times)
ALTER TABLE players
    ADD COLUMN IF NOT EXISTS first_win_date DATE;

-- 2. Replace level_thresholds with exponential curve
--    Formula: XP to advance from level N = floor(100 * N^1.5)
TRUNCATE level_thresholds;

INSERT INTO level_thresholds (level, xp_required)
SELECT
    lvl,
    COALESCE((
        SELECT SUM(FLOOR(100.0 * i ^ 1.5))::INTEGER
        FROM   generate_series(1, lvl - 1) AS i
    ), 0)
FROM generate_series(1, 50) AS lvl;

-- 3. Recalculate every player's level to match the new curve
--    (existing XP totals are kept; levels are re-derived)
UPDATE players p
SET level = (
    SELECT COALESCE(MAX(lt.level), 1)
    FROM   level_thresholds lt
    WHERE  lt.xp_required <= p.xp
);
