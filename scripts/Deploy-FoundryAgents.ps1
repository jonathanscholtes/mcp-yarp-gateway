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

# The AI Foundry connection must be created MANUALLY in the Foundry portal before running this script.
# The ARM API does not support specifying the HTTP header name alongside the credential value,
# which is required for Agent Service to inject the correct auth header into MCP requests.
#
# Manual steps (one-time, per project):
#   1. Open Azure AI Foundry portal → your project → Management → Connected resources
#   2. Click "+ New connection" → choose "Custom keys" (or "Remote MCP Server" if available)
#   3. Set:
#        Name            : yarp-proxy-mcp
#        Endpoint/URL    : $McpProxyUrl
#        Key name        : api-key          ← this becomes the HTTP header name
#        Key value       : <proxy API key>
#   4. Save. The connection only needs to be created once.
#
$connectionName = "yarp-proxy-mcp"
Write-Host "`n[PREREQ] Foundry connection '$connectionName' must exist (see script comments)." -ForegroundColor Cyan

# Verify the connection exists via the project connections API
try {
    $token = (az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv)
    $accountName = ([System.Uri]$AiProjectEndpoint).Host.Split('.')[0]
    $projectName  = $AiProjectEndpoint.TrimEnd('/').Split('/')[-1]
    $checkUrl = "https://${accountName}.services.ai.azure.com/api/projects/${projectName}/connections/${connectionName}?api-version=v1"
    $connResp = Invoke-RestMethod -Method GET -Uri $checkUrl -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
    Write-Host "  [OK] Connection '$connectionName' verified" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Connection '$connectionName' not found yet - agents will be deployed but auth will fail until the connection is added." -ForegroundColor Yellow
    Write-Host "         Add it manually in the Foundry portal (see deploy.ps1 summary output for details)." -ForegroundColor Yellow
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
