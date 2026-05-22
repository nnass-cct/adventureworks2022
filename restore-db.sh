#!/bin/bash
#
# Polls SQL Server until it accepts logins, then restores AdventureWorksDW2022
# from the .bak baked into the image.
#
# Run automatically by entrypoint.sh on first boot. Safe to re-run manually
# (RESTORE ... WITH REPLACE will overwrite an existing copy of the DB).

set -euo pipefail

: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set}"

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
# The base image historically shipped mssql-tools at /opt/mssql-tools/bin.
# Newer images ship mssql-tools18 (which requires -C to trust the self-signed
# cert). Fall back to the older path if needed.
if [[ ! -x "${SQLCMD}" ]]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
fi

# Poll for readiness. SQL Server can take 10-30s on cold start, longer under
# emulation on Apple Silicon. 60 attempts × 2s = 2 min ceiling.
echo "[restore] Waiting for SQL Server to accept connections..."
for i in {1..60}; do
  if "${SQLCMD}" -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C -Q "SELECT 1" &>/dev/null; then
    echo "[restore] SQL Server is up."
    break
  fi
  if [[ $i -eq 60 ]]; then
    echo "[restore] ERROR: SQL Server never became ready." >&2
    exit 1
  fi
  sleep 2
done

# Restore. The MOVE clauses are required because the logical file names in the
# .bak (AdventureWorksDW2022 / AdventureWorksDW2022_log) don't map to the
# physical paths inside our container — we have to tell SQL Server where to
# put the .mdf and .ldf. /var/opt/mssql/data is the default data directory.
echo "[restore] Restoring AdventureWorksDW2022..."
"${SQLCMD}" -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C -b -Q "
RESTORE DATABASE AdventureWorksDW2022
FROM DISK = '/var/opt/mssql/backup/AdventureWorksDW2022.bak'
WITH
  MOVE 'AdventureWorksDW2022'     TO '/var/opt/mssql/data/AdventureWorksDW2022.mdf',
  MOVE 'AdventureWorksDW2022_log' TO '/var/opt/mssql/data/AdventureWorksDW2022_log.ldf',
  REPLACE,
  STATS = 10;
"

echo "[restore] Done."
