function Get-ModuleConfiguration {
    [CmdletBinding()]
    param()
    
    # Define default configuration
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
        }
    }
    
    # Check for user configuration file
    $userConfigPath = Join-Path -Path $env:USERPROFILE -ChildPath ".osdcloudcustombuilder\config.json"
    if (Test-Path -Path $userConfigPath) {
        try {
            $userConfig = Get-Content -Path $userConfigPath -Raw | ConvertFrom-Json -AsHashtable
            
            # Merge user config with defaults
            foreach ($key in $userConfig.Keys) {
                if ($defaultConfig.ContainsKey($key)) {
                    if ($userConfig[$key] -is [Hashtable]) {
                        foreach ($subKey in $userConfig[$key].Keys) {
                            $defaultConfig[$key][$subKey] = $userConfig[$key][$subKey]
                        }
                    }
                    else {
                        $defaultConfig[$key] = $userConfig[$key]
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to load user configuration: $_"
        }
    }
    
    # Create cache directory if it doesn't exist
    if (-not (Test-Path -Path $defaultConfig.Paths.Cache)) {
        New-Item -Path $defaultConfig.Paths.Cache -ItemType Directory -Force | Out-Null
    }
    
    return $defaultConfig
}

# Export the function
Export-ModuleMember -Function Get-ModuleConfiguration