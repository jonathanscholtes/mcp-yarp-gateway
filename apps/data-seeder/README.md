# Data Seeder

Simple Python app that writes synthetic data into MongoDB / Azure Cosmos DB for MongoDB (DocumentDB).

It is intentionally lightweight and follows the same basic packaging/container pattern as your reference app, but it is focused only on seeding sample data.

## What it generates
- `contracts` documents
- `risk_memos` documents linked to contracts
- `market_data` snapshots

Default database and collections are configurable via environment variables.

## Environment variables
- `MONGODB_CONNECTION_STRING` (required)
- `MONGODB_DATABASE` (default: `contracts_db`)
- `MONGODB_CONTRACTS_COLLECTION` (default: `contracts`)
- `MONGODB_RISK_MEMOS_COLLECTION` (default: `risk_memos`)
- `MONGODB_MARKET_COLLECTION` (default: `market_data`)
- `GENERATOR_MODE` (`once` or `continuous`, default: `continuous`)
- `GENERATOR_BATCH_SIZE` (default: `20`)
- `GENERATOR_INTERVAL_SECONDS` (default: `30`)
- `GENERATOR_SEED` (default: `42`)

## Local run
From this folder:

```powershell
pip install .
$env:MONGODB_CONNECTION_STRING="mongodb+srv://<user>:<password>@<cluster>.mongocluster.cosmos.azure.com/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false"
$env:MONGODB_DATABASE="contracts_db"
$env:GENERATOR_MODE="once"
python -m src.generator
```

## Container run
From repo root:

```powershell
docker build -f apps/data-seeder/Dockerfile -t data-seeder:local .
docker run --rm -e MONGODB_CONNECTION_STRING="<connection-string>" -e GENERATOR_MODE="once" data-seeder:local
```

## AKS usage notes
- Run as a Deployment with `GENERATOR_MODE=continuous`.
- Store `MONGODB_CONNECTION_STRING` in Key Vault/secret and inject as env var.
- Tune batch size/interval to control write rate.

### Helm (standalone chart)

```powershell
helm upgrade --install data-seeder k8s/helm/data-seeder `
  --set registry=<your-acr>.azurecr.io `
  --set managedIdentityClientId=<managed-identity-client-id> `
  --set keyVault.name=<keyvault-name> `
  --set keyVault.tenantId=<tenant-id> `
  --set image=data-seeder `
  --set tag=0.1.0 `
  --set mode=continuous `
  --set batchSize=20 `
  --set intervalSeconds=30
```
