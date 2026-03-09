# MCP YARP Proxy - Main Deployment Orchestrator

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [string]$UserObjectId,

    [Parameter(Mandatory=$false)]
    [string]$AILocation
)

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

Import-Module "$PSScriptRoot\scripts\common\DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  YARP Proxy MongoDB MCP - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# Validate prerequisites
Test-RequiredTools -Tools @("kubectl", "helm", "kubelogin")

# Initialize Azure context
Initialize-AzureContext -Subscription $Subscription

#  PHASE 1: Infrastructure 
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta
$infraOutputs = & "$PSScriptRoot\scripts\Deploy-Infrastructure.ps1" `
    -Subscription $Subscription `
    -Location $Location `
    -AILocation $AILocation `
    -UserObjectId $UserObjectId

#  PHASE 2: Container Images 
Write-Host "`n=== PHASE 2: Container Image Builds ===" -ForegroundColor Magenta
& "$PSScriptRoot\scripts\Deploy-Containers.ps1" `
    -ContainerRegistryName $infraOutputs.containerRegistryName `
    -ResourceGroupName $infraOutputs.resourceGroupName

#  PHASE 3: Kubernetes 
Write-Host "`n=== PHASE 3: Kubernetes Platform Deployment ===" -ForegroundColor Magenta
$k8sOutputArray = & "$PSScriptRoot\scripts\Deploy-Kubernetes.ps1" `
    -AksName                 $infraOutputs.aksName `
    -ResourceGroupName       $infraOutputs.resourceGroupName `
    -ContainerRegistryName   $infraOutputs.containerRegistryName `
    -KeyVaultName            $infraOutputs.keyVaultName `
    -ManagedIdentityName     $infraOutputs.managedIdentityName `
    -ManagedIdentityClientId $infraOutputs.managedIdentityClientId

$k8sOutputs = $k8sOutputArray[-1]

if (-not $k8sOutputs) {
    throw "Deploy-Kubernetes.ps1 returned no outputs"
}

#  PHASE 4: Foundry Agents 
Write-Host "`n=== PHASE 4: Foundry Agents Deployment ===" -ForegroundColor Magenta

# Read proxy API key from Key Vault (set by infra as 'proxy-api-key')
$mcpApiKey = az keyvault secret show `
    --vault-name $infraOutputs.keyVaultName `
    --name "proxy-api-key" `
    --query value -o tsv 2>$null

if ($k8sOutputs.yarpProxyIP) {
    $mcpProxyUrl = "http://$($k8sOutputs.yarpProxyIP)/mcp"

    try {
        & "$PSScriptRoot\scripts\Deploy-FoundryAgents.ps1" `
            -AiProjectEndpoint $infraOutputs.aiProjectEndpoint `
            -McpProxyUrl       $mcpProxyUrl `
            -McpApiKey         $mcpApiKey `
            -ResourceGroupName $infraOutputs.resourceGroupName
    } catch {
        Write-Host "`n[WARNING] Agent deployment encountered issues: $_" -ForegroundColor Yellow
        Write-Host "Deploy agents manually:" -ForegroundColor Gray
        Write-Host "  .\scripts\Deploy-FoundryAgents.ps1 -AiProjectEndpoint <EP> -McpProxyUrl $mcpProxyUrl -McpApiKey <KEY>" -ForegroundColor Gray
    }
} else {
    Write-Host "`n[WARNING] YARP proxy external IP not yet assigned  skipping agent deployment." -ForegroundColor Yellow
    Write-Host "Check: kubectl get svc yarp-proxy -n tools" -ForegroundColor Gray
    Write-Host "Then run manually: .\scripts\Deploy-FoundryAgents.ps1 ..." -ForegroundColor Gray
}

#  Summary 
Write-Host @"

============================================================
                 Deployment Summary
============================================================
"@ -ForegroundColor Cyan

Write-Host "[OK] Azure Infrastructure deployed"     -ForegroundColor Green
Write-Host "[OK] Container images built and pushed" -ForegroundColor Green
Write-Host "[OK] Platform components deployed to AKS" -ForegroundColor Green
Write-Host "[OK] Foundry agents deployed | API Key: $mcpApiKey" -ForegroundColor Green    
Write-Host "`n=== Service Endpoints ===" -ForegroundColor Cyan

if ($k8sOutputs.grafanaIP) {
    Write-Host "Grafana    : http://$($k8sOutputs.grafanaIP):3000  (admin/admin)" -ForegroundColor Green
} else {
    Write-Host "Grafana    : kubectl port-forward -n platform svc/grafana 3000:3000" -ForegroundColor Yellow
}

if ($k8sOutputs.yarpProxyIP) {
    Write-Host "YARP Proxy : http://$($k8sOutputs.yarpProxyIP)/mcp" -ForegroundColor Green
} else {
    Write-Host "YARP Proxy : kubectl port-forward -n tools svc/yarp-proxy 8080:80" -ForegroundColor Yellow
}

Write-Host "`nMongoDB MCP Server: internal only (http://mongodb-mcp-server.tools.svc.cluster.local:3000)" -ForegroundColor Gray

Write-Host @"

============================================================
              Deployment Complete!
============================================================
"@ -ForegroundColor Green
