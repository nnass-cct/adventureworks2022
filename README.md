# AdventureWorksDW Docker Image

Pre-loaded SQL Server 2022 image with the **AdventureWorksDW2022** sample
database restored on first boot. Built from two Microsoft-published assets:

- `mcr.microsoft.com/mssql/server:2022-latest` — the official SQL Server image
- `AdventureWorksDW2022.bak` from `microsoft/sql-server-samples` releases

No third-party data, no community fork. The Dockerfile chains them at build time.

## Build

```bash
docker build -t adventureworksdw:latest .
```

The build downloads the `.bak` (~50 MB) from GitHub, so you need network access
at build time. Image size lands around 1.8 GB (most of which is the base image).

## Run

```bash
docker run -d -p 1433:1433 \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD='Your_password123' \
  --name awdw \
  adventureworksdw:latest
```

The password **must** satisfy SQL Server's complexity rules (≥8 chars, mix of
upper/lower/digit/symbol) or the engine refuses to start.

First boot takes ~30–60 seconds while the restore runs. Watch progress with:

```bash
docker logs -f awdw
```

You'll see `[init] AdventureWorksDW2022 restore complete.` when it's ready.

## Verify

```bash
docker exec -it awdw /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'Your_password123' -C \
  -d AdventureWorksDW2022 \
  -Q "SELECT TOP 5 SalesOrderNumber, SalesAmount FROM FactInternetSales;"
```

Or from your host (if you have `sqlcmd` locally):

```bash
sqlcmd -S localhost,1433 -U sa -P 'Your_password123' -C -d AdventureWorksDW2022 \
  -Q "SELECT COUNT(*) FROM FactInternetSales;"
```

## Connection details for candidates

| Field    | Value                  |
|----------|------------------------|
| Host     | `localhost`            |
| Port     | `1433`                 |
| User     | `sa`                   |
| Password | whatever you set above |
| Database | `AdventureWorksDW2022` |

Driver strings:
- Node.js (`mssql` / `tedious`): `Server=localhost,1433;Database=AdventureWorksDW2022;User Id=sa;Password=...;TrustServerCertificate=true;`
- Python (`pyodbc`): `DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost,1433;DATABASE=AdventureWorksDW2022;UID=sa;PWD=...;TrustServerCertificate=yes;`

## Architecture notes

The base image ships `linux/amd64` only. On Apple Silicon, Docker Desktop runs
it under Rosetta emulation — it works, but expect first boot to take closer to
60–90 seconds.

## Tearing it down

```bash
docker stop awdw && docker rm awdw
```

To wipe the restored database and start clean, also remove any mounted volume.
The default `docker run` above uses an anonymous volume that goes away with
`docker rm`.
