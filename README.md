# 🔀 MCP YARP Gateway

**A Secure Reverse Proxy for Model Context Protocol Traffic on Azure Kubernetes Service**

MCP YARP Gateway provides a production-oriented MCP access path on AKS where Azure AI Foundry agents communicate through a hardened YARP proxy layer to backend MCP tool servers — enforcing API key authentication and preserving HTTP streaming behavior.

> **Flow:** Azure AI Foundry Agent → YARP Proxy (API key auth) → MongoDB MCP Server (HTTP transport) → Azure Cosmos DB for MongoDB (DocumentDB)

---

## 🎯 Overview

This project secures and standardizes MCP HTTP traffic on AKS using a YARP reverse proxy as an authenticated gateway. Instead of exposing MCP tool servers directly, all agent traffic is routed through the proxy, which enforces API key authentication and forwards requests to internal-only MCP services.

**Key capabilities:**
- YARP reverse proxy enforcing API key authentication for all MCP traffic
- MongoDB MCP Server running in AKS with HTTP transport (internal ClusterIP only)
- Azure Cosmos DB for MongoDB (DocumentDB) as the backing data store
- Azure AI Foundry Agent integration via proxied MCP endpoint
- Synthetic data seeder for populating DocumentDB with test data
- Kubernetes-native deployment via Helm charts
- Azure-native infrastructure provisioned with Bicep

---

## 📐 Architecture

```mermaid
flowchart TD
    KV["🔐 Azure Key Vault<br/>Proxy API key · Connection strings"]
    COSMOS["☁️ MongoDB (DocumentDB)"]

    subgraph FOUNDRY["Azure AI Foundry"]
        AGENT["🤖 Foundry Agent<br/>Calls MCP endpoint via proxy"]
        TOOL["🔌 Foundry MCP Tool<br/>Custom Tool (Key-based)"]
    end

    subgraph AKS["☸️ AKS Cluster — Namespace: mcp-tools"]
        YARP["🔀 YARP Proxy<br/>API key auth · Port 8080"]
        MCP["🗄️ MongoDB MCP Server<br/>HTTP transport · Port 3000<br/>Internal ClusterIP only"]
        SEEDER["🌱 Data Seeder<br/>Synthetic data writer"]
    end

    AGENT --> TOOL
    TOOL -->|"MCP HTTP + API key header"| YARP
    YARP -->|"Unauthorized → 401"| TOOL
    YARP -->|"Forwards authenticated requests"| MCP
    MCP -->|"MDB_MCP_CONNECTION_STRING"| COSMOS
    SEEDER -->|"Writes synthetic data"| COSMOS
    KV -->|"Secrets injected at runtime"| YARP & MCP
```

### Core Components

| Component | Technology | Role |
|---|---|---|
| **YARP Proxy** | .NET 8, YARP | API key enforcement, HTTP request forwarding |
| **MongoDB MCP Server** | Node.js, MCP SDK | MCP tool server over HTTP transport |
| **Azure Cosmos DB for MongoDB** | Azure PaaS | DocumentDB backing store (DocumentDB API) |
| **Data Seeder** | Python | Continuous synthetic data writer |
| **Azure AI Foundry Agent** | Azure AI Foundry | AI agent consuming MCP tools via proxy |

---

## 📁 Project Structure

```
mcp-yarp-gateway/
├── deploy.ps1                          # Full end-to-end deployment orchestrator
├── README.md                           # This file
│
├── apps/
│   ├── yarp-proxy/                     # .NET 8 YARP reverse proxy
│   │   ├── Program.cs                  # Entry point, middleware, proxy config
│   │   ├── Proxy.csproj
│   │   ├── appsettings.json            # Proxy routes, cluster destinations, auth config
│   │   ├── appsettings.Development.json
│   │   └── Dockerfile
│   └── data-seeder/                    # Python synthetic data seeder
│       ├── src/
│       │   └── generator.py            # Data generation logic
│       └── Dockerfile
│
├── infra/                              # Infrastructure as Code (Bicep)
│   ├── main.bicep                      # Subscription-scoped main template
│   └── core/
│       ├── ai/                         # Azure AI Foundry (account, project, models)
│       ├── app/                        # App Service (optional)
│       ├── data/
│       │   ├── cosmosdb/               # Cosmos DB (NoSQL)
│       │   ├── mongodb/                # Cosmos DB for MongoDB
│       │   └── storage/                # Azure Storage accounts
│       ├── monitor/                    # Log Analytics, App Insights
│       ├── platform/                   # AKS, Container Registry
│       └── security/                   # Key Vault, Managed Identity, RBAC
│
├── k8s/helm/
│   ├── mcp-tools/                      # Namespace bootstrap (creates mcp-tools namespace)
│   ├── yarp-proxy/                     # YARP proxy Helm chart (port 8080)
│   ├── mongodb-mcp-server/             # MongoDB MCP server chart (internal, port 3000)
│   ├── data-seeder/                    # Synthetic data seeder chart
│   └── platform/                       # Shared platform resources
│
└── scripts/
    ├── Deploy-Infrastructure.ps1       # Phase 1: Bicep infra deployment
    ├── Deploy-Containers.ps1           # Phase 2: ACR image build & push
    ├── Deploy-Kubernetes.ps1           # Phase 3: Helm chart deployments
    ├── Deploy-FoundryAgents.ps1        # Phase 4: Azure AI Foundry agent setup
    └── common/
        └── DeploymentFunctions.psm1    # Shared PowerShell utilities
```

---

## 🚀 Deployment

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Azure CLI | Latest | `az login` authenticated |
| PowerShell | 7+ | Required for deployment scripts |
| Helm | 3+ | Required for Kubernetes deployments |
| Azure subscription | — | Sufficient quota for AKS, Cosmos DB, AI Foundry, ACR |

> No Docker required locally — container images are built in Azure Container Registry via `az acr build`.

### 1. Clone the Repository

```bash
git clone https://github.com/jonathanscholtes/mcp-yarp-gateway.git
cd mcp-yarp-gateway
```

### 2. Deploy Everything (Single Command)

```powershell
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"

.\deploy.ps1 `
    -Subscription "YOUR-SUBSCRIPTION-ID" `
    -Location "eastus2" `
    -UserObjectId "YOUR-AAD-OBJECT-ID"
```

Get your Object ID with:
```powershell
az ad signed-in-user show --query id -o tsv
```

**The deployment runs four phases automatically:**

| Phase | Script | What it does |
|---|---|---|
| 1 — Infrastructure | `Deploy-Infrastructure.ps1` | Creates all Azure resources via Bicep |
| 2 — Container Images | `Deploy-Containers.ps1` | Builds & pushes proxy and seeder images to ACR |
| 3 — Kubernetes | `Deploy-Kubernetes.ps1` | Deploys Helm charts to AKS |
| 4 — Foundry Agents | `Deploy-FoundryAgents.ps1` | Configures Azure AI Foundry agents |

**Resources created (~15–20 min):**

- Azure Kubernetes Service (AKS) cluster
- Azure Container Registry (proxy + seeder images)
- Azure Cosmos DB for MongoDB (DocumentDB backing store)
- Azure Key Vault + Managed Identity (secretless auth throughout)
- Azure AI Foundry (account, project, model deployment)
- Log Analytics Workspace + Application Insights

---

## 🔧 Configuration

### YARP Proxy Settings

| Variable | Default | Description |
|---|---|---|
| `Proxy:ApiKeyHeader` / `PROXY__APIKEYHEADER` | `x-api-key` | Header name checked for API key |
| `Proxy:ApiKey` / `PROXY__APIKEY` | — | Expected API key value (from Key Vault) |
| `Proxy:UpstreamTimeoutMinutes` / `PROXY__UPSTREAMTIMEOUTMINUTES` | `5` | Timeout for upstream MCP calls |
| `ReverseProxy:Clusters:mcp-cluster:Destinations:d1:Address` | — | Internal URL of MongoDB MCP server |

### MongoDB MCP Server Settings

| Variable | Default | Description |
|---|---|---|
| `MDB_MCP_CONNECTION_STRING` | — | DocumentDB connection string (from Key Vault) |
| `MDB_MCP_TRANSPORT` | `http` | Transport mode (`http` for proxy connectivity) |
| `MDB_MCP_HTTP_HOST` | `0.0.0.0` | Bind host |
| `MDB_MCP_HTTP_PORT` | `3000` | Service port |
| `MDB_MCP_READ_ONLY` | `true` | Restrict to read-only MCP tools (recommended) |
| `MDB_MCP_DISABLED_TOOLS` | — | Comma-separated list of tools to disable |
| `MDB_MCP_TELEMETRY` | — | Set to `disabled` if required by policy |

### Agent / Notebook Variables

| Variable | Description |
|---|---|
| `PROJECT_ENDPOINT` | Azure AI Foundry project endpoint URL |
| `MODEL_DEPLOYMENT_NAME` | Model deployment name |
| `MCP_SERVER_LABEL` | Label for MCP server registration |
| `MCP_SERVER_URL` | Set to YARP proxy endpoint (not MongoDB MCP directly) |

Authentication to AKS, Cosmos DB, and Key Vault uses **Managed Identity** — no connection strings or secrets committed in the repo.

---

## 🔐 Security Model

- Agent only communicates with the YARP proxy endpoint — never directly with MCP servers.
- YARP enforces API key header on every request and returns `401` for unauthorized calls.
- MongoDB MCP server is not internet-exposed; it is reachable only from within the cluster.
- Secrets are injected at runtime from Azure Key Vault — no credentials committed to source control.
- TLS termination is handled at the ingress/gateway layer.

---

## ✅ Validation Checklist

- [ ] YARP proxy pod is healthy and serving the `/mcp/*` route
- [ ] MongoDB MCP server pod is healthy with HTTP transport enabled
- [ ] `MDB_MCP_CONNECTION_STRING` resolves and connects to DocumentDB
- [ ] Unauthorized proxy calls return `401`
- [ ] Authorized proxy calls return successful MCP responses
- [ ] AI Foundry agent run succeeds using the proxy URL with expected tools available

---

## ♻️ Clean Up

Delete all resources by removing the resource group:

```powershell
az group delete --name "rg-mcp-yarp-eastus2" --yes --no-wait
```

---

## 📜 License

This project is licensed under the [MIT License](LICENSE.md).

---

## ⚠️ Disclaimer

**THIS CODE IS PROVIDED FOR EDUCATIONAL AND DEMONSTRATION PURPOSES ONLY.**

This sample code is not intended for production use and is provided "AS IS", without warranty of any kind. Azure services incur costs — monitor your usage and clean up resources when done. By using this code, you accept full responsibility for any consequences of its use.
