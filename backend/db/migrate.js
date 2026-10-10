'use strict';

/**
 * Brings the database up to date when the server starts. Each file only adds what's missing
 * (ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS), so running it every start is safe.
 * Add new files to the end of the list.
 */

const fs = require('fs');
const path = require('path');

const FILES = ['migrate_progression.sql'];

async function migrate(pool) {
    for (const f of FILES) {
        await pool.query(fs.readFileSync(path.join(__dirname, f), 'utf8'));
    }
}

module.exports = { migrate };
