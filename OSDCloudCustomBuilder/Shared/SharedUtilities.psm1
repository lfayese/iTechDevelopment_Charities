# Patched
Set-StrictMode -Version Latest
# SharedUtilities.psm1
# Centralized helpers for config, logging, paths, retries, etc.

function Write-Log {
    param (
        [Parameter(Mandatory="$true")][string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Verbose", "Debug")][string]$Level = "Info",
        [string]$Component = "SharedUtilities",
        [Exception]$Exception
    )
    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
        Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component -Exception $Exception
    } else {
        $prefix = "[$Component][$Level]"
        Write-Verbose "$prefix $Message"
    }
}

function Get-RelativePath {
    param (
        [Parameter(Mandatory = "$true")][string]$BasePath,
        [Parameter(Mandatory = "$true")][string]$FullPath
    )
    return $FullPath.Substring($BasePath.Length).TrimStart('\')
}

function Get-SafeModuleConfiguration {
    try {
        if (Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue) {
            return Get-ModuleConfiguration
        } else {
            Write-Log "Get-ModuleConfiguration not found. Returning empty config." "Warning"
            return @{}
        }
    } catch {
        Write-Log "Error loading module config: $_" "Error"
        return @{}
    }
}

function Invoke-WithRetry {
    param (
        [Parameter(Mandatory = "$true")][scriptblock]$ScriptBlock,
        [int]"$MaxRetries" = 3,
        [int]"$DelaySeconds" = 2
    )
    "$attempt" = 0
    while ("$attempt" -lt $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            "$attempt"++
            if ("$attempt" -eq $MaxRetries) {
                throw "Retry failed after $MaxRetries attempts: $_"
            }
            Start-Sleep -Seconds ("$DelaySeconds" * $attempt)
        }
    }
}

Export-ModuleMember -Function Write-Log, Get-RelativePath, Get-SafeModuleConfiguration, Invoke-WithRetry

function Test-IsAdmin {
    [OutputType([bool])]
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}