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

# ── Create Foundry account connection (ARM control plane) ─────────────────
# MCPTool requires project_connection_id; the sensitive api-key header
# cannot be passed via the headers parameter.  The connection is created at
# the CognitiveServices account level via the ARM API.
#
$connectionName = "yarp-proxy-mcp"

# Derive the account name from the project endpoint host
$accountName = ([System.Uri]$AiProjectEndpoint).Host.Split('.')[0]

# Look up the ARM resource ID for the CognitiveServices account
Write-Host "`nLooking up Foundry account '$accountName'..." -ForegroundColor Yellow
$account = az cognitiveservices account list --query "[?name=='$accountName'] | [0]" -o json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Could not find CognitiveServices account '$accountName'. Ensure you are logged into the correct subscription."
}
$accountResourceId = $account.id
Write-Host "  Account: $accountResourceId" -ForegroundColor Green

# Check whether the connection already exists
$connResourceId = "$accountResourceId/connections/$connectionName"
$connExists = $false
try {
    az rest --method GET --uri "https://management.azure.com${connResourceId}?api-version=2025-04-01-preview" --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        $connExists = $true
        Write-Host "  [OK] Connection '$connectionName' already exists" -ForegroundColor Green
    }
} catch { }

if (-not $connExists) {
    Write-Host "  Creating connection '$connectionName'..." -ForegroundColor Yellow
    $body = @{
        properties = @{
            category      = "RemoteTool"
            target        = $McpProxyUrl
            authType      = "CustomKeys"
            isSharedToAll = $true
            credentials   = @{
                type = "CustomKeys"
                keys = @{
                    "api-key" = $McpApiKey
                }
            }
            metadata      = @{
                type = "custom_MCP"
            }
        }
    }
    $bodyFile = [System.IO.Path]::GetTempFileName()
    $body | ConvertTo-Json -Depth 4 | Set-Content -Path $bodyFile -Encoding UTF8

    az rest --method PUT `
        --uri "https://management.azure.com${connResourceId}?api-version=2025-04-01-preview" `
        --headers "Content-Type=application/json" `
        --body "@$bodyFile" --output none

    Remove-Item $bodyFile -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create connection '$connectionName'"
    }
    Write-Host "  [OK] Connection '$connectionName' created" -ForegroundColor Green
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
