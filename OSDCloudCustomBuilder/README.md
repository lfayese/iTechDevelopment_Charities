# OSDCloudCustomBuilder

A PowerShell module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support. This module enhances the capabilities of OSDCloud by providing tools to create customized deployment media with integrated PowerShell 7.

## Overview

OSDCloudCustomBuilder enables you to:

- Create bootable custom OSDCloud ISO files with PowerShell 7 integration
- Customize Windows PE environments for modern deployment scenarios
- Include organization-specific scripts and tools in your deployment media
- Generate comprehensive documentation from code comments

## Installation

### Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Windows ADK installed
- OSD module (`Install-Module OSD -Force`)

### Installing the Module

#### Option 1: Install from Local Repository

```powershell
# Clone or download the repository to a local folder
# Navigate to the repository root folder

# Import directly from the local path
Import-Module -Path ".\OSDCloudCustomBuilder.psd1"

# Alternatively, for development/testing:
# Import with force to refresh any changes
Import-Module -Path ".\OSDCloudCustomBuilder.psd1" -Force
```

#### Option 2: Install from PowerShell Gallery

```powershell
# Install from PowerShell Gallery
Install-Module OSDCloudCustomBuilder -Force

# Import the module
Import-Module OSDCloudCustomBuilder
```

## Basic Usage

### Creating a Custom OSDCloud ISO

```powershell
# Create a basic custom OSDCloud ISO with PowerShell 7.5.0
New-CustomOSDCloudISO

# Create an ISO with specific output path
New-CustomOSDCloudISO -OutputPath "D:\OSDCloud\Custom.iso"

# Create an ISO with a specific PowerShell version
New-CustomOSDCloudISO -PwshVersion "7.4.1"
```

### Updating a Custom WIM with PowerShell 7

```powershell
# Update a WIM file with PowerShell 7
Update-CustomWimWithPwsh7 -WimPath "D:\WimFiles\boot.wim" -OutputPath "D:\WimFiles\boot_pwsh7.wim"

# Use the backward compatible alias 
Add-CustomWimWithPwsh7 -WimPath "D:\WimFiles\boot.wim" -OutputPath "D:\WimFiles\boot_pwsh7.wim" 
```

### Configuring the Module

```powershell
# Configure module settings
Set-OSDCloudCustomBuilderConfig -MaxThreads 8 -LogPath "D:\Logs\OSDCloud" -CachePath "D:\Cache\OSDCloud"

# Configure download timeout for large files
Set-OSDCloudCustomBuilderConfig -DownloadTimeout 1800
```

## Advanced Scenarios

### Customizing OSDCloud Templates

The module can use custom templates for OSDCloud workspaces:

```powershell
# Create a custom OSDCloud configuration
$config = @{
    OrganizationName = "Contoso"
    DefaultOSLanguage = "en-us"
    DefaultOSEdition = "Enterprise"
    ISOOutputPath = "D:\ISO\OSDCloud"
    CustomOSDCloudTemplate = "C:\OSDCloud\Templates\ContosoTemplate.json"
}

# Export the configuration
Export-OSDCloudConfig -Path "C:\Config\OSDCloud\config.json" -Config $config

# Import the configuration for use
Import-OSDCloudConfig -Path "C:\Config\OSDCloud\config.json"

# Create an ISO using the imported configuration
New-CustomOSDCloudISO
```

### Adding Custom Autopilot Scripts

The module supports including Autopilot scripts in your deployment media:

```powershell
# Place your Autopilot scripts in the OSDCloud\Autopilot directory
# The module will automatically include them in the ISO

# Check the Autopilot README for more information
Get-Content -Path "D:\iTechDevelopment_Charities\OSDCloud\Autopilot\Readme.md"
```

### Advanced ISO Creation

```powershell
# Create a highly customized ISO
New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath "D:\OSDCloud\Enterprise.iso" `
    -IncludeWinRE -UseRobocopy -CustomScriptsPath "D:\Scripts\Deployment" `
    -SkipVersionCheck -Force

# Create an ISO and keep temporary files for troubleshooting
New-CustomOSDCloudISO -PwshVersion "7.5.0" -SkipCleanup -Verbose
```

### Telemetry Configuration

```powershell
# Enable telemetry with standard detail level
Enable-OSDCloudTelemetry -DetailLevel "Standard" -StoragePath "D:\Telemetry"

# Disable telemetry 
Enable-OSDCloudTelemetry -Enable $false
```

### Documentation Generation

```powershell
# Generate comprehensive documentation
ConvertTo-OSDCloudDocumentation -OutputPath "D:\Docs\OSDCloudCustomBuilder"

# Include private functions in documentation
ConvertTo-OSDCloudDocumentation -IncludePrivateFunctions
```

## Project Structure

OSDCloudCustomBuilder/
├── Private/                # Internal helper functions
├── Public/                 # Exported module functions
├── Tests/                  # Pester test files
│   ├── Security/           # Security-focused tests
│   ├── Performance/        # Performance-focused tests
│   ├── ErrorHandling/      # Error handling tests
│   └── Logging/            # Logging tests
├── .github/                # GitHub workflows
├── OSDCloudCustomBuilder.psd1  # Module manifest
├── OSDCloudCustomBuilder.psm1  # Module implementation
└── README.md               # This file

```text

## Logging System

The module includes a comprehensive logging system:

```powershell
# Logs are created automatically during module operation
# Default log location: $env:TEMP\OSDCloudCustomBuilder.log

# You can customize the log path
Set-OSDCloudCustomBuilderConfig -LogPath "D:\Logs\OSDCloud"

# View logs using standard PowerShell commands
Get-Content -Path "$env:TEMP\OSDCloudCustomBuilder.log" -Tail 20

## Requirements

- PowerShell 5.1 or higher (PowerShell 7+ recommended for advanced features)
- Windows ADK for Windows PE features
- OSD PowerShell module
- Administrator privileges (for ISO creation and WIM manipulation)

## Version History

For a detailed list of changes and improvements, see the [CHANGELOG.md](CHANGELOG.md) file.

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file.

---

*Note: OSDCloudCustomBuilder is designed to extend the functionality of OSDCloud. For more information about OSDCloud itself, visit the [OSDCloud GitHub repository](https://github.com/OSDeploy/OSD).*
