#!/bin/sh
# Standby bootstrap for native PostgreSQL streaming replication.
# On first run (empty data dir) it clones the primary with pg_basebackup and
# configures itself as synchronous standby 'standby1'. On later runs it just
# starts and resumes streaming.
set -e

PGDATA=/var/lib/postgresql/data

# The named volume mounts as root; pg_basebackup/postgres run as 'postgres'.
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[standby] Waiting for primary to accept replication connections..."
  until pg_isready -h pg-primary -p 5432 -U repl_user >/dev/null 2>&1; do
    sleep 2
  done

  echo "[standby] Cloning primary via pg_basebackup..."
  rm -rf "${PGDATA:?}"/*
  # application_name=standby1 must match synchronous_standby_names on primary.
  # -R writes primary_conninfo + standby.signal into the new data dir.
  su-exec postgres pg_basebackup \
    -d "host=pg-primary port=5432 user=repl_user password=repl_password application_name=standby1" \
    -D "$PGDATA" -Fp -Xs -P -R
fi

chown -R postgres:postgres "$PGDATA"

echo "[standby] Starting as hot standby..."
exec su-exec postgres postgres -c listen_addresses='*' -c hot_standby=on
