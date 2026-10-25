// Copies the server's database backups to this PC, so they survive the server's disk failing.
// backend/scripts/backup_db.sh makes them on the server (nightly once its cron line is set up); this pulls the
// ones this PC doesn't have yet into a folder outside the repo (they hold players' emails and
// password hashes: never commit them).
//
//   node tools/backup_db.mjs            copy new backups to ~/Documents/AlleywayBrawlers-backups
//   node tools/backup_db.mjs --now      make a fresh one on the server first, then copy
//   node tools/backup_db.mjs <dir>      somewhere else
// Restore: pg_restore -d <database> <file>   (into an empty database)
import { mkdirSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const HOST = process.env.ALLEYWAY_HOST || 'alleyway';
const SSH_OPTS = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10'];
const args = process.argv.slice(2);
const dir = args.find(a => !a.startsWith('--')) || join(homedir(), 'Documents', 'AlleywayBrawlers-backups');
mkdirSync(dir, { recursive: true });

const ssh = (cmd) => spawnSync('ssh', [...SSH_OPTS, HOST, cmd], { encoding: 'utf8' });
if (args.includes('--now')) {
    const r = ssh('sh /opt/Turf_War/backend/scripts/backup_db.sh');
    if (r.status !== 0) {
        console.error(r.stderr || 'The backup on the server failed.');
        process.exit(1);
    }
    console.log(`Made ${r.stdout.trim()}`);
}
const list = ssh('ls -1 ~/backups/alleyway-*.dump 2>/dev/null');
const remote = list.stdout.split('\n').map(s => s.trim()).filter(Boolean);
const have = new Set(readdirSync(dir));
const missing = remote.filter(p => !have.has(p.split('/').pop()));
if (!missing.length) {
    console.log(`Up to date: ${remote.length} backup(s) on the server, all in ${dir}`);
    process.exit(0);
}
for (const p of missing) {
    const r = spawnSync('scp', [...SSH_OPTS, `${HOST}:${p}`, join(dir, p.split('/').pop())], { stdio: 'inherit' });
    if (r.status !== 0) process.exit(r.status || 1);
}
console.log(`Copied ${missing.length} backup(s) to ${dir}`);
console.log("(Restore one with: pg_restore -d <empty database> <file>)");
