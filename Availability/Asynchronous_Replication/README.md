# Asynchronous Replication CAP POC

Spring Boot + **PostgreSQL native ASYNCHRONOUS streaming replication**, dockerized.
This is the **AP-leaning counterpart** to the synchronous POC. It shows the opposite
CAP trade-off: **when the standby is unreachable, writes keep SUCCEEDING on the primary
(Availability preserved), but the standby falls behind and un-replicated writes can be
lost on failover (Consistency relaxed).**

Compare with `../../Consistency/Synchronous_Replication` (the CP demo where writes block instead).

## The only real difference from the sync POC
`synchronous_standby_names` is **left empty**. With no named synchronous standby, a
commit returns as soon as the primary flushes its own WAL and never waits for the
standby. Everything else (WAL streaming, pg_basebackup clone, hot standby) is identical.

## Components

| Service       | Role                                   | Host port |
|---------------|----------------------------------------|-----------|
| `apg-primary` | PostgreSQL master (accepts writes)     | 5442      |
| `apg-standby` | Asynchronous standby (streams in bg)   | 5443      |
| `async-app`   | Spring Boot REST API (listens on 4000) | 4001      |

Distinct names/ports/network from the sync POC, so both can run at once.

## Quick start
```bash
cd Availability/Asynchronous_Replication
docker compose up --build -d
docker compose ps
```

## Verify replication is ASYNC
```bash
docker exec -it apg-primary psql -U app_user -d appdb -c "SHOW synchronous_standby_names;"   # empty
docker exec -it apg-primary psql -U app_user -d appdb -c \
  "SELECT application_name, state, sync_state FROM pg_stat_replication;"                       # sync_state = async
```

## Endpoints
| Method | Path                     | Purpose                |
|--------|--------------------------|------------------------|
| POST   | `/api/records/write`     | `{ "payload": "..." }` |
| GET    | `/api/records/read`      | list all records       |
| GET    | `/api/records/read/{id}` | fetch one              |

App base URL: `http://localhost:4001`

See [DEMO.md](DEMO.md) for the full walkthrough and [NOTES.md](NOTES.md) for internals.

## Reset / teardown
```bash
docker compose down          # keep data volumes
docker compose down -v       # wipe volumes for a clean run
```
