# Run-Tests.ps1
[CmdletBinding()]
param(
    [switch]$Coverage
)

# Import the Pester module
if (-not (Get-Module -Name Pester -ListAvailable)) {
    Write-Warning "Pester module not found. Installing Pester..."
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import the configuration
$config = & (Join-Path $PSScriptRoot "pester.config.ps1")

# Override configuration if coverage is not requested
if (-not $Coverage) {
    $config.CodeCoverage.Enabled = $false
}

# Run the tests and capture the results
$results = Invoke-Pester -Configuration $config -PassThru

# Display summary
Write-Host "`nTest Summary:" -ForegroundColor Yellow
Write-Host "============" -ForegroundColor Yellow
Write-Host "Total Tests: $($results.TotalCount)" -ForegroundColor Cyan
Write-Host "Passed: $($results.PassedCount)" -ForegroundColor Green
Write-Host "Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped: $($results.SkippedCount)" -ForegroundColor Yellow

if ($Coverage -and $config.CodeCoverage.Enabled) {
    $coverageFile = Join-Path $PSScriptRoot "coverage.xml"
    Write-Host "`nCode Coverage Report generated: $coverageFile" -ForegroundColor Cyan
    Write-Host "You can upload this report to a service like Codecov for visualization." -ForegroundColor Cyan
}

# Return success/failure for CI systems
exit $results.FailedCount