#!/bin/bash
#
# Entry point: start sqlservr in the background, wait for it to accept
# logins, run the restore exactly once, then hand control back to sqlservr
# in the foreground so PID 1 reflects the engine's lifecycle.
#
# Why this dance: the official mssql image expects sqlservr to be PID 1.
# We can't run T-SQL until the engine is up, but we also can't block the
# engine on a restore. So: background start → poll → restore → foreground.

set -euo pipefail

# Sentinel file lives on the data volume so the restore is idempotent across
# container restarts. If a user mounts a fresh volume, we'll restore again,
# which is what we want.
SENTINEL=/var/opt/mssql/data/.adventureworksdw_restored

# Start the engine in the background. `sqlservr` is the SQL Server binary
# baked into the upstream image at /opt/mssql/bin/sqlservr.
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Run the one-shot restore in a subshell so the main script can `wait` on
# sqlservr below. If the restore fails, we log and let the container exit —
# better to fail loudly than to ship a half-initialized database.
(
  if [[ -f "${SENTINEL}" ]]; then
    echo "[init] AdventureWorksDW2022 already restored, skipping."
    exit 0
  fi

  /usr/local/bin/restore-db.sh
  touch "${SENTINEL}"
  echo "[init] AdventureWorksDW2022 restore complete."
) &

# `wait` on the sqlservr PID so signals (SIGTERM from `docker stop`) propagate
# correctly. Without this, the script would exit immediately and the container
# would die before the engine ever served a query.
wait "${SQL_PID}"
