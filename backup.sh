#!/usr/bin/env bash
set -euo pipefail

################################################################################
# pg-backup: PostgreSQL dump to DigitalOcean Spaces (+ optional Backblaze B2)
################################################################################
#
# OVERVIEW
# --------
# Dumps a PostgreSQL database, compresses it, and uploads to two
# S3-compatible backends (DO Spaces + Backblaze B2). Cleans up backups
# older than the configured retention period on each backend.
#
# USAGE
# -----
#   /backup.sh                    Run backup once
#   (or via cron schedule)
#
# CONFIGURATION
# -------------
# Postgres: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
# Naming:   DUMP_PREFIX, DUMP_DIR
# Spaces:   SPACES_ACCESS_KEY, SPACES_SECRET_KEY, SPACES_BUCKET, SPACES_ENDPOINT
# B2:       B2_ACCESS_KEY, B2_SECRET_KEY, B2_BUCKET, B2_ENDPOINT
# Retention: SPACES_RETENTION_DAYS, B2_RETENTION_DAYS
# Health:   HEALTHCHECK_URL (optional, pinged on success)
#
################################################################################

# Colors
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[1;33m'
red='\033[0;31m'
nc='\033[0m'

# Postgres
POSTGRES_HOST=${POSTGRES_HOST:?POSTGRES_HOST is required}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
POSTGRES_DB=${POSTGRES_DB:?POSTGRES_DB is required}

# Naming
DUMP_PREFIX=${DUMP_PREFIX:?DUMP_PREFIX is required}
DUMP_DIR=${DUMP_DIR:?DUMP_DIR is required}

# DO Spaces
SPACES_ACCESS_KEY=${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY is required}
SPACES_SECRET_KEY=${SPACES_SECRET_KEY:?SPACES_SECRET_KEY is required}
SPACES_BUCKET=${SPACES_BUCKET:?SPACES_BUCKET is required}
SPACES_ENDPOINT=${SPACES_ENDPOINT:-tor1.digitaloceanspaces.com}
SPACES_RETENTION_DAYS=${SPACES_RETENTION_DAYS:-3}

# Backblaze B2 (optional: skipped entirely when B2_BUCKET is unset)
B2_BUCKET=${B2_BUCKET:-}
B2_ENDPOINT=${B2_ENDPOINT:-s3.us-west-001.backblazeb2.com}
B2_RETENTION_DAYS=${B2_RETENTION_DAYS:-90}
if [ -n "${B2_BUCKET}" ]; then
  B2_ACCESS_KEY=${B2_ACCESS_KEY:?B2_ACCESS_KEY is required when B2_BUCKET is set}
  B2_SECRET_KEY=${B2_SECRET_KEY:?B2_SECRET_KEY is required when B2_BUCKET is set}
fi

# Health check (optional)
HEALTHCHECK_URL=${HEALTHCHECK_URL:-}

# Derived
TIMESTAMP=$(date -u +%Y-%m-%d_%H-%M-%S)
FILENAME="${DUMP_PREFIX}_${TIMESTAMP}.sql.gz"
LOCAL_PATH="/tmp/${FILENAME}"
REMOTE_PATH="${DUMP_DIR}/${FILENAME}"

################################################################################
# Main Orchestration
################################################################################

main() {
  echo "========================================="
  log "Starting backup: $(date -u)"
  info "Database: ${POSTGRES_DB}@${POSTGRES_HOST}"
  info "Destination: ${SPACES_BUCKET}/${REMOTE_PATH}"
  echo "========================================="

  configure_rclone
  dump_database
  upload_to_spaces
  upload_to_b2
  prune_spaces
  prune_b2
  ping_healthcheck
  cleanup

  echo "========================================="
  log "Backup completed: $(date -u)"
  echo "========================================="
}

################################################################################
# Helper Functions
################################################################################

log() { echo -e "${green}==>${nc} ${1}"; }
info() { echo -e "${blue}Info:${nc} ${1}"; }
warn() { echo -e "${yellow}Warning:${nc} ${1}"; }
error() { echo -e "${red}Error:${nc} ${1}" >&2; exit 1; }

################################################################################
# Core Functions
################################################################################

configure_rclone() {
  info "Configuring rclone remotes..."

  export RCLONE_CONFIG=/tmp/rclone.conf

  cat > "${RCLONE_CONFIG}" <<EOF
[spaces]
type = s3
provider = DigitalOcean
access_key_id = ${SPACES_ACCESS_KEY}
secret_access_key = ${SPACES_SECRET_KEY}
endpoint = ${SPACES_ENDPOINT}
acl = private
no_check_bucket = true
EOF

  [ -n "${B2_BUCKET}" ] || { info "B2 not configured, skipping"; return 0; }

  cat >> "${RCLONE_CONFIG}" <<EOF

[b2]
type = s3
provider = Other
access_key_id = ${B2_ACCESS_KEY}
secret_access_key = ${B2_SECRET_KEY}
endpoint = ${B2_ENDPOINT}
acl = private
no_check_bucket = true
EOF
  info "B2 configured: ${B2_BUCKET}"
}

dump_database() {
  info "Dumping ${POSTGRES_DB}..."

  export PGPASSWORD="${POSTGRES_PASSWORD}"
  pg_dump \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --no-owner \
    --no-privileges \
    | gzip > "${LOCAL_PATH}"
  unset PGPASSWORD

  local dump_size
  dump_size=$(du -h "${LOCAL_PATH}" | cut -f1)
  log "Dump created: ${FILENAME} (${dump_size})"
}

upload_to_spaces() {
  info "Uploading to Spaces: ${SPACES_BUCKET}/${REMOTE_PATH}"

  if ! rclone copyto "${LOCAL_PATH}" "spaces:${SPACES_BUCKET}/${REMOTE_PATH}"; then
    error "Failed to upload to Spaces"
  fi

  log "Spaces upload complete"
}

upload_to_b2() {
  [ -n "${B2_BUCKET}" ] || return 0
  info "Uploading to B2: ${B2_BUCKET}/${REMOTE_PATH}"

  if ! rclone copyto "${LOCAL_PATH}" "b2:${B2_BUCKET}/${REMOTE_PATH}"; then
    error "Failed to upload to B2"
  fi

  log "B2 upload complete"
}

prune_spaces() {
  info "Pruning Spaces backups older than ${SPACES_RETENTION_DAYS} days..."

  rclone delete "spaces:${SPACES_BUCKET}/${DUMP_DIR}/" \
    --min-age "${SPACES_RETENTION_DAYS}d" \
    --include "*.sql.gz" \
    -v
}

prune_b2() {
  [ -n "${B2_BUCKET}" ] || return 0
  info "Pruning B2 backups older than ${B2_RETENTION_DAYS} days..."

  rclone delete "b2:${B2_BUCKET}/${DUMP_DIR}/" \
    --min-age "${B2_RETENTION_DAYS}d" \
    --include "*.sql.gz" \
    -v
}

ping_healthcheck() {
  local url="${HEALTHCHECK_URL:-${PG_BACKUP_HEALTHCHECK_URL:-}}"
  [ -n "${url}" ] || return 0

  info "Pinging healthcheck..."
  wget -q -O /dev/null "${url}" || warn "Healthcheck ping failed (non-fatal)"
}

cleanup() {
  rm -f "${LOCAL_PATH}" /tmp/rclone.conf
  info "Temp files removed"
}

################################################################################
# Script Execution
################################################################################

main "$@"
