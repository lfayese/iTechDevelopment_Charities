<#
.SYNOPSIS
    Provides centralized logging functionality for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This function implements a centralized logging system for the OSDCloudCustomBuilder module.
    It supports multiple log levels, timestamps, and can output to console and/or log file.
    The log file location is configurable via the OSDCloudConfig settings.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    The log level. Valid values are 'Info', 'Warning', 'Error', 'Debug', and 'Verbose'.
    Default is 'Info'.
.PARAMETER Component
    The component name that is generating the log entry.
.PARAMETER LogFile
    Optional path to a log file. If not specified, the log file path from OSDCloudConfig will be used.
.PARAMETER NoConsole
    If specified, the message will not be written to the console.
.PARAMETER Exception
    An exception object to include in the log entry.
.EXAMPLE
    Invoke-OSDCloudLogger -Message "Starting process" -Level Info -Component "Initialize-BuildEnvironment"
    Logs an informational message from the Initialize-BuildEnvironment component.
.EXAMPLE
    Invoke-OSDCloudLogger -Message "Operation failed" -Level Error -Component "Add-CustomWimWithPwsh7" -Exception $_.Exception
    Logs an error message with exception details from the Add-CustomWimWithPwsh7 component.
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Invoke-OSDCloudLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug', 'Verbose')]
        [string]$Level = 'Info',
        
        [Parameter(Position = 2)]
        [string]$Component = 'OSDCloudCustomBuilder',
        
        [Parameter()]
        [string]$LogFile,
        
        [Parameter()]
        [switch]$NoConsole,
        
        [Parameter()]
        [System.Exception]$Exception
    )
    
    begin {
        # Get configuration if available
        try {
            $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
        }
        catch {
            $config = $null
        }
        
        # Determine log file path
        if (-not $LogFile) {
            if ($config -and $config.LogFilePath) {
                $LogFile = $config.LogFilePath
            }
            else {
                $LogFile = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
            }
        }
        
        # Ensure log directory exists
        $logDir = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -Path $logDir)) {
            try {
                New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                # If we can't create the log directory, fall back to temp
                $LogFile = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
            }
        }
        
        # Get verbose and debug preferences from config or use current settings
        $verboseEnabled = if ($config -and ($null -ne $config.VerboseLogging)) { 
            $config.VerboseLogging 
        } else { 
            $VerbosePreference -ne 'SilentlyContinue' 
        }
        
        $debugEnabled = if ($config -and ($null -ne $config.DebugLogging)) { 
            $config.DebugLogging 
        } else { 
            $DebugPreference -ne 'SilentlyContinue' 
        }
    }
    
    process {
        # Skip verbose or debug messages if not enabled
        if (($Level -eq 'Verbose' -and -not $verboseEnabled) -or 
            ($Level -eq 'Debug' -and -not $debugEnabled)) {
            return
        }
        
        # Format timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        
        # Format exception details if provided
        $exceptionDetails = ""
        if ($Exception) {
            $exceptionDetails = "`nException: $($Exception.GetType().FullName): $($Exception.Message)"
            if ($Exception.StackTrace) {
                $exceptionDetails += "`nStackTrace: $($Exception.StackTrace)"
            }
        }
        
        # Format the log entry
        $logEntry = "[$timestamp] [$Level] [$Component] $Message$exceptionDetails"
        
        # Write to log file
        try {
            Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # If writing to log file fails, at least try to write to console
            if (-not $NoConsole) {
                Write-Warning "Failed to write to log file: $_"
            }
        }
        
        # Write to console if not disabled
        if (-not $NoConsole) {
            switch ($Level) {
                'Info' { 
                    Write-Host $logEntry 
                }
                'Warning' { 
                    Write-Warning $logEntry.Replace("[$Level] ", "") 
                }
                'Error' { 
                    Write-Error $logEntry.Replace("[$Level] ", "") 
                }
                'Debug' { 
                    Write-Debug $logEntry.Replace("[$Level] ", "") 
                }
                'Verbose' { 
                    Write-Verbose $logEntry.Replace("[$Level] ", "") 
                }
            }
        }
    }
}