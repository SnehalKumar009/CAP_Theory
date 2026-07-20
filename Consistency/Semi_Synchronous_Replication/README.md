# Semi-Synchronous Replication CAP POC

Spring Boot + **PostgreSQL native SEMI-SYNCHRONOUS replication** (quorum), dockerized.
This is the **middle ground** between the strict-sync (CP, fragile) and async (AP) demos.

**The defining setting:** `synchronous_standby_names = 'ANY 1 (standby1, standby2)'`
A commit waits for **at least one** of the two standbys to confirm the WAL. The other
standby streams asynchronously.

- Kill **one** standby → the other confirms → **writes continue** (unlike strict sync,
  which blocks the moment its single standby drops).
- Kill **both** standbys → nobody can confirm → **writes block** (still CP: an acked
  write is always on >= 2 nodes).

## CAP positioning
Still **Consistency-favoring (CP)** for durability: every acknowledged write lives on
the primary + >= 1 standby. It just tolerates one standby failure without halting.
(Read staleness on replicas still applies — see the discussion in the project notes.)

## Components
| Service        | Role                                   | Host port |
|----------------|----------------------------------------|-----------|
| `spg-primary`  | master (accepts writes)                | 5452      |
| `spg-standby1` | sync candidate `standby1`              | 5453      |
| `spg-standby2` | sync candidate `standby2`              | 5454      |
| `semi-app`     | Spring Boot REST API (listens on 4000) | 4002      |

Distinct names/ports/network (`semi-net`) from the other POCs, so all can run at once.

## Quick start
```bash
cd Consistency/Semi_Synchronous_Replication
docker compose up --build -d
docker compose ps
```

## Verify the quorum is active
```bash
docker exec -it spg-primary psql -U app_user -d appdb -c "SHOW synchronous_standby_names;"
# -> ANY 1 (standby1, standby2)

docker exec -it spg-primary psql -U app_user -d appdb -c \
  "SELECT application_name, sync_state FROM pg_stat_replication ORDER BY application_name;"
# -> standby1 / standby2 with sync_state = quorum (or one sync + one potential)
```

## Endpoints
App base URL: `http://localhost:4002`
| Method | Path                     | Purpose                |
|--------|--------------------------|------------------------|
| POST   | `/api/records/write`     | `{ "payload": "..." }` |
| GET    | `/api/records/read`      | list all records       |

See [DEMO.md](DEMO.md) for the full walkthrough and [NOTES.md](NOTES.md) for internals.

## Reset / teardown
```bash
docker compose down -v
```
