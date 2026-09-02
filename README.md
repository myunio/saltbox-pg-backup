# unio-pg-backup

Nightly `pg_dump` of one PostgreSQL database, gzipped and uploaded to
DigitalOcean Spaces and, optionally, Backblaze B2. Prunes old dumps on each
target. Built to run as a [Kamal](https://kamal-deploy.org) accessory next to
a `postgres` accessory, but it is just a container with cron in it.

Image: `ghcr.io/myunio/unio-pg-backup` (PostgreSQL 18 client tools, rclone, dcron on Alpine).

## Environment

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `POSTGRES_HOST` | yes | | usually the postgres accessory's container name |
| `POSTGRES_PORT` | | `5432` | |
| `POSTGRES_USER` | | `postgres` | |
| `POSTGRES_PASSWORD` | yes | | |
| `POSTGRES_DB` | yes | | the one database to dump |
| `DUMP_PREFIX` | yes | | filename prefix, e.g. the database name |
| `DUMP_DIR` | yes | | object path prefix in each bucket, e.g. `production/db` |
| `SPACES_ACCESS_KEY` / `SPACES_SECRET_KEY` | yes | | |
| `SPACES_BUCKET` | yes | | |
| `SPACES_ENDPOINT` | | `tor1.digitaloceanspaces.com` | |
| `SPACES_RETENTION_DAYS` | | `3` | |
| `B2_BUCKET` | no | | set it to enable the B2 copy |
| `B2_ACCESS_KEY` / `B2_SECRET_KEY` | when B2_BUCKET set | | |
| `B2_ENDPOINT` | | `s3.us-west-001.backblazeb2.com` | |
| `B2_RETENTION_DAYS` | | `90` | |
| `CRON_SCHEDULE` | | `0 0 * * *` | |
| `HEALTHCHECK_URL` | no | | pinged with GET after a successful run |

Dumps are named `<DUMP_PREFIX>_<YYYY-MM-DD_HH-MM-SS>.sql.gz` (UTC) and stored
at `<DUMP_DIR>/<filename>`. `pg_dump` runs with `--no-owner --no-privileges`.

## Kamal accessory

```yaml
accessories:
  pg-backup:
    # renovate: datasource=docker depName=ghcr.io/myunio/unio-pg-backup
    image: ghcr.io/myunio/unio-pg-backup:1.0.0
    host: 203.0.113.10
    options:
      memory: 128m
    env:
      clear:
        POSTGRES_HOST: myapp-postgres
        POSTGRES_USER: postgres
        POSTGRES_DB: myapp_production
        DUMP_PREFIX: myapp_production
        DUMP_DIR: production/db
        SPACES_ENDPOINT: tor1.digitaloceanspaces.com
        SPACES_BUCKET: myapp-dr
        SPACES_RETENTION_DAYS: "30"
        B2_ENDPOINT: s3.us-west-001.backblazeb2.com
        B2_BUCKET: myapp-dr
        B2_RETENTION_DAYS: "90"
        CRON_SCHEDULE: "0 0 * * *"
      secret:
        - POSTGRES_PASSWORD
        - SPACES_ACCESS_KEY
        - SPACES_SECRET_KEY
        - B2_ACCESS_KEY
        - B2_SECRET_KEY
```

```bash
kamal accessory boot pg-backup
kamal accessory exec pg-backup /backup.sh   # run one now
kamal accessory exec pg-backup /list.sh     # what is in each bucket
kamal accessory logs pg-backup
```

## Restore

```bash
gunzip -c myapp_production_2026-09-08_00-00-00.sql.gz \
  | psql -h myapp-postgres -U postgres -d restore_test
```

## Releasing

Tag a semver release and the workflow publishes `ghcr.io/myunio/unio-pg-backup:<version>`,
plus `<major>.<minor>`, `<major>` and `latest`.

```bash
git tag v1.0.0 && git push --tags
```

The image is public. Pin an exact version in each app and let Renovate
propose bumps.
