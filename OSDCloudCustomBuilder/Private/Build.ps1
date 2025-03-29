# Build script for OSDCloudCustomBuilder module
param(
    [Parameter(Mandatory=$false)]
    [string]$Version = "1.0.0",
    
    [Parameter()]
    [switch]$PublishToGallery,
    
    [Parameter()]
    [string]$ApiKey,
    
    [Parameter()]
    [string]$LocalRepositoryPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
)

# Create directory structure for PowerShell to recognize the module
$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleName = "OSDCloudCustomBuilder"
$moduleVersion = $Version

# Update module version in psd1
$manifestPath = Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1"
Write-Host "Updating module version to $Version..." -ForegroundColor Cyan

try {
    # Read the manifest content
    if (Test-Path $manifestPath) {
        $manifestContent = Get-Content -Path $manifestPath -Raw
        $manifestContent = $manifestContent -replace "ModuleVersion = '.*'", "ModuleVersion = '$Version'"
        Set-Content -Path $manifestPath -Value $manifestContent
        Write-Host "Module version updated successfully." -ForegroundColor Green
    } else {
        Write-Error "Module manifest not found at $manifestPath"
        exit 1
    }
} catch {
    Write-Error "Failed to update module version: $_"
    exit 1
}

# Skip tests if Run-Tests.ps1 doesn't exist
$testScript = Join-Path -Path $moduleRoot -ChildPath "Tests\Run-Tests.ps1"
if (Test-Path $testScript) {
    Write-Host "Running tests..." -ForegroundColor Cyan
    & $testScript -CodeCoverage

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Tests failed. Aborting build."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "Test script not found at $testScript. Skipping tests." -ForegroundColor Yellow
}

# Create module output directory with version-specific folder
$versionedModuleDir = Join-Path -Path $LocalRepositoryPath -ChildPath "$moduleName\$moduleVersion"
if (Test-Path $versionedModuleDir) {
    Remove-Item -Path $versionedModuleDir -Recurse -Force
}
New-Item -Path $versionedModuleDir -ItemType Directory -Force | Out-Null

Write-Host "Copying files to module directory: $versionedModuleDir" -ForegroundColor Cyan

# Copy module files to the versioned directory
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1") -Destination $versionedModuleDir
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psm1") -Destination $versionedModuleDir
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Public") -Destination $versionedModuleDir -Recurse
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Private") -Destination $versionedModuleDir -Recurse

# Also copy to module base directory for compatibility
$moduleBaseDir = Join-Path -Path $LocalRepositoryPath -ChildPath "$moduleName"
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1") -Destination $moduleBaseDir -Force
Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psm1") -Destination $moduleBaseDir -Force
Write-Host "Module files copied to base directory for compatibility" -ForegroundColor Green

Write-Host "Module deployed successfully" -ForegroundColor Green

# Create a package if needed
$outputDir = Join-Path -Path $moduleRoot -ChildPath "output"
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$zipPath = Join-Path -Path $outputDir -ChildPath "$moduleName-$Version.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

Write-Host "Creating module package..." -ForegroundColor Cyan
Compress-Archive -Path "$versionedModuleDir\*" -DestinationPath $zipPath -Force
Write-Host "Module package created: $zipPath" -ForegroundColor Green

# Publish to PowerShell Gallery if requested
if ($PublishToGallery) {
    if (-not $ApiKey) {
        Write-Error "API key is required for publishing to PowerShell Gallery."
        exit 1
    }
    
    Write-Host "Publishing to PowerShell Gallery..." -ForegroundColor Cyan
    try {
        Publish-Module -Path $versionedModuleDir -NuGetApiKey $ApiKey -Verbose
        Write-Host "Module published successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to publish module: $_"
        exit 1
    }
}

Write-Host "`nBuild completed successfully!" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host "Package: $zipPath" -ForegroundColor Cyan
Write-Host "Module Path: $versionedModuleDir" -ForegroundColor Cyan

if ($PublishToGallery) {
    Write-Host "Published to PowerShell Gallery: https://www.powershellgallery.com/packages/$moduleName" -ForegroundColor Cyan
}

# Provide instructions for using the module
Write-Host "`nTo use the module, you can import it with:" -ForegroundColor Yellow
Write-Host "Import-Module -Name $moduleName -RequiredVersion $Version" -ForegroundColor Yellow
Write-Host "`nOr simply:" -ForegroundColor Yellow
Write-Host "Import-Module -Name $moduleName" -ForegroundColor Yellow
Write-Host "`nTo verify the module is loaded correctly:" -ForegroundColor Yellow
Write-Host "Get-Module -Name $moduleName" -ForegroundColor Yellow