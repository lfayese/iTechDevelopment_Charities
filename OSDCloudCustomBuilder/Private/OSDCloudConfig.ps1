<#
.SYNOPSIS
    Configuration management system for OSDCloudCustomBuilder module.
.DESCRIPTION
    This file provides a comprehensive configuration management system for the OSDCloudCustomBuilder module.
    It handles loading, saving, validating, and merging configuration settings.
    The configuration system supports both default settings and user-defined overrides.
.PARAMETER Path
    The path to the configuration file.
.PARAMETER Config
    A hashtable containing configuration settings.
.PARAMETER UserConfig
    A hashtable containing user-defined configuration settings to merge with defaults.
.PARAMETER DefaultConfig
    A hashtable containing default configuration settings.
.EXAMPLE
    $config = Get-OSDCloudConfig
    Retrieves the current configuration settings.
.EXAMPLE
    Import-OSDCloudConfig -Path "C:\OSDCloud\config.json"
    Loads configuration settings from a JSON file.
.EXAMPLE
    Export-OSDCloudConfig -Path "C:\OSDCloud\config.json"
    Saves the current configuration settings to a JSON file.
.NOTES
    Created for: OSDCloudCustomBuilder Module
    Author: OSDCloud Team
    Date: March 31, 2025
    Version: 1.1
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
    LogFilePath = "$env:TEMP\OSDCloud\Logs\OSDCloudCustomBuilder.log"
    VerboseLogging = $false
    DebugLogging = $false
    
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
    PowerShell7DownloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v7.3.4/PowerShell-7.3.4-win-x64.zip"
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
    
    # Integration settings
    SharedConfigPath = "$env:ProgramData\OSDCloud\Config"
    EnableSharedLogging = $true
    
    # Performance settings
    EnableParallelProcessing = $true
    MaxParallelTasks = 4
    UseRobocopyForLargeFiles = $true
    LargeFileSizeThresholdMB = 100
}

<#
.SYNOPSIS
    Validates the OSDCloud configuration settings.
.DESCRIPTION
    Validates the OSDCloud configuration settings to ensure all required fields are present
    and that all values are within acceptable ranges.
.PARAMETER Config
    A hashtable containing the configuration settings to validate.
.EXAMPLE
    $validation = Test-OSDCloudConfig
    if (-not $validation.IsValid) {
        Write-Warning "Invalid configuration: $($validation.Errors -join ', ')"
    }
.NOTES
    This function is used internally by the configuration management system.
#>
function Test-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:OSDCloudConfig
    )
    
    begin {
        $isValid = $true
        $validationErrors = @()
    }
    
    process {
        try {
            # Validate required fields
            $requiredFields = @(
                'OrganizationName',
                'LogFilePath',
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
                @{Name = 'MinimumCPUGeneration'; Min = 1; Max = 20},
                @{Name = 'MaxParallelTasks'; Min = 1; Max = 16},
                @{Name = 'LargeFileSizeThresholdMB'; Min = 10; Max = 1000}
            )
            
            foreach ($field in $numericFields) {
                if ($Config.ContainsKey($field.Name) -and 
                    ($Config[$field.Name] -lt $field.Min -or $Config[$field.Name] -gt $field.Max)) {
                    $isValid = $false
                    $validationErrors += "Invalid value for $($field.Name): $($Config[$field.Name]). Valid range is $($field.Min) to $($field.Max)"
                }
            }
            
            # Validate boolean values
            $booleanFields = @(
                'LoggingEnabled', 'EnableAutoRecovery', 'CreateBackups', 'AutopilotEnabled',
                'SkipAutopilotOOBE', 'RequireTPM20', 'CleanupTempFiles', 'IncludeWinRE',
                'OptimizeISOSize', 'ErrorRecoveryEnabled', 'EnableSharedLogging',
                'EnableParallelProcessing', 'UseRobocopyForLargeFiles', 'VerboseLogging',
                'DebugLogging'
            )
            
            foreach ($field in $booleanFields) {
                if ($Config.ContainsKey($field) -and $Config[$field] -isnot [bool]) {
                    $isValid = $false
                    $validationErrors += "Invalid value for $field: must be a boolean (true/false)"
                }
            }
            
            # Validate PowerShell version format
            if ($Config.ContainsKey('PowerShell7Version') -and 
                -not ($Config.PowerShell7Version -match '^\d+\.\d+\.\d+$')) {
                $isValid = $false
                $validationErrors += "Invalid PowerShell version format: $($Config.PowerShell7Version). Expected format: X.Y.Z"
            }
            
            # Validate URL format
            if ($Config.ContainsKey('PowerShell7DownloadUrl') -and 
                -not ($Config.PowerShell7DownloadUrl -match '^https?://')) {
                $isValid = $false
                $validationErrors += "Invalid URL format for PowerShell7DownloadUrl: $($Config.PowerShell7DownloadUrl)"
            }
        }
        catch {
            $isValid = $false
            $validationErrors += "Validation error: $_"
            
            # Log the error
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Configuration validation error: $_" -Level Error -Component "Test-OSDCloudConfig" -Exception $_.Exception
            }
        }
    }
    
    end {
        return [PSCustomObject]@{
            IsValid = $isValid
            Errors = $validationErrors
        }
    }
}

<#
.SYNOPSIS
    Loads OSDCloud configuration settings from a JSON file.
.DESCRIPTION
    Loads OSDCloud configuration settings from a JSON file and merges them with the default settings.
    The loaded settings are validated before being applied.
.PARAMETER Path
    The path to the JSON configuration file.
.EXAMPLE
    Import-OSDCloudConfig -Path "C:\OSDCloud\config.json"
.NOTES
    If the configuration file is invalid, the function will return $false and log warnings.
#>
function Import-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    begin {
        # Log the operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Importing configuration from $Path" -Level Info -Component "Import-OSDCloudConfig"
        }
    }
    
    process {
        try {
            if (-not (Test-Path $Path)) {
                $errorMessage = "Configuration file not found: $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-OSDCloudConfig"
                }
                else {
                    Write-Warning $errorMessage
                }
                return $false
            }
            
            $configJson = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $config = @{}
            
            # Convert JSON to hashtable
            $configJson.PSObject.Properties | ForEach-Object {
                $config[$_.Name] = $_.Value
            }
            
            # Validate the loaded configuration
            $validation = Test-OSDCloudConfig -Config $config
            
            if (-not $validation.IsValid) {
                $errorMessage = "Invalid configuration loaded from $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-OSDCloudConfig"
                    foreach ($error in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $error -Level Warning -Component "Import-OSDCloudConfig"
                    }
                }
                else {
                    Write-Warning $errorMessage
                    foreach ($error in $validation.Errors) {
                        Write-Warning $error
                    }
                }
                return $false
            }
            
            # Merge with default configuration
            $script:OSDCloudConfig = Merge-OSDCloudConfig -UserConfig $config
            
            $successMessage = "Configuration successfully loaded from $Path"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Import-OSDCloudConfig"
            }
            else {
                Write-Verbose $successMessage
            }
            
            return $true
        }
        catch {
            $errorMessage = "Error loading configuration from $Path`: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Import-OSDCloudConfig" -Exception $_.Exception
            }
            else {
                Write-Warning $errorMessage
            }
            return $false
        }
    }
}

<#
.SYNOPSIS
    Saves OSDCloud configuration settings to a JSON file.
.DESCRIPTION
    Saves the current or specified OSDCloud configuration settings to a JSON file.
    The configuration is validated before being saved.
.PARAMETER Path
    The path where the JSON configuration file will be saved.
.PARAMETER Config
    A hashtable containing the configuration settings to save. If not specified, the current configuration is used.
.EXAMPLE
    Export-OSDCloudConfig -Path "C:\OSDCloud\config.json"
.EXAMPLE
    $customConfig = Get-OSDCloudConfig
    $customConfig.LogLevel = "Debug"
    Export-OSDCloudConfig -Path "C:\OSDCloud\debug-config.json" -Config $customConfig
.NOTES
    If the directory for the configuration file does not exist, it will be created.
#>
function Export-OSDCloudConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $script:OSDCloudConfig
    )
    
    begin {
        # Log the operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Exporting configuration to $Path" -Level Info -Component "Export-OSDCloudConfig"
        }
    }
    
    process {
        try {
            # Validate the configuration before saving
            $validation = Test-OSDCloudConfig -Config $Config
            if (-not $validation.IsValid) {
                $errorMessage = "Cannot save invalid configuration to $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Export-OSDCloudConfig"
                    foreach ($error in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $error -Level Error -Component "Export-OSDCloudConfig"
                    }
                }
                else {
                    Write-Error $errorMessage
                    foreach ($error in $validation.Errors) {
                        Write-Error $error
                    }
                }
                return $false
            }
            
            # Create directory if it doesn't exist
            $directory = Split-Path -Path $Path -Parent
            if (-not (Test-Path $directory)) {
                if ($PSCmdlet.ShouldProcess($directory, "Create directory")) {
                    New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                else {
                    return $false
                }
            }
            
            # Convert hashtable to JSON and save
            if ($PSCmdlet.ShouldProcess($Path, "Save configuration")) {
                $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Force -ErrorAction Stop
                
                $successMessage = "Configuration successfully saved to $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Export-OSDCloudConfig"
                }
                else {
                    Write-Verbose $successMessage
                }
                
                return $true
            }
            else {
                return $false
            }
        }
        catch {
            $errorMessage = "Error saving configuration to $Path`: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Export-OSDCloudConfig" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            return $false
        }
    }
}

<#
.SYNOPSIS
    Merges user-defined configuration settings with default settings.
.DESCRIPTION
    Merges user-defined configuration settings with default settings to create a complete configuration.
    This function preserves all default settings while overriding them with user-defined values where provided.
.PARAMETER UserConfig
    A hashtable containing user-defined configuration settings.
.PARAMETER DefaultConfig
    A hashtable containing default configuration settings. If not specified, the current default configuration is used.
.EXAMPLE
    $userConfig = @{
        LogLevel = "Debug"
        CreateBackups = $false
    }
    $mergedConfig = Merge-OSDCloudConfig -UserConfig $userConfig
.NOTES
    This function is used internally by the configuration management system.
#>
function Merge-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$UserConfig,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$DefaultConfig = $script:OSDCloudConfig
    )
    
    begin {
        # Create a deep clone of the default config
        $mergedConfig = @{}
        foreach ($key in $DefaultConfig.Keys) {
            if ($DefaultConfig[$key] -is [hashtable]) {
                $mergedConfig[$key] = $DefaultConfig[$key].Clone()
            }
            elseif ($DefaultConfig[$key] -is [array]) {
                $mergedConfig[$key] = $DefaultConfig[$key].Clone()
            }
            else {
                $mergedConfig[$key] = $DefaultConfig[$key]
            }
        }
    }
    
    process {
        try {
            # Override default values with user settings
            foreach ($key in $UserConfig.Keys) {
                $mergedConfig[$key] = $UserConfig[$key]
            }
            
            # Log the merge operation
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                $overriddenKeys = $UserConfig.Keys -join ', '
                Invoke-OSDCloudLogger -Message "Merged configuration with overrides for: $overriddenKeys" -Level Verbose -Component "Merge-OSDCloudConfig"
            }
        }
        catch {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Error merging configurations: $_" -Level Error -Component "Merge-OSDCloudConfig" -Exception $_.Exception
            }
            else {
                Write-Error "Error merging configurations: $_"
            }
            # Return the default config if merging fails
            return $DefaultConfig
        }
    }
    
    end {
        return $mergedConfig
    }
}

<#
.SYNOPSIS
    Retrieves the current OSDCloud configuration settings.
.DESCRIPTION
    Retrieves the current OSDCloud configuration settings as a hashtable.
    This function can be used to get the current configuration for review or modification.
.EXAMPLE
    $config = Get-OSDCloudConfig
    $config.LogLevel = "Debug"
.NOTES
    Any changes made to the returned hashtable will not affect the actual configuration
    unless the modified hashtable is passed to Export-OSDCloudConfig or used to update
    the $script:OSDCloudConfig variable.
#>
function Get-OSDCloudConfig {
    [CmdletBinding()]
    param()
    
    begin {
        # Log the operation
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Retrieving current configuration" -Level Verbose -Component "Get-OSDCloudConfig"
        }
    }
    
    process {
        try {
            # Return a clone of the configuration to prevent unintended modifications
            $configClone = @{}
            foreach ($key in $script:OSDCloudConfig.Keys) {
                if ($script:OSDCloudConfig[$key] -is [hashtable]) {
                    $configClone[$key] = $script:OSDCloudConfig[$key].Clone()
                }
                elseif ($script:OSDCloudConfig[$key] -is [array]) {
                    $configClone[$key] = $script:OSDCloudConfig[$key].Clone()
                }
                else {
                    $configClone[$key] = $script:OSDCloudConfig[$key]
                }
            }
            
            return $configClone
        }
        catch {
            $errorMessage = "Error retrieving configuration: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Get-OSDCloudConfig" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            
            # Return an empty hashtable in case of error
            return @{}
        }
    }
}

<#
.SYNOPSIS
    Updates specific OSDCloud configuration settings.
.DESCRIPTION
    Updates specific OSDCloud configuration settings without replacing the entire configuration.
    This function allows you to modify individual settings while preserving all other settings.
.PARAMETER Settings
    A hashtable containing the configuration settings to update.
.EXAMPLE
    Update-OSDCloudConfig -Settings @{
        LogLevel = "Debug"
        CreateBackups = $false
        PowerShell7Version = "7.3.5"
    }
.NOTES
    The updated settings are validated before being applied.
#>
function Update-OSDCloudConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )
    
    begin {
        # Log the operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            $updatedKeys = $Settings.Keys -join ', '
            Invoke-OSDCloudLogger -Message "Updating configuration settings: $updatedKeys" -Level Info -Component "Update-OSDCloudConfig"
        }
    }
    
    process {
        try {
            # Create a temporary config with the updates
            $tempConfig = $script:OSDCloudConfig.Clone()
            foreach ($key in $Settings.Keys) {
                $tempConfig[$key] = $Settings[$key]
            }
            
            # Validate the updated configuration
            $validation = Test-OSDCloudConfig -Config $tempConfig
            if (-not $validation.IsValid) {
                $errorMessage = "Invalid configuration settings"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-OSDCloudConfig"
                    foreach ($error in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $error -Level Error -Component "Update-OSDCloudConfig"
                    }
                }
                else {
                    Write-Error $errorMessage
                    foreach ($error in $validation.Errors) {
                        Write-Error $error
                    }
                }
                return $false
            }
            
            # Apply the updates if validation passes
            if ($PSCmdlet.ShouldProcess("OSDCloud Configuration", "Update settings")) {
                foreach ($key in $Settings.Keys) {
                    $script:OSDCloudConfig[$key] = $Settings[$key]
                }
                
                $successMessage = "Configuration settings updated successfully"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Update-OSDCloudConfig"
                }
                else {
                    Write-Verbose $successMessage
                }
                
                return $true
            }
            else {
                return $false
            }
        }
        catch {
            $errorMessage = "Error updating configuration settings: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-OSDCloudConfig" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            return $false
        }
    }
}

# Look for a shared configuration file at startup
$sharedConfigPath = Join-Path -Path $script:OSDCloudConfig.SharedConfigPath -ChildPath "OSDCloudConfig.json"
if (Test-Path $sharedConfigPath) {
    try {
        Import-OSDCloudConfig -Path $sharedConfigPath -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Warning "Could not load shared configuration: $_"
    }
}

# Export functions and variables
Export-ModuleMember -Variable OSDCloudConfig
Export-ModuleMember -Function Test-OSDCloudConfig, Import-OSDCloudConfig, Export-OSDCloudConfig, Get-OSDCloudConfig, Merge-OSDCloudConfig, Update-OSDCloudConfig