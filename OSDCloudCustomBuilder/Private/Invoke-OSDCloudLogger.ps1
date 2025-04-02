# Patched
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Provides centralized logging functionality for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This function implements a centralized logging system for the OSDCloudCustomBuilder module.
    It supports multiple log levels, timestamps, and can output to console and/or log file.
    The log file location is configurable via the OSDCloudConfig settings.
    
    This enhanced version includes:
    - Improved thread safety for concurrent logging
    - Better error handling and fallback mechanisms
    - Standardized log format with consistent metadata
    - Performance optimizations for frequent logging calls
    - Support for structured logging with context data
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
.PARAMETER Context
    Optional hashtable of contextual data to include in the log entry.
.EXAMPLE
    Invoke-OSDCloudLogger -Message "Starting process" -Level Info -Component "Initialize-BuildEnvironment"
    Logs an informational message from the Initialize-BuildEnvironment component.
.EXAMPLE
    Invoke-OSDCloudLogger -Message "Operation failed" -Level Error -Component "Add-CustomWimWithPwsh7" -Exception $_.Exception
    Logs an error message with exception details from the Add-CustomWimWithPwsh7 component.
.EXAMPLE
    Invoke-OSDCloudLogger -Message "Processing file" -Level Info -Component "Copy-FilesInParallel" -Context @{FileName = "boot.wim"; Size = "250MB"}
    Logs an informational message with additional context data.
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Invoke-OSDCloudLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true", Position = 0)]
        [ValidateNotNullOrEmpty()]
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
        [System.Exception]$Exception,
        
        [Parameter()]
        [hashtable]$Context
    )
    
    begin {
        # Use a mutex for thread-safe file access
        $mutexName = "OSDCloudLogger_Mutex"
        $mutex = $null
        
        try {
            $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        }
        catch {
            # If mutex creation fails, continue without it (logging is still valuable)
            Write-Warning "Failed to create mutex for thread-safe logging: $_"
        }
        
        # If a custom LogFile is not provided, we use the cached value if available.
        if ($LogFile) {
            $currentLogFile = $LogFile
            # Ensure the log directory exists for the provided LogFile.
            $logDir = Split-Path -Path $currentLogFile -Parent
            if (-not (Test-Path -Path $logDir)) {
                try {
                    New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                catch {
                    # Fall back to the temp directory if creation fails.
                    $currentLogFile = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
                }
            }
        }
        else {
            if (-not $script:OSDCloudLogger_CacheInitialized) {
                # Retrieve config (if available) only once
                try {
                    $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
                }
                catch {
                    $config = $null
                }
                # Determine the log file based on config or default to temp
                if ($config -and $config.LogFilePath) {
                    $script:OSDCloudLogger_LogFile = $config.LogFilePath
                }
                else {
                    $script:OSDCloudLogger_LogFile = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
                }
                # Ensure log directory exists
                $logDir = Split-Path -Path $script:OSDCloudLogger_LogFile -Parent
                if (-not (Test-Path -Path $logDir)) {
                    try {
                        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }
                    catch {
                        # Fall back to temp folder in case of error.
                        $script:OSDCloudLogger_LogFile = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
                    }
                }
                # Cache the config for future calls.
                $script:OSDCloudLogger_CacheConfig = $config
                $script:OSDCloudLogger_CacheInitialized = $true
            }
            else {
                $config = $script:OSDCloudLogger_CacheConfig
            }
            $currentLogFile = $script:OSDCloudLogger_LogFile
        }
        
        # Cache verbose and debug settings from config or fallback to current preferences.
        $verboseEnabled = if ($config -and ($null -ne $config.VerboseLogging)) {
            $config.VerboseLogging 
        }
        else {
            $VerbosePreference -ne 'SilentlyContinue'
        }
        
        $debugEnabled = if ($config -and ($null -ne $config.DebugLogging)) {
            $config.DebugLogging 
        }
        else {
            $DebugPreference -ne 'SilentlyContinue'
        }
    }
    
    process {
        # Skip verbose or debug messages if they are not enabled.
        if (
            ($Level -eq 'Verbose' -and -not $verboseEnabled) -or 
            ($Level -eq 'Debug' -and -not $debugEnabled)
        ) {
            return
        }
        
        # Format timestamp just once per log entry.
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        
        # Format exception details if provided.
        $exceptionDetails = ""
        if ($Exception) {
            $exceptionDetails = "`nException: $($Exception.GetType().FullName): $($Exception.Message)"
            if ($Exception.StackTrace) {
                $exceptionDetails += "`nStackTrace: $($Exception.StackTrace)"
            }
        }
        
        # Format context data if provided
        $contextDetails = ""
        if ($Context -and $Context.Count -gt 0) {
            $contextDetails = "`nContext: "
            foreach ($key in $Context.Keys) {
                $contextDetails += "[$key=$($Context[$key])] "
            }
        }
        
        # Format the log entry with standardized metadata.
        $logEntry = "[$timestamp] [$Level] [$Component] $Message$contextDetails$exceptionDetails"
        
        # Use mutex for thread-safe file access if available
        $mutexAcquired = $false
        try {
            if ($mutex) {
                $mutexAcquired = $mutex.WaitOne(5000) # Wait up to 5 seconds
            }
            
            # Write to log file
            try {
                Add-Content -Path $currentLogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                # If writing to log file fails, try writing to console.
                if (-not $NoConsole) {
                    Write-Warning "Failed to write to log file: $_"
                }
                
                # Try to write to the temp directory as a fallback
                try {
                    $fallbackLog = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder_Fallback.log"
                    Add-Content -Path $fallbackLog -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
                }
                catch {
                    # At this point, we've tried our best to log
                }
            }
        }
        finally {
            # Release the mutex if acquired
            if ($mutex -and $mutexAcquired) {
                $mutex.ReleaseMutex()
            }
        }
        
        # Write log entry to console if not disabled.
        if (-not $NoConsole) {
            switch ($Level) {
                'Info' { Write-Verbose $logEntry }
                'Warning' { Write-Warning $logEntry }
                'Error' { Write-Error $logEntry }
                'Debug' { Write-Debug $logEntry }
                'Verbose' { Write-Verbose $logEntry }
            }
        }
    }
    
    end {
        # Clean up mutex if created
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}