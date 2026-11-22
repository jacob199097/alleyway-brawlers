-- Season borders (economy/seasons.js honours): the border a player wears round their picture, by the season's
-- id ("season:0"; its rank is the highest the player reached that season). NULL: none.
ALTER TABLE players ADD COLUMN IF NOT EXISTS border TEXT;
