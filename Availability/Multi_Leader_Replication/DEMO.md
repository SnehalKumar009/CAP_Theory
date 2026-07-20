# Demonstrating MULTI-LEADER Replication (and its conflict problem)

Two full read-write leaders with bidirectional logical replication.

App base URL:  http://localhost:4003
Node A psql:   docker exec -it mlg-node-a psql -U app_user -d appdb
Node B psql:   docker exec -it mlg-node-b psql -U app_user -d appdb

=====================================================================
1. NORMAL: a write on either leader appears on the other
=====================================================================
Write on A (gets an ODD id), then read from B — it replicated across:
    curl -s -X POST http://localhost:4003/api/records/write/a \
      -H "Content-Type: application/json" -d '{"payload":"from-A"}'
    curl -s http://localhost:4003/api/records/read/b

Write on B (gets an EVEN id), then read from A:
    curl -s -X POST http://localhost:4003/api/records/write/b \
      -H "Content-Type: application/json" -d '{"payload":"from-B"}'
    curl -s http://localhost:4003/api/records/read/a

Both leaders converge — this is active-active replication working.

=====================================================================
2. HARD CONFLICT: same primary key inserted on both -> replication HALTS
=====================================================================
Simulate a partition by disabling the subscriptions (nodes stop exchanging):
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_b DISABLE;"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_a DISABLE;"

Insert the SAME id (1001) with DIFFERENT data on each node:
    docker exec -it mlg-node-a psql -U app_user -d appdb -c \
      "INSERT INTO records(id, payload, origin_node) VALUES (1001, 'A-wins?', 'A');"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c \
      "INSERT INTO records(id, payload, origin_node) VALUES (1001, 'B-wins?', 'B');"

Heal the partition (re-enable replication):
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_b ENABLE;"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_a ENABLE;"

Now the apply worker hits a duplicate-key conflict and STOPS. Observe it:
    docker exec -it mlg-node-a psql -U app_user -d appdb -c \
      "SELECT subname, apply_error_count, sync_error_count FROM pg_stat_subscription_stats;"
      -- apply_error_count climbs above 0
    docker logs mlg-node-a | tail -n 30
      -- look for: 'duplicate key value violates unique constraint "records_pkey"'
    -- the failing LSN needed for step 4 also appears in these logs

The two nodes now DIVERGE (A has 'A-wins?', B has 'B-wins?') and replication is
stuck. This is the core multi-leader problem: conflicts are not auto-resolved.

=====================================================================
3. SOFT CONFLICT: same row UPDATED on both -> silent divergence (last-write-wins)
=====================================================================
First insert a shared row (let it replicate):
    curl -s -X POST http://localhost:4003/api/records/write/a \
      -H "Content-Type: application/json" -d '{"payload":"shared"}'
    # note its id (an odd number), call it N

Disable subs again (partition), then update the SAME row differently on each:
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_b DISABLE;"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_a DISABLE;"
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "UPDATE records SET payload='edited-on-A' WHERE id=N;"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c "UPDATE records SET payload='edited-on-B' WHERE id=N;"
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_b ENABLE;"
    docker exec -it mlg-node-b psql -U app_user -d appdb -c "ALTER SUBSCRIPTION sub_from_a ENABLE;"

Depending on apply order, the nodes may end up with DIFFERENT values for the same
row — divergence with no error. There is no built-in "correct" answer; that is the
conflict-resolution problem.

=====================================================================
4. RESOLVING A HALTED SUBSCRIPTION (from step 2)
=====================================================================
Native PostgreSQL does not auto-resolve. To unstick replication you manually fix
the conflicting row, e.g. delete the offending duplicate then re-enable:
    docker exec -it mlg-node-a psql -U app_user -d appdb -c "DELETE FROM records WHERE id=1001;"
    -- then let the incoming change apply, or skip the LSN:
    -- ALTER SUBSCRIPTION sub_from_b SKIP (lsn = '<failing_lsn_from_logs>');

=====================================================================
CAP SUMMARY (multi-leader)
=====================================================================
Availability (AP): both nodes accept writes, even when partitioned.
Consistency sacrificed: concurrent writes to the same data conflict ->
  - duplicate key  -> replication HALTS (hard conflict)
  - concurrent UPDATE -> silent divergence (soft conflict)
Native PostgreSQL detects but does NOT auto-resolve conflicts. Automatic resolution
(last-write-wins, CRDTs) requires extensions (BDR/pglogical, Symmetric DS, Bucardo)
or application-level rules — out of scope for this native POC.

Contrast: the single-leader POCs (sync/semi-sync/async) can NEVER conflict, because
only one node accepts writes.
