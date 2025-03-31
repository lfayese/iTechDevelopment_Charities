<# 
.SYNOPSIS
    PowerShell module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support.
.DESCRIPTION
    This module provides functions to create custom OSDCloud boot media with PowerShell 7 integration.
    It includes capabilities to import custom Windows images, optimize ISO size, and create bootable media.
.NOTES
    Version: 1.0.0
    Author: OSDCloud Team
    Copyright: (c) 2025 OSDCloud. All rights reserved.
#>
# Set strict mode to catch common issues
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Make sure we're running on the required PowerShell version
$requiredPSVersion = [Version]'5.1'
if ($PSVersionTable.PSVersion -lt $requiredPSVersion) {
    $errorMsg = "PowerShell $($requiredPSVersion.ToString()) or higher is required. Current version: $($PSVersionTable.PSVersion.ToString())"
    Write-Error $errorMsg
    throw $errorMsg
}
# Module internal variables
$script:ModuleRoot = $PSScriptRoot
$script:ModuleVersion = "1.0.0" # This should match the module manifest
Write-Verbose "Loading OSDCloudCustomBuilder module v$script:ModuleVersion from $script:ModuleRoot"
# Check if running in PS7+ for faster methods
$script:IsPS7OrHigher = $PSVersionTable.PSVersion.Major -ge 7
# Optimize function import with more efficient file processing using HashSet collections
$PrivateFunctions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$PublicFunctions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
# Updated Import-ModuleFunctions function
if ($script:IsPS7OrHigher) {
    function Import-ModuleFunctions {
        param (
            [string]$Path,
            [System.Collections.Generic.HashSet[string]]$FunctionList,
            [string]$Type
        )
        if (-not (Test-Path -Path $Path -ErrorAction SilentlyContinue)) { return }
        $files = @(Get-ChildItem -Path $Path -Filter "*.ps1" -File)
        if ($files.Count -eq 0) { return }
        # Use parallel processing only if file count exceeds a threshold (e.g., 3 files)
        if ($files.Count -gt 3) {
            $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            try {
                $files | ForEach-Object -Parallel {
                    try {
                        . $_.FullName
                        ($using:threadSafeList).Add($_.BaseName)
                    }
                    catch {
                        Write-Error "Failed to import $($using:Type) function $($_.FullName): $_"
                    }
                } -ThrottleLimit 16
                foreach ($item in $threadSafeList) {
                    $FunctionList.Add($item) | Out-Null
                }
            }
            catch {
                Write-Warning "Parallel import failed, falling back to sequential processing."
                foreach ($file in $files) {
                    try {
                        . $file.FullName
                        $FunctionList.Add($file.BaseName) | Out-Null
                    }
                    catch {
                        Write-Error "Failed to import $Type function $($file.FullName): $_"
                    }
                }
            }
        }
        else {
            # Sequential processing for small number of files to reduce overhead
            foreach ($file in $files) {
                try {
                    . $file.FullName
                    $FunctionList.Add($file.BaseName) | Out-Null
                }
                catch {
                    Write-Error "Failed to import $Type function $($file.FullName): $_"
                }
            }
        }
    }
}
else {
    # PS5.1 standard import
    function Import-ModuleFunctions {
        param (
            [string]$Path,
            [System.Collections.Generic.HashSet[string]]$FunctionList,
            [string]$Type
        )
        if (-not (Test-Path -Path $Path -ErrorAction SilentlyContinue)) { return }
        foreach ($file in @(Get-ChildItem -Path $Path -Filter "*.ps1" -File)) {
            try {
                . $file.FullName
                $FunctionList.Add($file.BaseName) | Out-Null
            }
            catch {
                Write-Error "Failed to import $Type function $($file.FullName): $_"
            }
        }
    }
}
# Use faster .NET methods for file existence checking
$PrivatePath = Join-Path -Path $script:ModuleRoot -ChildPath "Private"
$PublicPath = Join-Path -Path $script:ModuleRoot -ChildPath "Public"
$PrivatePathExists = [System.IO.Directory]::Exists($PrivatePath)
$PublicPathExists = [System.IO.Directory]::Exists($PublicPath)
# Import functions if the directories exist
if ($PrivatePathExists) {
    Import-ModuleFunctions -Path $PrivatePath -FunctionList $PrivateFunctions -Type "private"
}
if ($PublicPathExists) {
    Import-ModuleFunctions -Path $PublicPath -FunctionList $PublicFunctions -Type "public"
}
# Verify required helper functions exist using fast HashSet lookups
$RequiredHelpers = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('Copy-CustomWimToWorkspace', 'Copy-WimFileEfficiently', 'Customize-WinPEWithPowerShell7',
                'Optimize-ISOSize', 'New-CustomISO', 'Show-Summary'),
    [StringComparer]::OrdinalIgnoreCase
)
$MissingHelpers = [System.Collections.Generic.HashSet[string]]::new($RequiredHelpers, [StringComparer]::OrdinalIgnoreCase)
$MissingHelpers.ExceptWith($PrivateFunctions)
$MissingHelpers.ExceptWith($PublicFunctions)
if ($MissingHelpers.Count -gt 0) {
    $missingFunctionsMessage = "Missing required helper functions: $($MissingHelpers -join ', ')"
    Write-Error $missingFunctionsMessage
    throw $missingFunctionsMessage
}
# Check for recommended dependencies only once and cache results
if (-not (Get-Variable -Name 'DependencyCheckDone' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RecommendedModuleStatus = @{}
    $recommendedModules = @('OSD')
    foreach ($moduleName in $recommendedModules) {
        $status = [bool](Get-Module -Name $moduleName -ListAvailable)
        $script:RecommendedModuleStatus[$moduleName] = $status
        if (-not $status) {
            Write-Warning "Recommended module '$moduleName' is not installed. Some functionality may be limited."
        }
    }
    $script:DependencyCheckDone = $true
}
# Memory-efficient manifest handling
$script:ManifestCache = $null
function Get-ModuleManifest {
    if ($null -eq $script:ManifestCache) {
        $ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OSDCloudCustomBuilder.psd1'
        if ([System.IO.File]::Exists($ManifestPath)) {
            try {
                $script:ManifestCache = Import-PowerShellDataFile -Path $ManifestPath
            }
            catch {
                Write-Error "Failed to process module manifest: $_"
                $script:ManifestCache = $null
            }
        }
    }
    return $script:ManifestCache
}
# Use the cached manifest
$Manifest = Get-ModuleManifest
# More efficient export mechanism via HashSet lookups
function Export-ModuleFunctionality {
    param (
        [System.Collections.Generic.HashSet[string]]$AvailableFunctions,
        [string[]]$FunctionsToExport,
        [string[]]$VariablesToExport,
        [string[]]$AliasesToExport
    )
    $ExportSet = [System.Collections.Generic.HashSet[string]]::new($FunctionsToExport, [StringComparer]::OrdinalIgnoreCase)
    $ExportSet.IntersectWith($AvailableFunctions)
    $ExportArray = [string[]]$ExportSet
    Export-ModuleMember -Function $ExportArray -Variable $VariablesToExport -Alias $AliasesToExport
}
# Preload essential functions to minimize on-demand loading using a dictionary for fast lookups
$PreloadFunctions = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$PreloadFunctions['Add-CustomWimWithPwsh7'] = "$PSScriptRoot\Public\Add-CustomWimWithPwsh7.ps1"
$PreloadFunctions['New-CustomOSDCloudISO'] = "$PSScriptRoot\Public\New-CustomOSDCloudISO.ps1"
foreach ($funcName in $PreloadFunctions.Keys) {
    $funcPath = $PreloadFunctions[$funcName]
    if ([System.IO.File]::Exists($funcPath)) {
        . $funcPath
    }
}
# Process module manifest for exporting functions
if ($Manifest) {
    $script:ModuleVersion = $Manifest.ModuleVersion
    $ExportFunctions = $Manifest.FunctionsToExport
    $FunctionsHashSet = [System.Collections.Generic.HashSet[string]]::new($PublicFunctions, [StringComparer]::OrdinalIgnoreCase)
    $ValidExportFunctions = @($ExportFunctions | Where-Object { $FunctionsHashSet.Contains($_) })
    if ($ValidExportFunctions.Count -ne $ExportFunctions.Count) {
        $missingExports = @($ExportFunctions | Where-Object { -not $FunctionsHashSet.Contains($_) })
        Write-Warning "Some functions listed in the module manifest don't exist: $([string]::Join(', ', $missingExports))"
    }
    $ExportVariables = if ($Manifest.VariablesToExport -contains '*') {
        @('ModuleVersion')
    }
    else {
        $Manifest.VariablesToExport
    }
    $ExportAliases = $Manifest.AliasesToExport
    Export-ModuleFunctionality -AvailableFunctions $PublicFunctions -FunctionsToExport $ExportFunctions -VariablesToExport $ExportVariables -AliasesToExport $ExportAliases
}
else {
    # Fallback to hardcoded list if manifest fails
    $DefaultExports = @('Add-CustomWimWithPwsh7','New-CustomOSDCloudISO')
    $FunctionsHashSet = [System.Collections.Generic.HashSet[string]]::new($PublicFunctions, [StringComparer]::OrdinalIgnoreCase)
    $ValidExportFunctions = @($DefaultExports | Where-Object { $FunctionsHashSet.Contains($_) })
    if ($ValidExportFunctions.Count -ne $DefaultExports.Count) {
        $missingExports = @($DefaultExports | Where-Object { -not $FunctionsHashSet.Contains($_) })
        Write-Warning "Some default export functions don't exist: $([string]::Join(', ', $missingExports))"
    }
    Export-ModuleMember -Function $ValidExportFunctions -Variable 'ModuleVersion'
}
Write-Verbose "OSDCloudCustomBuilder module v$script:ModuleVersion loaded successfully with $($ValidExportFunctions.Count) functions"