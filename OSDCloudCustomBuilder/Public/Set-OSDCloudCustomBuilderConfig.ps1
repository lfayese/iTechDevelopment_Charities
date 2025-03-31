function Set-OSDCloudCustomBuilderConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DefaultPowerShellVersion,
        
        [Parameter(Mandatory = $false)]
        [string[]]$SupportedPowerShellVersions,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$PowerShellVersionHashes,
        
        [Parameter(Mandatory = $false)]
        [string]$PowerShellDownloadUrl,
        
        [Parameter(Mandatory = $false)]
        [int]$MountTimeout,
        
        [Parameter(Mandatory = $false)]
        [int]$DismountTimeout,
        
        [Parameter(Mandatory = $false)]
        [int]$DownloadTimeout,
        
        [Parameter(Mandatory = $false)]
        [int]$JobTimeout,
        
        [Parameter(Mandatory = $false)]
        [string]$CachePath,
        
        [Parameter(Mandatory = $false)]
        [string]$TempPath
    )
    
    # Get current configuration
    $config = Get-ModuleConfiguration
    
    # Update configuration with provided parameters
    if ($PSBoundParameters.ContainsKey('DefaultPowerShellVersion')) {
        $config.PowerShellVersions.Default = $DefaultPowerShellVersion
    }
    
    if ($PSBoundParameters.ContainsKey('SupportedPowerShellVersions')) {
        $config.PowerShellVersions.Supported = $SupportedPowerShellVersions
    }
    
    if ($PSBoundParameters.ContainsKey('PowerShellVersionHashes')) {
        foreach ($key in $PowerShellVersionHashes.Keys) {
            $config.PowerShellVersions.Hashes[$key] = $PowerShellVersionHashes[$key]
        }
    }
    
    if ($PSBoundParameters.ContainsKey('PowerShellDownloadUrl')) {
        $config.DownloadSources.PowerShell = $PowerShellDownloadUrl
    }
    
    if ($PSBoundParameters.ContainsKey('MountTimeout')) {
        $config.Timeouts.Mount = $MountTimeout
    }
    
    if ($PSBoundParameters.ContainsKey('DismountTimeout')) {
        $config.Timeouts.Dismount = $DismountTimeout
    }
    
    if ($PSBoundParameters.ContainsKey('DownloadTimeout')) {
        $config.Timeouts.Download = $DownloadTimeout
    }
    
    if ($PSBoundParameters.ContainsKey('JobTimeout')) {
        $config.Timeouts.Job = $JobTimeout
    }
    
    if ($PSBoundParameters.ContainsKey('CachePath')) {
        $config.Paths.Cache = $CachePath
    }
    
    if ($PSBoundParameters.ContainsKey('TempPath')) {
        $config.Paths.Temp = $TempPath
    }
    
    # Save configuration
    $configDir = Split-Path -Path "$env:USERPROFILE\.osdcloudcustombuilder\config.json" -Parent
    if (-not (Test-Path -Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path "$env:USERPROFILE\.osdcloudcustombuilder\config.json"
    
    Write-Host "OSDCloudCustomBuilder configuration updated successfully" -ForegroundColor Green
}

# Export the function
Export-ModuleMember -Function Set-OSDCloudCustomBuilderConfig