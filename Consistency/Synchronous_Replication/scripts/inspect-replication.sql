-- Run against primary (5432) or standby (5433) to observe replication state.
--   docker exec -it pg-primary psql -U postgres -d appdb -f -
--
-- On PRIMARY: shows connected synchronous standbys.
SELECT application_name, state, sync_state, sync_priority
FROM pg_stat_replication;

-- On PRIMARY: current synchronous_standby_names setting.
SHOW synchronous_standby_names;

-- On STANDBY: confirms it is in recovery (read-only replica).
SELECT pg_is_in_recovery();
