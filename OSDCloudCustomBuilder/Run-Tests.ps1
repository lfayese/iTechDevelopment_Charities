Import-Module .\OSDCloudCustomBuilder.psm1 -Force -Verbose

Write-Host "Testing exported functions..."
$ExportedFunctions = Get-Command -Module OSDCloudCustomBuilder | Select-Object -ExpandProperty Name
foreach ($Function in $ExportedFunctions) {
    Write-Host "Testing $Function..."
    try {
        & $Function -Verbose
        Write-Host "$Function executed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Error executing $Function: $_" -ForegroundColor Red
    }
}

Write-Host "All tests completed."

# Configure Pester for code coverage if requested
if ($WithCoverage) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = @(
        "./Public/*.ps1",
        "./Private/*.ps1"
    )
    $pesterConfig.CodeCoverage.OutputFormat = "JaCoCo"
    $pesterConfig.CodeCoverage.OutputPath = "./CodeCoverage.xml"
}

# Run tests
$testResults = Invoke-Pester -Configuration $pesterConfig

# Output summary
Write-Host "Tests completed with result: $($testResults.Result)"
Write-Host "Passed: $($testResults.PassedCount) | Failed: $($testResults.FailedCount) | Skipped: $($testResults.SkippedCount)"

# Exit with error code for CI if there are failures
if ($CI -and $testResults.FailedCount -gt 0) {
    exit 1
}
