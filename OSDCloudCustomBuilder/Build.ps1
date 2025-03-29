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

# Create both the PowerShell 5.1 and PowerShell 7 module directories
$psModulePaths = @(
    # PowerShell 5.1 paths
    "$env:USERPROFILE\Documents\WindowsPowerShell\Modules",
    "$env:ProgramFiles\WindowsPowerShell\Modules",
    
    # PowerShell 7 paths
    "$env:USERPROFILE\Documents\PowerShell\Modules",
    "$env:ProgramFiles\PowerShell\Modules"
)

# Install to the default user module location for both PS 5.1 and PS 7
$ps51ModuleDir = Join-Path -Path "$env:USERPROFILE\Documents\WindowsPowerShell\Modules" -ChildPath "$moduleName"
$ps7ModuleDir = Join-Path -Path "$env:USERPROFILE\Documents\PowerShell\Modules" -ChildPath "$moduleName"

# Create the directories if they don't exist
foreach ($dir in @($ps51ModuleDir, $ps7ModuleDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    } else {
        # Clean up existing files if the directory exists
        Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Copying module files to PowerShell 5.1 and PowerShell 7 directories..." -ForegroundColor Cyan

# Function to copy module files to a destination
function Copy-ModuleFiles {
    param(
        [string]$Destination
    )
    
    # Create the version directory for best practices
    $versionDir = Join-Path -Path $Destination -ChildPath $moduleVersion
    if (-not (Test-Path $versionDir)) {
        New-Item -Path $versionDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy module files to both the base dir (for compatibility) and version dir (for best practices)
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1") -Destination $Destination -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psm1") -Destination $Destination -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Public") -Destination $Destination -Recurse -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Private") -Destination $Destination -Recurse -Force
    
    # Copy to version directory as well
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psd1") -Destination $versionDir -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "$moduleName.psm1") -Destination $versionDir -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Public") -Destination $versionDir -Recurse -Force
    Copy-Item -Path (Join-Path -Path $moduleRoot -ChildPath "Private") -Destination $versionDir -Recurse -Force
}

# Copy to PS 5.1 location
Copy-ModuleFiles -Destination $ps51ModuleDir
Write-Host "Module files copied to PowerShell 5.1 modules directory: $ps51ModuleDir" -ForegroundColor Green

# Copy to PS 7 location
Copy-ModuleFiles -Destination $ps7ModuleDir
Write-Host "Module files copied to PowerShell 7 modules directory: $ps7ModuleDir" -ForegroundColor Green

# Create a package
$outputDir = Join-Path -Path $moduleRoot -ChildPath "output"
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$zipPath = Join-Path -Path $outputDir -ChildPath "$moduleName-$Version.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

Write-Host "Creating module package..." -ForegroundColor Cyan
Compress-Archive -Path "$ps51ModuleDir\*" -DestinationPath $zipPath -Force
Write-Host "Module package created: $zipPath" -ForegroundColor Green

# Publish to PowerShell Gallery if requested
if ($PublishToGallery) {
    if (-not $ApiKey) {
        Write-Error "API key is required for publishing to PowerShell Gallery."
        exit 1
    }
    
    Write-Host "Publishing to PowerShell Gallery..." -ForegroundColor Cyan
    try {
        Publish-Module -Path $ps51ModuleDir -NuGetApiKey $ApiKey -Verbose
        Write-Host "Module published successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to publish module: $_"
        exit 1
    }
}

Write-Host "`nBuild completed successfully!" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host "Package: $zipPath" -ForegroundColor Cyan
Write-Host "PowerShell 5.1 Module Path: $ps51ModuleDir" -ForegroundColor Cyan
Write-Host "PowerShell 7 Module Path: $ps7ModuleDir" -ForegroundColor Cyan

if ($PublishToGallery) {
    Write-Host "Published to PowerShell Gallery: https://www.powershellgallery.com/packages/$moduleName" -ForegroundColor Cyan
}

# Provide instructions for using the module
Write-Host "`nTo use the module in PowerShell 5.1, you can import it with:" -ForegroundColor Yellow
Write-Host "Import-Module -Name $moduleName" -ForegroundColor Yellow

Write-Host "`nTo use the module in PowerShell 7, you can import it with:" -ForegroundColor Yellow
Write-Host "Import-Module -Name $moduleName" -ForegroundColor Yellow

Write-Host "`nTo verify the module is loaded correctly:" -ForegroundColor Yellow
Write-Host "Get-Module -Name $moduleName | Select-Object Name, Version" -ForegroundColor Yellow