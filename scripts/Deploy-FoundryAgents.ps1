# Deploy Foundry agents for MongoDB data analysis via YARP proxy

param (
    [Parameter(Mandatory=$true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory=$true)]
    [string]$McpProxyUrl,

    [Parameter(Mandatory=$false)]
    [string]$McpApiKey = "",

    [Parameter(Mandatory=$false)]
    [string]$ModelDeployment = "gpt-4o"
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
    "--mcp-proxy-url", $McpProxyUrl
)
if ($McpApiKey) {
    $pythonArgs += @("--mcp-api-key", $McpApiKey)
}

python @pythonArgs

if ($LASTEXITCODE -ne 0) { throw "Agent deployment failed" }
Write-Host "`n[OK] Foundry agents deployed successfully" -ForegroundColor Green
