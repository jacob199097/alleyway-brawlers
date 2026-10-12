-- The Classic card back (assets/card_back.png) was retired: players who wore it go back to their deck's clan back.
UPDATE players SET card_back = NULL WHERE card_back = 'default';
