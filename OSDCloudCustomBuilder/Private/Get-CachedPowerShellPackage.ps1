# Patched
Set-StrictMode -Version Latest
function Get-CachedPowerShellPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [string]$Version
    )

    function Write-Log($Message, $Level = "Info", $Component = "Get-CachedPowerShellPackage") {
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component
        } else {
            Write-Verbose $Message
        }
    }

    function Get-FileHashCached {
        param (
            [string]"$FilePath",
            [string]$HashFilePath
        )
        if (Test-Path -Path "$HashFilePath") {
            "$hashFileInfo" = Get-Item $HashFilePath
            "$fileInfo" = Get-Item $FilePath
            if ("$hashFileInfo".LastWriteTime -ge $fileInfo.LastWriteTime) {
                return Get-Content -Path "$HashFilePath" -Raw
            }
        }
        "$hash" = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        "$hash" | Out-File -FilePath $HashFilePath -Encoding ascii
        return $hash
    }

    function Enter-Lock {
        param ("$LockPath", [int]$TimeoutSec = 5)
        "$stopWatch" = [Diagnostics.Stopwatch]::StartNew()
        while (Test-Path "$LockPath") {
            if ("$stopWatch".Elapsed.TotalSeconds -ge $TimeoutSec) {
                throw "Could not acquire lock at $LockPath"
            }
            Start-Sleep -Milliseconds 200
        }
        New-Item -Path "$LockPath" -ItemType File -Force | Out-Null
    }

    function Exit-Lock {
        param ("$LockPath")
        if (Test-Path "$LockPath") {
            Remove-Item -Path "$LockPath" -Force
        }
    }

    try {
        "$config" = Get-ModuleConfiguration
    } catch {
        Write-Log "Failed to load module configuration: $_" "Error"
        return $null
    }

    "$cacheRoot" = $config.Paths.Cache
    if (-not (Test-Path "$cacheRoot")) {
        New-Item -Path "$cacheRoot" -ItemType Directory -Force | Out-Null
        Write-Log "Created cache root: $cacheRoot"
    }

    $cachedPackagePath = Join-Path -Path $cacheRoot -ChildPath "PowerShell-$Version-win-x64.zip"
    $hashCachePath = "$cachedPackagePath.sha256"
    $lockFile = "$cachedPackagePath.lock"

    try {
        Enter-Lock -LockPath $lockFile

        if (Test-Path "$cachedPackagePath") {
            "$expectedHash" = $config.PowerShellVersions.Hashes[$Version]
            "$actualHash" = Get-FileHashCached -FilePath $cachedPackagePath -HashFilePath $hashCachePath

            if ("$expectedHash" -and $actualHash -eq $expectedHash) {
                Write-Log "Using valid cached PowerShell $Version package: $cachedPackagePath"
                return $cachedPackagePath
            }

            Write-Log "Hash mismatch for cached package. Expected: $expectedHash, Got: $actualHash" "Warning"
            Remove-Item -Path "$cachedPackagePath" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$hashCachePath" -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "Package not found in cache: $cachedPackagePath"
        }
    } catch {
        Write-Log "Error during cache validation: $_" "Error"
    } finally {
        Exit-Lock -LockPath $lockFile
    }

    return $null
}
Export-ModuleMember -Function Get-CachedPowerShellPackage