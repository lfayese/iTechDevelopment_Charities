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
    # Retrieve the existing configuration object
    $config = Get-ModuleConfiguration
    # Update configuration with provided parameters using PSBoundParameters checks
    if ($PSBoundParameters.ContainsKey('DefaultPowerShellVersion')) {
        $config.PowerShellVersions.Default = $DefaultPowerShellVersion
    }
    if ($PSBoundParameters.ContainsKey('SupportedPowerShellVersions')) {
        $config.PowerShellVersions.Supported = $SupportedPowerShellVersions
    }
    if ($PSBoundParameters.ContainsKey('PowerShellVersionHashes')) {
        # Merge the provided hashtable into the configuration.
        foreach ($item in $PowerShellVersionHashes.GetEnumerator()) {
            $config.PowerShellVersions.Hashes[$item.Key] = $item.Value
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
    # Define the configuration file path only once
    $configPath = Join-Path -Path $env:USERPROFILE -ChildPath ".osdcloudcustombuilder\config.json"
    $configDir = Split-Path -Path $configPath -Parent
    # Create the directory if it doesn't exist
    if (-not (Test-Path -Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    # Convert the configuration to JSON and save it
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath
    Write-Host "OSDCloudCustomBuilder configuration updated successfully" -ForegroundColor Green
}
# Export the function so it is available as a module member
Export-ModuleMember -Function Set-OSDCloudCustomBuilderConfig