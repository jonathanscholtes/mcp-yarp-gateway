# Deployment Scripts

This directory contains modular deployment scripts for the MCP YARP Gateway.

## Structure

```
scripts/
├── common/
│   └── DeploymentFunctions.psm1    # Shared utility functions
├── Deploy-Infrastructure.ps1        # Azure resource deployment (Bicep)
├── Deploy-Containers.ps1            # Container image builds (ACR)
├── Deploy-Kubernetes.ps1            # Kubernetes/Helm deployments
├── Deploy-FoundryAgents.ps1         # Foundry agent deployment
└── deploy_foundry_agents.py         # Python agent deployment logic
```

## Usage

### Full End-to-End Deployment

Use the main orchestrator script from the repo root:

```powershell
.\deploy.ps1 `
    -Subscription "<SUBSCRIPTION_ID>" `
    -Location "eastus2" `
    -UserObjectId "<YOUR-AAD-OBJECT-ID>"
```

### Modular Deployment

Each phase can be run independently for development, debugging, or updates:

#### 1. Infrastructure Only

```powershell
.\scripts\Deploy-Infrastructure.ps1 `
    -Subscription "<SUBSCRIPTION_ID>" `
    -Location "eastus2" `
    -UserObjectId "<YOUR-AAD-OBJECT-ID>"
```

Optional parameters: `-AILocation`, `-ProjectName`, `-EnvironmentName`, `-ResourceToken`

#### 2. Rebuild Containers

```powershell
.\scripts\Deploy-Containers.ps1 `
    -ContainerRegistryName "<acr-name>" `
    -ResourceGroupName "<resource-group>"
```

Optional parameter: `-Images @("yarp-proxy", "data-seeder")` (defaults to both)

#### 3. Redeploy Kubernetes Components

```powershell
.\scripts\Deploy-Kubernetes.ps1 `
    -AksName "<aks-cluster-name>" `
    -ResourceGroupName "<resource-group>" `
    -ContainerRegistryName "<acr-name>" `
    -KeyVaultName "<keyvault-name>" `
    -ManagedIdentityName "<identity-name>" `
    -ManagedIdentityClientId "<client-id>"
```

#### 4. Deploy/Update Agents Only

```powershell
.\scripts\Deploy-FoundryAgents.ps1 `
    -AiProjectEndpoint "https://<foundry-project-endpoint>" `
    -McpProxyUrl "http://<yarp-proxy-ip>/mcp" `
    -McpApiKey "<proxy-api-key>" `
    -ModelDeployment "gpt-4o"
```

## Shared Functions

The `common/DeploymentFunctions.psm1` module provides reusable utilities:

- `Initialize-AzureContext` - Azure CLI login and subscription selection
- `Test-RequiredTools` - Validate prerequisites (kubectl, helm, etc.)
- `Get-RandomAlphaNumeric` - Generate unique resource tokens
- `New-SecurePassword` - Generate secure passwords
- `Invoke-HelmWithRetry` - Retry logic for Helm deployments
- `Get-ServiceExternalIP` - Wait for LoadBalancer IPs
- `New-FederatedIdentityCredential` - Create workload identity credentials

## Benefits of Modular Structure

1. **Faster iterations** - Rebuild only what changed
2. **Easier debugging** - Run individual phases
3. **Better testing** - Test components in isolation
4. **Reusable** - Use scripts in CI/CD pipelines
5. **Maintainable** - Clearer separation of concerns
