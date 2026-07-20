# Demonstrating ASYNCHRONOUS Replication (the AP contrast)

Goal: show that with async replication the primary NEVER waits for the standby.
Writes stay available during a partition, but the standby lags and un-replicated
writes are lost if the primary dies before catch-up.

App base URL:  http://localhost:4001
Primary psql:  docker exec -it apg-primary psql -U app_user -d appdb
Standby psql:  docker exec -it apg-standby psql -U app_user -d appdb

=====================================================================
1. NORMAL: write replicates in the background
=====================================================================
    curl -s -X POST http://localhost:4001/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"async-1"}'

Both nodes have it (replication is fast, just not guaranteed-before-ack):
    docker exec -it apg-primary psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    docker exec -it apg-standby psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

Confirm it is asynchronous:
    docker exec -it apg-primary psql -U app_user -d appdb -c \
      "SELECT application_name, state, sync_state FROM pg_stat_replication;"
    -> sync_state = async

=====================================================================
2. THE KEY CONTRAST: writes DO NOT block when the standby is down
=====================================================================
Stop the standby (the partition):
    docker stop apg-standby

Now write several times — each returns IMMEDIATELY (no SyncRep wait):
    curl -s -X POST http://localhost:4001/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"during-outage-1"}'
    curl -s -X POST http://localhost:4001/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"during-outage-2"}'

(In the SYNC POC these would have HUNG. Here they succeed = Availability kept.)

Prove the writes are on the primary only (standby is behind / offline):
    docker exec -it apg-primary psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    # standby is stopped, so it has none of the 'during-outage' rows yet.

This is the CONSISTENCY GAP: primary and standby now diverge. If the primary were
to fail RIGHT NOW and the standby were promoted, 'during-outage-1/2' would be LOST.

=====================================================================
3. RECOVERY: eventual consistency (standby catches up)
=====================================================================
    docker start apg-standby

Give it a moment, then the standby has caught up automatically:
    docker exec -it apg-standby psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

Check how far behind it was / lag now (run on primary):
    docker exec -it apg-primary psql -U app_user -d appdb -c \
      "SELECT application_name, sync_state, sent_lsn, replay_lsn,
              pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
       FROM pg_stat_replication;"

=====================================================================
4. (Optional) SEE THE DATA-LOSS WINDOW EXPLICITLY
=====================================================================
    docker stop apg-standby
    # write a row that only the primary will have
    curl -s -X POST http://localhost:4001/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"will-be-lost"}'
    # simulate primary loss BEFORE the standby ever saw that row
    docker stop apg-primary
    # promote the stale standby
    docker start apg-standby
    docker exec -it apg-standby psql -U app_user -d appdb -c "SELECT pg_promote();"
    docker exec -it apg-standby psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    # 'will-be-lost' is NOT there -> data loss (Consistency sacrificed for Availability)

=====================================================================
CAP SUMMARY (async)
=====================================================================
Async is the AP-leaning choice:
  - Partition (standby down): primary keeps accepting writes  -> AVAILABLE
  - But standby lags; failover can lose un-replicated writes  -> NOT strongly consistent

Contrast with Synchronous_Replication (CP):
  - Partition (standby down): primary BLOCKS writes           -> CONSISTENT
  - But writes are unavailable until a standby ACKs           -> NOT available
