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
