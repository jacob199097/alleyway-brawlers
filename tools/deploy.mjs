// Updates the server from this PC over SSH: copies builds into downloads/, pulls the latest code
// and restarts the backend. Needs the "alleyway" SSH host (see "Deploying" in docs/CARD_PIPELINE.md).
//
//   node tools/deploy.mjs                 pull + restart
//   node tools/deploy.mjs --patch         also copy builds/AlleywayBrawlers-<latest>-patch.pck
//   node tools/deploy.mjs --build         also copy builds/AlleywayBrawlers-<latest>-windows.zip
//   node tools/deploy.mjs --sync-cards    also run backend/scripts/sync_cards.mjs after pulling
//   node tools/deploy.mjs --logs [n]      just show the backend's last n log lines (default 60)
//   node tools/deploy.mjs <file> ...      also copy these files into downloads/
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const HOST = process.env.ALLEYWAY_HOST || 'alleyway';
const REPO = '/opt/Turf_War';
const SSH_OPTS = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10'];   // never stop to ask for a password

const args = process.argv.slice(2);
const has = (flag) => args.includes(flag);

function ssh(command) {
    const r = spawnSync('ssh', [...SSH_OPTS, HOST, command], { stdio: 'inherit' });
    if (r.error) throw new Error(`Couldn't run ssh: ${r.error.message}`);
    return r.status;
}

if (has('--logs')) {
    const n = Number(args[args.indexOf('--logs') + 1]) || 60;
    process.exit(ssh(`journalctl -u alleyway-backend -n ${n} --no-pager`));
}

// Can we log in without a password?
if (spawnSync('ssh', [...SSH_OPTS, HOST, 'true'], { stdio: 'ignore' }).status !== 0) {
    console.error(`Can't log in to "${HOST}" with the SSH key. See "Deploying" in docs/CARD_PIPELINE.md.`);
    process.exit(1);
}

// The server pulls from GitHub, so everything must be pushed first
const git = (...a) => execFileSync('git', ['-C', ROOT, ...a], { encoding: 'utf8' }).trim();
try {
    git('fetch', '-q');
    const ahead = git('rev-list', '--count', '@{u}..HEAD');
    if (ahead !== '0') {
        console.error(`${ahead} commit(s) here aren't pushed yet. Push first, then deploy.`);
        process.exit(1);
    }
    if (git('status', '--porcelain', '--untracked-files=no')) console.warn('Note: you have uncommitted changes; the server only gets what is pushed.');
} catch (err) {
    console.warn(`Couldn't check git (${err.message.split('\n')[0]}); deploying anyway.`);
}

const latest = JSON.parse(readFileSync(join(ROOT, 'shared/game_version.json'), 'utf8')).latest;
const files = args.filter(a => !a.startsWith('--'));
if (has('--patch')) files.push(join(ROOT, 'builds', `AlleywayBrawlers-${latest}-patch.pck`));
if (has('--build')) files.push(join(ROOT, 'builds', `AlleywayBrawlers-${latest}-windows.zip`));
for (const f of files) {
    if (!existsSync(f)) {
        console.error(`Not found: ${f}`);
        process.exit(1);
    }
}
if (files.length) {
    console.log(`Copying ${files.length} file(s) to ${REPO}/downloads/ …`);
    const r = spawnSync('scp', [...SSH_OPTS, ...files, `${HOST}:${REPO}/downloads/`], { stdio: 'inherit' });
    if (r.status !== 0) process.exit(r.status || 1);
}

const steps = [
    `cd ${REPO}`,
    'git pull --ff-only',
    ...(has('--sync-cards') ? ['node backend/scripts/sync_cards.mjs'] : []),
    'sudo -n systemctl restart alleyway-backend',
    'sleep 2',
    'systemctl is-active alleyway-backend',
];
console.log('Pulling and restarting on the server …');
const status = ssh(steps.join(' && '));
if (status !== 0) {
    console.error('\nSomething failed on the server (output above). Recent backend log:');
    ssh('journalctl -u alleyway-backend -n 30 --no-pager');
    process.exit(status);
}
console.log('\nDeployed. https://alleywaybrawlers.duckdns.org is running the latest code.');
