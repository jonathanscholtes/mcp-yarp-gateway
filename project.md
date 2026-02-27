# MCP YARP Proxy + MongoDB MCP on AKS

## Goal
Deploy a production-oriented MCP access path on Azure Kubernetes Service (AKS) where:

Azure AI Foundry Agent → YARP Proxy (API key auth) → MongoDB MCP Server (HTTP transport) → Azure Cosmos DB for MongoDB (DocumentDB)

This project now standardizes on AKS for runtime and Azure Cosmos DB for MongoDB as the backing data store.

## Why this project exists
- Provide a secure HTTP ingress for MCP traffic using a hardened YARP proxy layer.
- Host the MongoDB MCP Server in AKS as an internal service instead of local/desktop MCP runtime.
- Use Azure-native managed infrastructure for scale, observability, and repeatable deployment.

## Architecture
### Core components
- **Azure AI Foundry Agent**
	- Calls MCP endpoint exposed by the proxy.
- **YARP Proxy (`apps/yarp-proxy`)**
	- Enforces API-key authentication.
	- Forwards MCP requests to MongoDB MCP server in-cluster.
	- Preserves request/response streaming behavior.
- **MongoDB MCP Server (`mongodb/mongodb-mcp-server`)**
	- Runs in AKS (containerized).
	- Uses HTTP transport (`--transport http`) for proxy-to-server connectivity.
	- Configured in read-only mode by default for safer operations.
- **Azure Cosmos DB for MongoDB (DocumentDB)**
	- Connection target for MongoDB MCP server via `MDB_MCP_CONNECTION_STRING`.
	- Provisioned from infra in `infra/core/data/mongodb`.

### Kubernetes layout (target)
- Namespace: `mcp-tools` (or environment-specific equivalent).
- Deployments:
	- `yarp-proxy`
	- `mongodb-mcp-server`
- Services:
	- `yarp-proxy` as ClusterIP/Ingress target.
	- `mongodb-mcp-server` as internal ClusterIP only.
- Secrets (via Key Vault + CSI/External Secrets or Kubernetes Secrets):
	- Proxy API key
	- `MDB_MCP_CONNECTION_STRING`

## Scope
### In scope
- AKS deployment path for YARP proxy and MongoDB MCP server.
- Proxy auth enforcement for all MCP HTTP traffic.
- MongoDB MCP server configured for DocumentDB connection via environment variables.
- End-to-end validation from notebook/agent through proxy to MongoDB MCP tools.

### Out of scope (current phase)
- Direct public exposure of MongoDB MCP server.
- Atlas API credential mode for MCP server (optional future mode).
- Multi-region active/active failover.

## Configuration baseline
### Agent / notebook variables
- `PROJECT_ENDPOINT`
- `MODEL_DEPLOYMENT_NAME`
- `MCP_SERVER_LABEL`
- `MCP_SERVER_URL` (set to YARP proxy endpoint)

### YARP proxy settings
- `Proxy:ApiKeyHeader` / `PROXY__APIKEYHEADER`
- `Proxy:ApiKey` / `PROXY__APIKEY`
- `Proxy:UpstreamTimeoutMinutes` / `PROXY__UPSTREAMTIMEOUTMINUTES`
- `ReverseProxy:Clusters:mcp-cluster:Destinations:d1:Address`

### MongoDB MCP server settings
- `MDB_MCP_CONNECTION_STRING` (DocumentDB connection string)
- `MDB_MCP_TRANSPORT=http`
- `MDB_MCP_HTTP_HOST=0.0.0.0`
- `MDB_MCP_HTTP_PORT=3000` (or service port)
- `MDB_MCP_READ_ONLY=true` (recommended default)
- Optional hardening:
	- `MDB_MCP_DISABLED_TOOLS` for write operations/categories
	- `MDB_MCP_TELEMETRY=disabled` if required by policy

## Security model
- Agent only talks to YARP endpoint.
- YARP enforces API key header and blocks unauthorized requests (`401`).
- MongoDB MCP server is not internet-exposed; only reachable from proxy/internal network.
- Secrets are injected at runtime (no credentials committed in repo).
- TLS termination handled at ingress/gateway; internal TLS requirements depend on cluster policy.

## Deployment approach
1. Provision AKS + network + DocumentDB through `infra/` Bicep.
2. Build/push proxy container image.
3. Deploy YARP and MongoDB MCP server into AKS using Helm/manifests under `k8s/helm`.
4. Configure YARP upstream destination to in-cluster MongoDB MCP service URL.
5. Configure notebook MCP endpoint to the proxy URL.
6. Run end-to-end MCP tool call test.

## Validation checklist
- [ ] YARP pod is healthy and serving `/mcp/*` route.
- [ ] MongoDB MCP server pod is healthy with HTTP transport enabled.
- [ ] `MDB_MCP_CONNECTION_STRING` resolves and connects to DocumentDB.
- [ ] Unauthorized proxy calls return `401`.
- [ ] Authorized proxy calls return successful MCP responses.
- [ ] Notebook run succeeds using proxy URL and expected tools.

## Key risks and mitigations
- **HTTP MCP exposure risk**  
	Mitigation: keep MongoDB MCP service internal-only and enforce auth at proxy/ingress.

- **DocumentDB compatibility/feature gaps**  
	Mitigation: begin with read-focused tools and validate required operations early.

- **Secret leakage in deployment pipelines**  
	Mitigation: use Key Vault-backed secret injection and avoid CLI args for sensitive values.

## Repository alignment
- Proxy implementation: `apps/yarp-proxy`
- Synthetic data seeder: `apps/data-seeder`
- Infrastructure (AKS, data, security): `infra/`
- Kubernetes deployment assets: `k8s/helm/`
  - `k8s/helm/mcp-tools` — namespace bootstrap (creates `tools` namespace)
  - `k8s/helm/yarp-proxy` — YARP reverse proxy with API-key authentication (port 8080)
  - `k8s/helm/mongodb-mcp-server` — MongoDB MCP server (HTTP transport, internal ClusterIP, port 3000)
  - `k8s/helm/data-seeder` — synthetic data seeder (continuous writer)
- Validation notebook: `Notebook/01_azure_ai_agent-mcp.ipynb`

## Immediate next milestones
- **M1**: AKS deployment of YARP + MongoDB MCP server (internal connectivity verified).
- **M2**: DocumentDB connection and read-only MCP tool validation.
- **M3**: Notebook/Foundry end-to-end validation through YARP.
- **M4**: Production hardening (policy, monitoring, rate limiting, rollout strategy).