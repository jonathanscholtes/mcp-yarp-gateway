# Build and push custom container images to Azure Container Registry
# Images: yarp-proxy (ASP.NET Core 8), data-seeder (Python)
# Note: mongodb-mcp-server uses the public image mongodb/mongodb-mcp-server and is not built here.

param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$false)]
    [string[]]$Images = @("yarp-proxy", "data-seeder")
)

Write-Host "`n=== Building Container Images ===" -ForegroundColor Cyan
Write-Host "Container Registry : $ContainerRegistryName" -ForegroundColor White
Write-Host "Resource Group     : $ResourceGroupName" -ForegroundColor White

$imageConfigs = @{
    "yarp-proxy"  = @{ path = "."; dockerfile = ".\apps\yarp-proxy\Dockerfile" }
    "data-seeder" = @{ path = "."; dockerfile = ".\apps\data-seeder\Dockerfile" }
}

foreach ($imageName in $Images) {
    if (-not $imageConfigs.ContainsKey($imageName)) {
        Write-Host "Unknown image '$imageName', skipping." -ForegroundColor Yellow
        continue
    }

    $config = $imageConfigs[$imageName]
    Write-Host "`nBuilding '${imageName}:latest'..." -ForegroundColor Yellow

    az acr build `
        --resource-group $ResourceGroupName `
        --registry $ContainerRegistryName `
        --file $config.dockerfile `
        --image "${imageName}:latest" `
        $config.path

    if ($LASTEXITCODE -ne 0) { throw "Image build failed for '$imageName'" }
    Write-Host "[OK] '${imageName}:latest' built and pushed" -ForegroundColor Green
}

Write-Host "`n[OK] All container images built successfully" -ForegroundColor Green
