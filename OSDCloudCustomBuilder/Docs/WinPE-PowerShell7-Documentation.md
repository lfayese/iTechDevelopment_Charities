# WinPE PowerShell 7 Module Documentation

## Overview

The WinPE PowerShell 7 module provides functions for customizing Windows PE (WinPE) images with PowerShell 7 support. This enhances the capabilities of WinPE environments by providing access to the latest PowerShell features and improvements.

## Main Functions

### Update-WinPEWithPowerShell7

This is the main orchestration function that coordinates the entire process of adding PowerShell 7 support to a WinPE image.

#### Syntax

```powershell
Update-WinPEWithPowerShell7 
    -TemporaryPath <String> 
    -WorkspacePath <String> 
    [-PowerShellVersion <String>] 
    [-PowerShellPackageFile <String>] 
    [-SkipCleanup] 
    [-WhatIf] 
    [-Confirm] 
    [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| TemporaryPath | String | The temporary path where working files will be stored. This path must have sufficient disk space and appropriate permissions for creating and modifying files. |
| WorkspacePath | String | The workspace path containing the WinPE image to update. This should point to a valid WinPE workspace directory containing the boot.wim file in the Media\Sources subdirectory. |
| PowerShellVersion | String | The PowerShell version to install. Default is "7.3.4". Must be in X.Y.Z format and be a supported version. |
| PowerShellPackageFile | String | The path to the PowerShell 7 zip file. If not specified, it will be downloaded from the official Microsoft repository. |
| SkipCleanup | Switch | If specified, temporary files will not be removed after processing. Useful for debugging. |
| WhatIf | Switch | Shows what would happen if the command runs. The command is not run. |
| Confirm | Switch | Prompts you for confirmation before running the command. |

#### Examples

```powershell
# Basic usage with default settings
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"

# Install specific PowerShell version with verbose output
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4" -Verbose

# Test run using local PowerShell package
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellPackageFile "C:\Temp\PowerShell-7.3.4-win-x64.zip" -WhatIf

# Keep temporary files and stop on any error
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -SkipCleanup -ErrorAction Stop
```

#### Notes

- Requires administrator privileges
- Windows ADK must be installed
- Internet connectivity is required if PowerShell package needs downloading
- Minimum 10GB free disk space in TemporaryPath is recommended
- Write access to WorkspacePath is required

## Helper Functions

The module includes several helper functions that are used by the main orchestration function:

### Initialize-WinPEMountPoint

Creates temporary directories for mounting the WinPE image and storing PowerShell 7 files.

### Mount-WinPEImage

Mounts a WinPE image file with retry logic and validation.

### Install-PowerShell7ToWinPE

Extracts and installs PowerShell 7 files to the mounted WinPE image.

### Update-WinPERegistry

Updates registry settings in the mounted WinPE image to support PowerShell 7.

### New-WinPEStartupProfile

Creates a PowerShell 7 profile directory in the mounted WinPE image.

### Update-WinPEStartup

Updates the WinPE startup script to initialize PowerShell 7.

### Dismount-WinPEImage

Safely dismounts the WinPE image with retry logic.

### Get-PowerShell7Package

Downloads or validates a PowerShell 7 package from the official Microsoft repository.

### Find-WinPEBootWim

Locates and validates the boot.wim file in a WinPE workspace.

### Remove-WinPETemporaryFiles

Removes temporary files created during WinPE customization.

### Save-WinPEDiagnostics

Collects diagnostic information from a mounted WinPE image for troubleshooting.

### Test-ValidPowerShellVersion

Validates if a PowerShell version string is in the correct format and is supported.

## Backward Compatibility

For backward compatibility, the module includes an alias:

```powershell
Customize-WinPEWithPowerShell7 -> Update-WinPEWithPowerShell7
```

## Error Handling

All functions implement comprehensive error handling with try/catch blocks and detailed error messages. The module includes diagnostic collection capabilities to help troubleshoot issues.

## Requirements

- Windows PowerShell 5.1 or later
- Windows Assessment and Deployment Kit (Windows ADK)
- Administrator privileges
- Internet connectivity (for downloading PowerShell 7 packages)
- Sufficient disk space (at least 10GB recommended)

## Examples

### Basic Usage

```powershell
# Import the module
Import-Module OSDCloudCustomBuilder

# Create a WinPE workspace
New-OSDCloudWorkspace -Path "C:\OSDCloud\Workspace"

# Add PowerShell 7 support to the WinPE image
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"

# Create an ISO from the customized WinPE image
New-OSDCloudISO -WorkspacePath "C:\OSDCloud\Workspace" -Destination "C:\OSDCloud\ISO"
```

### Advanced Usage

```powershell
# Create a WinPE workspace with custom settings
New-OSDCloudWorkspace -Path "C:\OSDCloud\Workspace" -CustomContent

# Download a specific PowerShell 7 version manually
$ps7Package = Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp\PowerShell-7.3.4-win-x64.zip"

# Add PowerShell 7 support to the WinPE image with the downloaded package
Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellPackageFile $ps7Package -SkipCleanup

# Create a bootable USB drive with the customized WinPE image
New-OSDCloudUSB -WorkspacePath "C:\OSDCloud\Workspace" -USBDrive "D:"
```

## Troubleshooting

If you encounter issues during the WinPE customization process:

1. Use the `-SkipCleanup` parameter to keep temporary files for inspection
2. Check the logs in the `$TemporaryPath\WinPE_Diagnostics_*` directory
3. Verify that you have administrator privileges
4. Ensure that the Windows ADK is installed and properly configured
5. Check that you have sufficient disk space in the temporary path
6. Verify internet connectivity if downloading PowerShell 7 packages

## Version History

- 1.0.0 - Initial release with comprehensive error handling and documentation
- 0.2.0 - Preview release with basic functionality