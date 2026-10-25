#!/bin/sh
# Backs up the game database (accounts, collections, decks, purchases) on the server:
#   sh backend/scripts/backup_db.sh [dir]     (default ~/backups; keeps the newest 14)
# A compressed pg_dump (custom format: restore with pg_restore -d <db> <file>). Reads the DB_*
# settings from backend/.env. Nightly on the server (crontab -e):
#   30 3 * * * sh /opt/Turf_War/backend/scripts/backup_db.sh >> $HOME/backups/backup.log 2>&1
# and copy the files off the machine too (tools/backup_db.mjs pulls them to the PC).
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=${1:-$HOME/backups}
mkdir -p "$DIR"
chmod 700 "$DIR"
# (.env isn't safe to source as a whole: only its DB_ lines)
eval "$(grep '^DB_' "$ROOT/backend/.env" | sed 's/^/export /')"
OUT="$DIR/alleyway-$(date +%Y-%m-%d-%H%M).dump"
PGPASSWORD="$DB_PASS" pg_dump -h "${DB_HOST:-localhost}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$OUT"
chmod 600 "$OUT"
# Keep the newest 14
ls -1t "$DIR"/alleyway-*.dump 2>/dev/null | tail -n +15 | xargs -r rm -f --
echo "$OUT"
