<#
.SYNOPSIS
    Analyzes telemetry data collected by OSDCloudCustomBuilder.
.DESCRIPTION
    This example script demonstrates how to access, parse, and analyze telemetry data
    collected by the OSDCloudCustomBuilder module. It shows how to identify performance
    bottlenecks, error patterns, and system resource usage.
.NOTES
    This script requires the OSDCloudCustomBuilder module to be installed and loaded.
#>

# Import required modules
Import-Module OSDCloudCustomBuilder -Force

# Get module configuration to find telemetry data path
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

# Load and parse telemetry data
try {
    Write-Host "Loading telemetry data from $telemetryPath..." -ForegroundColor Cyan
    $telemetryData = Get-Content -Path $telemetryPath -Raw | ConvertFrom-Json
    
    $entryCount = if ($telemetryData.Entries -and $telemetryData.Entries.Count) {
        $telemetryData.Entries.Count
    } else {
        0
    }
    
    if ($entryCount -eq 0) {
        Write-Warning "No telemetry entries found in the data file."
        exit
    }
    
    Write-Host "Found $entryCount telemetry entries. Analyzing..." -ForegroundColor Green
    
    # Analyze operation performance
    $operations = $telemetryData.Entries | Group-Object -Property OperationName
    
    Write-Host "`n=== Operation Performance Summary ===" -ForegroundColor Cyan
    $performanceSummary = $operations | ForEach-Object {
        $opEntries = $_.Group
        $successCount = ($opEntries | Where-Object Success -eq $true).Count
        $failureCount = ($opEntries | Where-Object Success -eq $false).Count
        $avgDuration = $opEntries | Measure-Object -Property Duration -Average | Select-Object -ExpandProperty Average
        $maxDuration = $opEntries | Measure-Object -Property Duration -Maximum | Select-Object -ExpandProperty Maximum
        
        [PSCustomObject]@{
            OperationName = $_.Name
            Count = $_.Count
            SuccessCount = $successCount
            FailureCount = $failureCount
            SuccessRate = if ($_.Count -gt 0) { [math]::Round(($successCount / $_.Count) * 100, 1) } else { 0 }
            AvgDurationMs = [math]::Round($avgDuration, 2)
            MaxDurationMs = [math]::Round($maxDuration, 2)
        }
    }
    
    $performanceSummary | Sort-Object -Property AvgDurationMs -Descending | Format-Table -AutoSize
    
    # Identify slow operations (top 5)
    Write-Host "`n=== Top 5 Slowest Operations ===" -ForegroundColor Cyan
    $telemetryData.Entries | 
        Sort-Object -Property Duration -Descending | 
        Select-Object -First 5 | 
        Format-Table OperationName, Duration, Success, Timestamp -AutoSize
    
    # Identify failures
    $failures = $telemetryData.Entries | Where-Object Success -eq $false
    if ($failures) {
        Write-Host "`n=== Failed Operations ===" -ForegroundColor Cyan
        $failures | 
            Select-Object OperationName, Duration, Timestamp, Error | 
            Format-Table -AutoSize
        
        # Group failures by error message
        $errorPatterns = $failures | 
            Where-Object { $_.Error } | 
            Group-Object -Property Error
        
        if ($errorPatterns.Count -gt 0) {
            Write-Host "`n=== Common Error Patterns ===" -ForegroundColor Cyan
            $errorPatterns | 
                Sort-Object -Property Count -Descending | 
                Format-Table Name, Count -AutoSize
        }
    }
    else {
        Write-Host "`n=== No failed operations found! ===" -ForegroundColor Green
    }
    
    # Memory usage analysis
    Write-Host "`n=== Memory Usage Statistics ===" -ForegroundColor Cyan
    $memoryStats = $telemetryData.Entries | 
        Where-Object { $_.MemoryDeltaMB } | 
        Measure-Object -Property MemoryDeltaMB -Average -Maximum -Minimum
    
    Write-Host "Average Memory Delta: $([math]::Round($memoryStats.Average, 2)) MB" -ForegroundColor White
    Write-Host "Maximum Memory Delta: $([math]::Round($memoryStats.Maximum, 2)) MB" -ForegroundColor White
    Write-Host "Minimum Memory Delta: $([math]::Round($memoryStats.Minimum, 2)) MB" -ForegroundColor White
    
    # Operations with highest memory usage
    Write-Host "`n=== Top 5 Memory-Intensive Operations ===" -ForegroundColor Cyan
    $telemetryData.Entries | 
        Where-Object { $_.MemoryDeltaMB } | 
        Sort-Object -Property MemoryDeltaMB -Descending | 
        Select-Object -First 5 | 
        Format-Table OperationName, MemoryDeltaMB, Duration, Timestamp -AutoSize
    
    # System load analysis if available
    $detailedEntries = $telemetryData.Entries | Where-Object { $_.SystemLoad }
    if ($detailedEntries.Count -gt 0) {
        Write-Host "`n=== System Load Statistics ===" -ForegroundColor Cyan
        $cpuLoadStats = $detailedEntries | 
            Measure-Object -Property { $_.SystemLoad.CPULoad } -Average -Maximum -Minimum
        
        $memLoadStats = $detailedEntries | 
            Measure-Object -Property { $_.SystemLoad.MemoryLoad } -Average -Maximum -Minimum
        
        Write-Host "CPU Load (Average): $([math]::Round($cpuLoadStats.Average, 2))%" -ForegroundColor White
        Write-Host "CPU Load (Maximum): $([math]::Round($cpuLoadStats.Maximum, 2))%" -ForegroundColor White
        Write-Host "Memory Load (Average): $([math]::Round($memLoadStats.Average, 2))%" -ForegroundColor White
        Write-Host "Memory Load (Maximum): $([math]::Round($memLoadStats.Maximum, 2))%" -ForegroundColor White
    }
    
    # Performance trends over time (if enough data)
    if ($entryCount -gt 10) {
        Write-Host "`n=== Recommendations Based on Telemetry Data ===" -ForegroundColor Cyan
        
        # Operations with high failure rates
        $highFailureOps = $performanceSummary | Where-Object { $_.SuccessRate -lt 90 -and $_.Count -gt 3 }
        if ($highFailureOps) {
            Write-Host "Operations with high failure rates (below 90% success):" -ForegroundColor Yellow
            $highFailureOps | Format-Table OperationName, Count, SuccessRate -AutoSize
        }
        
        # Operations that might need optimization
        $slowOps = $performanceSummary | Where-Object { $_.AvgDurationMs -gt 5000 -and $_.Count -gt 3 }
        if ($slowOps) {
            Write-Host "Operations that might need optimization (avg > 5 seconds):" -ForegroundColor Yellow
            $slowOps | Format-Table OperationName, Count, AvgDurationMs, MaxDurationMs -AutoSize
        }
        
        # Memory-intensive operations
        $memoryIntensiveOps = $telemetryData.Entries | 
            Where-Object { $_.MemoryDeltaMB -gt 50 } |
            Group-Object -Property OperationName |
            Select-Object Name, Count
            
        if ($memoryIntensiveOps) {
            Write-Host "Memory-intensive operations (delta > 50 MB):" -ForegroundColor Yellow
            $memoryIntensiveOps | Format-Table -AutoSize
        }
    }
}
catch {
    Write-Error "Failed to analyze telemetry data: $_"
}