# How Semi-Synchronous Replication Works — In This POC

Same machinery as the sync/async POCs, with a QUORUM synchronous_standby_names.

Files:
- postgres/primary/postgresql.conf              (synchronous_commit=on; names set via init)
- postgres/primary/init/01-replication-user.sql (creates repl_user)
- postgres/primary/init/02-semi-sync.sql        (ALTER SYSTEM SET ... 'ANY 1 (standby1, standby2)')
- postgres/standby/standby-entrypoint.sh        (shared by both standbys; identity via env)
- docker-compose.yml                            (spg-primary + spg-standby1 + spg-standby2 + app)

=====================================================================
WHAT MAKES THIS SEMI-SYNCHRONOUS
=====================================================================
One setting, applied via ALTER SYSTEM during init:
    synchronous_standby_names = 'ANY 1 (standby1, standby2)'

Meaning: a COMMIT must be confirmed by ANY 1 of the two named standbys before it
returns. The standby(s) not needed to satisfy the quorum stream asynchronously.

Compare the whole family (only this one line changes):
  Strict sync : 'standby1'                 -> wait for that specific standby
  Semi-sync   : 'ANY 1 (standby1, standby2)'-> wait for any one of two
  Async       : (empty)                    -> never wait

FIRST vs ANY:
  ANY k (...)   -> quorum; any k of the listed standbys can satisfy it.
  FIRST k (...) -> priority; prefers the earliest-listed, falls back in order.
We use ANY 1 so EITHER standby can keep writes flowing.

=====================================================================
HOW THE TWO STANDBYS GET DIFFERENT IDENTITIES
=====================================================================
Both standbys run the SAME standby-entrypoint.sh. Compose passes each its identity:
    spg-standby1 -> STANDBY_NAME=standby1
    spg-standby2 -> STANDBY_NAME=standby2
The script uses $STANDBY_NAME as the application_name in pg_basebackup's -R conninfo.
The primary matches those names against 'ANY 1 (standby1, standby2)'.

=====================================================================
WRITE FLOW (semi-sync commit)
=====================================================================
1. Client sends COMMIT to the primary.
2. Primary flushes the WAL to its OWN disk.
3. Primary streams the WAL to BOTH standbys.
4. As soon as AT LEAST ONE standby confirms (flush), the quorum is met.
5. Primary returns COMMIT success to the client.
   (The other standby may still be catching up asynchronously.)

If BOTH standbys are unreachable, step 4 never happens -> COMMIT blocks
(wait_event = SyncRep). Reads still work.

=====================================================================
CAP POSITIONING
=====================================================================
CP for durability: an acked write is always on primary + >= 1 standby (never lost to
a single-node failure, given LSN-aware failover).
More available than strict sync: survives ONE standby outage without blocking.
Blocks only when ALL quorum candidates are down.

Note (same nuance as before): reading from a standby can be slightly stale
(synchronous_commit=on guarantees the WAL is flushed on the confirmer, not yet
applied/visible). For linearizable reads, read from the primary or use remote_apply.
