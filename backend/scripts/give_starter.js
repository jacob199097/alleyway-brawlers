'use strict';
// Gives players a clan's starter deck (shared/clans.js starterRecipe). The cards it needs are topped
// up in their collection (nobody loses copies they already have).
//
// Without --add, every player gets it as their active deck: a "<Clan> Starter" deck is made
// (replacing an older one of that name), their other decks stay but are no longer active (empty
// ones, e.g. after retire_cards.js, are deleted), and their starting clan is set to it, so nobody
// is asked to pick one.
//
// With --add (one clan or more), every player who has picked a clan gets each starter as an extra
// deck: a "<Clan> Starter" deck is made if they don't have one, their active deck and clan stay as
// they are, and a mail tells them what they got. A "<Clan> Starter" deck they already have is left
// alone, as they may have changed it, unless --refresh: then it's set to the current recipe (it
// stays active if it was, and keeps its record). The dry run shows how each one differs.
//
//   node backend/scripts/give_starter.js nebula                       shows what would change
//   node backend/scripts/give_starter.js nebula --apply               does it (all or nothing)
//   node backend/scripts/give_starter.js nebula militia --add [--refresh] [--apply]
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { pool } = require('../db/pool');

const apply = process.argv.includes('--apply');
const add = process.argv.includes('--add');
const refresh = process.argv.includes('--refresh');
const clans = process.argv.slice(2).filter(a => !a.startsWith('--'));

(async () => {
    const { starterRecipe, pickableClans } = await import('../../shared/clans.js');
    const infos = clans.map(id => pickableClans().find(c => c.id === id));
    if (!clans.length || infos.some(i => !i) || (clans.length > 1 && !add)) {
        console.error(`Name a clan with a starter deck (several with --add): ${pickableClans().map(c => c.id).join(', ')}`);
        process.exitCode = 1;
        await pool.end();
        return;
    }
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const starters = [];
        for (const info of infos) starters.push(await load(client, info, starterRecipe(info.id)));
        if (add) await addStarters(client, starters);
        else await replaceStarter(client, starters[0]);
        if (!apply) {
            await client.query('ROLLBACK');
            console.log('\nNothing changed. Run again with --apply to do it.');
            return;
        }
        await client.query('COMMIT');
        console.log('\nDone.');
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        console.error('Failed, nothing changed:', err.message);
        process.exitCode = 1;
    } finally {
        client.release();
        await pool.end();
    }
})();

/** A starter with its database card IDs and names (card game IDs = cards.art_url). */
async function load(client, info, recipe) {
    const ids = [...new Set([recipe.leader, ...recipe.deck.map(([id]) => id), ...recipe.hideout.map(([id]) => id)].filter(Boolean))];
    const { rows } = await client.query('SELECT id, art_url, name FROM cards WHERE art_url = ANY($1::text[])', [ids]);
    const dbId = Object.fromEntries(rows.map(r => [r.art_url, r.id]));
    const names = Object.fromEntries(rows.map(r => [r.id, r.name.trim()]));
    const missing = ids.filter(id => !dbId[id]);
    if (missing.length) throw new Error(`These cards aren't on the server yet (run backend/scripts/sync_cards.mjs): ${missing.join(', ')}`);
    const total = recipe.deck.reduce((s, [, q]) => s + q, 0);
    if (total !== 40) throw new Error(`The ${info.name} starter deck must have 40 cards (got ${total}).`);
    const owns = [...recipe.deck, ...recipe.hideout];
    if (recipe.leader) owns.push([recipe.leader, 1]);
    return { info, recipe, dbId, names, owns, name: `${info.name} Starter`, leader: recipe.leader ? dbId[recipe.leader] : null };
}

async function topUp(client, playerId, s) {
    for (const [id, qty] of s.owns) {
        await client.query(
            `INSERT INTO player_inventory (player_id, card_id, quantity) VALUES ($1, $2, $3)
             ON CONFLICT (player_id, card_id) DO UPDATE SET quantity = GREATEST(player_inventory.quantity, EXCLUDED.quantity)`,
            [playerId, s.dbId[id], qty]);
    }
}

async function writeCards(client, deckId, s) {
    for (const [id, copies] of s.recipe.deck) {
        await client.query('INSERT INTO deck_cards (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deckId, s.dbId[id], copies]);
    }
    // ...and its Hideout (the higher levels of its Strivers)
    await client.query('DELETE FROM deck_hideout WHERE deck_id = $1', [deckId]);
    for (const [id, copies] of s.recipe.hideout) {
        await client.query('INSERT INTO deck_hideout (deck_id, card_id, copies) VALUES ($1, $2, $3)', [deckId, s.dbId[id], Math.min(3, copies)]);
    }
    await client.query('UPDATE decks SET hideout_set = TRUE WHERE id = $1', [deckId]);
}

/** How many copies topping up would add to a player's collection. */
async function newCopies(client, playerId, s) {
    const { rows } = await client.query('SELECT card_id, quantity FROM player_inventory WHERE player_id = $1', [playerId]);
    const have = Object.fromEntries(rows.map(r => [r.card_id, r.quantity]));
    return s.owns.reduce((n, [id, qty]) => n + Math.max(0, qty - (have[s.dbId[id]] || 0)), 0);
}

/** What setting a deck to the recipe would change ("+1 Rouke, -1 Kade"), or '' when it's the same. */
async function deckDiff(client, deck, s) {
    const { rows } = await client.query('SELECT card_id, copies FROM deck_cards WHERE deck_id = $1', [deck.id]);
    const want = Object.fromEntries(s.recipe.deck.map(([id, n]) => [s.dbId[id], n]));
    const have = Object.fromEntries(rows.map(r => [r.card_id, r.copies]));
    const out = [];
    for (const id of new Set([...Object.keys(want), ...Object.keys(have)])) {
        const d = (want[id] || 0) - (have[id] || 0);
        if (d) out.push(`${d > 0 ? '+' : ''}${d} ${s.names[id] || 'a card not in the starter'}`);
    }
    if (deck.leader_card_id !== s.leader) out.push(`leader ${s.names[s.leader] || 'none'}`);
    return out.join(', ');
}

async function replaceStarter(client, s) {
    const { rows: players } = await client.query('SELECT id, username FROM players ORDER BY created_at');
    console.log(`${players.length} player(s) get the ${s.name} (40 cards, leader ${s.recipe.leader}) as their active deck.`);
    if (!apply) return;
    for (const p of players) {
        await topUp(client, p.id, s);
        await client.query('DELETE FROM decks WHERE player_id = $1 AND name = $2', [p.id, s.name]);
        const { rows: [deck] } = await client.query(
            'INSERT INTO decks (player_id, name, is_active, leader_card_id) VALUES ($1, $2, TRUE, $3) RETURNING id',
            [p.id, s.name, s.leader]);
        await client.query('UPDATE decks SET is_active = FALSE WHERE player_id = $1 AND id <> $2', [p.id, deck.id]);
        // Decks left with no cards (all retired) go
        await client.query(
            `DELETE FROM decks d WHERE d.player_id = $1 AND d.id <> $2
             AND NOT EXISTS (SELECT 1 FROM deck_cards dc WHERE dc.deck_id = d.id)`, [p.id, deck.id]);
        await writeCards(client, deck.id, s);
        await client.query('UPDATE players SET chosen_clan = $1 WHERE id = $2', [s.info.id, p.id]);
    }
}

async function addStarters(client, starters) {
    const { rows: players } = await client.query('SELECT id, username FROM players WHERE chosen_clan IS NOT NULL ORDER BY created_at');
    console.log(`${players.length} player(s) who have picked a clan get: ${starters.map(s => s.name).join(', ')}${refresh ? ' (existing ones set to the recipe)' : ''}.`);
    for (const p of players) {
        const lines = [];
        for (const s of starters) {
            const { rows: [deck] } = await client.query(
                'SELECT id, leader_card_id FROM decks WHERE player_id = $1 AND name = $2 ORDER BY created_at LIMIT 1', [p.id, s.name]);
            const diff = deck ? await deckDiff(client, deck, s) : '';
            const gain = await newCopies(client, p.id, s);
            const did = !deck ? 'new deck'
                : !diff ? 'has it already'
                : refresh ? `deck updated (${diff})`
                : `has it already, left alone (the recipe would be ${diff})`;
            console.log(`  ${p.username}: ${s.name}: ${did}; ${gain} card(s) added to the collection`);
            if (!apply) continue;
            await topUp(client, p.id, s);
            if (!deck) {
                const { rows: [{ n }] } = await client.query('SELECT COUNT(*)::int AS n FROM decks WHERE player_id = $1 AND is_active', [p.id]);
                const { rows: [made] } = await client.query(
                    'INSERT INTO decks (player_id, name, is_active, leader_card_id) VALUES ($1, $2, $3, $4) RETURNING id',
                    [p.id, s.name, n === 0, s.leader]);
                await writeCards(client, made.id, s);
                lines.push(`• ${s.name}: a new deck, led by ${s.names[s.leader]}, with ${gain} card(s) for your collection.`);
            } else if (refresh && diff) {
                await client.query('DELETE FROM deck_cards WHERE deck_id = $1', [deck.id]);
                await client.query('UPDATE decks SET leader_card_id = $2, updated_at = NOW() WHERE id = $1', [deck.id, s.leader]);
                await writeCards(client, deck.id, s);
                lines.push(`• ${s.name}: your deck is updated (${diff}), with ${gain} card(s) for your collection.`);
            } else if (gain) {
                lines.push(`• ${s.name}: ${gain} card(s) for your collection, so you have every card it needs.`);
            }
        }
        if (lines.length) {
            await client.query(
                'INSERT INTO player_mail (player_id, sender, subject, body) VALUES ($1, $2, $3, $4)',
                [p.id, 'AlleyWay Brawlers', 'Free starter decks',
                 `On the house:\n\n${lines.join('\n')}\n\n` +
                 'Find them in the Deck Editor and pick the one you want to play. Your active deck hasn\'t changed.']);
        }
    }
}
