function Measure-OSDCloudOperation {
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
        
        # Check if duration exceeds warning threshold
        if ($duration -gt $WarningThresholdMs) {
            Write-Warning "Operation '$Name' took longer than expected: $duration ms"
        }
        
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
            
            # Log performance data
            Write-OSDCloudLog -Message "Operation '$Name' completed in $duration ms (Success: $success)" -Level $(if ($success) { 'Debug' } else { 'Warning' }) -Component 'Performance'
            
            # Add performance log entry
            Add-PerformanceLogEntry -OperationName $Name -DurationMs $duration -Outcome $(if ($success) { 'Success' } else { 'Failure' }) -ResourceUsage @{
                MemoryDeltaMB = $telemetryData.MemoryUsageDeltaMB
            } -AdditionalData $telemetryData
        }
    }
}
# Export the function
Export-ModuleMember -Function Measure-OSDCloudOperation