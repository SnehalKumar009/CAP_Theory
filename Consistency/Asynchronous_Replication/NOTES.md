# How Asynchronous Replication Works — In This POC

Same machinery as the synchronous POC, with ONE deliberate difference:
`synchronous_standby_names` is left EMPTY, so the primary never waits for the
standby before returning a commit.

Files:
- postgres/primary/postgresql.conf          (synchronous_standby_names NOT set)
- postgres/primary/pg_hba.conf
- postgres/primary/init/01-replication-user.sql   (creates repl_user; NO sync setup)
- postgres/standby/standby-entrypoint.sh    (pg_basebackup clone + hot standby)
- docker-compose.yml                        (apg-primary / apg-standby / async-app)

=====================================================================
WHAT MAKES THIS ASYNCHRONOUS
=====================================================================
In the SYNC POC we ran, during init:
    ALTER SYSTEM SET synchronous_standby_names = 'standby1';
Here we DO NOT. That single omission is the whole difference.

Rule:
  synchronous_standby_names empty  -> NO commit ever waits -> ASYNCHRONOUS
  synchronous_commit = on          -> only means "flush MY (primary's) WAL locally"

So a commit is durable on the PRIMARY's disk before returning, but the standby is
updated in the background over the WAL stream and may lag.

=====================================================================
PRIMARY STARTUP (same flow as sync, minus the sync setup)
=====================================================================
1. Image entrypoint runs; command = postgres -c config_file=/etc/postgresql/postgresql.conf
2. First run (empty volume): initdb -> temp server -> create appdb ->
   run init scripts:
     - 01-replication-user.sql -> CREATE ROLE repl_user WITH REPLICATION LOGIN
     (there is NO 02-sync-standby.sql here)
3. Temp server stops; real server starts with synchronous_standby_names EMPTY.
   Result: replication is asynchronous from the very first write.

=====================================================================
STANDBY STARTUP (identical to sync)
=====================================================================
1. Overrides image entrypoint with standby-entrypoint.sh.
2. First run: waits for apg-primary, then pg_basebackup ... -R clones the data dir,
   writing standby.signal + primary_conninfo (application_name=standby1).
3. Starts with hot_standby=on; WAL receiver connects out to the primary and
   streams WAL. Because the primary has no sync names, this stream is async.

NOTE: application_name=standby1 is still sent, but since synchronous_standby_names
is empty, the primary never treats it as synchronous -> sync_state = async.

=====================================================================
HOW A WRITE FLOWS (async)
=====================================================================
1. Client sends COMMIT to primary.
2. Primary writes + flushes WAL to its OWN disk.
3. Primary RETURNS SUCCESS to the client immediately.   <-- does NOT wait
4. Separately/asynchronously, the WAL sender pushes that WAL to the standby,
   which replays it "eventually".

If the standby is down at step 4, steps 1-3 still succeed. The standby simply
catches up later when it reconnects (eventual consistency). Any writes not yet
shipped are lost only if the primary is lost before catch-up.

=====================================================================
CAP POSITIONING
=====================================================================
AP-leaning:
  - Available under partition (writes succeed with standby down).
  - Not strongly consistent (standby lags; failover may lose recent writes).

Compare Synchronous_Replication (CP): consistent but blocks writes under partition.
Same code, one parameter (synchronous_standby_names) flips the trade-off.
