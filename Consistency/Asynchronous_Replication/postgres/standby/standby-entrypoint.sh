#!/bin/sh
# Standby bootstrap for native PostgreSQL ASYNCHRONOUS streaming replication.
# On first run (empty data dir) it clones the primary with pg_basebackup and
# starts as a hot standby. Because the primary has no synchronous_standby_names,
# this standby streams WAL asynchronously (it may lag behind the primary).
set -e

PGDATA=/var/lib/postgresql/data

# The named volume mounts as root; pg_basebackup/postgres run as 'postgres'.
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[standby] Waiting for primary to accept replication connections..."
  until pg_isready -h apg-primary -p 5432 -U repl_user >/dev/null 2>&1; do
    sleep 2
  done

  echo "[standby] Cloning primary via pg_basebackup..."
  rm -rf "${PGDATA:?}"/*
  # -R writes primary_conninfo + standby.signal into the new data dir.
  su-exec postgres pg_basebackup \
    -d "host=apg-primary port=5432 user=repl_user password=repl_password application_name=standby1" \
    -D "$PGDATA" -Fp -Xs -P -R
fi

chown -R postgres:postgres "$PGDATA"

# PostgreSQL refuses to start if the data directory is group/world accessible.
chmod 0700 "$PGDATA"

echo "[standby] Starting as hot standby (asynchronous)..."
exec su-exec postgres postgres -c listen_addresses='*' -c hot_standby=on
