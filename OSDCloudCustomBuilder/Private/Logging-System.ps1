<#
.SYNOPSIS
    Enhanced logging system integrated with the module configuration.
.DESCRIPTION
    Provides standardized logging functions that respect module configuration settings
    and support multiple output destinations including console, file, and eventlog.
.NOTES
    Version: 0.3.0
    Author: OSDCloud Team
#>

# Define supported log levels
enum LogLevel {
    Debug
    Info
    Warning
    Error
    Critical
}

# Class to track log statistics
class LogStatistics {
    [int]$DebugCount = 0
    [int]$InfoCount = 0
    [int]$WarningCount = 0
    [int]$ErrorCount = 0
    [int]$CriticalCount = 0
    [datetime]$StartTime = [datetime]::Now
    
    [void] IncrementCounter([LogLevel]$level) {
        switch ($level) {
            ([LogLevel]::Debug) { $this.DebugCount++ }
            ([LogLevel]::Info) { $this.InfoCount++ }
            ([LogLevel]::Warning) { $this.WarningCount++ }
            ([LogLevel]::Error) { $this.ErrorCount++ }
            ([LogLevel]::Critical) { $this.CriticalCount++ }
        }
    }
    
    [int] GetTotalCount() {
        return $this.DebugCount + $this.InfoCount + $this.WarningCount + $this.ErrorCount + $this.CriticalCount
    }
}

# Initialize log statistics
$script:LogStats = [LogStatistics]::new()

# Initialize log file details
$script:LogFile = $null
$script:LogFileStream = $null
$script:LogWriter = $null

<#
.SYNOPSIS
    Initializes the logging system based on module configuration.
.DESCRIPTION
    Sets up the logging system according to the module configuration settings.
    Creates log files, establishes eventlog sources, and configures behavior.
.PARAMETER Force
    If specified, reinitializes the logging system even if already initialized.
.EXAMPLE
    Initialize-OSDCloudLogging -Force
#>
function Initialize-OSDCloudLogging {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$Force
    )
    
    # Skip initialization if already done unless Force is specified
    if ($script:LogFile -and -not $Force) {
        Write-Verbose "Logging system already initialized. Use -Force to reinitialize."
        return
    }
    
    # Close existing log file if any
    if ($script:LogWriter) {
        try {
            $script:LogWriter.Close()
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
        }
        catch {
            Write-Warning "Error closing existing log writer: $_"
        }
    }
    
    if ($script:LogFileStream) {
        try {
            $script:LogFileStream.Close()
            $script:LogFileStream.Dispose()
            $script:LogFileStream = $null
        }
        catch {
            Write-Warning "Error closing existing log file stream: $_"
        }
    }
    
    # Get logging configuration from module settings
    try {
        $config = Get-ModuleConfiguration
        
        # Default log path if not in config or config loading fails
        $logPath = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
        
        # Use configured log path if available
        if ($config -and $config.ContainsKey('LogPath')) {
            $logPath = $config.LogPath
        }
        
        # Create directory if it doesn't exist
        $logDir = Split-Path -Path $logPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force
        }
        
        # Set up file logging
        $script:LogFile = $logPath
        $script:LogFileStream = [System.IO.FileStream]::new($script:LogFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $script:LogWriter = [System.IO.StreamWriter]::new($script:LogFileStream)
        
        # Additional logging settings
        $script:EnableConsoleLogging = $true
        $script:EnableFileLogging = $true
        $script:EnableEventLogging = $false
        $script:MinimumLogLevel = [LogLevel]::Info
        
        # Override defaults with config values if present
        if ($config) {
            if ($config.ContainsKey('Logging')) {
                $logConfig = $config.Logging
                
                if ($logConfig.ContainsKey('EnableConsoleLogging')) {
                    $script:EnableConsoleLogging = $logConfig.EnableConsoleLogging
                }
                
                if ($logConfig.ContainsKey('EnableFileLogging')) {
                    $script:EnableFileLogging = $logConfig.EnableFileLogging
                }
                
                if ($logConfig.ContainsKey('EnableEventLogging')) {
                    $script:EnableEventLogging = $logConfig.EnableEventLogging
                }
                
                if ($logConfig.ContainsKey('MinimumLogLevel')) {
                    $levelName = $logConfig.MinimumLogLevel
                    if ([Enum]::TryParse([LogLevel], $levelName, [ref]$null)) {
                        $script:MinimumLogLevel = [LogLevel]$levelName
                    }
                }
            }
            
            # Handle EnableVerboseLogging as a shortcut to set debug level
            if ($config.ContainsKey('EnableVerboseLogging') -and $config.EnableVerboseLogging) {
                $script:MinimumLogLevel = [LogLevel]::Debug
            }
        }
        
        # Set up EventLog source if enabled
        if ($script:EnableEventLogging) {
            $source = "OSDCloudCustomBuilder"
            $logName = "Application"
            
            # Check if the source exists, create if not (requires admin)
            if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
                try {
                    [System.Diagnostics.EventLog]::CreateEventSource($source, $logName)
                    Write-Verbose "Created EventLog source: $source"
                }
                catch {
                    Write-Warning "Failed to create EventLog source: $_"
                    $script:EnableEventLogging = $false
                }
            }
        }
        
        # Log initialization info
        $initMessage = "Logging initialized. File: $script:LogFile, Level: $script:MinimumLogLevel, Outputs: "
        $outputs = @()
        if ($script:EnableConsoleLogging) { $outputs += "Console" }
        if ($script:EnableFileLogging) { $outputs += "File" }
        if ($script:EnableEventLogging) { $outputs += "EventLog" }
        $initMessage += ($outputs -join ", ")
        
        Write-Verbose $initMessage
        if ($script:EnableFileLogging) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $script:LogWriter.WriteLine("[$timestamp] [Info] $initMessage")
            $script:LogWriter.Flush()
        }
        
        # Reset statistics
        $script:LogStats = [LogStatistics]::new()
    }
    catch {
        # Fallback to console-only logging if initialization fails
        Write-Warning "Failed to initialize logging system: $_"
        $script:EnableConsoleLogging = $true
        $script:EnableFileLogging = $false
        $script:EnableEventLogging = $false
        $script:MinimumLogLevel = [LogLevel]::Info
    }
}

<#
.SYNOPSIS
    Writes a log message to configured destinations with integrated configuration support.
.DESCRIPTION
    Records log entries to file, console, and/or event log based on module configuration.
    Respects minimum log level settings and handles format consistency.
.PARAMETER Message
    The message to be logged.
.PARAMETER Level
    The severity level of the log message.
.PARAMETER NoTimestamp
    If specified, omits the timestamp prefix in console output.
.PARAMETER Component
    Optional component name to identify the source of the log.
.EXAMPLE
    Write-OSDCloudLog -Message "Processing completed successfully" -Level Info
.EXAMPLE
    Write-OSDCloudLog -Message "Failed to access network resource" -Level Error -Component "NetworkAccess"
#>
function Write-OSDCloudLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [LogLevel]$Level = [LogLevel]::Info,
        
        [Parameter()]
        [switch]$NoTimestamp,
        
        [Parameter()]
        [string]$Component = ""
    )
    
    # Initialize logging if not already done
    if (-not $script:LogFile) {
        Initialize-OSDCloudLogging
    }
    
    # Track log statistics
    $script:LogStats.IncrementCounter($Level)
    
    # Skip logging if below minimum level
    if ([int]$Level -lt [int]$script:MinimumLogLevel) {
        return
    }
    
    # Format message
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $componentText = if ($Component) { "[$Component] " } else { "" }
    $formattedMessage = "[$timestamp] [$Level] $componentText$Message"
    $consoleMessage = if ($NoTimestamp) { "[$Level] $componentText$Message" } else { $formattedMessage }
    
    # Write to console if enabled
    if ($script:EnableConsoleLogging) {
        switch ($Level) {
            ([LogLevel]::Debug) { 
                Write-Verbose $consoleMessage 
            }
            ([LogLevel]::Info) { 
                Write-Host $consoleMessage 
            }
            ([LogLevel]::Warning) { 
                Write-Warning $Message 
            }
            ([LogLevel]::Error) { 
                $host.UI.WriteErrorLine($consoleMessage) 
            }
            ([LogLevel]::Critical) {
                $currentColor = $host.UI.RawUI.ForegroundColor
                $host.UI.RawUI.ForegroundColor = 'Red'
                Write-Host $consoleMessage -ForegroundColor Red -BackgroundColor Black
                $host.UI.RawUI.ForegroundColor = $currentColor
            }
        }
    }
    
    # Write to file if enabled
    if ($script:EnableFileLogging -and $script:LogWriter) {
        try {
            $script:LogWriter.WriteLine($formattedMessage)
            $script:LogWriter.Flush()
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
            $script:EnableFileLogging = $false
        }
    }
    
    # Write to EventLog if enabled
    if ($script:EnableEventLogging) {
        try {
            $eventType = switch ($Level) {
                ([LogLevel]::Debug) { "Information" }
                ([LogLevel]::Info) { "Information" }
                ([LogLevel]::Warning) { "Warning" }
                ([LogLevel]::Error) { "Error" }
                ([LogLevel]::Critical) { "Error" }
            }
            
            $eventId = switch ($Level) {
                ([LogLevel]::Debug) { 100 }
                ([LogLevel]::Info) { 200 }
                ([LogLevel]::Warning) { 300 }
                ([LogLevel]::Error) { 400 }
                ([LogLevel]::Critical) { 500 }
            }
            
            Write-EventLog -LogName Application -Source "OSDCloudCustomBuilder" -EventId $eventId -EntryType $eventType -Message $Message
        }
        catch {
            Write-Warning "Failed to write to EventLog: $_"
            $script:EnableEventLogging = $false
        }
    }
}

<#
.SYNOPSIS
    Gets statistics about the current logging session.
.DESCRIPTION
    Returns information about logged messages, counts by level, and timestamps.
.EXAMPLE
    Get-OSDCloudLogStatistics | Format-List
#>
function Get-OSDCloudLogStatistics {
    [CmdletBinding()]
    [OutputType([LogStatistics])]
    param()
    
    return $script:LogStats
}

<#
.SYNOPSIS
    Gets the path to the current log file.
.DESCRIPTION
    Returns the full path to the log file being used by the logging system.
.EXAMPLE
    $logPath = Get-OSDCloudLogPath
    notepad $logPath
#>
function Get-OSDCloudLogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:LogFile
}

<#
.SYNOPSIS
    Closes and finalizes the logging system.
.DESCRIPTION
    Properly closes the log file and releases resources.
.EXAMPLE
    Close-OSDCloudLogging
#>
function Close-OSDCloudLogging {
    [CmdletBinding()]
    param()
    
    if ($script:LogWriter) {
        try {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $totalCount = $script:LogStats.GetTotalCount()
            $duration = [datetime]::Now - $script:LogStats.StartTime
            $formattedDuration = "{0:d\d\ h\h\ m\m\ s\s}" -f $duration
            
            $finalMessage = "[$timestamp] [Info] Logging session ended. Total logs: $totalCount, Duration: $formattedDuration, Errors: $($script:LogStats.ErrorCount), Warnings: $($script:LogStats.WarningCount)"
            $script:LogWriter.WriteLine($finalMessage)
            $script:LogWriter.Flush()
            $script:LogWriter.Close()
            $script:LogWriter.Dispose()
            $script:LogWriter = $null
            
            if ($script:LogFileStream) {
                $script:LogFileStream.Close()
                $script:LogFileStream.Dispose()
                $script:LogFileStream = $null
            }
            
            Write-Verbose "Logging system closed. $finalMessage"
        }
        catch {
            Write-Warning "Error while closing logging system: $_"
        }
    }
}

# Initialize logging when module loads
Initialize-OSDCloudLogging

# Ensure logging is closed when module is removed
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Close-OSDCloudLogging
}

# Export functions
Export-ModuleMember -Function Write-OSDCloudLog, Get-OSDCloudLogStatistics, Get-OSDCloudLogPath, Initialize-OSDCloudLogging, Close-OSDCloudLogging