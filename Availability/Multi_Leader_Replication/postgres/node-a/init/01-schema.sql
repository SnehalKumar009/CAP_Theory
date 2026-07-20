-- NODE A schema (runs once on first init).
-- Odd-numbered ids so normal writes on the two leaders never collide on the PK.
CREATE ROLE repl_user WITH REPLICATION LOGIN PASSWORD 'repl_password';

CREATE SEQUENCE records_id_seq START 1 INCREMENT 2;

CREATE TABLE records (
    id          bigint      PRIMARY KEY DEFAULT nextval('records_id_seq'),
    payload     text        NOT NULL,
    origin_node text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER SEQUENCE records_id_seq OWNED BY records.id;

GRANT SELECT ON records TO repl_user;

-- Publish this node's local changes so the OTHER node can subscribe.
CREATE PUBLICATION pub_records FOR TABLE records;
