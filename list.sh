#!/usr/bin/env bash
# List the dumps currently in Spaces and (if configured) B2.
# Uses the same environment as backup.sh. Safe to run any time:
#   kamal accessory exec pg-backup /list.sh
set -euo pipefail

SPACES_ACCESS_KEY=${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY is required}
SPACES_SECRET_KEY=${SPACES_SECRET_KEY:?SPACES_SECRET_KEY is required}
SPACES_BUCKET=${SPACES_BUCKET:?SPACES_BUCKET is required}
SPACES_ENDPOINT=${SPACES_ENDPOINT:-tor1.digitaloceanspaces.com}
DUMP_DIR=${DUMP_DIR:?DUMP_DIR is required}
B2_BUCKET=${B2_BUCKET:-}
B2_ENDPOINT=${B2_ENDPOINT:-s3.us-west-001.backblazeb2.com}

export RCLONE_CONFIG
RCLONE_CONFIG=$(mktemp)
trap 'rm -f "${RCLONE_CONFIG}"' EXIT

cat > "${RCLONE_CONFIG}" <<CFG
[spaces]
type = s3
provider = DigitalOcean
access_key_id = ${SPACES_ACCESS_KEY}
secret_access_key = ${SPACES_SECRET_KEY}
endpoint = ${SPACES_ENDPOINT}
no_check_bucket = true
CFG

echo "== Spaces: ${SPACES_BUCKET}/${DUMP_DIR}"
rclone ls "spaces:${SPACES_BUCKET}/${DUMP_DIR}/"

if [ -n "${B2_BUCKET}" ]; then
  cat >> "${RCLONE_CONFIG}" <<CFG

[b2]
type = s3
provider = Other
access_key_id = ${B2_ACCESS_KEY:?}
secret_access_key = ${B2_SECRET_KEY:?}
endpoint = ${B2_ENDPOINT}
no_check_bucket = true
CFG
  echo "== B2: ${B2_BUCKET}/${DUMP_DIR}"
  rclone ls "b2:${B2_BUCKET}/${DUMP_DIR}/"
fi
