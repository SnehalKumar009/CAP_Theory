# Multi-Leader (Master-Master) Replication CAP POC

Spring Boot + **two full read-write PostgreSQL leaders** with **native bidirectional
logical replication** (PG16). Demonstrates the multi-leader architecture and its
defining problem: **write conflicts**.

## CAP positioning — Availability (AP)
Both nodes accept writes, so during a partition **each side keeps writing** (highly
available). The price: the same data modified on both sides **diverges**, and hard
conflicts (duplicate keys) **halt replication**. Consistency is sacrificed. That is
why this lives under `Availability/`.

## Mechanism (different from the other POCs!)
The sync/semi-sync/async demos use **physical/streaming** replication (read-only
standbys). Multi-leader is impossible there. This POC uses **logical replication**:
- Each node has a `PUBLICATION pub_records`.
- Each node has a `SUBSCRIPTION` to the other, created with `origin = none`
  (prevents infinite loops). See [postgres/setup/create-subscriptions.sh](postgres/setup/create-subscriptions.sh).
- Odd ids on node A, even ids on node B, so *normal* writes never collide on the PK.

## Components
| Service      | Role                                        | Host port |
|--------------|---------------------------------------------|-----------|
| `mlg-node-a` | read-write leader A (odd ids)               | 5462      |
| `mlg-node-b` | read-write leader B (even ids)              | 5463      |
| `mlg-init`   | one-shot; creates the two subscriptions     | —         |
| `multi-app`  | Spring Boot API; writes to EITHER leader     | 4003      |

Distinct names/ports/network (`multi-net`) from the other POCs.

## Quick start
```bash
cd Availability/Multi_Leader_Replication
docker compose up --build -d
docker compose ps        # mlg-init should exit 0; the rest healthy
```

## Verify bidirectional replication is up
```bash
docker exec -it mlg-node-a psql -U app_user -d appdb -c "SELECT subname, subenabled FROM pg_subscription;"
docker exec -it mlg-node-b psql -U app_user -d appdb -c "SELECT subname, subenabled FROM pg_subscription;"
```

## Endpoints
App base URL: `http://localhost:4003`
| Method | Path                        | Purpose                          |
|--------|-----------------------------|----------------------------------|
| POST   | `/api/records/write/a`      | write to leader A `{"payload":""}`|
| POST   | `/api/records/write/b`      | write to leader B                |
| GET    | `/api/records/read/a`       | read from leader A               |
| GET    | `/api/records/read/b`       | read from leader B               |

See [DEMO.md](DEMO.md) for normal replication + the conflict scenarios, and
[NOTES.md](NOTES.md) for internals and conflict-resolution options.

## Reset / teardown
```bash
docker compose down -v
```
