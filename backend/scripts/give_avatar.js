'use strict';
// Gives one player a profile picture they couldn't unlock otherwise (db/migrate_avatar_gifts.sql), e.g.
// the art of a card that was based on them, and mails them about it. Their current picture stays.
//
//   node backend/scripts/give_avatar.js <username> <card id> ["mail text"]            shows what would happen
//   node backend/scripts/give_avatar.js <username> <card id> ["mail text"] --apply    does it
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const apply = process.argv.includes('--apply');
const [username, cardId, text] = process.argv.slice(2).filter(a => !a.startsWith('--'));

(async () => {
    try {
        const { CARD_CATALOG } = await import('../../shared/cards.js');
        const card = CARD_CATALOG[cardId];
        if (!username || !card) {
            console.error('usage: node backend/scripts/give_avatar.js <username> <card id, e.g. card_nebu_042> ["mail text"] [--apply]');
            process.exitCode = 1;
            return;
        }
        const { rows: [p] } = await pool.query('SELECT id, username FROM players WHERE LOWER(username) = LOWER($1)', [username]);
        if (!p) {
            console.error(`No player called ${username}.`);
            process.exitCode = 1;
            return;
        }
        const avatar = `card:${cardId}`;
        const body = text || `You've been given a special profile picture: ${card.name}. ` +
            'Wear it from Achievements → Your Look.';
        console.log(`${p.username} gets the ${card.name} profile picture (${avatar}), with this mail:\n  ${body}`);
        if (!apply) {
            console.log('\nNothing changed. Run again with --apply to do it.');
            return;
        }
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            const { rowCount } = await client.query(
                'INSERT INTO player_avatar_gifts (player_id, avatar) VALUES ($1, $2) ON CONFLICT DO NOTHING', [p.id, avatar]);
            if (rowCount) {
                await client.query('INSERT INTO player_mail (player_id, sender, subject, body) VALUES ($1, $2, $3, $4)',
                    [p.id, 'AlleyWay Brawlers', 'A profile picture, just for you', body]);
            }
            await client.query('COMMIT');
            console.log(rowCount ? '\nDone.' : '\nThey already had it: nothing changed.');
        } catch (err) {
            await client.query('ROLLBACK').catch(() => {});
            throw err;
        } finally {
            client.release();
        }
    } catch (err) {
        console.error('Failed:', err.message);
        process.exitCode = 1;
    } finally {
        await pool.end();
    }
})();
