-- Runs once, during primary initialization (empty data dir only).
-- Creates the role the standby uses to stream WAL.
-- NOTE: there is intentionally NO synchronous_standby_names setup here — that is
-- what keeps replication ASYNCHRONOUS.
CREATE ROLE repl_user WITH REPLICATION LOGIN PASSWORD 'repl_password';
