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

#region Module Setup
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
#endregion Module Setup

#region Function Import
# Create collections to track imported functions
$script:PrivateFunctions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:PublicFunctions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# Auto-Import Functions
function Import-ModuleFunctions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$FunctionList,
        
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    if (-not (Test-Path -Path $Path -ErrorAction SilentlyContinue)) { 
        Write-Verbose "Path not found: $Path"
        return 
    }
    
    $files = @(Get-ChildItem -Path $Path -Filter "*.ps1" -File)
    Write-Verbose "Found $($files.Count) $Type function files in $Path"
    
    if ($files.Count -eq 0) { return }
    
    # Use parallel processing in PS7+ if file count exceeds threshold
    if ($script:IsPS7OrHigher -and $files.Count -gt 3) {
        $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        try {
            $files | ForEach-Object -Parallel {
                try {
                    . $_.FullName
                    $null = ($using:threadSafeList).Add($_.BaseName)
                    Write-Verbose "Imported $($using:Type) function: $($_.BaseName)"
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
            Write-Warning "Parallel import failed, falling back to sequential processing: $_"
            foreach ($file in $files) {
                Import-FunctionFile -File $file -FunctionList $FunctionList -Type $Type
            }
        }
    }
    else {
        # Sequential processing for PS5.1 or small number of files
        foreach ($file in $files) {
            Import-FunctionFile -File $file -FunctionList $FunctionList -Type $Type
        }
    }
}

function Import-FunctionFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,
        
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$FunctionList,
        
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    try {
        . $File.FullName
        $null = $FunctionList.Add($File.BaseName)
        Write-Verbose "Imported $Type function: $($File.BaseName)"
    }
    catch {
        Write-Error "Failed to import $Type function $($File.FullName): $_"
    }
}

# Import all function files from Private and Public folders
$PrivatePath = Join-Path -Path $script:ModuleRoot -ChildPath "Private"
$PublicPath = Join-Path -Path $script:ModuleRoot -ChildPath "Public"

if ([System.IO.Directory]::Exists($PrivatePath)) {
    Import-ModuleFunctions -Path $PrivatePath -FunctionList $script:PrivateFunctions -Type "Private"
}

if ([System.IO.Directory]::Exists($PublicPath)) {
    Import-ModuleFunctions -Path $PublicPath -FunctionList $script:PublicFunctions -Type "Public"
}

# Special handling for OSDCloudConfig.ps1 which contains multiple functions
$OSDCloudConfigFile = Join-Path -Path $PrivatePath -ChildPath "OSDCloudConfig.ps1"
$OSDCloudConfigFunctions = @('Get-OSDCloudConfig', 'Import-OSDCloudConfig', 'Export-OSDCloudConfig', 'Update-OSDCloudConfig')

if ([System.IO.File]::Exists($OSDCloudConfigFile)) {
    # The file was already dot-sourced during Import-ModuleFunctions, just add the function names
    foreach ($funcName in $OSDCloudConfigFunctions) {
        if (Get-Command -Name $funcName -ErrorAction SilentlyContinue) {
            if (-not $script:PublicFunctions.Contains($funcName)) {
                $null = $script:PublicFunctions.Add($funcName)
                Write-Verbose "Added OSDCloudConfig function to public functions: $funcName"
            }
        }
    }
}

# Verify required helper functions
$RequiredHelpers = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'Copy-CustomWimToWorkspace', 'Copy-WimFileEfficiently', 'Update-WinPEWithPowerShell7',
        'Optimize-ISOSize', 'New-CustomISO', 'Show-Summary', 'Get-ModuleConfiguration',
        'Test-ValidPowerShellVersion', 'Get-CachedPowerShellPackage', 'Write-OSDCloudLog'
    ),
    [StringComparer]::OrdinalIgnoreCase
)

$MissingHelpers = [System.Collections.Generic.HashSet[string]]::new($RequiredHelpers, [StringComparer]::OrdinalIgnoreCase)
$MissingHelpers.ExceptWith($script:PrivateFunctions)
$MissingHelpers.ExceptWith($script:PublicFunctions)

if ($MissingHelpers.Count -gt 0) {
    $missingFunctionsMessage = "Missing required helper functions: $($MissingHelpers -join ', ')"
    Write-Error $missingFunctionsMessage
    throw $missingFunctionsMessage
}
#endregion Function Import

#region Module Export
# Get module manifest
$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OSDCloudCustomBuilder.psd1'
$Manifest = if ([System.IO.File]::Exists($ManifestPath)) {
    try {
        Import-PowerShellDataFile -Path $ManifestPath
    }
    catch {
        Write-Error "Failed to process module manifest: $_"
        $null
    }
}

# Define aliases
$Aliases = @{
    'Add-CustomWimWithPwsh7' = 'Update-CustomWimWithPwsh7'
    'Customize-WinPEWithPowerShell7' = 'Update-WinPEWithPowerShell7'
}

# Create aliases
foreach ($alias in $Aliases.Keys) {
    $target = $Aliases[$alias]
    if (Get-Command -Name $target -ErrorAction SilentlyContinue) {
        New-Alias -Name $alias -Value $target -ErrorAction SilentlyContinue
        Write-Verbose "Created alias: $alias -> $target"
    }
}

# Export module members based on manifest
if ($Manifest) {
    # Get functions to export from manifest
    $ExportFunctions = $Manifest.FunctionsToExport
    
    # Filter to only include functions that actually exist
    $ValidExportFunctions = @($ExportFunctions | Where-Object { 
        $script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue)
    })
    
    if ($ValidExportFunctions.Count -ne $ExportFunctions.Count) {
        $missingExports = @($ExportFunctions | Where-Object { 
            -not ($script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue))
        })
        Write-Warning "Some functions listed in the module manifest don't exist: $([string]::Join(', ', $missingExports))"
    }
    
    # Get variables and aliases to export
    $ExportVariables = if ($Manifest.VariablesToExport -contains '*') {
        @('ModuleVersion')
    }
    else {
        $Manifest.VariablesToExport
    }
    
    $ExportAliases = @($Manifest.AliasesToExport)
    $ExportAliases += @($Aliases.Keys)
    
    # Export module members
    Export-ModuleMember -Function $ValidExportFunctions -Variable $ExportVariables -Alias $ExportAliases
}
else {
    # Fallback export if manifest isn't available
    $DefaultExports = @(
        'Update-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO',
        'Get-OSDCloudConfig',
        'Import-OSDCloudConfig',
        'Export-OSDCloudConfig',
        'Update-OSDCloudConfig',
        'Set-OSDCloudCustomBuilderConfig'
    )
    
    $ValidExportFunctions = @($DefaultExports | Where-Object { 
        $script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue)
    })
    
    if ($ValidExportFunctions.Count -ne $DefaultExports.Count) {
        $missingExports = @($DefaultExports | Where-Object { 
            -not ($script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue))
        })
        Write-Warning "Some default export functions don't exist: $([string]::Join(', ', $missingExports))"
    }
    
    # Export module members
    Export-ModuleMember -Function $ValidExportFunctions -Variable 'ModuleVersion' -Alias @($Aliases.Keys)
}
#endregion Module Export

# Force garbage collection to clean up memory
[System.GC]::Collect()

Write-Verbose "OSDCloudCustomBuilder module v$script:ModuleVersion loaded successfully with $($ValidExportFunctions.Count) exported functions"