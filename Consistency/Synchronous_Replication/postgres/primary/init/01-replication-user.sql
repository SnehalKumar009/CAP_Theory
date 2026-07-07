-- Runs once, during primary initialization (empty data dir only).
-- Creates the role the standby uses to stream WAL.
CREATE ROLE repl_user WITH REPLICATION LOGIN PASSWORD 'repl_password';
