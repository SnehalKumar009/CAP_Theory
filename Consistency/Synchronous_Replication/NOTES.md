# How Synchronous Replication Works — In This POC

A walkthrough of what actually happens in OUR setup (postgres:16-alpine +
docker-compose), tied to the exact files we wrote.

Files referenced:
- postgres/primary/postgresql.conf
- postgres/primary/pg_hba.conf
- postgres/primary/init/01-replication-user.sql
- postgres/primary/init/02-sync-standby.sql
- postgres/standby/standby-entrypoint.sh
- docker-compose.yml

=====================================================================
1. WHAT HAPPENS WHEN THE PRIMARY STARTS
=====================================================================
The primary uses the image's built-in `docker-entrypoint.sh`. Our compose
`command: postgres -c config_file=/etc/postgresql/postgresql.conf` is passed to it.

Boot sequence:
1. Entrypoint sees the command starts with `postgres` -> runs DB setup.
2. `docker_setup_env` reads POSTGRES_USER/PASSWORD/DB and checks if
   /var/lib/postgresql/data/PG_VERSION exists:
     - absent  -> first-time init (empty volume)
     - present -> skip all init, go straight to start
3. Verifies POSTGRES_PASSWORD is set (missing => the "superuser password not
   specified" error).

If data dir is EMPTY (first run only):
4. `initdb` creates a fresh cluster (with a default postgresql.conf inside PGDATA).
5. A TEMPORARY server starts on the local socket only. It DOES load our
   config_file. (This is why synchronous_standby_names is NOT put in that file —
   it would make the setup writes below hang.)
6. Creates the `appdb` database.
7. Runs our init scripts from /docker-entrypoint-initdb.d in FILENAME order:
     - 01-replication-user.sql -> CREATE ROLE repl_user WITH REPLICATION LOGIN...
     - 02-sync-standby.sql      -> ALTER SYSTEM SET synchronous_standby_names='standby1'
       (this only writes to postgresql.auto.conf; it does NOT take effect on the
        temp server, so no blocking during setup)
8. Temp server stops.

Always (every run):
9. `exec postgres -c config_file=/etc/postgresql/postgresql.conf` starts the REAL
   server. It loads postgresql.conf THEN postgresql.auto.conf on top, so
   synchronous_standby_names='standby1' becomes active here. Sync replication is
   now armed. The primary listens on all addresses and waits to be connected to.

KEY: init scripts run ONCE, only when the volume is empty. Changing them needs
`docker compose down -v`.

=====================================================================
2. WHAT HAPPENS WHEN THE STANDBY STARTS
=====================================================================
The standby OVERRIDES the image entrypoint:
  entrypoint: ["/bin/sh", "/standby-entrypoint.sh"]
So none of the initdb / init-scripts machinery runs. We control everything.

Boot sequence (standby-entrypoint.sh):
1. Runs as root; `set -e` (any failure aborts the container).
2. mkdir + chown $PGDATA to postgres (named volume mounts as root).
3. Decision: does $PGDATA/PG_VERSION exist?
     - absent  -> must clone from primary
     - present -> skip clone, just resume streaming

First run only (clone):
4. Wait until primary accepts connections (pg_isready loop).
5. pg_basebackup takes a physical byte-for-byte copy of the primary's data dir:
     su-exec postgres pg_basebackup \
       -d "host=pg-primary ... application_name=standby1" \
       -D "$PGDATA" -Fp -Xs -P -R
   -R writes into the new data dir:
     - standby.signal   -> boot in standby (recovery, read-only) mode
     - primary_conninfo -> where the primary is + application_name=standby1
   This pg_basebackup connection is only for the COPY; it then closes. It does
   NOT permanently register the sync standby.

Always:
6. chown + chmod 0700 $PGDATA (postgres refuses a group/world-accessible dir).
7. exec postgres -c listen_addresses='*' -c hot_standby=on
   - sees standby.signal -> starts in recovery mode
   - reads primary_conninfo -> connects OUT to the primary
   - hot_standby=on -> allows read-only queries while replaying WAL (port 5433)

=====================================================================
3. HOW THE STANDBY "MARKS ITSELF" AS THE SYNC STANDBY TO THE PRIMARY
=====================================================================
There is no explicit "please be my sync replica" message. It is implicit, and it
happens on the RUNNING SERVER's connection (NOT the pg_basebackup copy):

1. The standby's WAL RECEIVER opens a replication connection to the primary using
   primary_conninfo. Under the hood libpq adds `replication=true` to the startup
   packet -> primary spawns a WAL SENDER (not a normal query backend).
2. The same startup packet carries `application_name=standby1`.
3. Standby issues:  START_REPLICATION <LSN> TIMELINE 1  -> "start sending WAL".
4. When that WAL sender registers, the primary compares application_name against
   synchronous_standby_names ('standby1'). MATCH -> this connection is marked
   SYNCHRONOUS, and commits now block until it ACKs.

Wiring summary:
  replication=true          -> "this is a replication link"
  application_name=standby1 -> identity announced
  START_REPLICATION         -> "start streaming WAL"
  name in synchronous_standby_names -> primary flags it as SYNC

If application_name != standby1, streaming still works but the primary treats it
as ASYNC and commits never block. The name is the entire wiring.

Note: pg_basebackup -R does not mark anything sync; it just plants
application_name=standby1 into primary_conninfo so the LATER server connection
inherits the same identity.

=====================================================================
4. HOW A WRITE ON THE PRIMARY REACHES THE STANDBY (SYNC COMMIT)
=====================================================================
Direction: the standby PULLS (initiates the connection), then the primary PUSHES
WAL over that connection.

For one write (synchronous_commit = on):
1. Client sends COMMIT to the primary.
2. Primary writes + FLUSHES the WAL record to its own disk (durable locally).
3. Primary's WAL sender PUSHES that WAL to the standby over the existing link.
4. Standby's WAL receiver writes + flushes the WAL, then sends an ACK back with
   its write/flush/replay LSN positions.
5. Only after the ACK (from standby1) does the primary return COMMIT success to
   the client.

  standby --(1) connects out, START_REPLICATION--> primary
  primary --(2) pushes WAL for the write---------> standby
  standby --(3) flush + ACK (LSN feedback)-------> primary
  primary --(4) COMMIT returns to client---------> app

While waiting at step 5, the backend shows in pg_stat_activity as:
  state=active, wait_event_type=IPC, wait_event=SyncRep

If the standby is unreachable, step 3 never arrives -> the COMMIT blocks
(Consistency over Availability). Reads still work. When the standby returns, the
blocked commit completes with no data loss.

=====================================================================
CAP SUMMARY
=====================================================================
This is a CP system: on a partition (standby unreachable) the primary sacrifices
Availability (writes block) to preserve Consistency (no divergence; the standby
never misses an acknowledged commit).
