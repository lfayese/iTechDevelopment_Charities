<#
.SYNOPSIS
    Centralized logging and error handling module for OSDCloud deployment scripts.
.DESCRIPTION
    This module provides standardized logging and error handling functions for all OSDCloud scripts.
    It supports different log levels, log file rotation, and structured error handling with recovery options.
.NOTES
    Created for: Charity OSDCloud Deployment
    Author: iTech Development
    Date: March 30, 2025
#>

# Define global variables for logging
$script:LogPath = "$env:TEMP\OSDCloud\Logs"
$script:LogFile = "OSDCloud_$(Get-Date -Format 'yyyyMMdd').log"
$script:LogRotationDays = 7
$script:LogLevel = "Info" # Possible values: Debug, Info, Warning, Error, Fatal
$script:LogLevels = @{
    "Debug"   = 0
    "Info"    = 1
    "Warning" = 2
    "Error"   = 3
    "Fatal"   = 4
}
$script:LogInitialized = $false
$script:ErrorCollection = @()

# Initialize the logging system
function Initialize-OSDCloudLogger {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = "$env:TEMP\OSDCloud\Logs",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFileName = "OSDCloud_$(Get-Date -Format 'yyyyMMdd').log",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Fatal")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [int]$RotationDays = 7
    )
    
    try {
        # Set global variables
        $script:LogPath = $LogDirectory
        $script:LogFile = $LogFileName
        $script:LogLevel = $Level
        $script:LogRotationDays = $RotationDays
        
        # Create log directory if it doesn't exist
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        # Perform log rotation
        Invoke-OSDCloudLogRotation
        
        # Create log file if it doesn't exist
        $fullLogPath = Join-Path -Path $script:LogPath -ChildPath $script:LogFile
        if (-not (Test-Path -Path $fullLogPath)) {
            New-Item -Path $fullLogPath -ItemType File -Force | Out-Null
        }
        
        # Log initialization
        $message = "OSDCloud Logging initialized at level: $Level"
        Write-OSDCloudLog -Message $message -Level "Info" -NoConsole
        
        $script:LogInitialized = $true
        return $true
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
        return $false
    }
}

# Rotate log files
function Invoke-OSDCloudLogRotation {
    [CmdletBinding()]
    param()
    
    try {
        # Get all log files
        $logFiles = Get-ChildItem -Path $script:LogPath -Filter "OSDCloud_*.log" -ErrorAction SilentlyContinue
        
        # Delete log files older than rotation days
        $cutoffDate = (Get-Date).AddDays(-$script:LogRotationDays)
        $logFiles | Where-Object { $_.LastWriteTime -lt $cutoffDate } | ForEach-Object {
            Remove-Item -Path $_.FullName -Force
        }
    }
    catch {
        Write-Warning "Failed to rotate log files: $_"
    }
}

# Write to log file
function Write-OSDCloudLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Fatal")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )
    
    # Initialize logging if not already done
    if (-not $script:LogInitialized) {
        Initialize-OSDCloudLogger
    }
    
    # Check if message should be logged based on current log level
    if ($script:LogLevels[$Level] -ge $script:LogLevels[$script:LogLevel]) {
        # Format the log entry
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Write to log file
        $fullLogPath = Join-Path -Path $script:LogPath -ChildPath $script:LogFile
        Add-Content -Path $fullLogPath -Value $logEntry
        
        # Write to console if not suppressed
        if (-not $NoConsole) {
            $consoleColor = switch ($Level) {
                "Debug"   { "Gray" }
                "Info"    { "White" }
                "Warning" { "Yellow" }
                "Error"   { "Red" }
                "Fatal"   { "DarkRed" }
                default   { "White" }
            }
            
            Write-Host $logEntry -ForegroundColor $consoleColor
        }
    }
}

# Handle errors with standardized approach
function Write-OSDCloudError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = "OSDCloud",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Warning", "Error", "Fatal")]
        [string]$Level = "Error",
        
        [Parameter(Mandatory = $false)]
        [switch]$Throw
    )
    
    # Construct error message
    $errorMessage = "$Message"
    
    # Add error record details if available
    if ($ErrorRecord) {
        $errorMessage += " | ErrorDetails: $($ErrorRecord.Exception.Message)"
        $errorMessage += " | ScriptStackTrace: $($ErrorRecord.ScriptStackTrace)"
    }
    
    # Add to error collection
    $script:ErrorCollection += [PSCustomObject]@{
        Timestamp = Get-Date
        Component = $Component
        Level = $Level
        Message = $Message
        ErrorRecord = $ErrorRecord
    }
    
    # Log the error
    Write-OSDCloudLog -Message $errorMessage -Level $Level
    
    # Throw if requested
    if ($Throw) {
        throw $Message
    }
}

# Attempt to recover from error
function Invoke-OSDCloudErrorRecovery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [array]$Arguments = @()
    )
    
    $retryCount = 0
    $success = $false
    $lastError = $null
    
    while (-not $success -and $retryCount -lt $MaxRetries) {
        try {
            if ($retryCount -gt 0) {
                Write-OSDCloudLog -Message "Retrying operation '$Operation' (Attempt $($retryCount + 1) of $MaxRetries)" -Level "Warning"
                Start-Sleep -Seconds $RetryDelaySeconds
            }
            
            if ($Arguments.Count -gt 0) {
                $result = & $ScriptBlock @Arguments
            }
            else {
                $result = & $ScriptBlock
            }
            
            $success = $true
            return $result
        }
        catch {
            $lastError = $_
            $retryCount++
            
            Write-OSDCloudError -Message "Failed during operation '$Operation' (Attempt $retryCount of $MaxRetries)" -ErrorRecord $_ -Component $Operation
            
            # If we've exhausted retries, log a fatal error
            if ($retryCount -ge $MaxRetries) {
                Write-OSDCloudError -Message "Operation '$Operation' failed after $MaxRetries attempts" -ErrorRecord $_ -Level "Fatal" -Component $Operation
            }
        }
    }
    
    # If we get here, all retries failed
    throw $lastError
}

# Get a summary of all errors
function Get-OSDCloudErrorSummary {
    [CmdletBinding()]
    param()
    
    return $script:ErrorCollection
}

# Check if a dependency is installed
function Test-OSDCloudDependency {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion,
        
        [Parameter(Mandatory = $false)]
        [switch]$Required
    )
    
    $dependencyFound = $false
    
    switch -Regex ($Name) {
        # PowerShell module
        '^Module:(.+)' {
            $moduleName = $matches[1].Trim()
            $module = Get-Module -Name $moduleName -ListAvailable
            
            if ($module) {
                $dependencyFound = $true
                
                if ($MinimumVersion) {
                    $dependencyFound = [version]($module | Sort-Object Version -Descending | Select-Object -First 1).Version -ge [version]$MinimumVersion
                }
            }
            
            Write-OSDCloudLog -Message "Dependency check: Module '$moduleName' $(if($dependencyFound){'found'}else{'not found'})$(if($MinimumVersion){" (Required version: $MinimumVersion)"})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
        }
        
        # Executable
        '^Exe:(.+)' {
            $exeName = $matches[1].Trim()
            $exePath = Get-Command -Name $exeName -ErrorAction SilentlyContinue
            
            $dependencyFound = $null -ne $exePath
            
            Write-OSDCloudLog -Message "Dependency check: Executable '$exeName' $(if($dependencyFound){'found'}else{'not found'})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
        }
        
        # Windows feature
        '^Feature:(.+)' {
            $featureName = $matches[1].Trim()
            
            try {
                $feature = Get-WindowsOptionalFeature -FeatureName $featureName -Online -ErrorAction Stop
                $dependencyFound = $feature.State -eq "Enabled"
            }
            catch {
                $dependencyFound = $false
            }
            
            Write-OSDCloudLog -Message "Dependency check: Windows Feature '$featureName' $(if($dependencyFound){'enabled'}else{'not enabled'})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
        }
        
        # Default - treat as PowerShell module
        default {
            $module = Get-Module -Name $Name -ListAvailable
            
            if ($module) {
                $dependencyFound = $true
                
                if ($MinimumVersion) {
                    $dependencyFound = [version]($module | Sort-Object Version -Descending | Select-Object -First 1).Version -ge [version]$MinimumVersion
                }
            }
            
            Write-OSDCloudLog -Message "Dependency check: Module '$Name' $(if($dependencyFound){'found'}else{'not found'})$(if($MinimumVersion){" (Required version: $MinimumVersion)"})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
        }
    }
    
    if ($Required -and -not $dependencyFound) {
        Write-OSDCloudError -Message "Required dependency '$Name' not found" -Level "Fatal" -Component "DependencyCheck" -Throw
    }
    
    return $dependencyFound
}

# Export functions
Export-ModuleMember -Function Initialize-OSDCloudLogger, Write-OSDCloudLog, Write-OSDCloudError, 
                              Invoke-OSDCloudErrorRecovery, Get-OSDCloudErrorSummary, Test-OSDCloudDependency