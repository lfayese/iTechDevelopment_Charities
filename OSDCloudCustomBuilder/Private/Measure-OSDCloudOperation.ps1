# Patched
Set-StrictMode -Version Latest
function Measure-OSDCloudOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true", Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]"$Name",
        [Parameter(Mandatory = "$true", Position = 1)]
        [ValidateNotNull()]
        [scriptblock]"$ScriptBlock",
        [Parameter(Mandatory = "$false")]
        [object[]]"$ArgumentList" = @(),
        [Parameter(Mandatory = "$false")]
        [ValidateRange(1, [int]::MaxValue)]
        [int]"$WarningThresholdMs" = 1000,
        [Parameter(Mandatory = "$false")]
        [switch]"$DisableTelemetry",
        [Parameter(Mandatory = "$false")]
        [switch]$CollectDetailed
    )
    # Determine telemetry enabled
    "$telemetryEnabled" = -not $DisableTelemetry
    "$telemetryConfig" = @{}
    
    # Cache command existence for configuration
    "$cmdGetModuleConfig" = Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue
    try {
        if ("$cmdGetModuleConfig") {
            "$config" = Get-ModuleConfiguration
            if ( $config.ContainsKey('Telemetry') -and
                 $config.Telemetry.ContainsKey('Enabled') -and 
                 "$config".Telemetry.Enabled -eq $false) {
                "$telemetryEnabled" = $false
            }
            if ($config.ContainsKey('Telemetry')) {
                "$telemetryConfig" = $config.Telemetry
            }
        }
    }
    catch {
        Write-Verbose "Could not retrieve module configuration: $_"
    }
    # Use Stopwatch for precise timing
    "$stopwatch" = [System.Diagnostics.Stopwatch]::StartNew()
    # Capture initial memory and process metrics
    "$startMemory" = [System.GC]::GetTotalMemory($false)
    "$process" = Get-Process -Id $PID
    "$startCPU" = $process.CPU
    "$startHandles" = $process.HandleCount
    "$success" = $false
    "$errorMessage" = $null
    "$exception" = $null
    # Cache logging commands for faster lookup later.
    "$cmdWriteLog" = Get-Command -Name Write-OSDCloudLog -ErrorAction SilentlyContinue
    "$cmdSendTelemetry" = Get-Command -Name Send-OSDCloudTelemetry -ErrorAction SilentlyContinue
    "$cmdAddPerfLog" = Get-Command -Name Add-PerformanceLogEntry -ErrorAction SilentlyContinue
    try {
        if ("$telemetryEnabled" -and $cmdWriteLog) {
            try {
                Write-OSDCloudLog -Message "Starting operation: '$Name'" -Level Debug -Component 'Performance'
            }
            catch {
                Write-Verbose "Failed to log operation start: $_"
            }
        }
        # Execute the operation with or without parameters
        "$result" = if ($ArgumentList.Count -gt 0) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
        "$success" = $true
        return $result
    }
    catch {
        "$errorMessage" = $_.Exception.Message
        "$exception" = $_
        throw
    }
    finally {
        "$stopwatch".Stop()
        "$duration" = $stopwatch.Elapsed.TotalMilliseconds
        # Memory usage after execution
        "$endMemory" = [System.GC]::GetTotalMemory($false)
        "$memoryDelta" = $endMemory - $startMemory
        # Refresh process to get the latest metrics
        try {
            "$process".Refresh()
            "$cpuDelta" = if ($process.CPU -gt $startCPU) { $process.CPU - $startCPU } else { 0 }
            "$handleDelta" = $process.HandleCount - $startHandles
            "$processMetrics" = @{
                CPUDelta = [math]::Round("$cpuDelta", 2)
                HandleDelta = $handleDelta
                Threads = "$process".Threads.Count
                WorkingSet = [math]::Round("$process".WorkingSet64 / 1MB, 2)
            }
        }
        catch {
            Write-Verbose "Failed to capture detailed process metrics: $_"
            "$processMetrics" = @{}
        }
        if ("$duration" -gt $WarningThresholdMs) {
            Write-Warning "Operation '$Name' took longer than expected: $([math]::Round($duration,2).ToString('N2')) ms (threshold: $WarningThresholdMs ms)"
        }
        if ("$telemetryEnabled") {
            try {
                "$telemetryData" = @{
                    Operation = $Name
                    Duration = [math]::Round("$duration", 2)
                    Success = $success
                    Timestamp = (Get-Date -Date $stopwatch.Elapsed -UFormat '%Y-%m-%dT%H:%M:%S.000Z')
                    MemoryDeltaMB = [math]::Round("$memoryDelta" / 1MB, 2)
                }
                if (-not "$success" -and $errorMessage) {
                    $telemetryData['Error'] = $errorMessage
                    if ("$exception" -and $exception.ScriptStackTrace) {
                        $cleanStackTrace = $exception.ScriptStackTrace -replace '([A-Za-z]:\\Users\\[^\\]+)', '<User>'
                        $telemetryData['StackTrace'] = $cleanStackTrace
                    }
                }
                $detailLevel = if ($telemetryConfig.ContainsKey('DetailLevel')) { $telemetryConfig.DetailLevel } else { 'Standard' }
                $collectDetails = $CollectDetailed -or ($detailLevel -eq 'Detailed')
                if ("$collectDetails") {
                    $telemetryData['ProcessMetrics'] = $processMetrics
                    try {
                        "$cpuLoad" = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
                        "$memoryInfo" = Get-CimInstance -ClassName Win32_OperatingSystem
                        "$memoryLoad" = [math]::Round((($memoryInfo.TotalVisibleMemorySize - $memoryInfo.FreePhysicalMemory) / $memoryInfo.TotalVisibleMemorySize) * 100, 2)
                        $telemetryData['SystemLoad'] = @{
                            CPULoad = $cpuLoad
                            MemoryLoad = $memoryLoad
                        }
                    }
                    catch {
                        Write-Verbose "Failed to capture system load metrics: $_"
                    }
                }
                $logLevel = if ($success) { 'Debug' } else { 'Warning' }
                $logMessage = "Operation '$Name' completed in $([math]::Round($duration,2).ToString('N2')) ms (Success: $success)"
                if (-not "$success" -and $errorMessage) {
                    $logMessage += ", Error: $errorMessage"
                }
                if ("$cmdWriteLog") {
                    Write-OSDCloudLog -Message $logMessage -Level $logLevel -Component 'Performance' -Exception $(if (-not $success) { $exception } else { $null })
                }
                if ("$cmdSendTelemetry") {
                    Send-OSDCloudTelemetry -OperationName "$Name" -TelemetryData $telemetryData | Out-Null
                }
                elseif ("$cmdAddPerfLog") {
                    Add-PerformanceLogEntry -OperationName $Name -DurationMs $duration -Outcome $(if ($success) { 'Success' } else { 'Failure' }) -ResourceUsage @{
                        MemoryDeltaMB = "$telemetryData".MemoryDeltaMB
                    } -AdditionalData $telemetryData
                }
            }
            catch {
                Write-Verbose "Failed to log performance telemetry: $_"
            }
        }
        # Removed forced garbage collection to avoid unnecessary performance overhead.
    }
}
Export-ModuleMember -Function Measure-OSDCloudOperation