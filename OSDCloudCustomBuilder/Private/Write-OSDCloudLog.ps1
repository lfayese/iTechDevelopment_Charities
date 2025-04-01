<#
.SYNOPSIS
    Writes log messages to a centralized log file for OSDCloud operations.
.DESCRIPTION
    This function writes log messages with specified severity levels to a centralized log file.
    It supports Info, Warning, and Error levels and includes contextual information such as
    the function name and exception details.
.PARAMETER Message
    The log message to write.
.PARAMETER Level
    The severity level of the log message (Info, Warning, Error).
.PARAMETER Component
    The name of the function or component generating the log message.
.PARAMETER Exception
    (Optional) The exception object to include in the log message.
.EXAMPLE
    Write-OSDCloudLog -Message "Operation completed successfully" -Level Info -Component "Initialize-WinPEMountPoint"
.EXAMPLE
    Write-OSDCloudLog -Message "Failed to mount image" -Level Error -Component "Mount-WinPEImage" -Exception $_.Exception
.NOTES
    Author: OSDCloud Team
    Version: 1.0.0
#>
function Write-OSDCloudLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Component,
        [Parameter()]
        [System.Exception]$Exception
    )
    
    # Cache the log directory in a script-scoped variable for performance 
    if (-not $script:LogDirectory) {
        $script:LogDirectory = Join-Path -Path $env:ProgramData -ChildPath "OSDCloud\Logs"
        if (-not (Test-Path -Path $script:LogDirectory)) {
            New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
        }
    }
    
    # Build the log file path and log entry using a single call to Get-Date for timestamp
    $dateNow = Get-Date
    $logFile = Join-Path -Path $script:LogDirectory -ChildPath ("OSDCloud-Log-$($dateNow.ToString('yyyyMMdd')).log")
    $timestamp = $dateNow.ToString('yyyy-MM-dd HH:mm:ss')
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    if ($Exception) {
        $logEntry += " | Exception: $($Exception.Message)"
    }
    
    # Use Add-Content for appending log entry
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    
    # Optionally provide real-time console feedback based on severity
    switch ($Level) {
        'Error'   { Write-Error $logEntry; break }
        'Warning' { Write-Warning $logEntry; break }
        default   { Write-Host $logEntry }
    }
}
# Export the function
Export-ModuleMember -Function Write-OSDCloudLog