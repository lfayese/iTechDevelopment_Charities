<#
.SYNOPSIS
    Measures and logs performance metrics for OSDCloud operations.
.DESCRIPTION
    This function wraps a scriptblock with performance measurement code to track
    execution time, memory usage, and success/failure status. It provides detailed
    performance telemetry and can issue warnings when operations exceed specified
    duration thresholds. The function supports passing arguments to the scriptblock
    and handles exceptions properly.
.PARAMETER Name
    A descriptive name for the operation being measured. This name is used in logs
    and telemetry data.
.PARAMETER ScriptBlock
    The scriptblock containing the operation code to execute and measure.
.PARAMETER ArgumentList
    An optional array of arguments to pass to the scriptblock.
.PARAMETER WarningThresholdMs
    The threshold in milliseconds above which a warning will be logged.
    Default is 1000ms (1 second).
.PARAMETER DisableTelemetry
    If specified, disables telemetry logging for this operation.
.EXAMPLE
    Measure-OSDCloudOperation -Name "Copy WIM File" -ScriptBlock {
        Copy-Item -Path $source -Destination $target
    }
    Measures the performance of a simple file copy operation.
.EXAMPLE
    Measure-OSDCloudOperation -Name "Mount WIM" -ScriptBlock {
        param($path, $mountPoint)
        Mount-WindowsImage -ImagePath $path -Path $mountPoint -Index 1
    } -ArgumentList @("C:\install.wim", "C:\mount") -WarningThresholdMs 5000
    Measures a WIM mounting operation with arguments and a custom warning threshold.
.NOTES
    The function requires Write-OSDCloudLog and Add-PerformanceLogEntry to be available
    for logging telemetry data.
#>
function Measure-OSDCloudOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @(),
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$WarningThresholdMs = 1000,
        
        [Parameter(Mandatory = $false)]
        [switch]$DisableTelemetry
    )
    
    # Determine if telemetry is enabled based on parameter and/or configuration
    $telemetryEnabled = -not $DisableTelemetry
    
    try {
        # Get configuration if available
        if (Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue) {
            $config = Get-ModuleConfiguration
            # If telemetry is explicitly disabled in config, honor that setting
            if ($config.ContainsKey('Telemetry') -and 
                $config.Telemetry.ContainsKey('Enabled') -and 
                $config.Telemetry.Enabled -eq $false) {
                $telemetryEnabled = $false
            }
        }
    }
    catch {
        # If we can't get config, just continue with default telemetry setting
        Write-Verbose "Could not retrieve module configuration: $_"
    }
    
    # Start timing and memory tracking
    $startTime = Get-Date
    $startMemory = [System.GC]::GetTotalMemory($false)
    $success = $false
    $errorMessage = $null
    $exception = $null
    
    try {
        # Log operation start if telemetry is enabled
        if ($telemetryEnabled) {
            try {
                Write-OSDCloudLog -Message "Starting operation: '$Name'" -Level Debug -Component 'Performance'
            }
            catch {
                # Don't fail if logging fails
                Write-Verbose "Failed to log operation start: $_"
            }
        }
        
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
        $exception = $_
        # Re-throw the exception to maintain proper error handling
        throw
    }
    finally {
        # Calculate duration
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        # Check if duration exceeds warning threshold
        if ($duration -gt $WarningThresholdMs) {
            Write-Warning "Operation '$Name' took longer than expected: $($duration.ToString('N2')) ms (threshold: $WarningThresholdMs ms)"
        }
        
        # Log telemetry if enabled
        if ($telemetryEnabled) {
            try {
                $endMemory = [System.GC]::GetTotalMemory($false)
                $memoryDelta = $endMemory - $startMemory
                $telemetryData = @{
                    Operation = $Name
                    Duration = [math]::Round($duration, 2)
                    Success = $success
                    Timestamp = $startTime.ToString('o')
                    Error = $errorMessage
                    MemoryUsageDelta = $memoryDelta
                    MemoryUsageDeltaMB = [math]::Round($memoryDelta / 1MB, 2)
                }
                
                # Log performance data
                $logLevel = if ($success) { 'Debug' } else { 'Warning' }
                $logMessage = "Operation '$Name' completed in $($duration.ToString('N2')) ms (Success: $success)"
                if (-not $success -and $errorMessage) {
                    $logMessage += ", Error: $errorMessage"
                }
                
                Write-OSDCloudLog -Message $logMessage -Level $logLevel -Component 'Performance' -Exception $(if (-not $success) { $exception } else { $null })
                
                # Add performance log entry if the function is available
                if (Get-Command -Name Add-PerformanceLogEntry -ErrorAction SilentlyContinue) {
                    Add-PerformanceLogEntry -OperationName $Name -DurationMs $duration -Outcome $(if ($success) { 'Success' } else { 'Failure' }) -ResourceUsage @{
                        MemoryDeltaMB = $telemetryData.MemoryUsageDeltaMB
                    } -AdditionalData $telemetryData
                }
            }
            catch {
                # Don't fail if telemetry logging fails
                Write-Verbose "Failed to log performance telemetry: $_"
            }
        }
        
        # Force garbage collection to clean up resources
        [System.GC]::Collect()
    }
}

# Export the function
Export-ModuleMember -Function Measure-OSDCloudOperation