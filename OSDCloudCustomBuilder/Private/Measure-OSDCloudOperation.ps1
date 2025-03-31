function Measure-FunctionPerformance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @(),

        [Parameter(Mandatory = $false)]
        [int]$WarningThresholdMs = 1000
    )
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @()
    )
    
    $telemetryEnabled = $true
    
    # Start timing and memory tracking
    $startTime = Get-Date
    $startMemory = [System.GC]::GetTotalMemory($false)
    $success = $false
    $errorMessage = $null
    
    try {
        # Execute the operation
        $result = if ($ArgumentList.Count -gt 0) {
            & $ScriptBlock @ArgumentList
        }
        else {
            & $ScriptBlock
        }
        
        $success = $true
        return $result
    }
    catch {
        $errorMessage = $_.Exception.Message
        throw
    }
    finally {
        # Calculate duration
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        # Log telemetry if enabled
        if ($telemetryEnabled) {
            $endMemory = [System.GC]::GetTotalMemory($false)
            $memoryDelta = $endMemory - $startMemory

            $telemetryData = @{
                Operation = $Name
                Duration = $duration
                Success = $success
                Timestamp = $startTime.ToString('o')
                Error = $errorMessage
                MemoryUsageDelta = $memoryDelta
                MemoryUsageDeltaMB = [math]::Round($memoryDelta / 1MB, 2)
            }
            
            # Log locally
            $telemetryDir = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder\Telemetry"
            if (-not (Test-Path -Path $telemetryDir)) {
                New-Item -Path $telemetryDir -ItemType Directory -Force | Out-Null
            }
            
            $telemetryFile = Join-Path -Path $telemetryDir -ChildPath "performance_$(Get-Date -Format 'yyyyMMdd').json"
            
            try {
                if (Test-Path -Path $telemetryFile) {
                    $existingData = Get-Content -Path $telemetryFile -Raw | ConvertFrom-Json
                    $existingData += $telemetryData
                    $existingData | ConvertTo-Json | Set-Content -Path $telemetryFile
                }
                else {
                    @($telemetryData) | ConvertTo-Json | Set-Content -Path $telemetryFile
                }
            }
            catch {
                Write-Warning "Failed to write telemetry data: $_"
            }
            
            # Log performance data
            Write-OSDCloudLog -Message "Operation '$Name' completed in $duration ms (Success: $success)" -Level $(if ($success) { 'Debug' } else { 'Warning' }) -Component 'Performance'
        }
    }
}

# Export the function
Export-ModuleMember -Function Measure-OSDCloudOperation