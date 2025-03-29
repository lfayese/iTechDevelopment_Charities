# Build script for OSDCloudCustomBuilder module
param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [Parameter()]
    [switch]$PublishToGallery,
    
    [Parameter()]
    [string]$ApiKey,
    
    [Parameter()]
    [string]$LocalRepositoryPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
)

# Update module version
$manifestPath = "$PSScriptRoot\OSDCloudCustomBuilder.psd1"
Write-Host "Updating module version to $Version..." -ForegroundColor Cyan

try {
    $manifestContent = Get-Content -Path $manifestPath -Raw
    $manifestContent = $manifestContent -replace "ModuleVersion = '.*'", "ModuleVersion = '$Version'"
    Set-Content -Path $manifestPath -Value $manifestContent
    Write-Host "Module version updated successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to update module version: $_"
    exit 1
}

# Run tests
Write-Host "Running tests..." -ForegroundColor Cyan
$testScript = "$PSScriptRoot\Run-Tests.ps1"
& $testScript -CodeCoverage

if ($LASTEXITCODE -ne 0) {
    Write-Error "Tests failed. Aborting build."
    exit $LASTEXITCODE
}

# Create module output directory
$outputDir = "$PSScriptRoot\output\OSDCloudCustomBuilder"
if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force
}
New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

# Copy module files to output directory
Write-Host "Copying files to output directory..." -ForegroundColor Cyan
Copy-Item -Path "$PSScriptRoot\OSDCloudCustomBuilder.psd1" -Destination $outputDir
Copy-Item -Path "$PSScriptRoot\OSDCloudCustomBuilder.psm1" -Destination $outputDir
Copy-Item -Path "$PSScriptRoot\Public" -Destination $outputDir -Recurse
Copy-Item -Path "$PSScriptRoot\Private" -Destination $outputDir -Recurse
Copy-Item -Path "$PSScriptRoot\README.md" -Destination $outputDir
Copy-Item -Path "$PSScriptRoot\LICENSE" -Destination $outputDir -ErrorAction SilentlyContinue

# Create module package
Write-Host "Creating module package..." -ForegroundColor Cyan
$zipPath = "$PSScriptRoot\output\OSDCloudCustomBuilder-$Version.zip"
Compress-Archive -Path "$outputDir\*" -DestinationPath $zipPath -Force

Write-Host "Module package created: $zipPath" -ForegroundColor Green

# Deploy to local repository
$localRepoModulePath = Join-Path -Path $LocalRepositoryPath -ChildPath "OSDCloudCustomBuilder"
Write-Host "Deploying to local repository: $localRepoModulePath" -ForegroundColor Cyan

# Create directory if it doesn't exist
if (-not (Test-Path $localRepoModulePath)) {
    New-Item -Path $localRepoModulePath -ItemType Directory -Force | Out-Null
} else {
    # Clean up the existing module directory
    Remove-Item -Path "$localRepoModulePath\*" -Recurse -Force
}

# Copy the module to the local repository
Copy-Item -Path "$outputDir\*" -Destination $localRepoModulePath -Recurse -Force
Write-Host "Module deployed to local repository successfully." -ForegroundColor Green

# Publish to PowerShell Gallery if requested (keeping this option for flexibility)
if ($PublishToGallery) {
    if (-not $ApiKey) {
        Write-Error "API key is required for publishing to PowerShell Gallery."
        exit 1
    }
    
    Write-Host "Publishing to PowerShell Gallery..." -ForegroundColor Cyan
    try {
        Publish-Module -Path $outputDir -NuGetApiKey $ApiKey -Verbose
        Write-Host "Module published successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to publish module: $_"
        exit 1
    }
}

Write-Host "`nBuild completed successfully!" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host "Package: $zipPath" -ForegroundColor Cyan
Write-Host "Local Repository: $localRepoModulePath" -ForegroundColor Cyan

if ($PublishToGallery) {
    Write-Host "Published to PowerShell Gallery: https://www.powershellgallery.com/packages/OSDCloudCustomBuilder" -ForegroundColor Cyan
}

# Provide instructions for using the local module
Write-Host "`nTo use the module from your local repository, you can import it with:" -ForegroundColor Yellow
Write-Host "Import-Module -Name OSDCloudCustomBuilder" -ForegroundColor Yellow
Write-Host "`nTo verify the module is loaded correctly:" -ForegroundColor Yellow
Write-Host "Get-Module -Name OSDCloudCustomBuilder" -ForegroundColor Yellow