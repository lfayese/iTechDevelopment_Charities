<#
.SYNOPSIS
    Initializes the configuration system for the module.
.DESCRIPTION
    Sets up the default configuration and loads any existing configuration from the standard location.
#>
function Initialize-ModuleConfiguration {
    [OutputType([void])]
    [CmdletBinding()]
    param()
    
    # Default configuration path in user profile
    $script:ConfigPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "OSDCloudCustomBuilder\config.json"
    
    # Default configuration
    $script:DefaultConfig = @{
        LogPath = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
        TelemetryEnabled = $false
        TelemetryDetail = "Basic"
        TelemetryStoragePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "OSDCloudCustomBuilder\Telemetry"
        DefaultPowerShellVersion = "7.5.0"
        EnableVerboseLogging = $false
        
        # Error handling configuration
        ErrorHandling = @{
            ContinueOnError = $false
            CollectErrorTelemetry = $true
            MaxErrorsToStore = 100
            ErrorTelemetryLevel = "Full"  # Basic, Standard, Full
        }
        
        # Logging configuration
        Logging = @{
            EnableConsoleLogging = $true
            EnableFileLogging = $true
            EnableEventLogging = $false
            MinimumLogLevel = "Info"       # Debug, Info, Warning, Error, Critical
            MaxLogFileSizeMB = 10
            MaxLogRetentionDays = 30
            RotateLogs = $true
        }
        
        Timeouts = @{
            Download = 300  # seconds
            Mount = 120     # seconds
            Dismount = 60   # seconds
        }
    }
    
    # Initialize with defaults
    $script:Config = $script:DefaultConfig.Clone()
    
    # Try to load existing configuration
    if (Test-Path -Path $script:ConfigPath) {
        try {
            $savedConfig = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
            
            # Merge saved settings with defaults (keeping defaults for missing properties)
            foreach ($property in $savedConfig.PSObject.Properties) {
                if ($property.Name -in @("ErrorHandling", "Logging", "Timeouts") -and $property.Value) {
                    # Handle nested configuration objects
                    foreach ($nestedProp in $property.Value.PSObject.Properties) {
                        $script:Config[$property.Name][$nestedProp.Name] = $nestedProp.Value
                    }
                }
                else {
                    $script:Config[$property.Name] = $property.Value
                }
            }
            
            # Log configuration loading
            $logMessage = "Loaded configuration from $script:ConfigPath"
            
            # Try to use logging system if it exists
            $loggerExists = Get-Command -Name Write-OSDCloudLog -ErrorAction SilentlyContinue
            if ($loggerExists) {
                Write-OSDCloudLog -Message $logMessage -Level Debug -Component "Configuration"
            }
            else {
                Write-Verbose $logMessage
            }
        }
        catch {
            # Attempt structured error handling if available
            $errorHandlerExists = Get-Command -Name Write-OSDCloudError -ErrorAction SilentlyContinue
            if ($errorHandlerExists) {
                Write-OSDCloudError -ErrorRecord $_ -Message "Failed to load configuration from $script:ConfigPath. Using defaults." -Category Configuration -Source "Initialize-ModuleConfiguration" -SuppressError
            }
            else {
                Write-Warning "Failed to load configuration from $script:ConfigPath. Using defaults. $_"
            }
        }
    }
    else {
        Write-Verbose "No existing configuration found. Using defaults."
    }
    
    # Make EnableVerboseLogging globally accessible if it's defined
    if ($null -ne $script:Config.EnableVerboseLogging) {
        $global:EnableVerboseLogging = $script:Config.EnableVerboseLogging
    }
    
    # Ensure telemetry directory exists if enabled
    if ($script:Config.TelemetryEnabled -and $script:Config.TelemetryStoragePath) {
        if (-not (Test-Path -Path $script:Config.TelemetryStoragePath)) {
            try {
                New-Item -Path $script:Config.TelemetryStoragePath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created telemetry directory: $($script:Config.TelemetryStoragePath)"
            }
            catch {
                # Attempt structured error handling if available
                $errorHandlerExists = Get-Command -Name Write-OSDCloudError -ErrorAction SilentlyContinue
                if ($errorHandlerExists) {
                    Write-OSDCloudError -ErrorRecord $_ -Message "Failed to create telemetry directory" -Category FileSystem -Source "Initialize-ModuleConfiguration" -SuppressError
                }
                else {
                    Write-Warning "Failed to create telemetry directory: $($script:Config.TelemetryStoragePath). $_"
                }
                
                $script:Config.TelemetryEnabled = $false
            }
        }
    }
    
    # Handle log directory creation
    try {
        $logDir = Split-Path -Path $script:Config.LogPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created log directory: $logDir"
        }
    }
    catch {
        # Fall back to TEMP directory if log path creation fails
        $script:Config.LogPath = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder.log"
        
        # Attempt structured error handling if available
        $errorHandlerExists = Get-Command -Name Write-OSDCloudError -ErrorAction SilentlyContinue
        if ($errorHandlerExists) {
            Write-OSDCloudError -ErrorRecord $_ -Message "Failed to create log directory, falling back to TEMP" -Category FileSystem -Source "Initialize-ModuleConfiguration" -SuppressError
        }
        else {
            Write-Warning "Failed to create log directory, falling back to: $($script:Config.LogPath). $_"
        }
    }
}

<#
.SYNOPSIS
    Gets the current module configuration.
.DESCRIPTION
    Returns the current configuration settings for the module.
.PARAMETER Setting
    Optional. The specific setting to retrieve. If not specified, returns the entire configuration.
.EXAMPLE
    Get-ModuleConfiguration -Setting 'TelemetryEnabled'
    Returns the value of the TelemetryEnabled setting.
.EXAMPLE
    Get-ModuleConfiguration
    Returns the entire configuration object.
#>
function Get-ModuleConfiguration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $Setting
    )
    
    # Ensure configuration is initialized
    if (-not $script:Config) {
        Write-Verbose "Configuration not found, initializing..."
        Initialize-ModuleConfiguration
    }
    
    if ($Setting) {
        if ($script:Config.ContainsKey($Setting)) {
            return $script:Config[$Setting]
        }
        else {
            Write-Warning "Configuration setting '$Setting' not found."
            return $null
        }
    }
    else {
        return $script:Config
    }
}

<#
.SYNOPSIS
    Updates the module configuration with new settings.
.DESCRIPTION
    Allows updating of module configuration settings and saves them to the configuration file.
.PARAMETER Settings
    A hashtable containing the settings to update.
.PARAMETER NoSave
    If specified, the configuration is updated in memory only and not saved to disk.
.EXAMPLE
    Update-ModuleConfiguration -Settings @{ TelemetryEnabled = $true; EnableVerboseLogging = $true }
    Updates the telemetry and verbose logging settings and saves the configuration.
#>
function Update-ModuleConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings,
        
        [Parameter()]
        [switch] $NoSave
    )
    
    # Ensure configuration is initialized
    if (-not $script:Config) {
        Write-Verbose "Configuration not found, initializing..."
        Initialize-ModuleConfiguration
    }
    
    # Update settings
    foreach ($key in $Settings.Keys) {
        if ($key -eq "Timeouts" -and $Settings[$key] -is [hashtable]) {
            foreach ($timeoutKey in $Settings[$key].Keys) {
                $script:Config.Timeouts[$timeoutKey] = $Settings[$key][$timeoutKey]
            }
        }
        else {
            $script:Config[$key] = $Settings[$key]
            
            # Update global variable if this is EnableVerboseLogging
            if ($key -eq 'EnableVerboseLogging') {
                $global:EnableVerboseLogging = $Settings[$key]
            }
        }
    }
    
    # Save configuration if not using NoSave switch
    if (-not $NoSave) {
        $configDir = Split-Path -Path $script:ConfigPath -Parent
        if (-not (Test-Path -Path $configDir)) {
            try {
                New-Item -Path $configDir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created configuration directory: $configDir"
            }
            catch {
                Write-Error "Failed to create configuration directory: $configDir. $_"
                return
            }
        }
        
        try {
            $script:Config | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ConfigPath -Force
            Write-Verbose "Configuration saved to $script:ConfigPath"
        }
        catch {
            Write-Error "Failed to save configuration to $script:ConfigPath. $_"
        }
    }
}

<#
.SYNOPSIS
    Resets the module configuration to defaults.
.DESCRIPTION
    Resets all configuration settings to their default values.
.PARAMETER NoSave
    If specified, the configuration is reset in memory only and not saved to disk.
.EXAMPLE
    Reset-ModuleConfiguration
    Resets all configuration settings to defaults and saves the configuration.
#>
function Reset-ModuleConfiguration {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch] $NoSave
    )
    
    $script:Config = $script:DefaultConfig.Clone()
    
    # Update global variable if EnableVerboseLogging is defined
    if ($null -ne $script:Config.EnableVerboseLogging) {
        $global:EnableVerboseLogging = $script:Config.EnableVerboseLogging
    }
    
    Write-Verbose "Configuration reset to defaults."
    
    # Save configuration if not using NoSave switch
    if (-not $NoSave) {
        $configDir = Split-Path -Path $script:ConfigPath -Parent
        if (-not (Test-Path -Path $configDir)) {
            try {
                New-Item -Path $configDir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created configuration directory: $configDir"
            }
            catch {
                Write-Error "Failed to create configuration directory: $configDir. $_"
                return
            }
        }
        
        try {
            $script:Config | ConvertTo-Json -Depth 4 | Set-Content -Path $script:ConfigPath -Force
            Write-Verbose "Default configuration saved to $script:ConfigPath"
        }
        catch {
            Write-Error "Failed to save configuration to $script:ConfigPath. $_"
        }
    }
}

# Initialize the configuration when module is loaded
Initialize-ModuleConfiguration