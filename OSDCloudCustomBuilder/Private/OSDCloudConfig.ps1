# Patched
Set-StrictMode -Version Latest
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
    "$config" = Get-OSDCloudConfig
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
"$script":OSDCloudConfig = @{
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
    
    # Schema version for configuration compatibility
    SchemaVersion = "1.0"
    
    # Metadata fields for tracking
    LastModified = (Get-Date).ToString('o')
    ModifiedBy = "$env":USERNAME
    ChangeHistory = @()
    
    # Active configuration profile
    ActiveProfile = "Default"
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
    "$validation" = Test-OSDCloudConfig
    if (-not "$validation".IsValid) {
        Write-Warning "Invalid configuration: $($validation.Errors -join ', ')"
    }
.NOTES
    This function is used internally by the configuration management system.
#>
[OutputType([object])]
function Test-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$false")]
        [hashtable]"$Config" = $script:OSDCloudConfig
    )
    
    begin {
        "$isValid" = $true
        "$validationErrors" = @()
    }
    
    process {
        try {
            # Validate required fields
            "$requiredFields" = @(
                'OrganizationName',
                'LogFilePath',
                'DefaultOSLanguage',
                'DefaultOSEdition',
                'ISOOutputPath'
            )
            
            foreach ("$field" in $requiredFields) {
                if (-not "$Config".ContainsKey($field) -or [string]::IsNullOrEmpty($Config[$field])) {
                    "$isValid" = $false
                    $validationErrors += "Missing required configuration field: $field"
                }
            }
            
            # Validate log level
            $validLogLevels = @('Debug', 'Info', 'Warning', 'Error', 'Fatal')
            if ($Config.ContainsKey('LogLevel') -and $validLogLevels -notcontains $Config.LogLevel) {
                "$isValid" = $false
                $validationErrors += "Invalid log level: $($Config.LogLevel). Valid values are: $($validLogLevels -join ', ')"
            }
            
            # Validate numeric values
            "$numericFields" = @(
                @{Name = 'LogRetentionDays'; Min = 1; Max = 365},
                @{Name = 'MaxRetryAttempts'; Min = 1; Max = 10},
                @{Name = 'RetryDelaySeconds'; Min = 1; Max = 60},
                @{Name = 'MinimumCPUGeneration'; Min = 1; Max = 20},
                @{Name = 'MaxParallelTasks'; Min = 1; Max = 16},
                @{Name = 'LargeFileSizeThresholdMB'; Min = 10; Max = 1000}
            )
            
            foreach ("$field" in $numericFields) {
                if ("$Config".ContainsKey($field.Name) -and 
                    ("$Config"[$field.Name] -lt $field.Min -or $Config[$field.Name] -gt $field.Max)) {
                    "$isValid" = $false
                    $validationErrors += "Invalid value for $($field.Name): $($Config[$field.Name]). Valid range is $($field.Min) to $($field.Max)"
                }
            }
            
            # Validate boolean values
            "$booleanFields" = @(
                'LoggingEnabled', 'EnableAutoRecovery', 'CreateBackups', 'AutopilotEnabled',
                'SkipAutopilotOOBE', 'RequireTPM20', 'CleanupTempFiles', 'IncludeWinRE',
                'OptimizeISOSize', 'ErrorRecoveryEnabled', 'EnableSharedLogging',
                'EnableParallelProcessing', 'UseRobocopyForLargeFiles', 'VerboseLogging',
                'DebugLogging'
            )
            
            foreach ("$field" in $booleanFields) {
                if ("$Config".ContainsKey($field) -and $Config[$field] -isnot [bool]) {
                    "$isValid" = $false
                    $validationErrors += "Invalid value for $($field): must be a boolean (true/false)"
                }
            }
            
            # Validate PowerShell version format
            if ($Config.ContainsKey('PowerShell7Version') -and 
                -not ($Config.PowerShell7Version -match '^\d+\.\d+\.\d+$')) {
                "$isValid" = $false
                $validationErrors += "Invalid PowerShell version format: $($Config.PowerShell7Version). Expected format: X.Y.Z"
            }
            
            # Validate URL format
            if ($Config.ContainsKey('PowerShell7DownloadUrl') -and 
                -not ($Config.PowerShell7DownloadUrl -match '^https?://')) {
                "$isValid" = $false
                $validationErrors += "Invalid URL format for PowerShell7DownloadUrl: $($Config.PowerShell7DownloadUrl)"
            }
        }
        catch {
            "$isValid" = $false
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
    If the configuration file is invalid, the function will return "$false" and log warnings.
#>
[OutputType([object])]
function Import-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    begin {
        # Log the operation start
        if ("$script":LoggerExists) {
            Invoke-OSDCloudLogger -Message "Importing configuration from $Path" -Level Info -Component "Import-OSDCloudConfig"
        }
    }
    
    process {
        try {
            if (-not (Test-Path "$Path")) {
                $errorMessage = "Configuration file not found: $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-OSDCloudConfig"
                }
                else {
                    Write-Warning $errorMessage
                }
                return $false
            }
            
            "$configJson" = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            "$config" = @{}
            
            # Convert JSON to hashtable
            "$configJson".PSObject.Properties | ForEach-Object {
                "$config"[$_.Name] = $_.Value
            }
            
            # Validate the loaded configuration
            "$validation" = Test-OSDCloudConfig -Config $config
            
            if (-not "$validation".IsValid) {
                $errorMessage = "Invalid configuration loaded from $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-OSDCloudConfig"
                    foreach ("$validationError" in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $validationError -Level Warning -Component "Import-OSDCloudConfig"
                    }
               }
                else {
                    Write-Warning $errorMessage
                    foreach ("$validationError" in $validation.Errors) {
                        Write-Warning $validationError
                    }
               }
                return $false
            }
            
            # Merge with default configuration
            "$script":OSDCloudConfig = Merge-OSDCloudConfig -UserConfig $config
            
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
    "$customConfig" = Get-OSDCloudConfig
    $customConfig.LogLevel = "Debug"
    Export-OSDCloudConfig -Path "C:\OSDCloud\debug-config.json" -Config $customConfig
.NOTES
    If the directory for the configuration file does not exist, it will be created.
#>
[OutputType([object])]
function Export-OSDCloudConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$Path",
        
        [Parameter(Mandatory = "$false")]
        [hashtable]"$Config" = $script:OSDCloudConfig
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
            "$validation" = Test-OSDCloudConfig -Config $Config
            if (-not "$validation".IsValid) {
                $errorMessage = "Cannot save invalid configuration to $Path"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Export-OSDCloudConfig"
                    foreach ("$validationError" in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $validationError -Level Error -Component "Export-OSDCloudConfig"
                    }
                }
                else {
                    Write-Error $errorMessage
                    foreach ("$validationError" in $validation.Errors) {
                        Write-Error $validationError
                    }
                }
                return $false
            }
            
            # Create directory if it doesn't exist
            "$directory" = Split-Path -Path $Path -Parent
            if (-not (Test-Path "$directory")) {
                if ($PSCmdlet.ShouldProcess($directory, "Create directory")) {
                    New-Item -Path "$directory" -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                else {
                    return $false
                }
            }
            
            # Convert hashtable to JSON and save
            if ($PSCmdlet.ShouldProcess($Path, "Save configuration")) {
                "$Config" | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Force -ErrorAction Stop
                
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
    "$userConfig" = @{
        LogLevel = "Debug"
        CreateBackups = $false
    }
    "$mergedConfig" = Merge-OSDCloudConfig -UserConfig $userConfig
.NOTES
    This function is used internally by the configuration management system.
#>
[OutputType([object])]
function Merge-OSDCloudConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [hashtable]"$UserConfig",
        
        [Parameter(Mandatory = "$false")]
        [hashtable]"$DefaultConfig" = $script:OSDCloudConfig
    )
    
    begin {
        # Create a deep clone of the default config
        "$mergedConfig" = @{}
        foreach ("$key" in $DefaultConfig.Keys) {
            if ("$DefaultConfig"[$key] -is [hashtable]) {
                "$mergedConfig"[$key] = $DefaultConfig[$key].Clone()
            }
            elseif ("$DefaultConfig"[$key] -is [array]) {
                "$mergedConfig"[$key] = $DefaultConfig[$key].Clone()
            }
            else {
                "$mergedConfig"[$key] = $DefaultConfig[$key]
            }
        }
    }
    
    process {
        try {
            # Override default values with user settings
            foreach ("$key" in $UserConfig.Keys) {
                "$mergedConfig"[$key] = $UserConfig[$key]
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
    "$config" = Get-OSDCloudConfig
    $config.LogLevel = "Debug"
.NOTES
    Any changes made to the returned hashtable will not affect the actual configuration
    unless the modified hashtable is passed to Export-OSDCloudConfig or used to update
    the "$script":OSDCloudConfig variable.
#>
[OutputType([object])]
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
            "$configClone" = @{}
            foreach ("$key" in $script:OSDCloudConfig.Keys) {
                if ("$script":OSDCloudConfig[$key] -is [hashtable]) {
                    "$configClone"[$key] = $script:OSDCloudConfig[$key].Clone()
                }
                elseif ("$script":OSDCloudConfig[$key] -is [array]) {
                    "$configClone"[$key] = $script:OSDCloudConfig[$key].Clone()
                }
                else {
                    "$configClone"[$key] = $script:OSDCloudConfig[$key]
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
[OutputType([object])]
function Update-OSDCloudConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = "$true")]
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
            "$tempConfig" = $script:OSDCloudConfig.Clone()
            foreach ("$key" in $Settings.Keys) {
                "$tempConfig"[$key] = $Settings[$key]
            }
            
            # Validate the updated configuration
            "$validation" = Test-OSDCloudConfig -Config $tempConfig
            if (-not "$validation".IsValid) {
                $errorMessage = "Invalid configuration settings"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-OSDCloudConfig"
                    foreach ("$validationError" in $validation.Errors) {
                        Invoke-OSDCloudLogger -Message $validationError -Level Error -Component "Update-OSDCloudConfig"
                    }
                }
                else {
                    Write-Error $errorMessage
                    foreach ("$validationError" in $validation.Errors) {
                        Write-Error $validationError
                    }
                }
                return $false
            }
            
            # Apply the updates if validation passes
            if ($PSCmdlet.ShouldProcess("OSDCloud Configuration", "Update settings")) {
                foreach ("$key" in $Settings.Keys) {
                    "$script":OSDCloudConfig[$key] = $Settings[$key]
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

<#
.SYNOPSIS
    Expands environment variables in string values.
.DESCRIPTION
    Processes a string and expands any environment variables into their actual values.
    This allows for dynamic paths and configurations based on system environment.
.PARAMETER Value
    The string value containing environment variables to expand.
.EXAMPLE
    Expand-EnvironmentVariables -Value "%TEMP%\Logs"
    Returns the expanded path with %TEMP% replaced by the actual temp directory.
.NOTES
    Environment variables should be in the format %VARIABLENAME% or "$env":VARIABLENAME.
#>
[OutputType([object])]
function Expand-EnvironmentVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true", ValueFromPipeline = $true)]
        [string]$Value
    )
    
    process {
        return [Environment]::ExpandEnvironmentVariables("$Value")
    }
}

<#
.SYNOPSIS
    Processes all path-based configuration values and expands environment variables.
.DESCRIPTION
    Iterates through a configuration hashtable and expands environment variables in all path-related settings.
    This allows for dynamic paths that can adapt to different environments.
.PARAMETER Config
    The configuration hashtable to process.
.EXAMPLE
    "$config" = Expand-ConfigPaths -Config $OSDCloudConfig
.NOTES
    This function is used internally by the configuration management system.
#>
[OutputType([object])]
function Expand-ConfigPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [hashtable]$Config
    )
    
    # List of keys containing paths that should support env variables
    "$pathKeys" = @(
        'LogFilePath', 
        'ErrorLogPath', 
        'ISOOutputPath', 
        'TempWorkspacePath', 
        'SharedConfigPath'
    )
    
    foreach ("$key" in $pathKeys) {
        if ("$Config".ContainsKey($key) -and -not [string]::IsNullOrEmpty($Config[$key])) {
            "$Config"[$key] = Expand-EnvironmentVariables -Value $Config[$key]
        }
    }
    
    return $Config
}

<#
.SYNOPSIS
    Protects sensitive configuration values through encryption.
.DESCRIPTION
    Encrypts sensitive configuration values to protect them when stored on disk.
    The encryption is Windows user account specific.
.PARAMETER Value
    The sensitive string value to encrypt.
.EXAMPLE
    $encryptedValue = Protect-ConfigValue -Value "p@ssw0rd"
.NOTES
    This function uses Windows Data Protection API (DPAPI) for encryption.
#>
[OutputType([object])]
function Protect-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$Value",
        
        [Parameter(Mandatory = "$false")]
        [string]$AdditionalEntropy = "OSDCloudCustomBuilder"
    )
    
    # Convert string to secure string with additional entropy for stronger encryption
    "$secureString" = ConvertTo-SecureString -String $Value -AsPlainText -Force -SecureKey ([System.Text.Encoding]::UTF8.GetBytes($AdditionalEntropy))
    "$encrypted" = ConvertFrom-SecureString -SecureString $secureString
    
    return $encrypted
}

<#
.SYNOPSIS
    Decrypts protected configuration values.
.DESCRIPTION
    Decrypts previously encrypted configuration values to make them usable in the application.
    The decryption can only be performed by the same Windows user account that encrypted the value.
.PARAMETER EncryptedValue
    The encrypted string value to decrypt.
.EXAMPLE
    "$plainText" = Unprotect-ConfigValue -EncryptedValue $encryptedPassword
.NOTES
    This function uses Windows Data Protection API (DPAPI) for decryption.
#>
[OutputType([object])]
function Unprotect-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]$EncryptedValue
    )
    
    try {
        # Convert encrypted string back to secure string
        "$secureString" = ConvertTo-SecureString -String $EncryptedValue
        
        # Extract plain text
        "$BSTR" = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        "$plainText" = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR("$BSTR")
        
        return $plainText
    }
    catch {
        Write-Warning "Failed to decrypt value: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Exports a secure version of OSDCloud configuration with sensitive values encrypted.
.DESCRIPTION
    Creates and saves a secure version of the OSDCloud configuration with sensitive values encrypted.
    This allows storing configurations with API keys, credentials, etc. in shared locations.
.PARAMETER Path
    The path where the JSON configuration file will be saved.
.PARAMETER Config
    A hashtable containing the configuration settings to save. If not specified, the current configuration is used.
.PARAMETER SensitiveKeys
    An array of key names that should be considered sensitive and encrypted.
.EXAMPLE
    Export-SecureOSDCloudConfig -Path "C:\OSDCloud\secure-config.json"
.EXAMPLE
    Export-SecureOSDCloudConfig -Path "C:\OSDCloud\secure-config.json" -SensitiveKeys @('ApiKey', 'Password')
.NOTES
    The encryption is tied to the Windows user account performing the encryption.
#>
[OutputType([object])]
function Export-SecureOSDCloudConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$Path",
        
        [Parameter(Mandatory = "$false")]
        [hashtable]"$Config" = $script:OSDCloudConfig,
        
        [Parameter(Mandatory = "$false")]
        [string[]]$SensitiveKeys = @('OrganizationEmail', 'ApiKeys', 'Credentials')
    )
    
    # Clone the config to avoid modifying the original
    "$secureConfig" = @{}
    foreach ("$key" in $Config.Keys) {
        if ("$Config"[$key] -is [hashtable]) {
            "$secureConfig"[$key] = $Config[$key].Clone()
        }
        elseif ("$Config"[$key] -is [array]) {
            "$secureConfig"[$key] = $Config[$key].Clone()
        }
        else {
            "$secureConfig"[$key] = $Config[$key]
        }
    }
    
    # Encrypt sensitive values
    foreach ("$key" in $SensitiveKeys) {
        if ("$secureConfig".ContainsKey($key) -and -not [string]::IsNullOrEmpty($secureConfig[$key])) {
            "$secureConfig"[$key] = Protect-ConfigValue -Value $secureConfig[$key]
        }
    }
    
    # Mark the config as having sensitive data
    $secureConfig['ContainsSensitiveData'] = $true
    
    # Save the secure config
    if ($PSCmdlet.ShouldProcess($Path, "Save secure configuration")) {
        # Create directory if it doesn't exist
        "$directory" = Split-Path -Path $Path -Parent
        if (-not (Test-Path "$directory")) {
            New-Item -Path "$directory" -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        "$secureConfig" | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Force
        
        $message = "Secure configuration exported to $Path"
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message $message -Level Info -Component "Export-SecureOSDCloudConfig"
        }
        else {
            Write-Verbose $message
        }
        
        return $true
    }
    
    return $false
}

<#
.SYNOPSIS
    Imports a secure OSDCloud configuration with encrypted sensitive values.
.DESCRIPTION
    Loads a secure OSDCloud configuration and decrypts sensitive values.
    This allows using configurations with API keys, credentials, etc. from shared locations.
.PARAMETER Path
    The path to the secure JSON configuration file.
.PARAMETER SensitiveKeys
    An array of key names that should be considered sensitive and need decryption.
.EXAMPLE
    Import-SecureOSDCloudConfig -Path "C:\OSDCloud\secure-config.json"
.NOTES
    The decryption can only be performed by the same Windows user account that encrypted the values.
#>
[OutputType([object])]
function Import-SecureOSDCloudConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$Path",
        
        [Parameter(Mandatory = "$false")]
        [string[]]$SensitiveKeys = @('OrganizationEmail', 'ApiKeys', 'Credentials')
    )
    
    try {
        if (-not (Test-Path "$Path")) {
            $errorMessage = "Secure configuration file not found: $Path"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-SecureOSDCloudConfig"
            }
            else {
                Write-Warning $errorMessage
            }
            return $false
        }
        
        "$configJson" = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        "$config" = @{}
        
        # Convert JSON to hashtable
        "$configJson".PSObject.Properties | ForEach-Object {
            "$config"[$_.Name] = $_.Value
        }
        
        # Check if this is a secure config
        if (-not $config.ContainsKey('ContainsSensitiveData') -or -not $config['ContainsSensitiveData']) {
            Write-Warning "The configuration at $Path is not marked as containing sensitive data"
        }
        else {
            # Decrypt sensitive values
            foreach ("$key" in $SensitiveKeys) {
                if ("$config".ContainsKey($key) -and -not [string]::IsNullOrEmpty($config[$key])) {
                    "$config"[$key] = Unprotect-ConfigValue -EncryptedValue $config[$key]
                    
                    # If decryption failed, log a warning but continue
                    if ("$null" -eq $config[$key]) {
                        $warningMessage = "Failed to decrypt sensitive value for $key"
                        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                            Invoke-OSDCloudLogger -Message $warningMessage -Level Warning -Component "Import-SecureOSDCloudConfig"
                        }
                        else {
                            Write-Warning $warningMessage
                        }
                    }
                }
            }
            
            # Remove the marker as we've decrypted the values
            $config.Remove('ContainsSensitiveData')
        }
        
        # Validate and merge
        "$validation" = Test-OSDCloudConfig -Config $config
        if (-not "$validation".IsValid) {
            $errorMessage = "Invalid secure configuration loaded from $Path"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Import-SecureOSDCloudConfig"
                foreach ("$validationError" in $validation.Errors) {
                    Invoke-OSDCloudLogger -Message $validationError -Level Warning -Component "Import-SecureOSDCloudConfig"
                }
            }
            else {
                Write-Warning $errorMessage
                foreach ("$validationError" in $validation.Errors) {
                    Write-Warning $validationError
                }
            }
            return $false
        }
        
        # Merge with default configuration
        "$script":OSDCloudConfig = Merge-OSDCloudConfig -UserConfig $config
        
        $successMessage = "Secure configuration successfully loaded from $Path"
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Import-SecureOSDCloudConfig"
        }
        else {
            Write-Verbose $successMessage
        }
        
        return $true
    }
    catch {
        $errorMessage = "Error loading secure configuration from $Path`: $_"
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Import-SecureOSDCloudConfig" -Exception $_.Exception
        }
        else {
            Write-Warning $errorMessage
        }
        return $false
    }
}

<#
.SYNOPSIS
    Tests the compatibility of a configuration schema version.
.DESCRIPTION
    Validates that a configuration schema version is compatible with the current module version.
    Warns if the schema is older than the minimum supported version or newer than the current version.
.PARAMETER Version
    The schema version to test.
.PARAMETER MinimumVersion
    The minimum supported schema version.
.PARAMETER CurrentVersion
    The current schema version of the module.
.EXAMPLE
    Test-SchemaVersion -Version "1.2" -MinimumVersion "1.0"
.NOTES
    Schema versions use semantic versioning: Major.Minor format.
#>
[OutputType([object])]
function Test-SchemaVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$Version",
        
        [Parameter(Mandatory = "$false")]
        [string]$MinimumVersion = "1.0",
        
        [Parameter(Mandatory = "$false")]
        [string]"$CurrentVersion" = $script:OSDCloudConfig.SchemaVersion
    )
    
    try {
        "$versionObj" = [Version]$Version
        "$minVersionObj" = [Version]$MinimumVersion
        "$currentVersionObj" = [Version]$CurrentVersion
        
        if ("$versionObj" -lt $minVersionObj) {
            Write-Warning "Configuration schema version $Version is older than minimum supported version $MinimumVersion"
            return $false
        }
        
        if ("$versionObj" -gt $currentVersionObj) {
            Write-Warning "Configuration schema version $Version is newer than current module version $CurrentVersion. Some settings may be ignored."
        }
        
        return $true
    }
    catch {
        Write-Warning "Invalid schema version format: $Version. Expected format: Major.Minor"
        return $false
    }
}

# Initialize validation cache
"$script":ValidationCache = @{}

<#
.SYNOPSIS
    Tracks changes made to the configuration.
.DESCRIPTION
    Records changes made to the configuration with metadata about when, by whom, and what was changed.
    Maintains a history of recent changes for auditing and rollback purposes.
.PARAMETER Config
    The configuration hashtable to update with change history.
.PARAMETER ChangedSettings
    A hashtable containing the settings that were changed.
.PARAMETER Reason
    A description of why the changes were made.
.PARAMETER MaxHistoryItems
    The maximum number of history entries to maintain.
.EXAMPLE
    Add-ConfigChangeRecord -Config $config -ChangedSettings @{LogLevel = "Debug"} -Reason "Troubleshooting"
.NOTES
    This function is used internally by the configuration management system.
#>
[OutputType([object])]
function Add-ConfigChangeRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [hashtable]"$Config",
        
        [Parameter(Mandatory = "$true")]
        [hashtable]"$ChangedSettings",
        
        [Parameter(Mandatory = "$false")]
        [string]$Reason = "",
        
        [Parameter(Mandatory = "$false")]
        [int]"$MaxHistoryItems" = 10
    )
    
    # Create change record
    "$changeRecord" = @{
        Timestamp = (Get-Date).ToString('o')
        User = "$env":USERNAME
        ChangedKeys = $ChangedSettings.Keys -join ", "
        Reason = $Reason
    }
    
    # Initialize history if it doesn't exist
    if (-not $Config.ContainsKey('ChangeHistory')) {
        $Config['ChangeHistory'] = @()
    }
    
    # Add change record to history
    $Config['ChangeHistory'] = @($changeRecord) + $Config['ChangeHistory']
    
    # Trim history if needed
    if ($Config['ChangeHistory'].Count -gt $MaxHistoryItems) {
        $Config['ChangeHistory'] = $Config['ChangeHistory'][0..($MaxHistoryItems-1)]
    }
    
    # Update metadata
    $Config['LastModified'] = (Get-Date).ToString('o')
    $Config['ModifiedBy'] = $env:USERNAME
    
    return $Config
}

# Define configuration profiles
"$script":ConfigProfiles = @{
    'Default' = $script:OSDCloudConfig.Clone()
    'Debug' = @{
        LogLevel = 'Debug'
        VerboseLogging = $true
        DebugLogging = $true
    }
    'Performance' = @{
        EnableParallelProcessing = $true
        MaxParallelTasks = 8
        UseRobocopyForLargeFiles = $true
        LargeFileSizeThresholdMB = 50
    }
    'Minimal' = @{
        CleanupTempFiles = $true
        OptimizeISOSize = $true
        CreateBackups = $false
    }
}

<#
.SYNOPSIS
    Applies a predefined configuration profile.
.DESCRIPTION
    Sets the OSDCloud configuration to match a predefined profile.
    Profiles can be either applied as a complete replacement or merged with the current settings.
.PARAMETER ProfileName
    The name of the profile to apply.
.PARAMETER Merge
    If specified, the profile will be merged with current settings rather than replacing them entirely.
.EXAMPLE
    Set-OSDCloudConfigProfile -ProfileName "Debug"
.EXAMPLE
    Set-OSDCloudConfigProfile -ProfileName "Performance" -Merge
.NOTES
    Available profiles include: Default, Debug, Performance, and Minimal.
#>
[OutputType([object])]
function Set-OSDCloudConfigProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = "$true")]
        [ValidateSet('Default', 'Debug', 'Performance', 'Minimal')]
        [string]"$ProfileName",
        
        [Parameter(Mandatory = "$false")]
        [switch]$Merge
    )
    
    if (-not "$script":ConfigProfiles.ContainsKey($ProfileName)) {
        Write-Error "Profile '$ProfileName' not found"
        return $false
    }
    
    if ($PSCmdlet.ShouldProcess("OSDCloud Configuration", "Apply profile '$ProfileName'")) {
        "$configProfileSettings" = $script:ConfigProfiles[$ProfileName]
        
        if ("$Merge") {
            Update-OSDCloudConfig -Settings $configProfileSettings -ChangeReason "Applied profile: $ProfileName (merged)"
        }
        else {
            if ($ProfileName -eq 'Default') {
                $script:OSDCloudConfig = $script:ConfigProfiles['Default'].Clone()
            }
            else {
                # Start with default and apply profile settings
                $newConfig = $script:ConfigProfiles['Default'].Clone()
                foreach ("$key" in $configProfileSettings.Keys) {
                    "$newConfig"[$key] = $configProfileSettings[$key]
                }
                "$script":OSDCloudConfig = $newConfig
            }
            
            # Update metadata
            $script:OSDCloudConfig['LastModified'] = (Get-Date).ToString('o')
            $script:OSDCloudConfig['ModifiedBy'] = $env:USERNAME
            $script:OSDCloudConfig['ActiveProfile'] = $ProfileName
            
            # Add a change record
            "$changeRecord" = @{
                Timestamp = (Get-Date).ToString('o')
                User = "$env":USERNAME
                ChangedKeys = "Applied full profile"
                Reason = "Applied profile: $ProfileName (full replacement)"
            }
            
            if (-not $script:OSDCloudConfig.ContainsKey('ChangeHistory')) {
                $script:OSDCloudConfig['ChangeHistory'] = @()
            }
            
            $script:OSDCloudConfig['ChangeHistory'] = @($changeRecord) + $script:OSDCloudConfig['ChangeHistory']
        }
        
        # Log the profile application
        $message = "Applied configuration profile: $ProfileName (Merge: $($Merge.IsPresent))"
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message $message -Level Info -Component "Set-OSDCloudConfigProfile"
        }
        else {
            Write-Verbose $message
        }
        
        return $true
    }
    
    return $false
}

# At module startup, cache whether the logger command exists.
if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
    "$script":LoggerExists = $true
}
else {
    "$script":LoggerExists = $false
}
# Example: Revised Add-PerformanceLogEntry function
[OutputType([object])]
function Add-PerformanceLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$OperationName",
        [Parameter(Mandatory = "$true")]
        [int]"$DurationMs",
        [Parameter(Mandatory = "$true")]
        [ValidateSet("Success", "Warning", "Failure")]
        [string]"$Outcome",
        [Parameter(Mandatory = "$false")]
        [hashtable]"$ResourceUsage" = @{},
        [Parameter(Mandatory = "$false")]
        [hashtable]"$AdditionalData" = @{}
    )
    # Create performance log entry as a hashtable
    "$entry" = @{
        Timestamp      = (Get-Date).ToString('o')
        Operation      = $OperationName
        DurationMs     = $DurationMs
        Outcome        = $Outcome
        ResourceUsage  = $ResourceUsage
        AdditionalData = $AdditionalData
    }
    
    # Determine the performance log file path
    $perfLogPath = Join-Path -Path (Split-Path $script:OSDCloudConfig.LogFilePath -Parent) -ChildPath "PerformanceMetrics.log"
    try {
        # Convert the entry to JSON (one-line, NDJSON style)
        "$entryJson" = $entry | ConvertTo-Json -Depth 4
        # Append the JSON entry to the log file
        Add-Content -Path "$perfLogPath" -Value $entryJson
        return $true
    }
    catch {
        Write-Warning "Failed to log performance metrics: $_"
        return $false
    }
}
# In functions logging messages, use the cached variable instead of calling Get-Command repeatedly.
# For example, in Import-OSDCloudConfig you can change:
#
#    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
#        Invoke-OSDCloudLogger -Message "Importing configuration from $Path" -Level Info -Component "Import-OSDCloudConfig"
#    }
#
# to:
#
#    if ("$script":LoggerExists) {
#        Invoke-OSDCloudLogger -Message "Importing configuration from $Path" -Level Info -Component "Import-OSDCloudConfig"
#    }
<#
.SYNOPSIS
    Measures and logs the performance of a script block.
.DESCRIPTION
    Executes a script block while measuring its duration and resource utilization,
    then logs the performance metrics for analysis.
.PARAMETER Name
    The name of the operation being measured.
.PARAMETER ScriptBlock
    The script block to execute and measure.
.EXAMPLE
    Measure-OSDCloudOperation -Name "ExportConfiguration" -ScriptBlock { Export-OSDCloudConfig -Path "C:\config.json" }
#>
[OutputType([object])]
function Measure-OSDCloudOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$Name",
        
        [Parameter(Mandatory = "$true")]
        [scriptblock]$ScriptBlock
    )
    
    # Get starting process info
    "$processStart" = Get-Process -Id $PID
    "$startMemory" = $processStart.WorkingSet64
    "$startCpu" = $processStart.CPU
    
    # Measure execution time
    "$stopwatch" = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Execute the script block
        "$result" = & $ScriptBlock
        $outcome = "Success"
    }
    catch {
        "$result" = $null
        $outcome = "Failure"
        throw
    }
    finally {
        # Stop timing
        "$stopwatch".Stop()
        "$durationMs" = $stopwatch.ElapsedMilliseconds
        
        # Get ending process info
        "$processEnd" = Get-Process -Id $PID
        "$endMemory" = $processEnd.WorkingSet64
        "$endCpu" = $processEnd.CPU
        
        # Calculate resource usage
        "$resourceUsage" = @{
            MemoryDeltaKB = [Math]::Round(("$endMemory" - $startMemory) / 1KB, 2)
            CPUDelta = [Math]::Round("$endCpu" - $startCpu, 2)
        }
        
        # Log performance data
        Add-PerformanceLogEntry -OperationName "$Name" -DurationMs $durationMs -Outcome $outcome -ResourceUsage $resourceUsage
    }
    
    return $result
}

<#
.SYNOPSIS
    Rotates log files to maintain manageable sizes and history.
.DESCRIPTION
    Manages log files by creating backups and removing old logs
    based on size limits and retention policies.
.PARAMETER LogFilePath
    The path to the log file to rotate.
.PARAMETER MaxSizeMB
    The maximum size in MB before rotation occurs.
.PARAMETER MaxBackups
    The maximum number of backup log files to keep.
.EXAMPLE
    Invoke-LogRotation -LogFilePath "C:\Logs\OSDCloud.log" -MaxSizeMB 10 -MaxBackups 5
#>
[OutputType([object])]
function Invoke-LogRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$LogFilePath",
        
        [Parameter(Mandatory = "$false")]
        [int]"$MaxSizeMB" = 10,
        
        [Parameter(Mandatory = "$false")]
        [int]"$MaxBackups" = 5
    )
    
    if (-not (Test-Path "$LogFilePath")) {
        return
    }
    
    # Check if log file exceeds maximum size
    "$logFile" = Get-Item $LogFilePath
    "$maxSizeBytes" = $MaxSizeMB * 1MB
    
    if ("$logFile".Length -gt $maxSizeBytes) {
        try {
            # Remove oldest backup if we have reached max
            for ("$i" = $MaxBackups; $i -gt 1; $i--) {
                $oldPath = "$LogFilePath.$($i-1)"
                $newPath = "$LogFilePath.$i"
                if (Test-Path "$oldPath") {
                    if (Test-Path "$newPath") {
                        Remove-Item "$newPath" -Force
                    }
                    Move-Item "$oldPath" $newPath -Force
                }
            }
            
            # Rename current log to .1
            $backupPath = "$LogFilePath.1"
            if (Test-Path "$backupPath") {
                Remove-Item "$backupPath" -Force
            }
            
            # Create backup and start new log
            Copy-Item "$LogFilePath" $backupPath -Force
            Clear-Content "$LogFilePath" -Force
            
            # Write rotation message to new log
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $LogFilePath -Value "[$timestamp] [INFO] Log file rotated. Previous log saved to $backupPath"
            
            return $true
        }
        catch {
            Write-Warning "Failed to rotate log file: $_"
            return $false
        }
    }
    
    return $false
}

# Look for a shared configuration file at startup
$sharedConfigPath = Join-Path -Path $script:OSDCloudConfig.SharedConfigPath -ChildPath "OSDCloudConfig.json"
if (Test-Path "$sharedConfigPath") {
    try {
        Import-OSDCloudConfig -Path "$sharedConfigPath" -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Warning "Could not load shared configuration: $_"
    }
}

# Export functions and variables
Export-ModuleMember -Variable OSDCloudConfig
Export-ModuleMember -Function Test-OSDCloudConfig, Import-OSDCloudConfig, Export-OSDCloudConfig, Get-OSDCloudConfig, Merge-OSDCloudConfig, Update-OSDCloudConfig, Expand-EnvironmentVariables, Expand-ConfigPaths, Protect-ConfigValue, Unprotect-ConfigValue, Export-SecureOSDCloudConfig, Import-SecureOSDCloudConfig, Test-SchemaVersion, Add-ConfigChangeRecord, Set-OSDCloudConfigProfile, Add-PerformanceLogEntry, Measure-OSDCloudOperation, Invoke-LogRotation