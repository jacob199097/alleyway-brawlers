'use strict';

/**
 * Brings the database up to date when the server starts. Each file only adds what's missing
 * (ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS), so running it every start is safe.
 * Add new files to the end of the list.
 */

const fs = require('fs');
const path = require('path');

const FILES = ['migrate_progression.sql', 'migrate_retire_classic_back.sql', 'migrate_level_rewards.sql', 'migrate_card_avatars.sql', 'migrate_mastery_challenge.sql', 'migrate_last_played.sql', 'migrate_daily.sql', 'migrate_deck_hideout.sql', 'migrate_account_deletion.sql', 'migrate_turf.sql'];

async function migrate(pool) {
    for (const f of FILES) {
        await pool.query(fs.readFileSync(path.join(__dirname, f), 'utf8'));
    }
}

module.exports = { migrate };
