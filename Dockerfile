# pg-backup: nightly pg_dump to DigitalOcean Spaces and Backblaze B2.
#
# PostgreSQL 18 client tools + rclone. Runs on a cron schedule via dcron.
# See README.md for the environment contract.

FROM postgres:18-alpine

RUN apk add --no-cache \
  rclone \
  dcron \
  bash \
  gzip

COPY backup.sh /backup.sh
COPY list.sh /list.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /backup.sh /list.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
