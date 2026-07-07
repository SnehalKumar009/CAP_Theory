# Demonstrating Synchronous Replication (Primary → Standby → Commit)

## Sync-commit sequence in PostgreSQL
1. Client sends COMMIT.
2. Primary writes + flushes the record to its OWN WAL (durable on primary).
3. Primary streams that WAL to the standby and WAITS for the standby to flush it.
4. Standby ACKs -> only THEN the primary returns success to the client.

So the commit is durable on BOTH nodes before the client sees success.

---

## 1. Insert data (through the Spring app)
    curl -s -X POST http://localhost:8080/api/records/write \
      -H "Content-Type: application/json" \
      -d '{"payload":"hello-sync"}'

## 2. Prove it landed on BOTH nodes
    docker exec -it pg-primary psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"
    docker exec -it pg-standby psql -U app_user -d appdb -c "SELECT * FROM records ORDER BY id;"

Same row appears on 5432 (primary) and the read-only standby.

## 3. Prove the standby is synchronous and caught up
    docker exec -it pg-primary psql -U app_user -d appdb -c \
    "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

Expect: sync_state = sync, and flush_lsn advanced to the commit — the standby
persisted the WAL BEFORE the client got its response.

## 4. The smoking gun — show the commit WAITING for the standby
Stop the standby, then insert:

    # Terminal A: remove the standby's ability to ACK
    docker stop pg-standby

    # Terminal A: this write now HANGS (no standby to confirm the WAL)
    curl -s -X POST http://localhost:8080/api/records/write \
      -H "Content-Type: application/json" -d '{"payload":"during-outage"}'

While it hangs, in Terminal B show WHY:

    docker exec -it pg-primary psql -U app_user -d appdb -c \
    "SELECT pid, state, wait_event_type, wait_event, query
     FROM pg_stat_activity WHERE wait_event = 'SyncRep';"

You will see the backend blocked on wait_event = SyncRep — it has written its own
WAL but is waiting for the synchronous standby.

Reads still work meanwhile:
    curl -s http://localhost:8080/api/records/read

Heal it — the blocked commit completes automatically, no data loss:
    docker start pg-standby     # the hanging curl in Terminal A returns success

---

This proves: local WAL write -> wait for standby sync -> then commit/ack (CP behavior).
When the standby is unreachable, writes block (Consistency chosen over Availability),
while reads remain available.
