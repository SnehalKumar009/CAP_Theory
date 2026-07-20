-- Runs once, during primary initialization (empty data dir only).
-- Creates the role both standbys use to stream WAL.
CREATE ROLE repl_user WITH REPLICATION LOGIN PASSWORD 'repl_password';
