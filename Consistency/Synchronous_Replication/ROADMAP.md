# Synchronous Replication POC — Roadmap

## Goal
Demonstrate **synchronous (strong-consistency) replication** with PostgreSQL + Spring Boot,
and show the **CAP trade-off**: when a replica/network is down, the system chooses
**Consistency over Availability** (writes block/fail instead of diverging).

## Stack (decided)
- **DB engine:** PostgreSQL **native** synchronous streaming replication
  (`synchronous_commit=on`, `synchronous_standby_names`).
- **App:** Spring Boot REST API (`/write`, `/read`).
- **Orchestration:** Docker Compose.
- **HA (later phase):** Patroni + etcd + HAProxy for automatic failover & split-brain protection.

## Architecture
```
Client → Spring Boot API → PG Primary ──(sync WAL)──► PG Standby1
                                        └─(sync WAL)──► PG Standby2
```
- Writes go to primary; primary blocks commit until synchronous standby(s) ack.
- Reads can be served from standbys.

## Phased Plan

### Phase 0 — Design
- Define consistency guarantee, failure modes, success criteria.

### Phase 1 — Baseline single node
- Spring Boot + one PostgreSQL in Docker. CRUD working end-to-end.

### Phase 2 — Add synchronous replication
- Primary + 1 standby. `synchronous_commit=on`, `synchronous_standby_names='*'`.
- Verify: a write on primary is immediately visible on standby.

### Phase 3 — Demonstrate the CAP failure (core demo)
- Cut the standby's network (`docker network disconnect`) or kill the container.
- Show: **writes hang/fail** on primary (waiting for sync ack) → Consistency chosen.
- Reads still work.
- Restore network → replication catches up, writes resume. No data loss.

### Phase 4 — Production-grade HA (Patroni)
- Patroni + etcd (leader lock / DCS) + HAProxy.
- Automatic failover: kill primary → standby auto-promoted in seconds.
- Split-brain protection: etcd lock guarantees only one primary during a partition.
- Quorum sync (`ANY 1 (s1, s2)`), health/readiness probes, replication-lag metrics.

### Phase 5 — Demo harness
- Scripts: `start.sh`, `break-network.sh`, `restore-network.sh`.
- Small load generator to visualize behavior during failure.
- README explaining the CAP observation.

## Deliverables
- `docker-compose.yml` (app + primary + standbys)
- Spring Boot service with `/write` and `/read`
- Postgres config for primary & standby
- Demo/chaos scripts
- README with CAP talking points

## Key Demo Talking Points
- **Normal:** commit returns only after replica ack — data on all nodes before success.
- **Partition:** primary refuses to commit (CP system) → Consistency > Availability.
- **Recovery:** standby resyncs via WAL; no data loss.
- **Failover (Phase 4):** auto-promotion + split-brain prevention via etcd lock.

## Progress
- [ ] Phase 0 — Design
- [ ] Phase 1 — Baseline single node
- [ ] Phase 2 — Synchronous replication
- [ ] Phase 3 — CAP failure demo
- [ ] Phase 4 — Patroni HA
- [ ] Phase 5 — Demo harness
