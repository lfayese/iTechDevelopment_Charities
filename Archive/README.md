# OSDCloudCustomBuilder

[![Build Status](https://github.com/ofayese/OSDCloudCustomBuilder/workflows/Build/badge.svg)](https://github.com/ofayese/OSDCloudCustomBuilder/actions)
[![PSGallery Version](https://img.shields.io/powershellgallery/v/OSDCloudCustomBuilder.svg?style=flat&logo=powershell&label=PSGallery)](https://www.powershellgallery.com/packages/OSDCloudCustomBuilder/)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OSDCloudCustomBuilder.svg?style=flat&logo=powershell&label=Downloads)](https://www.powershellgallery.com/packages/OSDCloudCustomBuilder/)
[![codecov](https://codecov.io/gh/ofayese/OSDCloudCustomBuilder/branch/main/graph/badge.svg)](https://codecov.io/gh/ofayese/OSDCloudCustomBuilder)

A PowerShell module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support.

## Prerequisites

- Windows 10 or Windows 11
- PowerShell 5.1 or later
- Administrator privileges
- Windows Assessment and Deployment Kit (ADK) with WinPE feature installed
- OSD PowerShell module

## Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name OSDCloudCustomBuilder -Scope CurrentUser
```

## Offline Deployment

If the module is not published to the PowerShell Gallery or you need to deploy in an offline environment, you can use the following methods:

### Method 1: Manual Module Deployment

1. Download or clone the module from its source on a connected machine:
```powershell
git clone https://github.com/ofayese/OSDCloudCustomBuilder.git
```

2. Copy the module to a portable storage device.

3. On the offline machine, copy the module to a PowerShell module path:
```powershell
Copy-Item -Path "D:\OSDCloudCustomBuilder" -Destination "C:\Program Files\WindowsPowerShell\Modules\" -Recurse
```

### Method 2: Create a Local PowerShell Repository

1. On a connected machine, create a local repository:
```powershell
New-Item -Path "C:\LocalPSRepo" -ItemType Directory
Publish-Module -Path "C:\Path\To\OSDCloudCustomBuilder" -Repository LocalRepo
```

2. Copy the repository folder to the offline machine.

3. Register and use the local repository:
```powershell
Register-PSRepository -Name LocalRepo -SourceLocation "C:\LocalPSRepo" -InstallationPolicy Trusted
Install-Module -Name OSDCloudCustomBuilder -Repository LocalRepo
```

### Method 3: Create an Offline Installation Package

1. On a connected machine, save the module and dependencies:
```powershell
Save-Module -Name OSDCloudCustomBuilder -Path "C:\OfflineModules"
```

2. Copy the folder to the offline machine and import directly:
```powershell
Import-Module "C:\OfflineModules\OSDCloudCustomBuilder"
```

## Usage

### Create a custom OSDCloud ISO with PowerShell 7 support

```powershell
# Basic usage
Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"

# With custom ISO filename
Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"

# Include WinRE for WiFi support
Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -IncludeWinRE

# Skip cleanup of temporary files
Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -SkipCleanup
```

## Features

- Creates a complete OSDCloud ISO with a custom Windows Image (WIM) file
- Adds PowerShell 7 support to WinPE environment
- Optimizes ISO size by removing unnecessary language files
- Includes customization scripts for deployment
- Supports Autopilot integration
- Optional WinRE support for WiFi connectivity

## How It Works

1. Creates an OSDCloud template and workspace
2. Copies the custom WIM file to the workspace
3. Customizes the WinPE environment with PowerShell 7
4. Injects custom scripts and configurations
5. Optimizes the ISO size
6. Builds the final ISO file

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.