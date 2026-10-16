// The live balance dashboard's data: runs backend/scripts/balance_dashboard.js on the server (over
// SSH, host "alleyway") and writes its numbers as four JSON files of rows, which are attached to
// the dashboard page (a claude.ai artifact) as its sources: summary, clans, leaders, cards.
//
//   node tools/live_balance.mjs <out_dir> [--days 30] [--from saved.json]
//
// --from: use a saved output of the server script instead of running it.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const opt = (name, fallback) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const out = args.find(a => !a.startsWith('--') && args[args.indexOf(a) - 1]?.startsWith('--') !== true);
if (!out) {
    console.error('usage: node tools/live_balance.mjs <out_dir> [--days 30] [--from saved.json]');
    process.exit(2);
}
const days = Number(opt('days', 30)) || 30;
const raw = opt('from', '')
    ? readFileSync(opt('from', ''), 'utf8')
    : execFileSync('ssh', ['alleyway', `cd /opt/Turf_War && node backend/scripts/balance_dashboard.js --days ${days}`], { encoding: 'utf8', maxBuffer: 64 << 20 });
const r = JSON.parse(raw);

mkdirSync(out, { recursive: true });
const write = (name, rows) => writeFileSync(join(out, name), JSON.stringify(rows, null, 1));
write('summary.json', [{
    generated_at: r.generated_at, days: r.days, matches: r.matches, from_replays: r.from_replays,
    first_player_win_rate: r.first_player_wins, avg_turns: r.avg_turns,
    challenge_games: r.challenge.games, challenge_wins: r.challenge.wins, challenge_win_rate: r.challenge.win_rate,
    ...Object.fromEntries(Object.entries(r.modes).map(([k, v]) => [`mode_${k}`, v])),
}]);
write('clans.json', r.clans.map(c => ({
    clan: c.name, vs_players_games: c.pvp.games, vs_players_win_rate: c.pvp.win_rate,
    vs_cpu_games: c.cpu.games, vs_cpu_win_rate: c.cpu.win_rate,
})));
write('leaders.json', r.leaders.map(l => ({ leader: l.name, games: l.games, wins: l.wins, win_rate: l.win_rate })));
write('cards.json', r.cards.map(c => ({
    card: c.name, id: c.id, clan: c.clan, type: c.type, authority: c.authority, in_decks: c.in_decks, drawn: c.drawn,
    play_rate: c.play_rate, win_when_drawn: c.win_drawn, impact: c.impact,
})));
console.log(`Wrote summary, clans, leaders and cards to ${out}: ${r.matches} matches over ${r.days} days (${r.from_replays} from replays).`);
