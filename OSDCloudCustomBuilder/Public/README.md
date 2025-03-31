# OSDCloudCustomBuilder Public Functions

This directory contains the public functions exported by the OSDCloudCustomBuilder module. These functions are the primary interface for users to interact with the module.

## Available Functions

### Update-CustomWimWithPwsh7

This function updates a Windows Image (WIM) file with PowerShell 7 support. It mounts the WIM file, adds PowerShell 7, and configures the environment for PowerShell 7 usage in WinPE.

```powershell
Update-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
```

Parameters:
- `-WimPath`: Path to your custom Windows image file
- `-OutputPath`: Destination folder for the OSDCloud workspace
- `-ISOFileName`: Specify a custom ISO filename
- `-IncludeWinRE`: Include WinRE for WiFi support
- `-SkipCleanup`: Retain temporary files for troubleshooting
- `-PowerShellVersion`: Specify PowerShell version to use
- `-MountTimeout`: Set timeout for mounting operations (in seconds)
- `-DismountTimeout`: Set timeout for dismounting operations (in seconds)
- `-DownloadTimeout`: Set timeout for download operations (in seconds)

### New-CustomOSDCloudISO

Creates a bootable ISO file with the custom OSDCloud environment.

```powershell
New-CustomOSDCloudISO -WorkspacePath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"
```

Parameters:
- `-WorkspacePath`: Path to the OSDCloud workspace
- `-ISOFileName`: Name of the ISO file to create
- `-OptimizeSize`: Optimize the ISO size by removing unnecessary files
- `-SkipCleanup`: Retain temporary files for troubleshooting

### Set-OSDCloudCustomBuilderConfig

Configures the OSDCloudCustomBuilder module settings.

```powershell
Set-OSDCloudCustomBuilderConfig -DefaultPowerShellVersion "7.5.0" -MountTimeout 600
```

Parameters:
- `-DefaultPowerShellVersion`: Set the default PowerShell version to use
- `-SupportedPowerShellVersions`: Specify supported PowerShell versions
- `-PowerShellVersionHashes`: Add hash values for PowerShell package verification
- `-PowerShellDownloadUrl`: Customize the PowerShell download URL template
- `-MountTimeout`: Set default timeout for mounting operations
- `-DismountTimeout`: Set default timeout for dismounting operations
- `-DownloadTimeout`: Set default timeout for download operations
- `-JobTimeout`: Set default timeout for background jobs
- `-CachePath`: Specify custom path for caching downloaded packages
- `-TempPath`: Specify custom path for temporary files

## Aliases

The module provides backward compatibility aliases for renamed functions:

- `Add-CustomWimWithPwsh7` -> `Update-CustomWimWithPwsh7`
- `Customize-WinPEWithPowerShell7` -> `Update-WinPEWithPowerShell7`

## Security Features

All public functions include:
- Parameter validation for security
- SupportsShouldProcess for system-modifying operations
- Proper error handling with try/catch blocks
- Logging with Write-OSDCloudLog
- Package verification with hash validation
- TLS 1.2 enforcement for secure downloads
- Command escaping to prevent injection attacks