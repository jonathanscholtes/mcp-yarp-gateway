# Deploy Foundry agents for MongoDB data analysis via YARP proxy

param (
    [Parameter(Mandatory=$true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory=$true)]
    [string]$McpProxyUrl,

    [Parameter(Mandatory=$true)]
    [string]$McpApiKey,

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

# ── Create Foundry MCP tool connection via Bicep ─────────────────────────
# MCPTool requires project_connection_id; the sensitive api-key header
# cannot be passed via the headers parameter.  The connection is created at
# the CognitiveServices account level using the mcp-connection.bicep template.
#
$connectionName = "yarp-proxy-mcp"

# Derive account name and resource group from the project endpoint
$accountName = ([System.Uri]$AiProjectEndpoint).Host.Split('.')[0]

Write-Host "`nLooking up Foundry account '$accountName'..." -ForegroundColor Yellow
$account = az cognitiveservices account list --query "[?name=='$accountName'] | [0]" -o json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Could not find CognitiveServices account '$accountName'. Ensure you are logged into the correct subscription."
}

# Extract resource group from the account resource ID
$rgName = if ($ResourceGroupName) { $ResourceGroupName } else { ($account.id -split '/')[4] }
Write-Host "  Account: $($account.id)" -ForegroundColor Green
Write-Host "  Resource Group: $rgName" -ForegroundColor Green

# Deploy the MCP connection via Bicep (idempotent)
Write-Host "  Deploying MCP connection '$connectionName'..." -ForegroundColor Yellow
$bicepFile = "$PSScriptRoot\..\infra\core\ai\aifoundry\mcp-connection.bicep"

az deployment group create `
    --resource-group $rgName `
    --template-file $bicepFile `
    --parameters accountName=$accountName connectionName=$connectionName mcpProxyUrl=$McpProxyUrl mcpApiKey=$McpApiKey `
    --output none

if ($LASTEXITCODE -ne 0) {
    throw "Failed to deploy MCP connection '$connectionName'"
}
Write-Host "  [OK] Connection '$connectionName' deployed" -ForegroundColor Green

# Verify YARP proxy is running
Write-Host "`nVerifying YARP proxy pod..." -ForegroundColor Yellow
$podStatus = kubectl get pods -n tools -l app=yarp-proxy -o jsonpath='{.items[0].status.phase}' 2>$null
if ($podStatus -eq "Running") {
    Write-Host "  yarp-proxy is running" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] yarp-proxy pod not ready (status: $podStatus). Agents may fail." -ForegroundColor Yellow
}

# Deploy agents
Write-Host "`nDeploying agents to Microsoft Foundry..." -ForegroundColor Yellow

$pythonArgs = @(
    "scripts/deploy_foundry_agents.py",
    "--project-endpoint", $AiProjectEndpoint,
    "--model-deployment", $ModelDeployment,
    "--mcp-proxy-url", $McpProxyUrl,
    "--mcp-api-key", $McpApiKey,
    "--connection-name", $connectionName
)

python @pythonArgs

if ($LASTEXITCODE -ne 0) { throw "Agent deployment failed" }
Write-Host "`n[OK] Foundry agents deployed successfully" -ForegroundColor Green
