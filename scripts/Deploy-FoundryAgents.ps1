# Deploy Foundry agents for MongoDB data analysis via YARP proxy

param (
    [Parameter(Mandatory=$true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory=$true)]
    [string]$McpProxyUrl,

    [Parameter(Mandatory=$false)]
    [string]$McpApiKey = "",

    [Parameter(Mandatory=$false)]
    [string]$ModelDeployment = "gpt-4o",

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = ""
)

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Write-Host "`n=== Deploying Foundry Agents ===" -ForegroundColor Cyan

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    throw "Python not found. Required for agent deployment."
}

# Install dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Yellow
pip install -r scripts/requirements-agents.txt --quiet

Write-Host "`nAgent Configuration:" -ForegroundColor Cyan
Write-Host "  Project Endpoint  : $AiProjectEndpoint" -ForegroundColor White
Write-Host "  Model Deployment  : $ModelDeployment" -ForegroundColor White
Write-Host "  MCP Proxy URL     : $McpProxyUrl" -ForegroundColor White
Write-Host "  API Key           : $(if ($McpApiKey) { '***set***' } else { 'NOT SET' })" -ForegroundColor White

# Create AI Foundry connection to store the YARP proxy API key securely
# The agents API does not allow inline headers - credentials must be in a connection
$connectionName = "yarp-proxy-mcp"
if ($McpApiKey -and $ResourceGroupName) {
    Write-Host "`nCreating AI Foundry connection '$connectionName'..." -ForegroundColor Yellow

    # Extract account name from endpoint hostname: https://<account>.services.ai.azure.com/...
    $accountName = ([System.Uri]$AiProjectEndpoint).Host.Split('.')[0]
    $subscriptionId = (az account show --query id -o tsv)

    $connectionBody = @{
        properties = @{
            authType    = "ApiKey"
            category    = "ApiKey"
            target      = $McpProxyUrl
            isSharedToAll = $true
            credentials = @{ key = $McpApiKey }
        }
    } | ConvertTo-Json -Depth 5

    $connectionUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$accountName/connections/${connectionName}?api-version=2025-06-01"

    az rest --method PUT --url $connectionUrl --body $connectionBody --headers "Content-Type=application/json" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Connection '$connectionName' created/updated" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] Could not create connection - agents may fail to auth" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[INFO] Skipping connection creation (no API key or resource group provided)" -ForegroundColor Gray
}

# Verify YARP proxy is running
Write-Host "`nVerifying YARP proxy pod..." -ForegroundColor Yellow
$podStatus = kubectl get pods -n tools -l app=yarp-proxy -o jsonpath='{.items[0].status.phase}' 2>$null
if ($podStatus -eq "Running") {
    Write-Host "  yarp-proxy is running" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] yarp-proxy pod not ready (status: $podStatus). Agents may fail." -ForegroundColor Yellow
}

# Deploy agents
Write-Host "`nDeploying agents to Azure AI Foundry..." -ForegroundColor Yellow

$pythonArgs = @(
    "scripts/deploy_foundry_agents.py",
    "--project-endpoint", $AiProjectEndpoint,
    "--model-deployment", $ModelDeployment,
    "--mcp-proxy-url", $McpProxyUrl,
    "--connection-name", $connectionName
)
if ($McpApiKey) {
    $pythonArgs += @("--mcp-api-key", $McpApiKey)
}

python @pythonArgs

if ($LASTEXITCODE -ne 0) { throw "Agent deployment failed" }
Write-Host "`n[OK] Foundry agents deployed successfully" -ForegroundColor Green
