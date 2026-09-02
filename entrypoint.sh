#!/usr/bin/env bash
set -euo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-0 0 * * *}"

echo "pg-backup: schedule '${CRON_SCHEDULE}'"
echo "pg-backup: ${POSTGRES_DB:-postgres}@${POSTGRES_HOST:-localhost} → ${SPACES_BUCKET:-?}/${DUMP_DIR:-?}"

echo "${CRON_SCHEDULE} /backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
touch /var/log/backup.log

crond
exec tail -f /var/log/backup.log
