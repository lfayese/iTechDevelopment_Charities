<# 
.SYNOPSIS
    PowerShell module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support.
.DESCRIPTION
    This module provides functions to create custom OSDCloud boot media with PowerShell 7 integration.
    It includes capabilities to import custom Windows images, optimize ISO size, and create bootable media.
.NOTES
    Version: 0.2.0
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
$script:ModuleVersion = "0.2.0" # Updated to match the module manifest
Write-Verbose "Loading OSDCloudCustomBuilder module v$script:ModuleVersion from $script:ModuleRoot"

# Define path to PowerShell 7 package in the OSDCloud folder
$script:PowerShell7ZipPath = Join-Path -Path (Split-Path -Parent $script:ModuleRoot) -ChildPath "OSDCloud\PowerShell-7.5.0-win-x64.zip"
if ([System.IO.File]::Exists($script:PowerShell7ZipPath)) {
    Write-Verbose "PowerShell 7 package found at: $script:PowerShell7ZipPath"
}
else {
    Write-Warning "PowerShell 7 package not found at: $script:PowerShell7ZipPath"
}

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
                        $null = ($using:threadSafeList).Add($_.BaseName)
                    }
                    catch {
                        Write-Error "Failed to import $($using:Type) function $($_.FullName): $_"
                    }
                } -ThrottleLimit 16
                foreach ($item in $threadSafeList) {
                    $null = $FunctionList.Add($item)
                }
            }
            catch {
                Write-Warning "Parallel import failed, falling back to sequential processing."
                foreach ($file in $files) {
                    try {
                        . $file.FullName
                        $null = $FunctionList.Add($file.BaseName)
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
                    $null = $FunctionList.Add($file.BaseName)
                }
                catch {
                    Write-Error "Failed to import $Type function $($file.FullName): $_"
                }
            }
        }
    }
}
else {
    # PS5.1 standard import - FIXED: Added missing Type parameter
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
                $null = $FunctionList.Add($file.BaseName)
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
    [string[]]@('Copy-CustomWimToWorkspace', 'Copy-WimFileEfficiently', 'Update-WinPEWithPowerShell7',
                'Optimize-ISOSize', 'New-CustomISO', 'Show-Summary', 'Get-ModuleConfiguration',
                'Test-ValidPowerShellVersion', 'Get-CachedPowerShellPackage', 'Write-OSDCloudLog'),
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
$PreloadFunctions['Update-CustomWimWithPwsh7'] = "$PSScriptRoot\Public\Update-CustomWimWithPwsh7.ps1"
$PreloadFunctions['New-CustomOSDCloudISO'] = "$PSScriptRoot\Public\New-CustomOSDCloudISO.ps1"
$PreloadFunctions['Set-OSDCloudCustomBuilderConfig'] = "$PSScriptRoot\Public\Set-OSDCloudCustomBuilderConfig.ps1"

# Update paths for OSDCloudConfig functions to point to the Private folder
$PreloadFunctions['Get-OSDCloudConfig'] = "$PSScriptRoot\Private\OSDCloudConfig.ps1"
$PreloadFunctions['Import-OSDCloudConfig'] = "$PSScriptRoot\Private\OSDCloudConfig.ps1"
$PreloadFunctions['Export-OSDCloudConfig'] = "$PSScriptRoot\Private\OSDCloudConfig.ps1"
$PreloadFunctions['Update-OSDCloudConfig'] = "$PSScriptRoot\Private\OSDCloudConfig.ps1"
$PreloadFunctions['Get-ModuleConfiguration'] = "$PSScriptRoot\Private\Get-ModuleConfiguration.ps1"
$PreloadFunctions['Write-OSDCloudLog'] = "$PSScriptRoot\Private\Write-OSDCloudLog.ps1"
$PreloadFunctions['Measure-OSDCloudOperation'] = "$PSScriptRoot\Private\Measure-OSDCloudOperation.ps1"
$PreloadFunctions['Test-ValidPowerShellVersion'] = "$PSScriptRoot\Private\Test-ValidPowerShellVersion.ps1"
$PreloadFunctions['Get-CachedPowerShellPackage'] = "$PSScriptRoot\Private\Get-CachedPowerShellPackage.ps1"
$PreloadFunctions['Copy-FilesInParallel'] = "$PSScriptRoot\Private\Copy-FilesInParallel.ps1"

foreach ($funcName in $PreloadFunctions.Keys) {
    $funcPath = $PreloadFunctions[$funcName]
    if ([System.IO.File]::Exists($funcPath)) {
        . $funcPath
    }
}

# Special handling for multiple functions in one file
$OSDCloudConfigFunctions = @('Get-OSDCloudConfig', 'Import-OSDCloudConfig', 'Export-OSDCloudConfig', 'Update-OSDCloudConfig')
foreach ($funcName in $OSDCloudConfigFunctions) {
    if (-not $PublicFunctions.Contains($funcName)) {
        $null = $PublicFunctions.Add($funcName)
    }
}

# Add our new utility functions to the PrivateFunctions set
$NewUtilityFunctions = @(
    'Get-ModuleConfiguration',
    'Write-OSDCloudLog',
    'Measure-OSDCloudOperation',
    'Test-ValidPowerShellVersion',
    'Get-CachedPowerShellPackage',
    'Copy-FilesInParallel'
)

foreach ($funcName in $NewUtilityFunctions) {
    if (-not $PrivateFunctions.Contains($funcName)) {
        $null = $PrivateFunctions.Add($funcName)
    }
}

# Add our new public functions to the PublicFunctions set
$NewPublicFunctions = @(
    'Set-OSDCloudCustomBuilderConfig'
)

foreach ($funcName in $NewPublicFunctions) {
    if (-not $PublicFunctions.Contains($funcName)) {
        $null = $PublicFunctions.Add($funcName)
    }
}

# Check if PowerShell 7 customization function exists, otherwise create a helper
$winPEPs7File = Join-Path -Path $script:ModuleRoot -ChildPath "Private\WinPE-PowerShell7.ps1"
if ([System.IO.File]::Exists($winPEPs7File)) {
    . $winPEPs7File
    $null = $PrivateFunctions.Add('Update-WinPEWithPowerShell7')
    Write-Verbose "Loaded PowerShell 7 customization functions from WinPE-PowerShell7.ps1"
}
else {
    Write-Warning "WinPE-PowerShell7.ps1 not found in Private folder. Using fallback implementation."
    # Fallback implementation would be here
}

# Process module manifest for exporting functions
if ($Manifest) {
    $script:ModuleVersion = $Manifest.ModuleVersion
    $ExportFunctions = $Manifest.FunctionsToExport
    $FunctionsHashSet = [System.Collections.Generic.HashSet[string]]::new($PublicFunctions, [StringComparer]::OrdinalIgnoreCase)
    
    # Add OSDCloudConfig functions if they exist in the file
    foreach ($func in $OSDCloudConfigFunctions) {
        if (Get-Command -Name $func -ErrorAction SilentlyContinue) {
            $null = $FunctionsHashSet.Add($func)
        }
    }
    
    # Add new public functions
    foreach ($func in $NewPublicFunctions) {
        if (Get-Command -Name $func -ErrorAction SilentlyContinue) {
            $null = $FunctionsHashSet.Add($func)
        }
    }
    
    # Add backward compatibility aliases
    $null = $FunctionsHashSet.Add('Add-CustomWimWithPwsh7')
    $null = $FunctionsHashSet.Add('Customize-WinPEWithPowerShell7')
    
    # Add all functions from the manifest that exist
    $ValidExportFunctions = @($ExportFunctions | Where-Object { $FunctionsHashSet.Contains($_) })
    
    # Add our new functions to export
    $ValidExportFunctions += @($NewPublicFunctions | Where-Object { $FunctionsHashSet.Contains($_) })
    
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
    $ExportAliases += @('Add-CustomWimWithPwsh7', 'Customize-WinPEWithPowerShell7')
    
    Export-ModuleFunctionality -AvailableFunctions $PublicFunctions -FunctionsToExport $ValidExportFunctions -VariablesToExport $ExportVariables -AliasesToExport $ExportAliases
}
else {
    # Fallback to hardcoded list if manifest fails - updated to include all functions from manifest
    $DefaultExports = @(
        'Update-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO',
        'Get-OSDCloudConfig',
        'Import-OSDCloudConfig',
        'Export-OSDCloudConfig',
        'Update-OSDCloudConfig',
        'Set-OSDCloudCustomBuilderConfig'
    )
    
    $FunctionsHashSet = [System.Collections.Generic.HashSet[string]]::new($PublicFunctions, [StringComparer]::OrdinalIgnoreCase)
    $ValidExportFunctions = @($DefaultExports | Where-Object { $FunctionsHashSet.Contains($_) })
    
    if ($ValidExportFunctions.Count -ne $DefaultExports.Count) {
        $missingExports = @($DefaultExports | Where-Object { -not $FunctionsHashSet.Contains($_) })
        Write-Warning "Some default export functions don't exist: $([string]::Join(', ', $missingExports))"
    }
    
    # Export functions and aliases
    Export-ModuleMember -Function $ValidExportFunctions -Variable 'ModuleVersion' -Alias @('Add-CustomWimWithPwsh7', 'Customize-WinPEWithPowerShell7')
}

# Force garbage collection to clean up memory
[System.GC]::Collect()

Write-Verbose "OSDCloudCustomBuilder module v$script:ModuleVersion loaded successfully with $($ValidExportFunctions.Count) functions"