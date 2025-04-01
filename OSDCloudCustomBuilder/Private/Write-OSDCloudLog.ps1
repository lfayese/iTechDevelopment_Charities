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

    # Define log directory and file
    $logDirectory = Join-Path -Path "$env:ProgramData" -ChildPath "OSDCloud\Logs"
    if (-not (Test-Path -Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    $logFile = Join-Path -Path $logDirectory -ChildPath "OSDCloud-Log-$(Get-Date -Format 'yyyyMMdd').log"

    # Build log entry
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"

    if ($Exception) {
        $logEntry += " | Exception: $($Exception.Message)"
    }

    # Write to log file
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8

    # Optionally write to console for real-time feedback
    if ($Level -eq 'Error') {
        Write-Error $logEntry
    } elseif ($Level -eq 'Warning') {
        Write-Warning $logEntry
    } else {
        Write-Host $logEntry
    }
}

# Export the function
Export-ModuleMember -Function Write-OSDCloudLog