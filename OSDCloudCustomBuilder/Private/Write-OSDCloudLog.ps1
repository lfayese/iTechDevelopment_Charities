function Write-OSDCloudLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug', 'Verbose')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'OSDCloudCustomBuilder',
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception = $null,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $null
    )
    
    # Get configuration
    $config = Get-ModuleConfiguration
    
    # Default log path if not specified
    if (-not $LogFilePath) {
        $logDir = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder\Logs"
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $LogFilePath = Join-Path -Path $logDir -ChildPath "OSDCloudCustomBuilder_$(Get-Date -Format 'yyyyMMdd').log"
    }
    
    # Format timestamp
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    
    # Format log entry
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Add exception details if provided
    if ($Exception) {
        $logEntry += "`r`nException: $($Exception.Message)"
        $logEntry += "`r`nStack Trace: $($Exception.StackTrace)"
    }
    
    # Write to log file
    try {
        Add-Content -Path $LogFilePath -Value $logEntry -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
    
    # Output to console based on level
    switch ($Level) {
        'Info' {
            Write-Host $logEntry
        }
        'Warning' {
            Write-Warning $logEntry
        }
        'Error' {
            Write-Error $logEntry
        }
        'Debug' {
            Write-Debug $logEntry
        }
        'Verbose' {
            Write-Verbose $logEntry
        }
    }
    
    # If Invoke-OSDCloudLogger exists, also log through it
    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
        Invoke-OSDCloudLogger -Message $Message -Level $Level -Component $Component -Exception $Exception
    }
}

# Export the function
Export-ModuleMember -Function Write-OSDCloudLog