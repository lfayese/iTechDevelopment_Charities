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
# Get module version from manifest to ensure consistency
$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OSDCloudCustomBuilder.psd1'
try {
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
    $script:ModuleVersion = $Manifest.ModuleVersion
}
catch {
    # Fallback version if manifest can't be read
    $script:ModuleVersion = "0.2.0"
    Write-Warning "Could not read module version from manifest: $_"
}
# Enforce TLS 1.2 for secure communications
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Verbose "TLS 1.2 protocol enforced: $([Net.ServicePointManager]::SecurityProtocol)"
# Set strict mode to catch common issues
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Make sure we're running on the required PowerShell version
$requiredPSVersion = [Version]'5.1'
if ($PSVersionTable.PSVersion -lt $requiredPSVersion) {
    $errorMsg = "PowerShell $($requiredPSVersion) or higher is required. Current version: $($PSVersionTable.PSVersion)"
    Write-Error $errorMsg
    throw $errorMsg
}
# Module internal variables
$script:ModuleRoot = $PSScriptRoot
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
# Initialize logging system
function Initialize-ModuleLogging {
    [CmdletBinding()]
    param()
    # Check for OSDCloud logger
    $script:LoggerExists = $false
    try {
        $loggerCommand = Get-Command -Name Invoke-OSDCloudLogger -ErrorAction Stop
        $script:LoggerExists = $true
        Write-Verbose "OSDCloud logger found: $($loggerCommand.Source)"
    }
    catch {
        Write-Verbose "OSDCloud logger not available, using standard logging"
    }
    # Create a fallback logging function if needed
    if (-not $script:LoggerExists) {
        if (-not (Get-Command -Name Write-OSDCloudLog -ErrorAction SilentlyContinue)) {
            function global:Write-OSDCloudLog {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory = $true, Position = 0)]
                    [string]$Message,
                    [Parameter()]
                    [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
                    [string]$Level = 'Info'
                )
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $logMessage = "[$timestamp] [$Level] $Message"
                switch ($Level) {
                    'Info' { Write-Host $logMessage }
                    'Warning' { Write-Warning $Message }
                    'Error' { Write-Error $Message }
                    'Debug' { Write-Verbose $Message }
                }
            }
        }
    }
}
# Initialize logging
Initialize-ModuleLogging
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
    $files = Get-ChildItem -Path $Path -Filter "*.ps1" -File
    Write-Verbose "Found $($files.Count) $Type function files in $Path"
    if ($files.Count -eq 0) { return }
    # Use parallel processing in PS7+ if file count exceeds threshold (say >5)
    if ($script:IsPS7OrHigher -and $files.Count -gt 5) {
        $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $errorList = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        try {
            $files | ForEach-Object -Parallel {
                try {
                    # Use $_ to reference the current pipeline object
                    . $_.FullName
                    # To reduce logging overhead in parallel, accumulate only minimal output
                    $localList = $using:threadSafeList
                    $null = $localList.Add($_.BaseName)
                }
                catch {
                    $errorInfo = [PSCustomObject]@{
                        File  = $_.FullName
                        Error = $_
                    }
                    $localErrorList = $using:errorList
                    $null = $localErrorList.Add($errorInfo)
                }
            } -ThrottleLimit 16
            foreach ($item in $threadSafeList) {
                $null = $FunctionList.Add($item)
                Write-Verbose "Imported $Type function (cached): $item"
            }
            foreach ($errorItem in $errorList) {
                Write-Error "Failed to import $Type function $($errorItem.File): $($errorItem.Error)"
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
    foreach ($funcName in $OSDCloudConfigFunctions) {
        if ((Get-Command -Name $funcName -ErrorAction SilentlyContinue) -and (-not $script:PublicFunctions.Contains($funcName))) {
            $null = $script:PublicFunctions.Add($funcName)
            Write-Verbose "Added OSDCloudConfig function to public functions: $funcName"
        }
    }
}
# Verify required helper functions using the cached lists instead of repeated Get-Command calls
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
# Define aliases with proper error handling
$Aliases = @{
    'Add-CustomWimWithPwsh7' = 'Update-CustomWimWithPwsh7'
    'Customize-WinPEWithPowerShell7' = 'Update-WinPEWithPowerShell7'
}
foreach ($alias in $Aliases.Keys) {
    $target = $Aliases[$alias]
    if ($script:PublicFunctions.Contains($target) -or (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
        if (-not (Get-Alias -Name $alias -ErrorAction SilentlyContinue)) {
            New-Alias -Name $alias -Value $target
            Write-Verbose "Created alias: $alias -> $target"
        }
        else {
            Write-Verbose "Alias already exists: $alias"
        }
    }
    else {
        Write-Warning "Cannot create alias '$alias' because target function '$target' does not exist"
    }
}
if ($Manifest) {
    $ExportFunctions = $Manifest.FunctionsToExport
    $ValidExportFunctions = @()
    foreach ($func in $ExportFunctions) {
        if ($script:PublicFunctions.Contains($func) -or (Get-Command -Name $func -ErrorAction SilentlyContinue)) {
            $ValidExportFunctions += $func
        }
    }
    if ($ValidExportFunctions.Count -ne $ExportFunctions.Count) {
        $missingExports = $ExportFunctions | Where-Object {
            -not ($script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue))
        }
        Write-Warning "Some functions listed in the module manifest don't exist: $([string]::Join(', ', $missingExports))"
    }
    $ExportVariables = if ($Manifest.VariablesToExport -contains '*') {
        @('ModuleVersion')
    }
    else {
        $Manifest.VariablesToExport
    }
    $ExportAliases = @($Manifest.AliasesToExport) + @($Aliases.Keys)
    Export-ModuleMember -Function $ValidExportFunctions -Variable $ExportVariables -Alias $ExportAliases
}
else {
    $DefaultExports = @(
        'Update-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO',
        'Get-OSDCloudConfig',
        'Import-OSDCloudConfig',
        'Export-OSDCloudConfig',
        'Update-OSDCloudConfig',
        'Set-OSDCloudCustomBuilderConfig'
    )
    $ValidExportFunctions = @()
    foreach ($func in $DefaultExports) {
        if ($script:PublicFunctions.Contains($func) -or (Get-Command -Name $func -ErrorAction SilentlyContinue)) {
            $ValidExportFunctions += $func
        }
    }
    if ($ValidExportFunctions.Count -ne $DefaultExports.Count) {
        $missingExports = $DefaultExports | Where-Object {
            -not ($script:PublicFunctions.Contains($_) -or (Get-Command -Name $_ -ErrorAction SilentlyContinue))
        }
        Write-Warning "Some default export functions don't exist: $([string]::Join(', ', $missingExports))"
    }
    Export-ModuleMember -Function $ValidExportFunctions -Variable 'ModuleVersion' -Alias @($Aliases.Keys)
}
#endregion Module Export
# Register module cleanup on unload if supported
if ($PSVersionTable.PSVersion.Major -ge 5) {
    $MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
        Write-Verbose "Unloading OSDCloudCustomBuilder module v$script:ModuleVersion"
        [System.GC]::Collect()
    }
}
else {
    [System.GC]::Collect()
}
Write-Verbose "OSDCloudCustomBuilder module v$script:ModuleVersion loaded successfully with $($ValidExportFunctions.Count) exported functions"