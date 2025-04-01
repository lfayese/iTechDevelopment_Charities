<#
.SYNOPSIS
    Retrieves the configuration settings for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This function loads and returns the configuration settings for the OSDCloudCustomBuilder module.
    It merges default configuration with user-defined settings from a JSON configuration file,
    and also supports environment variable overrides. The function handles configuration loading
    errors gracefully and creates required directories if they don't exist.
.PARAMETER ConfigPath
    Optional path to a custom configuration file. If not specified, the function looks for
    a config.json file in the user's .osdcloudcustombuilder directory.
.PARAMETER NoEnvironmentOverride
    If specified, disables the environment variable override functionality.
.EXAMPLE
    Get-ModuleConfiguration
    Returns the merged configuration using default locations and settings.
.EXAMPLE
    Get-ModuleConfiguration -ConfigPath "C:\CustomConfig\myconfig.json"
    Returns configuration using the specified custom configuration file.
.EXAMPLE
    Get-ModuleConfiguration -NoEnvironmentOverride
    Returns configuration without applying environment variable overrides.
.NOTES
    Environment variable overrides use the format OSDCB_SECTION_KEY.
    For example, OSDCB_TIMEOUTS_MOUNT would override the Timeouts.Mount setting.
#>
function Get-ModuleConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateScript({
            if (-not (Test-Path $_) -and $_ -ne '') {
                throw "The specified configuration file does not exist: $_"
            }
            if ($_ -ne '' -and -not ($_ -match '\.json$')) {
                throw "The configuration file must be a JSON file"
            }
            return $true
        })]
        [string]$ConfigPath = '',
        
        [Parameter()]
        [switch]$NoEnvironmentOverride
    )
    
    begin {
        # Initialize logging if the function is available
        $loggingAvailable = $false
        try {
            if (Get-Command -Name Write-OSDCloudLog -ErrorAction SilentlyContinue) {
                $loggingAvailable = $true
                Write-OSDCloudLog -Message "Starting module configuration retrieval" -Level Info -Component "Get-ModuleConfiguration"
            }
        }
        catch {
            # Silently continue if logging is not available
        }
        
        # Helper function to log messages
        function Write-ConfigLog {
            param(
                [string]$Message,
                [string]$Level = "Info",
                [System.Management.Automation.ErrorRecord]$Exception = $null
            )
            
            if ($loggingAvailable) {
                Write-OSDCloudLog -Message $Message -Level $Level -Component "Get-ModuleConfiguration" -Exception $Exception
            }
            
            switch ($Level) {
                "Error" { Write-Error $Message }
                "Warning" { Write-Warning $Message }
                "Info" { Write-Verbose $Message }
                default { Write-Verbose $Message }
            }
        }
    }
    
    process {
        try {
            # Define default configuration
            Write-ConfigLog "Initializing default configuration"
            $defaultConfig = @{
                PowerShellVersions = @{
                    Default = "7.3.4"
                    Supported = @("7.3.4", "7.4.0", "7.4.1", "7.5.0")
                    Hashes = @{
                        "7.3.4" = "4092F9C94F11C9D4C748D27E012B4AB9F80935F30F753744EB42E4B8980CE76B"
                        "7.4.0" = "E7C7DF60C5BD226BFF91F7681A9F38F47D47666804840F87218F72EFFC3C2B9A"
                        "7.4.1" = "0EB56A005B68C833FF690BC0EFF00DC7D392C9F27835B6A353129D7E9A1910EF"
                        "7.5.0" = "A1C81C21E42AB6C43F8A93F65F36C0F95C3A48C4A948C5A63D8F9ACBF1CB06C5"
                    }
                }
                DownloadSources = @{
                    PowerShell = "https://github.com/PowerShell/PowerShell/releases/download/v{0}/PowerShell-{0}-win-x64.zip"
                }
                Timeouts = @{
                    Mount = 300
                    Dismount = 300
                    Download = 600
                    Job = 1200
                }
                Paths = @{
                    Cache = Join-Path -Path $env:LOCALAPPDATA -ChildPath "OSDCloudCustomBuilder\Cache"
                    Temp = Join-Path -Path $env:TEMP -ChildPath "OSDCloudCustomBuilder"
                    Logs = Join-Path -Path $env:LOCALAPPDATA -ChildPath "OSDCloudCustomBuilder\Logs"
                }
                Logging = @{
                    Enabled = $true
                    Level = "Info"  # Possible values: Error, Warning, Info, Verbose, Debug
                    RetentionDays = 30
                }
            }
            
            # Determine user configuration path
            $userConfigPath = if ($ConfigPath -ne '') {
                $ConfigPath
            } else {
                Join-Path -Path $env:USERPROFILE -ChildPath ".osdcloudcustombuilder\config.json"
            }
            
            # Load and merge user configuration if available
            if (Test-Path -Path $userConfigPath) {
                try {
                    Write-ConfigLog "Loading user configuration from $userConfigPath"
                    $userConfigContent = Get-Content -Path $userConfigPath -Raw -ErrorAction Stop
                    $userConfig = $userConfigContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    
                    # Merge user config with defaults using recursive merge
                    Write-ConfigLog "Merging user configuration with defaults"
                    MergeHashtables -Source $userConfig -Target $defaultConfig
                }
                catch [System.IO.IOException] {
                    Write-ConfigLog "Failed to read user configuration file: $_" -Level "Warning" -Exception $_
                }
                catch [System.Management.Automation.RuntimeException] {
                    Write-ConfigLog "Failed to parse user configuration JSON: $_" -Level "Warning" -Exception $_
                }
                catch {
                    Write-ConfigLog "Unexpected error loading user configuration: $_" -Level "Warning" -Exception $_
                }
            } else {
                Write-ConfigLog "No user configuration found at $userConfigPath"
            }
            
            # Apply environment variable overrides
            if (-not $NoEnvironmentOverride) {
                try {
                    Write-ConfigLog "Checking for environment variable overrides"
                    ApplyEnvironmentOverrides -Config $defaultConfig
                }
                catch {
                    Write-ConfigLog "Error applying environment variable overrides: $_" -Level "Warning" -Exception $_
                }
            }
            
            # Create required directories
            foreach ($directory in @($defaultConfig.Paths.Cache, $defaultConfig.Paths.Logs)) {
                try {
                    if (-not (Test-Path -Path $directory)) {
                        Write-ConfigLog "Creating directory: $directory"
                        New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }
                }
                catch {
                    Write-ConfigLog "Failed to create directory $directory: $_" -Level "Warning" -Exception $_
                }
            }
            
            Write-ConfigLog "Configuration retrieval completed successfully"
            return $defaultConfig
        }
        catch {
            Write-ConfigLog "Critical error in Get-ModuleConfiguration: $_" -Level "Error" -Exception $_
            throw "Failed to retrieve module configuration: $_"
        }
    }
}

<#
.SYNOPSIS
    Recursively merges two hashtables.
.DESCRIPTION
    Helper function that recursively merges the source hashtable into the target hashtable.
    When both source and target have the same key and both values are hashtables, it performs
    a recursive merge. Otherwise, the source value overwrites the target value.
.PARAMETER Source
    The source hashtable to merge from.
.PARAMETER Target
    The target hashtable to merge into.
#>
function MergeHashtables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Source,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Target
    )
    
    foreach ($key in $Source.Keys) {
        if ($Target.ContainsKey($key)) {
            if ($Source[$key] -is [hashtable] -and $Target[$key] -is [hashtable]) {
                # Recursive merge for nested hashtables
                MergeHashtables -Source $Source[$key] -Target $Target[$key]
            }
            else {
                # Override value
                $Target[$key] = $Source[$key]
            }
        }
        else {
            # Add new key
            $Target[$key] = $Source[$key]
        }
    }
}

<#
.SYNOPSIS
    Applies environment variable overrides to configuration.
.DESCRIPTION
    Applies environment variable overrides to the configuration hashtable.
    Environment variables must be in the format OSDCB_SECTION_KEY.
.PARAMETER Config
    The configuration hashtable to apply overrides to.
#>
function ApplyEnvironmentOverrides {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )
    
    # Get all environment variables starting with OSDCB_
    $envVars = Get-ChildItem -Path Env: | Where-Object { $_.Name -like "OSDCB_*" }
    
    foreach ($var in $envVars) {
        $parts = $var.Name -split '_', 3
        if ($parts.Count -ge 3) {
            $section = $parts[1]
            $key = $parts[2]
            
            if ($Config.ContainsKey($section) -and $Config[$section] -is [hashtable]) {
                $value = $var.Value
                
                # Try to convert the value to the appropriate type
                if ($value -eq "true" -or $value -eq "false") {
                    $value = [bool]::Parse($value)
                }
                elseif ($value -match "^\d+$") {
                    $value = [int]::Parse($value)
                }
                elseif ($value -match "^\d+\.\d+$") {
                    $value = [double]::Parse($value)
                }
                
                # Apply the override
                $Config[$section][$key] = $value
                Write-Verbose "Applied environment override: $section.$key = $value"
            }
        }
    }
}

# Export the function
Export-ModuleMember -Function Get-ModuleConfiguration