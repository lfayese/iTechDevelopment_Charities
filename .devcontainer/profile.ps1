# PowerShell Profile for DevContainer

# Set default formatting
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Helper function to load the module from the workspace
function Import-WorkspaceModule {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".." -Resolve
    Import-Module $modulePath -Force -Verbose
    Write-Host "Loaded OSDCloudCustomBuilder module from $modulePath" -ForegroundColor Green
}

# Set up aliases for common tasks
New-Alias -Name build -Value ./Build.ps1
New-Alias -Name test -Value ./Run-Tests.ps1

# Welcome message
function Show-DevContainerWelcome {
    Write-Host "PowerShell 7.5.0 DevContainer" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available commands:" -ForegroundColor Yellow
    Write-Host "  build         - Run the build script" -ForegroundColor Yellow
    Write-Host "  test          - Run the test suite" -ForegroundColor Yellow
    Write-Host "  Import-WorkspaceModule - Import the module from the workspace" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
}

# Show welcome message
Show-DevContainerWelcome