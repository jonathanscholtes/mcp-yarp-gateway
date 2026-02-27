# Deploy platform components to AKS using Helm
# Deploys: monitoring (platform), MongoDB MCP server, YARP proxy, data seeder

param (
    [Parameter(Mandatory=$true)]
    [string]$AksName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory=$true)]
    [string]$ManagedIdentityName,

    [Parameter(Mandatory=$true)]
    [string]$ManagedIdentityClientId
)

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Write-Host "`n=== Deploying Platform Components to AKS ===" -ForegroundColor Cyan

# Authenticate to AKS
Write-Host "Getting AKS credentials for: $AksName" -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroupName --name $AksName --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

# Fix Docker credential helper issue
$dockerConfigPath = "$env:USERPROFILE\.docker\config.json"
if (Test-Path $dockerConfigPath) { Remove-Item $dockerConfigPath -Force }

# Resolve shared values
$tenantId      = az account show --query tenantId -o tsv
$oidcIssuer    = az aks show --name $AksName --resource-group $ResourceGroupName --query "oidcIssuerProfile.issuerUrl" -o tsv
$acrLoginServer = "$ContainerRegistryName.azurecr.io"

#  STEP 1: Platform (Prometheus, Grafana, OTel, KEDA) 
Write-Host "`n1. Deploying Platform (monitoring)..." -ForegroundColor Magenta
helm upgrade --install platform .\k8s\helm\platform `
    --namespace platform --create-namespace `
    --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw "Platform deployment failed" }
Write-Host "[OK] Platform deployed" -ForegroundColor Green

#  STEP 2: Workload Identity (federated credentials for all service accounts)
Write-Host "`n2. Configuring Azure Workload Identity..." -ForegroundColor Magenta

foreach ($sa in @("yarp-proxy-sa", "mongodb-mcp-server-sa", "data-seeder-sa")) {
    New-FederatedIdentityCredential `
        -ServiceAccountName $sa `
        -Namespace "tools" `
        -ManagedIdentityName $ManagedIdentityName `
        -ResourceGroupName $ResourceGroupName `
        -OidcIssuer $oidcIssuer
}
Write-Host "[OK] Workload identity configured" -ForegroundColor Green

#  STEP 3: Namespace bootstrap 
Write-Host "`n3. Bootstrapping tools namespace..." -ForegroundColor Magenta
helm upgrade --install mcp-tools .\k8s\helm\mcp-tools `
    --namespace tools --create-namespace `
    --wait --timeout 2m
if ($LASTEXITCODE -ne 0) { throw "Namespace bootstrap failed" }
Write-Host "[OK] Namespace tools ready" -ForegroundColor Green

#  STEP 4: MongoDB MCP Server 
Write-Host "`n4. Deploying MongoDB MCP Server..." -ForegroundColor Magenta
helm upgrade --install mongodb-mcp-server .\k8s\helm\mongodb-mcp-server `
    --namespace tools `
    --set managedIdentityClientId=$ManagedIdentityClientId `
    --set keyVault.name=$KeyVaultName `
    --set keyVault.tenantId=$tenantId `
    --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw "MongoDB MCP server deployment failed" }
Write-Host "[OK] MongoDB MCP server deployed" -ForegroundColor Green

#  STEP 5: YARP Proxy 
Write-Host "`n5. Deploying YARP Proxy..." -ForegroundColor Magenta
helm upgrade --install yarp-proxy .\k8s\helm\yarp-proxy `
    --namespace tools `
    --set registry=$acrLoginServer `
    --set tag=latest `
    --set managedIdentityClientId=$ManagedIdentityClientId `
    --set keyVault.name=$KeyVaultName `
    --set keyVault.tenantId=$tenantId `
    --set proxy.apiKeyHeader=api-key `
    --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw "YARP proxy deployment failed" }
Write-Host "[OK] YARP proxy deployed" -ForegroundColor Green

#  STEP 6: Data Seeder 
Write-Host "`n6. Deploying Data Seeder..." -ForegroundColor Magenta
helm upgrade --install data-seeder .\k8s\helm\data-seeder `
    --namespace tools `
    --set registry=$acrLoginServer `
    --set image=data-seeder `
    --set tag=latest `
    --set managedIdentityClientId=$ManagedIdentityClientId `
    --set keyVault.name=$KeyVaultName `
    --set keyVault.tenantId=$tenantId `
    --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw "Data seeder deployment failed" }
Write-Host "[OK] Data seeder deployed" -ForegroundColor Green

#  Collect endpoints 
Write-Host "`nRetrieving service endpoints..." -ForegroundColor Yellow
$grafanaIP   = Get-ServiceExternalIP -ServiceName "grafana"    -Namespace "platform" -MaxWaitSeconds 300
$yarpProxyIP = Get-ServiceExternalIP -ServiceName "yarp-proxy" -Namespace "tools"    -MaxWaitSeconds 300

Write-Host "`n[OK] All platform components deployed" -ForegroundColor Green

return [PSCustomObject]@{
    grafanaIP   = $grafanaIP
    yarpProxyIP = $yarpProxyIP
}
