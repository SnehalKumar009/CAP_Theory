# How Multi-Leader Replication Works — In This POC

Two full read-write PostgreSQL leaders kept in sync with NATIVE bidirectional
LOGICAL replication (PG16). Fundamentally different mechanism from the other POCs.

Files:
- postgres/common/postgresql.conf          (wal_level = logical)
- postgres/common/pg_hba.conf              (allows replication connections)
- postgres/node-a/init/01-schema.sql       (odd-id sequence + publication)
- postgres/node-b/init/01-schema.sql       (even-id sequence + publication)
- postgres/setup/create-subscriptions.sh   (creates the two subscriptions)
- app/ (Spring Boot, two datasources -> write to either leader)
- docker-compose.yml

=====================================================================
PHYSICAL vs LOGICAL REPLICATION (why the change)
=====================================================================
Sync/semi-sync/async POCs = PHYSICAL (streaming) replication:
  - ships raw WAL bytes; standby is a read-only clone.
  - CANNOT be multi-master (standby cannot accept writes).

Multi-leader REQUIRES LOGICAL replication:
  - decodes WAL into logical row changes (INSERT/UPDATE/DELETE).
  - publish/subscribe per table; each node stays fully read-write.
  - enabled by wal_level = logical.

=====================================================================
HOW BIDIRECTIONAL REPLICATION IS WIRED
=====================================================================
On EACH node (init script):
    CREATE PUBLICATION pub_records FOR TABLE records;

Then the one-shot mlg-init container creates BOTH subscriptions:
    on node A:  CREATE SUBSCRIPTION sub_from_b ... PUBLICATION pub_records
                WITH (origin = none, copy_data = true);
    on node B:  CREATE SUBSCRIPTION sub_from_a ... PUBLICATION pub_records
                WITH (origin = none, copy_data = true);

origin = none  -> a change that arrived via replication is NOT re-published back.
                  Without it, A->B->A->... would loop forever.
copy_data      -> initial snapshot (both empty at start).

Subscriptions are created after both nodes are healthy because CREATE SUBSCRIPTION
must connect to the remote node immediately.

=====================================================================
AVOIDING TRIVIAL PK COLLISIONS
=====================================================================
If both leaders generated ids from 1,2,3..., every insert would collide on the PK.
So:
    node A: CREATE SEQUENCE records_id_seq START 1 INCREMENT 2;  (1,3,5,...)
    node B: CREATE SEQUENCE records_id_seq START 2 INCREMENT 2;  (2,4,6,...)
Replicated rows carry their id value, so no node re-generates ids for incoming rows.
This lets NORMAL active-active writes coexist. Conflicts must be induced deliberately
(same explicit id, or concurrent update of the same row) — see DEMO.md.

=====================================================================
WRITE FLOW
=====================================================================
1. App writes to leader A (or B) via its own datasource.
2. A commits locally and returns success immediately (each leader is independent).
3. A's publication decodes the change; B's subscription apply worker replays it.
4. Same in reverse for writes on B.
There is NO cross-node coordination on the write path -> that is why both stay
available under partition, and also why conflicts are possible.

=====================================================================
CONFLICTS (the defining problem)
=====================================================================
Hard conflict (duplicate key): apply worker ERRORS and the subscription STOPS until
  a human fixes the row or SKIPs the LSN. Nodes diverge meanwhile.
Soft conflict (concurrent UPDATE of same row): applies without error but nodes can
  end with different values -> silent divergence.

Native PostgreSQL DETECTS but does NOT auto-RESOLVE conflicts. Automatic strategies
(last-write-wins timestamps, CRDTs, per-column merges) require extensions:
  - EDB BDR / pglogical
  - SymmetricDS
  - Bucardo
...or application-level conflict handling. Out of scope for this native POC — here
we demonstrate the PROBLEM, not a productionized resolution.

=====================================================================
CAP POSITIONING
=====================================================================
AP: available under partition (both nodes keep accepting writes), at the cost of
consistency (divergence / halted replication on conflict). This is the opposite end
of the spectrum from the strict-synchronous single-leader CP demo.
