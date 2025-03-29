# OSDCloud Deployment for Charities

This repository contains a customized implementation of OSDCloud technology for Windows operating system deployment with zero infrastructure. This solution simplifies Windows deployment for charities using custom scripts and interfaces.

## Overview

This solution enables you to:

- Deploy Windows 10/11 with minimal technical knowledge
- Automatically select appropriate OS versions based on hardware compatibility
- Apply custom organizational configurations
- Streamline the deployment process with a user-friendly interface
- Support multiple languages
- Integrate custom WIM files for specialized deployments
- Leverage PowerShell 7 for enhanced deployment capabilities

## Prerequisites

- Windows 10 or Windows 11 operating system (Home, Pro, Enterprise editions supported)
- PowerShell 5.1 or higher
- Administrator permissions
- Internet connectivity for downloading operating system images
- Windows Assessment and Deployment Kit (ADK) with WinPE feature installed (for building custom media)

## Repository Structure

- `/Archive`: Contains deprecated scripts and backups of previous OSDCloud implementations, retained for reference purposes only
- `/Docs`: PowerShell module documentation for OSDCloud cmdlets
- `/OSDCloud`: Core custom deployment scripts
  - `OSDCloudDeploymentGUI.ps1`: Main graphical deployment interface with hardware compatibility checks
  - `iDCMDMUI.ps1`: Custom UI launcher with USB device detection for custom WIM files
  - `/Autopilot`: Windows Autopilot integration scripts
    - `OSDCloud_UploadAutopilot.ps1`: Uploads hardware hash to Microsoft Intune for Autopilot registration
    - `OSDCloud_Tenant_Lockdown.ps1`: Configures UEFI variables for tenant lockdown
    - `Create_4kHash_using_OA3_Tool.ps1`: Creates hardware hash using Windows ADK OA3 tool
- `/OSDCloudCustomBuilder`: PowerShell module for creating deployment media
  - `OSDCloudCustomBuilder.psm1`: Main module that exports functions for creating custom OSDCloud environments
  - Public functions:
    - `Add-CustomWimWithPwsh7`: Adds PowerShell 7 and custom WIM files to OSDCloud environment
    - `New-CustomOSDCloudISO`: Creates bootable ISO with the custom configuration

## Getting Started

### Installation

1. Open PowerShell as Administrator
2. Install the OSD PowerShell Module:

```powershell
Install-Module OSD -Force
```

3. Verify installation:

```powershell
Get-Module OSD -ListAvailable
```

4. Clone or download this repository to a local folder

## Using the OSDCloud Custom Interface

The custom interface (`iDcMDMOSDCloudGUI.ps1`) provides a simplified deployment experience specifically tailored for charity organizations. This section walks through how to use this interface.

### Step 1: Preparing the Deployment Environment

1. Boot into Windows PE using an OSDCloud USB drive or ISO
2. Open PowerShell and navigate to the repository folder:

```powershell
cd D:\iTechDevelopment_Charities\OSDCloud
```

3. Run the custom OSDCloud GUI script:

```powershell
.\OSDCloudDeploymentGUI.ps1
```

### Step 2: Using the Deployment Interface

- **Automatic OS Selection**: The script automatically detects hardware compatibility (TPM 2.0 and compatible CPU) and selects the appropriate Windows version (Windows 10 for older hardware, Windows 11 for compatible systems). For unsupported hardware, the script provides a warning message and defaults to Windows 10 if possible, or halts the deployment with detailed instructions for manual intervention.
- **Language Selection**: Choose from available operating system languages (English and German currently supported)
- **Driver Management**: Select from different driver options:
  - Microsoft Update Catalog (recommended for most cases)
  - Manufacturer-specific driver packs (if available)
  - No drivers (for specialized deployments)
- **Custom WIM Support**: Automatically detects and allows selection of custom Windows images if present in X:\OSDCloud\custom.wim

To deploy Windows:
1. Select your preferred language
2. Choose the appropriate driver package option
3. Review the selected Windows version (automatically determined by hardware)
4. If available, choose whether to use a custom WIM file
5. Click "StartOSDCloud" to begin the deployment process

### Step 3: Post-Deployment

After the deployment completes:
1. The system will automatically restart
2. Windows will boot into the Out-of-Box Experience (OOBE)
3. Complete the Windows setup with your organization's information

## Building Custom Deployment Media

The OSDCloudCustomBuilder module is designed to create customized deployment media with PowerShell 7 support and custom Windows images.

### Creating a Custom OSDCloud Environment with PowerShell 7

1. Import the OSDCloudCustomBuilder module:

```powershell
Import-Module -Path "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\OSDCloudCustomBuilder.psm1" -Force
```

2. Create a custom OSDCloud environment with PowerShell 7 and a custom WIM:

```powershell
Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
```

3. Available parameters:
   - `-WimPath`: Path to your custom Windows image file  
     Example: `-WimPath "C:\Path\to\your\windows.wim"`
   - `-OutputPath`: Destination folder for the OSDCloud workspace  
     Example: `-OutputPath "C:\OSDCloud"`
   - `-ISOFileName`: Specify a custom ISO filename  
     Example: `-ISOFileName "CustomOSDCloud.iso"`
   - `-IncludeWinRE`: Include WinRE for WiFi support  
     Example: `-IncludeWinRE $true`
   - `-SkipCleanup`: Retain temporary files for troubleshooting  
     Example: `-SkipCleanup $true`

### Creating Bootable Media

After creating your custom workspace:

1. Create a bootable USB drive:

```powershell
New-OSDCloudUSB -WorkspacePath C:\OSDCloud
```

2. Or create a bootable ISO file:

```powershell
New-OSDCloudISO -WorkspacePath C:\OSDCloud
```

## Integration Between OSDCloud and OSDCloudCustomBuilder

The repository is structured to provide a complete Windows deployment solution:

1. **OSDCloudCustomBuilder** provides the tools to create custom deployment media:
   - Adds PowerShell 7 to the WinPE environment
   - Injects custom Windows images into deployment media
   - Creates bootable ISOs with optimized size

2. **OSDCloud** provides the deployment experience:
   - Detects custom WIM files created by OSDCloudCustomBuilder
   - Implements hardware compatibility checks
   - Provides a simplified GUI for deployment settings
   - Supports Windows Autopilot integration

This integration allows administrators to:
1. Create customized deployment images with the OSDCloudCustomBuilder module
2. Deploy these images to charitable organizations' computers using the simplified OSDCloud interface
3. Register devices with Microsoft Autopilot for zero-touch provisioning

## Windows Autopilot Integration

The solution includes Windows Autopilot integration which can be used directly from the WinPE environment:

1. Boot the target device into WinPE using the custom OSDCloud media
2. Navigate to the Autopilot folder:
```powershell
cd D:\iTechDevelopment_Charities\OSDCloud\Autopilot
```
3. Execute the Autopilot registration script:
```powershell
.\OSDCloud_UploadAutopilot.ps1
```

This process:
- Uses the OA3Tool from Windows ADK to generate a hardware hash
- Uploads the device information to Microsoft Intune
- Registers the device for zero-touch deployment

## Advanced Configuration

### Customizing the Deployment Process

The main configuration files can be found in:
- `OSDCloud\iDcMDMOSDCloudGUI.ps1`: Contains the GUI configuration and deployment settings
- `OSDCloud\iDCMDMUI.ps1`: Contains the launcher interface settings

Key configuration elements include:
- OS Edition settings (Enterprise by default)
- UEFI integration settings for tenant lockdown via UEFI variables
- Custom WIM detection and integration
- Hardware compatibility checks

### PowerShell 7 Integration

The solution includes PowerShell 7 support for enhanced deployment capabilities:
- PowerShell 7 is integrated into the WinPE environment by the OSDCloudCustomBuilder
- Provides improved performance and advanced scripting features
- Enables more complex deployment scenarios

## Troubleshooting

- **Hardware Compatibility Issues**: The script automatically checks for TPM 2.0 and CPU compatibility. If Windows 11 compatibility is not detected, it will default to Windows 10.
- **Driver Problems**: If you experience driver issues, try using a different driver source in the GUI.
- **Log Files**: 
  - WinPE Phase: Logs are stored in `X:\OSDCloud\Logs`
  - Windows Phase: Logs are stored in `C:\Windows\Logs\OSDCloud`
- **Custom WIM Not Detected**: Verify the custom.wim file is placed in one of the supported locations. The deployment interface searches multiple locations and connected USB drives.

## Support and Contribution

For issues or questions, please contact the repository maintainers. Contributions to improve the deployment process for charity organizations are welcome.

## Additional Resources

- [OSDeploy GitHub](https://github.com/OSDeploy/OSD)
- [OSDCloud Documentation](https://www.osdcloud.com)
- [PowerShell 7 Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Windows Autopilot Documentation](https://docs.microsoft.com/en-us/windows/deployment/windows-autopilot/windows-autopilot)
