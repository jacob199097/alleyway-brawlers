// The auction house's abuse report: sales flagged as possibly one person trading with their own accounts,
// the pairs of players who trade with each other most, and accounts made from the same (scrambled) IP
// address. Nothing here is automatic: it's for a person to look at (economy/auction.js).
//
//   node backend/scripts/auction_report.mjs [days]     (default: the last 30 days)
//
// Flags: same_ip = the buyer and seller used the same connection (signing up, listing or bidding);
// repeat_pair = the same two players traded REPEAT_PAIR_SALES times within REPEAT_PAIR_DAYS days
// (economy/auction_settings.js). Two people in one home share an IP address, so look before acting.
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

dotenv.config({ path: join(dirname(fileURLToPath(import.meta.url)), '..', '.env') });
const { pool } = (await import('../db/pool.js')).default;
const auction = (await import('../economy/auction.js')).default;

const days = Number(process.argv[2]) || 30;
const r = await auction.report(days);

console.log(`Auction house, the last ${days} days\n`);
console.log(`Flagged sales (${r.flagged.length}):`);
for (const s of r.flagged) {
    console.log(`  #${s.id}  ${s.settled_at.toISOString().slice(0, 16).replace('T', ' ')}  ${s.card} for ${s.high_bid}: ${s.seller ?? '(deleted)'} → ${s.buyer ?? '(deleted)'}  [${s.flags.join(', ')}]`);
}
console.log(`\nPlayers who trade with each other (2+ sales):`);
for (const p of r.pairs) console.log(`  ${p.a} ↔ ${p.b}: ${p.sales} sales, ${p.karat} Karat`);
console.log(`\nAccounts made from the same IP address:`);
for (const group of r.sharedSignups) console.log(`  ${group.join(', ')}`);
await pool.end();
