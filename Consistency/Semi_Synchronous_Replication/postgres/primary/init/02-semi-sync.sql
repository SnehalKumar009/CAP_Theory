-- Applied during primary initialization. ALTER SYSTEM writes to
-- postgresql.auto.conf, which is only read when the REAL server starts (after
-- bootstrap) — so it does not block the bootstrap phase.
--
-- SEMI-SYNCHRONOUS quorum: a commit must be confirmed by ANY 1 of the two named
-- standbys. Whichever standbys are NOT needed to satisfy the quorum stream
-- asynchronously. This is the defining setting of this POC.
ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (standby1, standby2)';
