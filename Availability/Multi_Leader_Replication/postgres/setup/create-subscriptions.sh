#!/bin/sh
# One-shot setup: create the two subscriptions that make replication BIDIRECTIONAL.
# Each node subscribes to the other's publication. WITH (origin = none) prevents
# infinite replication loops (a change received via replication is not re-shipped).
set -e

export PGPASSWORD=app_password

echo "[setup] Waiting for both leaders to be ready..."
until pg_isready -h mlg-node-a -p 5432 -U app_user -d appdb >/dev/null 2>&1; do sleep 2; done
until pg_isready -h mlg-node-b -p 5432 -U app_user -d appdb >/dev/null 2>&1; do sleep 2; done

create_sub() {
  local_node="$1"; sub_name="$2"; remote_node="$3"
  exists=$(psql -h "$local_node" -U app_user -d appdb -tAc \
    "SELECT 1 FROM pg_subscription WHERE subname='$sub_name'")
  if [ "$exists" = "1" ]; then
    echo "[setup] $sub_name already exists on $local_node — skipping"
  else
    echo "[setup] Creating $sub_name on $local_node (from $remote_node)"
    psql -h "$local_node" -U app_user -d appdb -v ON_ERROR_STOP=1 -c \
      "CREATE SUBSCRIPTION $sub_name
         CONNECTION 'host=$remote_node port=5432 user=repl_user password=repl_password dbname=appdb'
         PUBLICATION pub_records
         WITH (origin = none, copy_data = true);"
  fi
}

# Node A pulls from Node B; Node B pulls from Node A -> bidirectional.
create_sub mlg-node-a sub_from_b mlg-node-b
create_sub mlg-node-b sub_from_a mlg-node-a

echo "[setup] Bidirectional logical replication configured."
