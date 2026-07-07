# Synchronous Replication CAP POC (Phases 1–3)

Spring Boot + **PostgreSQL native synchronous streaming replication**, fully dockerized.
Demonstrates strong consistency and the CAP trade-off: **when the standby is unreachable,
writes block (Consistency chosen over Availability)** while reads keep working.

See [ROADMAP.md](ROADMAP.md) for the full phase plan.

## Components

| Service      | Role                                  | Host port |
|--------------|---------------------------------------|-----------|
| `pg-primary` | PostgreSQL master (accepts writes)    | 5432      |
| `pg-standby` | Synchronous standby (ACKs every commit)| 5433     |
| `app`        | Spring Boot REST API                  | 8080      |

Synchronous replication is enabled with `synchronous_commit=on` and **1 required
synchronous replica**, so a commit on the primary only returns after the standby
has persisted the WAL.

## Prerequisites
- Docker Desktop (with Compose v2)
- PowerShell (Windows) for the helper scripts

## Quick start

```powershell
cd Consistency/Synchronous_Replication
docker compose up --build -d
```

Wait until all three containers are healthy:

```powershell
docker compose ps
```

## Phase 1 — Baseline (app + DB work)

```powershell
./scripts/demo.ps1 -Payload "hello"
```
Expected: write returns an `id`, read lists the record.

## Phase 2 — Verify synchronous replication

Confirm the standby is registered as **sync**:

```powershell
docker exec -it pg-primary psql -U postgres -d appdb -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```
Expected: one row with `sync_state = sync`.

Confirm the write is already on the standby (read-only replica, port 5433):

```powershell
docker exec -it pg-standby psql -U postgres -d appdb -c "SELECT * FROM records;"
```

## Phase 3 — The CAP failure demo

1. **Partition the standby** (it can no longer ACK WAL):
   ```powershell
   ./scripts/break-network.ps1
   ```

2. **Attempt a write — it BLOCKS** (Consistency > Availability):
   ```powershell
   ./scripts/demo.ps1 -Payload "during-partition"
   ```
   The write hangs and the script reports it did not complete. The commit is
   waiting for a synchronous standby that no longer exists.

3. **Reads still work** (partial availability):
   ```powershell
   Invoke-RestMethod http://localhost:8080/api/records/read
   ```

4. **Heal the partition** — the standby catches up via WAL and blocked writes
   complete with **no data loss**:
   ```powershell
   ./scripts/restore-network.ps1
   ```

## Endpoints

| Method | Path                     | Purpose                     |
|--------|--------------------------|-----------------------------|
| POST   | `/api/records/write`     | `{ "payload": "..." }`      |
| GET    | `/api/records/read`      | list all records            |
| GET    | `/api/records/read/{id}` | fetch one                   |
| GET    | `/actuator/health`       | health check                |

## Reset / teardown

```powershell
docker compose down          # keep data volumes
docker compose down -v       # wipe volumes for a clean run
```

## Notes / design rationale
- **Why writes hang instead of erroring:** native PostgreSQL synchronous commit has
  no timeout; the commit waits for a standby ACK. That *is* the CP behavior. Phase 4
  (Patroni) adds automatic failover + split-brain protection so the cluster can promote
  a new node instead of blocking forever.
- **Single sync replica** keeps the demo deterministic. Production would use quorum
  commit, e.g. `synchronous_standby_names = 'ANY 1 (s1, s2)'`.
- Credentials here are demo-only; use secrets management in real deployments.
