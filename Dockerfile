# syntax=docker/dockerfile:1.6
#
# AdventureWorksDW pre-loaded SQL Server image.
#
# Chains two Microsoft-published assets:
#   1. The official SQL Server 2022 image (mcr.microsoft.com/mssql/server)
#   2. The official AdventureWorksDW2022.bak from microsoft/sql-server-samples
#
# Build:  docker build -t adventureworksdw:latest .
# Run:    docker run -d -p 1433:1433 \
#           -e ACCEPT_EULA=Y \
#           -e MSSQL_SA_PASSWORD='Your_password123' \
#           --name awdw adventureworksdw:latest
# Connect: sqlcmd -S localhost,1433 -U sa -P 'Your_password123' -C -d AdventureWorksDW2022

FROM mcr.microsoft.com/mssql/server:2022-latest

# We need root to install curl and place files; SQL Server's own entrypoint
# will drop back to the unprivileged `mssql` user (uid 10001) at runtime.
USER root

# curl is needed to fetch the .bak at build time. The base image is Ubuntu-based.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pull the official Microsoft .bak as a build step so the image is self-contained.
# Pinning to a specific release tag (`adventureworks`) keeps this reproducible —
# if Microsoft ever re-publishes under a new tag, bump it here.
ARG BAK_URL=https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorksDW2022.bak
RUN mkdir -p /var/opt/mssql/backup \
    && curl -fsSL -o /var/opt/mssql/backup/AdventureWorksDW2022.bak "${BAK_URL}"

# Restore script + entrypoint wrapper. Kept in /usr/local/bin so they're on PATH
# and owned by root (read-only for the mssql user, which is what we want).
# --chmod=0755 guarantees executable bit regardless of host filesystem state
# (Macs/Windows often don't preserve +x on shell scripts).
COPY --chmod=0755 restore-db.sh /usr/local/bin/restore-db.sh
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chown -R mssql:root /var/opt/mssql/backup

# SQL Server's base image runs as `mssql` (uid 10001). Switch back before CMD
# so the engine starts unprivileged, matching the upstream image's behavior.
USER mssql

# Our entrypoint launches sqlservr in the background, waits for it to accept
# connections, runs the one-shot restore, then `exec`s sqlservr in the
# foreground so container lifecycle still tracks the engine process.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
