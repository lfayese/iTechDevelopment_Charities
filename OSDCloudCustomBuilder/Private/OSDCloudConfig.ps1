<#
.SYNOPSIS
    Configuration settings for OSDCloud Deployment for Charities
.DESCRIPTION
    This file contains centralized configuration settings for the OSDCloud Deployment solution.
    Supports loading from and saving to JSON configuration files, and provides validation functions.
.NOTES
    Created for: Charity OSDCloud Deployment
    Author: iTech Development
    Date: March 30, 2025
    Version: 1.0
#>

# Default configuration settings
$script:OSDCloudConfig = @{
    # Organization settings
    OrganizationName = "iTechDevelopment_Charities"
    OrganizationContact = "IT Support"
    OrganizationEmail = "support@charity.org"
    
    # Logging settings
    LoggingEnabled = $true
    LogLevel = "Info"  # Debug, Info, Warning, Error, Fatal
    LogRetentionDays = 30
    LogPath = "$env:TEMP\OSDCloud\Logs"
    
    # Default deployment settings
    DefaultOSLanguage = "en-us"
    DefaultOSEdition = "Enterprise"
    DefaultOSLicense = "Volume"
    
    # Recovery settings
    MaxRetryAttempts = 3
    RetryDelaySeconds = 5
    EnableAutoRecovery = $true
    CreateBackups = $true
    
    # Customization settings
    CustomWimSearchPaths = @(
        "X:\OSDCloud\custom.wim",
        "C:\OSDCloud\custom.wim",
        "D:\OSDCloud\custom.wim",
        "E:\OSDCloud\custom.wim"
    )
    
    # PowerShell 7 settings
    PowerShell7Version = "7.3.4"
    PowerShell7Modules = @(
        "OSD",
        "Microsoft.Graph.Intune",
        "WindowsAutopilotIntune"
    )
    
    # Autopilot settings
    AutopilotEnabled = $true
    SkipAutopilotOOBE = $true
    
    # Hardware compatibility settings
    RequireTPM20 = $true
    MinimumCPUGeneration = 8  # For Intel CPUs
    
    # ISO building settings
    ISOOutputPath = "C:\OSDCloud\ISO"
    TempWorkspacePath = "$env:TEMP\OSDCloudWorkspace"
    CleanupTempFiles = $true
    IncludeWinRE = $true
    OptimizeISOSize = $true
    
    # Error handling settings
    ErrorRecoveryEnabled = $true
    ErrorLogPath = "$env:TEMP\OSDCloud\Logs\Errors"
    MaxErrorRetry = 3
    ErrorRetryDelay = 5
}

# Validate configuration settings
function Test-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:OSDCloudConfig
    )
    
    $isValid = $true
    $validationErrors = @()
    
    # Validate required fields
    $requiredFields = @(
        'OrganizationName',
        'LogPath',
        'DefaultOSLanguage',
        'DefaultOSEdition',
        'ISOOutputPath'
    )
    
    foreach ($field in $requiredFields) {
        if (-not $Config.ContainsKey($field) -or [string]::IsNullOrEmpty($Config[$field])) {
            $isValid = $false
            $validationErrors += "Missing required configuration field: $field"
        }
    }
    
    # Validate log level
    $validLogLevels = @('Debug', 'Info', 'Warning', 'Error', 'Fatal')
    if ($Config.ContainsKey('LogLevel') -and $validLogLevels -notcontains $Config.LogLevel) {
        $isValid = $false
        $validationErrors += "Invalid log level: $($Config.LogLevel). Valid values are: $($validLogLevels -join ', ')"
    }
    
    # Validate numeric values
    $numericFields = @(
        @{Name = 'LogRetentionDays'; Min = 1; Max = 365},
        @{Name = 'MaxRetryAttempts'; Min = 1; Max = 10},
        @{Name = 'RetryDelaySeconds'; Min = 1; Max = 60},
        @{Name = 'MinimumCPUGeneration'; Min = 1; Max = 20}
    )
    
    foreach ($field in $numericFields) {
        if ($Config.ContainsKey($field.Name) -and 
            ($Config[$field.Name] -lt $field.Min -or $Config[$field.Name] -gt $field.Max)) {
            $isValid = $false
            $validationErrors += "Invalid value for $($field.Name): $($Config[$field.Name]). Valid range is $($field.Min) to $($field.Max)"
        }
    }
    
    return [PSCustomObject]@{
        IsValid = $isValid
        Errors = $validationErrors
    }
}

# Load configuration from a JSON file
function Import-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not (Test-Path $Path)) {
            Write-Warning "Configuration file not found: $Path"
            return $false
        }
        
        $configJson = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $config = @{}
        
        # Convert JSON to hashtable
        $configJson.PSObject.Properties | ForEach-Object {
            $config[$_.Name] = $_.Value
        }
        
        # Validate the loaded configuration
        $validation = Test-OSDCloudConfig -Config $config
        
        if (-not $validation.IsValid) {
            Write-Warning "Invalid configuration loaded from $Path"
            foreach ($error in $validation.Errors) {
                Write-Warning $error
            }
            return $false
        }
        
        # Merge with default configuration
        $script:OSDCloudConfig = Merge-OSDCloudConfig -UserConfig $config
        
        Write-Verbose "Configuration successfully loaded from $Path"
        return $true
    }
    catch {
        Write-Warning "Error loading configuration from $Path`: $_"
        return $false
    }
}

# Save configuration to a JSON file
function Export-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:OSDCloudConfig
    )
    
    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Path $Path -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Convert hashtable to JSON and save
        $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Force
        
        Write-Verbose "Configuration successfully saved to $Path"
        return $true
    }
    catch {
        Write-Warning "Error saving configuration to $Path`: $_"
        return $false
    }
}

# Merge default configuration with user settings
function Merge-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$UserConfig,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$DefaultConfig = $script:OSDCloudConfig
    )
    
    $mergedConfig = $DefaultConfig.Clone()
    
    # Override default values with user settings
    foreach ($key in $UserConfig.Keys) {
        $mergedConfig[$key] = $UserConfig[$key]
    }
    
    return $mergedConfig
}

# Get the current configuration
function Get-OSDCloudConfig {
    [CmdletBinding()]
    param()
    
    return $script:OSDCloudConfig
}

# Export functions and variables
Export-ModuleMember -Variable OSDCloudConfig
Export-ModuleMember -Function Test-OSDCloudConfig, Import-OSDCloudConfig, Export-OSDCloudConfig, Get-OSDCloudConfig, Merge-OSDCloudConfig