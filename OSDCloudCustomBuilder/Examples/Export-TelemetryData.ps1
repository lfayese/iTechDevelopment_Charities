<# 
.SYNOPSIS
    Exports telemetry data to various formats for further analysis.
.DESCRIPTION
    This sample script demonstrates how to export OSDCloudCustomBuilder telemetry data
    to different formats including CSV, HTML, JSON, and XML for further analysis. It
    allows for filtering of telemetry data and includes visualization for reports.
.PARAMETER OutputFolder
    Folder where exported files will be saved. Default is the current directory.
.PARAMETER ExportFormat
    Format(s) to export data to. Valid options are CSV, HTML, JSON, and XML.
    Default is all formats.
.PARAMETER FilterDays
    Only include telemetry data from the last X days. Default is all data.
.PARAMETER OperationName
    Filter telemetry data to specific operations.
.EXAMPLE
    .\Export-TelemetryData.ps1 -OutputFolder "C:\Exports" -ExportFormat CSV,HTML
    Exports telemetry data to CSV and HTML formats in the specified folder.
.EXAMPLE
    .\Export-TelemetryData.ps1 -FilterDays 7 -OperationName "Update-CustomWimWithPwsh7"
    Exports data for the specified operation from the last 7 days to all formats.
.NOTES
    This script requires the OSDCloudCustomBuilder module to be installed and loaded.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = (Get-Location).Path,
    [Parameter(Mandatory = $false)]
    [ValidateSet('CSV', 'HTML', 'JSON', 'XML')]
    [string[]]$ExportFormat = @('CSV', 'HTML', 'JSON', 'XML'),
    [Parameter(Mandatory = $false)]
    [int]$FilterDays = 0,
    [Parameter(Mandatory = $false)]
    [string]$OperationName
)
# Import required modules
Import-Module OSDCloudCustomBuilder -Force
# Ensure output folder exists
if (-not (Test-Path -Path $OutputFolder)) {
    try {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        Write-Host "Created output folder: $OutputFolder" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to create output folder: $_"
        exit 1
    }
}
# Get telemetry file path
$config = Get-ModuleConfiguration
if (-not $config.Telemetry -or -not $config.Telemetry.StoragePath) {
    Write-Warning "Telemetry is not configured. Configure it with Set-OSDCloudTelemetry first."
    exit
}
$telemetryPath = Join-Path -Path $config.Telemetry.StoragePath -ChildPath "telemetry.json"
if (-not (Test-Path -Path $telemetryPath)) {
    Write-Warning "No telemetry data found at $telemetryPath."
    exit
}
# Load telemetry data
try {
    Write-Host "Loading telemetry data from $telemetryPath..." -ForegroundColor Cyan
    $telemetryData = Get-Content -Path $telemetryPath -Raw | ConvertFrom-Json
    if (-not $telemetryData.Entries -or $telemetryData.Entries.Count -eq 0) {
        Write-Warning "No telemetry entries found in the data file."
        exit
    }
    
    # Filter telemetry entries in one pass
    $entries = $telemetryData.Entries | Where-Object {
        $include = $true
        
        # Apply FilterDays if specified and if Timestamp exists
        if ($FilterDays -gt 0 -and $_.Timestamp) {
            $timestamp = $null
            if ([DateTime]::TryParse($_.Timestamp, [ref]$timestamp)) {
                if ($timestamp -lt (Get-Date).AddDays(-$FilterDays)) {
                    $include = $false
                }
            }
        }
        
        # Apply OperationName filter if specified
        if ($OperationName) {
            if ($_.OperationName -ne $OperationName -and $_.Operation -ne $OperationName) {
                $include = $false
            }
        }
        $include
    }
    
    $entryCount = $telemetryData.Entries.Count
    $filteredCount = $entries.Count
    Write-Host "Found $entryCount telemetry entries. After filtering: $filteredCount entries" -ForegroundColor Green
    if ($filteredCount -eq 0) {
        Write-Warning "No entries matched the filter criteria."
        exit
    }
    
    # Prepare base filename
    $timestampStr = Get-Date -Format "yyyyMMdd-HHmmss"
    $baseFilename = "OSDCloudTelemetry_$timestampStr"
    if ($OperationName) {
        $baseFilename += "_$OperationName"
    }
    if ($FilterDays -gt 0) {
        $baseFilename += "_Last${FilterDays}Days"
    }
    
    # Export to each requested format
    foreach ($format in $ExportFormat) {
        $outputPath = Join-Path -Path $OutputFolder -ChildPath "$baseFilename.$($format.ToLower())"
        try {
            switch ($format) {
                'CSV' {
                    Write-Host "Exporting to CSV: $outputPath" -ForegroundColor Cyan
                    $entries |
                        Select-Object OperationName, Duration, Success, MemoryDeltaMB, Timestamp, Error |
                        Export-Csv -Path $outputPath -NoTypeInformation
                }
                'HTML' {
                    Write-Host "Exporting to HTML: $outputPath" -ForegroundColor Cyan
                    # Create HTML report with inline styling
                    $htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>OSDCloudCustomBuilder Telemetry Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1, h2 { color: #0066cc; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th { background-color: #0066cc; color: white; text-align: left; padding: 8px; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        tr:hover { background-color: #ddd; }
        .success { color: green; }
        .failure { color: red; }
        .summary { background-color: #f8f8f8; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>OSDCloudCustomBuilder Telemetry Report</h1>
    <div class="summary">
        <p><strong>Report Generated:</strong> $(Get-Date)</p>
        <p><strong>Installation ID:</strong> $($telemetryData.InstallationId)</p>
        <p><strong>Total Entries:</strong> $filteredCount</p>
        <p><strong>Filter Applied:</strong> $($OperationName ? "Operation: $OperationName" : "All Operations")$($FilterDays -gt 0 ? ", Last $FilterDays days" : "")</p>
    </div>
"@
                    # Operation summary table generation
                    $operationSummary = $entries | Group-Object -Property OperationName | ForEach-Object {
                        $opEntries = $_.Group
                        $successCount = ($opEntries | Where-Object Success -eq $true).Count
                        $failureCount = ($opEntries | Where-Object Success -eq $false).Count
                        $avgDuration = ($opEntries | Measure-Object -Property Duration -Average).Average
                        [PSCustomObject]@{
                            OperationName = $_.Name
                            Count         = $_.Count
                            SuccessCount  = $successCount
                            FailureCount  = $failureCount
                            SuccessRate   = if ($_.Count -gt 0) { [math]::Round(($successCount / $_.Count) * 100, 1) } else { 0 }
                            AvgDurationMs = [math]::Round($avgDuration, 2)
                        }
                    }
                    $summaryTable = $operationSummary | Sort-Object -Property Count -Descending | ConvertTo-Html -Fragment -As Table
                    $entriesHtml = $entries |
                        Select-Object OperationName, Duration, Success, MemoryDeltaMB, Timestamp, Error |
                        ConvertTo-Html -Fragment -As Table
                    # Replace success/failure text for coloring
                    $entriesHtml = $entriesHtml -replace '<td>True</td>', '<td class="success">Success</td>'
                    $entriesHtml = $entriesHtml -replace '<td>False</td>', '<td class="failure">Failure</td>'
                    $htmlFooter = @"
</body>
</html>
"@
                    $htmlReport = $htmlHeader + "<h2>Operation Summary</h2>" + $summaryTable + "<h2>Telemetry Entries</h2>" + $entriesHtml + $htmlFooter
                    $htmlReport | Out-File -FilePath $outputPath -Encoding UTF8
                }
                'JSON' {
                    Write-Host "Exporting to JSON: $outputPath" -ForegroundColor Cyan
                    $entries | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
                }
                'XML' {
                    Write-Host "Exporting to XML: $outputPath" -ForegroundColor Cyan
                    $entries | Export-Clixml -Path $outputPath
                }
            }
            Write-Host "Successfully exported to $format format" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export to $format format: $_"
        }
    }
    
    Write-Host "`nExport Summary:" -ForegroundColor Cyan
    foreach ($format in $ExportFormat) {
        $outputPath = Join-Path -Path $OutputFolder -ChildPath "$baseFilename.$($format.ToLower())"
        Write-Host "- $format $outputPath" -ForegroundColor White
    }
}
catch {
    Write-Error "Failed to process telemetry data: $_"
}