-- Applied during primary initialization. ALTER SYSTEM writes to
-- postgresql.auto.conf, which is only read when the REAL server starts (after
-- bootstrap). This enables synchronous replication without blocking the
-- bootstrap phase.
ALTER SYSTEM SET synchronous_standby_names = 'standby1';
