// Replays games recorded from the Godot rules (godot/tests/export_golden.gd) through the
// server's JavaScript rules and checks every event matches.
//   godot --headless --path godot --script res://tests/export_golden.gd -- golden.json 25
//   node shared/duel/engine.test.mjs golden.json
import { readFileSync } from 'node:fs';
import { DuelState } from './DuelState.js';

const file = process.argv[2];
if (!file) {
    console.error('usage: node shared/duel/engine.test.mjs <golden.json>');
    process.exit(2);
}
const games = JSON.parse(readFileSync(file, 'utf8'));

/** Deep equality that treats 1 and 1.0 alike and ignores key order. */
function diff(a, b, path = '') {
    if (typeof a === 'number' && typeof b === 'number') return a === b ? null : `${path}: ${a} != ${b}`;
    if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') {
        return a === b ? null : `${path}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`;
    }
    if (Array.isArray(a) !== Array.isArray(b)) return `${path}: array vs object`;
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
        const d = diff(a[k], b[k], `${path}.${k}`);
        if (d) return d;
    }
    return null;
}

let failed = 0;
let totalEvents = 0;
games.forEach((g, gi) => {
    const d = new DuelState(g.decks, g.hideouts, g.leaders, g.first, -1);
    d.start();
    for (const [si, step] of g.steps.entries()) {
        if (step.action) {
            if (!d.doAction(step.side, step.action)) {
                console.error(`game ${gi} step ${si}: JS refused ${JSON.stringify(step.action)}`);
                failed++;
                return;
            }
        }
        const got = d.takeEvents();
        const want = step.events;
        totalEvents += want.length;
        if (got.length !== want.length) {
            console.error(`game ${gi} step ${si}: ${got.length} events, expected ${want.length}`);
            console.error('  got  ', got.map(e => e.type).join(','));
            console.error('  want ', want.map(e => e.type).join(','));
            failed++;
            return;
        }
        for (let i = 0; i < want.length; i++) {
            const problem = diff(got[i], want[i], `${want[i].type}`);
            if (problem) {
                console.error(`game ${gi} step ${si} event ${i}: ${problem}`);
                failed++;
                return;
            }
        }
    }
    if (d.winner !== g.winner) {
        console.error(`game ${gi}: winner ${d.winner} != ${g.winner}`);
        failed++;
    }
});
console.log(`${games.length} games, ${totalEvents} events compared, ${failed} mismatching game(s)`);
process.exit(failed ? 1 : 0);
