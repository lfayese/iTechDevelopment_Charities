function Get-FileHashCached {
    param (
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$HashFilePath
    )
    
    # If the hash file exists and is newer than the file, use the cached hash.
    if (Test-Path -Path $HashFilePath) {
        $hashFileInfo = Get-Item $HashFilePath
        $fileInfo = Get-Item $FilePath
        if ($hashFileInfo.LastWriteTime -ge $fileInfo.LastWriteTime) {
            return Get-Content -Path $HashFilePath -Raw
        }
    }
    
    # Otherwise compute the hash 
    $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    # Save it to the hash file for future use
    $hash | Out-File -FilePath $HashFilePath -Encoding ascii
    return $hash
}
# A very simple file-lock mechanism based on a lock file.
function Enter-Lock {
    param (
        [string]$LockPath,
        [int]$TimeoutSec = 5
    )
    
    $stopWatch = [Diagnostics.Stopwatch]::StartNew()
    while (Test-Path -Path $LockPath) {
        if ($stopWatch.Elapsed.TotalSeconds -ge $TimeoutSec) {
            throw "Could not acquire lock at $LockPath"
        }
        Start-Sleep -Milliseconds 200
    }
    # Create lock file
    New-Item -Path $LockPath -ItemType File -Force | Out-Null
}
function Exit-Lock {
    param (
        [string]$LockPath
    )
    if (Test-Path -Path $LockPath) {
        Remove-Item -Path $LockPath -Force
    }
}
# Global (static) variable to track if cache directory exists
if (-not $script:CacheDirExists) { $script:CacheDirExists = @{} }
function Get-CachedPowerShellPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    # Get module configuration
    $config = Get-ModuleConfiguration
    
    # Define cache location
    $cacheRoot = $config.Paths.Cache
    # Check (and cache) if the directory exists to avoid repeated filesystem calls.
    if (-not $script:CacheDirExists.ContainsKey($cacheRoot)) {
        if (-not (Test-Path -Path $cacheRoot)) {
            New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
        }
        $script:CacheDirExists[$cacheRoot] = $true
    }
    $cachedPackagePath = Join-Path -Path $cacheRoot -ChildPath "PowerShell-$Version-win-x64.zip"
    $hashCachePath = $cachedPackagePath + ".sha256"
    # Simple lock file to avoid concurrency issues.
    $lockFile = $cachedPackagePath + ".lock"
    try {
        Enter-Lock -LockPath $lockFile -TimeoutSec 5
        if (Test-Path -Path $cachedPackagePath) {
            # If we have a reference hash stored in configuration, verify the hash.
            if ($config.PowerShellVersions.Hashes.ContainsKey($Version)) {
                $expectedHash = $config.PowerShellVersions.Hashes[$Version]
                # Get-FileHashCached reduces the need for the expensive computation.
                $actualHash = Get-FileHashCached -FilePath $cachedPackagePath -HashFilePath $hashCachePath
                
                if ($actualHash -eq $expectedHash) {
                    Write-OSDCloudLog -Message "Using cached PowerShell $Version package from $cachedPackagePath" -Level Info -Component "Get-CachedPowerShellPackage"
                    return $cachedPackagePath
                }
                else {
                    Write-OSDCloudLog -Message "Cached PowerShell $Version package has invalid hash. Expected: $expectedHash, Got: $actualHash" -Level Warning -Component "Get-CachedPowerShellPackage"
                    # Delete the invalid file and clean up the cached hash.
                    Remove-Item -Path $cachedPackagePath -Force -ErrorAction SilentlyContinue
                    if (Test-Path $hashCachePath) {
                        Remove-Item -Path $hashCachePath -Force -ErrorAction SilentlyContinue
                    }
                    return $null
                }
            }
            else {
                Write-OSDCloudLog -Message "Using cached PowerShell $Version package from $cachedPackagePath (hash verification skipped)" -Level Info -Component "Get-CachedPowerShellPackage"
                return $cachedPackagePath
            }
        }
    }
    finally {
        Exit-Lock -LockPath $lockFile
    }
    
    return $null
}
# Export the function
Export-ModuleMember -Function Get-CachedPowerShellPackage