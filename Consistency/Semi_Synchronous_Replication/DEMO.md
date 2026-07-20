# Demonstrating SEMI-SYNCHRONOUS Replication (quorum: ANY 1 of 2)

Goal: show the middle ground. A commit waits for AT LEAST ONE standby.
  - Kill ONE  standby -> writes CONTINUE (the other confirms).
  - Kill BOTH standbys -> writes BLOCK (no confirmation possible).

App base URL:  http://localhost:4002
Primary  psql: docker exec -it spg-primary  psql -U app_user -d appdb
Standby1 psql: docker exec -it spg-standby1 psql -U app_user -d appdb
Standby2 psql: docker exec -it spg-standby2 psql -U app_user -d appdb

=====================================================================
1. NORMAL: confirm quorum semi-sync is active
=====================================================================
    docker exec -it spg-primary psql -U app_user -d appdb -c "SHOW synchronous_standby_names;"
    # -> ANY 1 (standby1, standby2)

    docker exec -it spg-primary psql -U app_user -d appdb -c \
      "SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY application_name;"
    # -> both standby1 and standby2 present; sync_state = quorum

Write a row (all three nodes end up with it):
    curl -s -X POST http://localhost:4002/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"semi-1"}'

    docker exec -it spg-primary  psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    docker exec -it spg-standby1 psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    docker exec -it spg-standby2 psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

=====================================================================
2. KILL ONE STANDBY -> writes CONTINUE (the key advantage over strict sync)
=====================================================================
    docker stop spg-standby2

Write again — succeeds IMMEDIATELY because standby1 still confirms the quorum:
    curl -s -X POST http://localhost:4002/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"one-standby-down"}'

    # still durable on primary + standby1:
    docker exec -it spg-primary  psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    docker exec -it spg-standby1 psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

Contrast: in strict sync (single 'standby1'), stopping that one standby would have
BLOCKED all writes. Here the quorum keeps you writable AND still durable on >= 2 nodes.

=====================================================================
3. KILL BOTH STANDBYS -> writes BLOCK (still CP: never ack without a confirmer)
=====================================================================
    docker stop spg-standby1     # now BOTH standbys are down

This write HANGS (no standby can confirm the quorum):
    curl -s -X POST http://localhost:4002/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"both-down"}'

While it hangs, in another terminal see WHY:
    docker exec -it spg-primary psql -U app_user -d appdb -c \
      "SELECT pid, state, wait_event_type, wait_event, query
       FROM pg_stat_activity WHERE wait_event = 'SyncRep';"
    # -> backend blocked on wait_event = SyncRep

Reads still work:
    curl -s http://localhost:4002/api/records/read

=====================================================================
4. RECOVERY -> bring back ONE standby, the blocked write completes
=====================================================================
    docker start spg-standby1
    # the hanging curl from step 3 returns success as soon as standby1 confirms

    docker exec -it spg-standby1 psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

Optionally restore full redundancy:
    docker start spg-standby2

=====================================================================
CAP SUMMARY (semi-sync)
=====================================================================
Consistency-favoring (CP) for durability: every acked write is on primary + >= 1 standby.
Better availability than strict sync: tolerates ONE standby failure without blocking.
Blocks only when ALL quorum candidates are gone.

Spectrum (same code, only synchronous_standby_names differs):
  Strict sync   'standby1'              -> block if that 1 standby is down   (most fragile CP)
  Semi-sync     'ANY 1 (standby1,std2)' -> block only if BOTH are down       (balanced CP)
  Async         (empty)                 -> never block, may lose writes      (AP)
