<#
.SYNOPSIS
    Sets or retrieves configuration for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This function allows you to view and modify the configuration settings for the OSDCloudCustomBuilder module.
    Changes are persisted between PowerShell sessions.
.PARAMETER Setting
    The name of the specific setting to retrieve. If not specified, all settings are returned.
.PARAMETER Value
    The new value to set for the specified setting.
.PARAMETER Reset
    If specified, resets all configuration settings to their default values.
.PARAMETER DefaultPowerShellVersion
    The default PowerShell version to use for OSDCloud customization (e.g., "7.5.0").
.PARAMETER TelemetryEnabled
    Enables or disables telemetry collection.
.PARAMETER TelemetryDetail
    The level of telemetry detail to collect. Valid values are "Basic", "Standard", "Full".
.PARAMETER EnableVerboseLogging
    Enables or disables verbose logging.
.PARAMETER LogPath
    The path where log files will be stored.
.PARAMETER Timeouts
    A hashtable containing timeout values for various operations.
.EXAMPLE
    Set-OSDCloudCustomBuilderConfig -TelemetryEnabled $false -EnableVerboseLogging $true
    Disables telemetry and enables verbose logging for the module.
.EXAMPLE
    Set-OSDCloudCustomBuilderConfig -Setting "DefaultPowerShellVersion" -Value "7.5.0"
    Sets the default PowerShell version to use.
.EXAMPLE
    Set-OSDCloudCustomBuilderConfig -Reset
    Resets all configuration settings to their default values.
.EXAMPLE
    Set-OSDCloudCustomBuilderConfig
    Returns the current configuration settings.
.NOTES
    File Name      : Set-OSDCloudCustomBuilderConfig.ps1
    Version        : 0.3.0
    Author         : OSDCloud Team
#>
function Set-OSDCloudCustomBuilderConfig {
    [CmdletBinding(DefaultParameterSetName = 'Multiple')]
    param (
        [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
        [string]$Setting,
        
        [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
        [object]$Value,
        
        [Parameter(ParameterSetName = 'Reset')]
        [switch]$Reset,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [string]$DefaultPowerShellVersion,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [bool]$TelemetryEnabled,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [ValidateSet('Basic', 'Standard', 'Full')]
        [string]$TelemetryDetail,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [bool]$EnableVerboseLogging,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [string]$LogPath,
        
        [Parameter(ParameterSetName = 'Multiple')]
        [hashtable]$Timeouts
    )
    
    # Import required functions if running standalone
    try {
        $moduleFunctions = Get-Command -Module OSDCloudCustomBuilder -ErrorAction Stop
        $hasModuleFunctions = $true
    }
    catch {
        $hasModuleFunctions = $false
    }
    
    if (-not $hasModuleFunctions) {
        Write-Verbose "Running in standalone mode, trying to import module functions..."
        try {
            # Try to find and import module for standalone operation
            $moduleRoot = Split-Path -Parent $PSScriptRoot
            $modulePsd1 = Join-Path -Path $moduleRoot -ChildPath "OSDCloudCustomBuilder.psd1"
            if (Test-Path -Path $modulePsd1) {
                Import-Module $modulePsd1 -Force
                Write-Verbose "Successfully imported module from $modulePsd1"
            }
            else {
                throw "Cannot find module manifest at $modulePsd1"
            }
        }
        catch {
            Write-Error "Failed to load module functions. This function requires the OSDCloudCustomBuilder module: $_"
            return
        }
    }
    
    # If no parameters are provided, simply return the current configuration
    if ($PSBoundParameters.Count -eq 0) {
        return Get-ModuleConfiguration
    }
    
    # Handle different parameter sets
    switch ($PSCmdlet.ParameterSetName) {
        'Reset' {
            Write-Verbose "Resetting all configuration settings to defaults"
            Reset-ModuleConfiguration
            return Get-ModuleConfiguration
        }
        
        'Single' {
            Write-Verbose "Setting single configuration value: $Setting = $Value"
            
            # Validate special cases
            if ($Setting -eq 'Timeouts' -and $Value -isnot [hashtable]) {
                Write-Error "When setting 'Timeouts', Value must be a hashtable"
                return
            }
            
            if ($Setting -eq 'TelemetryDetail' -and $Value -notin @('Basic', 'Standard', 'Full')) {
                Write-Error "TelemetryDetail must be one of: 'Basic', 'Standard', 'Full'"
                return
            }
            
            # Create settings hashtable with just the one setting
            $settings = @{ $Setting = $Value }
            Update-ModuleConfiguration -Settings $settings
            
            # Return the updated configuration
            return Get-ModuleConfiguration
        }
        
        'Multiple' {
            # Create settings hashtable from provided parameters
            $settings = @{}
            
            if ($PSBoundParameters.ContainsKey('DefaultPowerShellVersion')) {
                $settings['DefaultPowerShellVersion'] = $DefaultPowerShellVersion
            }
            
            if ($PSBoundParameters.ContainsKey('TelemetryEnabled')) {
                $settings['TelemetryEnabled'] = $TelemetryEnabled
            }
            
            if ($PSBoundParameters.ContainsKey('TelemetryDetail')) {
                $settings['TelemetryDetail'] = $TelemetryDetail
            }
            
            if ($PSBoundParameters.ContainsKey('EnableVerboseLogging')) {
                $settings['EnableVerboseLogging'] = $EnableVerboseLogging
            }
            
            if ($PSBoundParameters.ContainsKey('LogPath')) {
                $settings['LogPath'] = $LogPath
            }
            
            if ($PSBoundParameters.ContainsKey('Timeouts')) {
                $settings['Timeouts'] = $Timeouts
            }
            
            # Only update if we have settings to update
            if ($settings.Count -gt 0) {
                Write-Verbose "Updating multiple configuration settings: $($settings.Keys -join ', ')"
                Update-ModuleConfiguration -Settings $settings
            }
            
            # Return the updated configuration
            return Get-ModuleConfiguration
        }
    }
}
# Export the function so it is available as a module member
Export-ModuleMember -Function Set-OSDCloudCustomBuilderConfig