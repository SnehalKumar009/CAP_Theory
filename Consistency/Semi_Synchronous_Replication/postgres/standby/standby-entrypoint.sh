#!/bin/sh
# Standby bootstrap for native PostgreSQL SEMI-SYNCHRONOUS streaming replication.
# Shared by BOTH standbys; each passes its own identity via env vars:
#   STANDBY_NAME  -> application_name the primary matches in 'ANY 1 (standby1, standby2)'
#   PRIMARY_HOST  -> host of the primary to clone/stream from
# On first run (empty data dir) it clones the primary with pg_basebackup and
# starts as a hot standby.
set -e

PGDATA=/var/lib/postgresql/data
PRIMARY_HOST="${PRIMARY_HOST:-spg-primary}"
APP_NAME="${STANDBY_NAME:-standby1}"

# The named volume mounts as root; pg_basebackup/postgres run as 'postgres'.
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[$APP_NAME] Waiting for primary ($PRIMARY_HOST) to accept replication connections..."
  until pg_isready -h "$PRIMARY_HOST" -p 5432 -U repl_user >/dev/null 2>&1; do
    sleep 2
  done

  echo "[$APP_NAME] Cloning primary via pg_basebackup..."
  rm -rf "${PGDATA:?}"/*
  # application_name=$APP_NAME must be one of the names in synchronous_standby_names.
  # -R writes primary_conninfo + standby.signal into the new data dir.
  su-exec postgres pg_basebackup \
    -d "host=$PRIMARY_HOST port=5432 user=repl_user password=repl_password application_name=$APP_NAME" \
    -D "$PGDATA" -Fp -Xs -P -R
fi

chown -R postgres:postgres "$PGDATA"

# PostgreSQL refuses to start if the data directory is group/world accessible.
chmod 0700 "$PGDATA"

echo "[$APP_NAME] Starting as hot standby..."
exec su-exec postgres postgres -c listen_addresses='*' -c hot_standby=on
