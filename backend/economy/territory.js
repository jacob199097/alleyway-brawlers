'use strict';

/**
 * THE TURF MAP: the city's districts are the 1v1 arenas (godot/data/arenas.json) and the Turf
 * Defense bosses' arenas. Every match is fought in one, and it wins influence there for the clan
 * the player's deck belongs to (POINTS). Each week (Monday to Monday, UTC) starts the map afresh:
 * a district goes to the clan with the most influence in it, if that beats the local gang that runs
 * it (a seeded strength each week). When the week is over, everyone who fought for a clan in a
 * district it took is paid KARAT.district, and its top fighter (the district's boss) KARAT.boss on
 * top: claimed from the map (POST /api/territory/claim), for up to CLAIM_WEEKS weeks back.
 */

const fs = require('fs');
const path = require('path');
const { pool } = require('../db/pool');

const KARAT = { district: 50, boss: 50 };
const CLAIM_WEEKS = 4;
/** Influence a match is worth, by mode and outcome; CPU ones only when they paid rewards. */
const POINTS = {
    online: { win: 3, draw: 2, loss: 1 },          // casual, ranked, friendly
    cpu_hard: { win: 2, draw: 1, loss: 0 },         // Ranked (hard CPU), the weekly challenge, Hard VS CPU
    cpu: { win: 1, draw: 0, loss: 0 },              // Easy and Normal VS CPU
    coop: { win: 3, draw: 1, loss: 1 },             // Turf Defense, each player
};
/** A district's gang by its star rating this week (1..5, index = stars): the CPU's play (ai), its
 *  starting Morale and Authority extra each turn (rules.edge), and the influence a match is worth.
 *  What it pays is TURF_STAR_REWARD_SCALE in postMatch.js. */
const GANG_STARS = [null,
    { ai: 'easy', morale: 0, edge: 0, points: { win: 1, draw: 0, loss: 0 } },
    { ai: 'normal', morale: 0, edge: 0, points: { win: 1, draw: 0, loss: 0 } },
    { ai: 'hard', morale: 0, edge: 0, points: { win: 2, draw: 1, loss: 0 } },
    { ai: 'hard', morale: 9000, edge: 0, points: { win: 2, draw: 1, loss: 0 } },
    { ai: 'hard', morale: 9000, edge: 1, points: { win: 3, draw: 1, loss: 0 } },
];
const LOCALS_MIN = 3;
const LOCALS_SPREAD = 6;   // a local gang's strength: 3..8
const GANG_FIRST = ['Rust', 'Gutter', 'Neon', 'Iron', 'Velvet', 'Bone', 'Static', 'Copper', 'Ash', 'Midnight', 'Glass', 'Hollow', 'Chrome', 'Smoke'];
const GANG_LAST = ['Rats', 'Kings', 'Saints', 'Jackals', 'Vipers', 'Hounds', 'Ghosts', 'Crows', 'Wolves', 'Choir', 'Hyenas'];

/** The districts: every arena once, in the arenas file's order: [{id, name, image}]. */
const DISTRICTS = (() => {
    try {
        return JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/data/arenas.json'), 'utf8'))
            .map(a => ({ id: String(a.id), name: String(a.name || a.id), image: String(a.image || '') }));
    } catch { return []; }
})();
const isDistrict = (id) => DISTRICTS.some(d => d.id === id);

function hash(s) {
    let h = 2166136261;
    for (const ch of String(s)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
    return h;
}

/** The Monday (UTC) a moment's week starts on, 'YYYY-MM-DD'. */
function weekOf(at = new Date()) {
    const d = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));
    d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
    return d.toISOString().slice(0, 10);
}
const addDays = (week, n) => new Date(Date.parse(week + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);

/** The gang that runs a district when no clan has it: the same name every week, a new strength each week. */
function locals(district, week) {
    const h = hash(district);
    return { name: `The ${GANG_FIRST[h % GANG_FIRST.length]} ${GANG_LAST[(h >>> 8) % GANG_LAST.length]}`,
        strength: LOCALS_MIN + hash(`${week}:${district}`) % LOCALS_SPREAD };
}

/** A district's star rating this week, 1..5: its gang's strength against the other districts'
 *  (5 = the toughest gang, and the best pay), spread evenly over the districts. */
function starsOf(district, week = weekOf()) {
    const ranked = DISTRICTS.map(d => ({ id: d.id, s: locals(d.id, week).strength, h: hash(`${week}:stars:${d.id}`) }))
        .sort((a, b) => a.s - b.s || a.h - b.h);
    const i = ranked.findIndex(x => x.id === district);
    return i < 0 ? 1 : 1 + Math.floor(i * 5 / ranked.length);
}

/** The local gang running a district this week, for a fight there from the turf map:
 *  {name, district (its name), seed (picks the gang's picture), stars, ai, morale, edge};
 *  null if it isn't a district. */
function gangOf(district) {
    const d = DISTRICTS.find(x => x.id === district);
    if (!d) return null;
    const stars = starsOf(d.id);
    const { ai, morale, edge } = GANG_STARS[stars];
    return { name: locals(d.id, weekOf()).name, district: d.name, seed: hash('gang:' + d.id), stars, ai, morale, edge };
}

/** What a match is worth: mode as onlineMatch/coopMatch name it, outcome win|loss|draw;
 *  stars: a turf map fight's gang (its rating decides it). */
function pointsFor({ mode, outcome, difficulty = null, stars = null }) {
    let table = POINTS.online;
    if (GANG_STARS[stars]) table = GANG_STARS[stars].points;
    else if (mode === 'cpu_coop' || mode === 'coop') table = POINTS.coop;
    else if (mode === 'cpu_ranked' || mode === 'cpu_challenge' || (mode === 'cpu' && difficulty === 'hard')) table = POINTS.cpu_hard;
    else if (String(mode).startsWith('cpu')) table = POINTS.cpu;
    return table[outcome] ?? 0;
}

/**
 * A finished match for one player: influence for their clan in the district it was fought in →
 * {district, name, clan, points} for the post-match screen, or null when it earned none.
 */
async function record({ playerId, district, clan, mode, outcome, difficulty = null, stars = null, at = new Date() }) {
    if (!playerId || !isDistrict(district) || !clan || !/^[a-z0-9_]+$/.test(clan)) return null;
    const points = pointsFor({ mode, outcome, difficulty, stars });
    if (points <= 0) return null;
    await pool.query(
        `INSERT INTO territory_influence (week, district, clan, player_id, points) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (week, district, clan, player_id) DO UPDATE SET points = territory_influence.points + EXCLUDED.points`,
        [weekOf(at), district, clan, playerId, points]);
    return { district, name: DISTRICTS.find(d => d.id === district).name, clan, points };
}

/**
 * The map for a week: each district's standings and who holds it.
 * → {week, districts: [{id, name, image, locals, clans: [{clan, points}], holder, boss}]}
 * holder = a clan id, or '' while the locals hold it; boss = {playerId, username, points} of the
 * holding clan's top fighter (null for the locals).
 */
async function weekMap(week) {
    const { rows } = await pool.query(
        `SELECT t.district, t.clan, t.player_id, t.points, p.username
         FROM territory_influence t JOIN players p ON p.id = t.player_id
         WHERE t.week = $1`, [week]);
    return {
        week,
        districts: DISTRICTS.map(d => {
            const mine = rows.filter(r => r.district === d.id);
            const totals = {};
            for (const r of mine) totals[r.clan] = (totals[r.clan] || 0) + r.points;
            const clans = Object.entries(totals).map(([clan, points]) => ({ clan, points }))
                .sort((a, b) => b.points - a.points || a.clan.localeCompare(b.clan));
            const gang = locals(d.id, week);
            // A clan takes it from the locals by beating their strength, and from another clan by outscoring it (a tie keeps it nobody's)
            const top = clans[0];
            const holder = top && top.points > gang.strength && !(clans[1] && clans[1].points === top.points) ? top.clan : '';
            const best = holder ? mine.filter(r => r.clan === holder).sort((a, b) => b.points - a.points || String(a.username).localeCompare(String(b.username)))[0] : null;
            return { ...d, locals: { ...gang, stars: starsOf(d.id, week) }, clans, holder,
                boss: best ? { playerId: best.player_id, username: best.username, points: best.points } : null,
                fighters: mine.map(r => ({ playerId: r.player_id, clan: r.clan, points: r.points })) };
        }),
    };
}

/** What a finished week pays a player: {karat, districts: [{id, name, clan, boss}]}. */
function payFrom(map, playerId) {
    const out = { karat: 0, districts: [] };
    for (const d of map.districts) {
        if (!d.holder || !d.fighters.some(f => f.playerId === playerId && f.clan === d.holder && f.points > 0)) continue;
        const boss = d.boss?.playerId === playerId;
        out.karat += KARAT.district + (boss ? KARAT.boss : 0);
        out.districts.push({ id: d.id, name: d.name, clan: d.holder, boss });
    }
    return out;
}

/** Finished weeks a player hasn't claimed yet, newest first, with what each pays. */
async function unclaimed(playerId, now = new Date()) {
    const current = weekOf(now);
    const weeks = Array.from({ length: CLAIM_WEEKS }, (_, i) => addDays(current, -7 * (i + 1)));
    const { rows } = await pool.query(
        `SELECT DISTINCT week::text AS week FROM territory_influence WHERE player_id = $1 AND week = ANY($2::date[])
         EXCEPT SELECT week::text FROM territory_claims WHERE player_id = $1`, [playerId, weeks]);
    const out = [];
    for (const w of weeks.filter(x => rows.some(r => r.week === x))) {
        const pay = payFrom(await weekMap(w), playerId);
        if (pay.karat > 0) out.push({ week: w, ...pay });
    }
    return out;
}

/** The map screen (GET /api/territory): this week live, last week's holders, and Karat waiting. */
async function overview(playerId, now = new Date()) {
    const week = weekOf(now);
    const map = await weekMap(week);
    const last = await weekMap(addDays(week, -7));
    const { clanList } = await import('../../shared/clans.js');
    const pending = await unclaimed(playerId, now);
    return {
        week, endsAt: addDays(week, 7) + 'T00:00:00Z',
        clans: clanList().map(c => ({ id: c.id, name: c.name, color: c.color })),
        districts: map.districts.map(d => ({
            id: d.id, name: d.name, image: d.image, locals: d.locals, clans: d.clans, holder: d.holder,
            boss: d.boss ? { username: d.boss.username, points: d.boss.points } : null,
            mine: Object.fromEntries(d.fighters.filter(f => f.playerId === playerId).map(f => [f.clan, f.points])),
            lastHolder: last.districts.find(x => x.id === d.id)?.holder || '',
        })),
        reward: pending.length ? { karat: pending.reduce((s, w) => s + w.karat, 0), weeks: pending } : null,
        karat: KARAT, points: POINTS,
    };
}

/** Pays every finished, unclaimed week (once each) → {karat, newKarat}. */
async function claim(playerId, now = new Date()) {
    const pending = await unclaimed(playerId, now);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        let karat = 0;
        for (const w of pending) {
            const { rowCount } = await client.query(
                'INSERT INTO territory_claims (player_id, week, karat) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
                [playerId, w.week, w.karat]);
            if (rowCount) karat += w.karat;
        }
        const { rows: [p] } = await client.query('UPDATE players SET karat = karat + $1 WHERE id = $2 RETURNING karat', [karat, playerId]);
        await client.query('COMMIT');
        return { karat, newKarat: p ? p.karat : null };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { record, overview, claim, weekMap, payFrom, pointsFor, locals, weekOf, gangOf, starsOf, DISTRICTS, KARAT, POINTS, GANG_STARS };
