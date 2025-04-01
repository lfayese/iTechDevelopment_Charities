# OSDCloud Deployment for Charities

[![PowerShell Module CI/CD](https://github.com/ofayese/OSDCloudCustomBuilder/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/ofayese/OSDCloudCustomBuilder/actions/workflows/ci-cd.yml)
[![codecov](https://codecov.io/gh/ofayese/OSDCloudCustomBuilder/branch/main/graph/badge.svg)](https://codecov.io/gh/ofayese/OSDCloudCustomBuilder)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/OSDCloudCustomBuilder)](https://www.powershellgallery.com/packages/OSDCloudCustomBuilder)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/OSDCloudCustomBuilder)](https://www.powershellgallery.com/packages/OSDCloudCustomBuilder)

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
- Utilize enhanced security features with package verification and TLS 1.2
- Take advantage of performance optimizations with parallel processing
- Collect optional telemetry to identify issues in production environments
- Generate comprehensive documentation from code comments

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
    - `Update-CustomWimWithPwsh7`: Adds PowerShell 7 and custom WIM files to OSDCloud environment
    - `New-CustomOSDCloudISO`: Creates bootable ISO with the custom configuration
    - `Set-OSDCloudCustomBuilderConfig`: Configures module settings for customization
    - `Set-OSDCloudTelemetry`: Configures telemetry options for troubleshooting
    - `ConvertTo-OSDCloudDocumentation`: Generates documentation from code comments
  - `/Examples`: Sample scripts demonstrating key functionality
    - `Create-CustomISOWithTelemetry.ps1`: Creates a custom ISO with telemetry enabled
    - `Generate-ModuleDocumentation.ps1`: Generates comprehensive documentation
    - `Analyze-TelemetryData.ps1`: Analyzes telemetry data to identify issues
    - `Export-TelemetryData.ps1`: Exports telemetry for external analysis

## Getting Started

### Installation

1. Open PowerShell as Administrator
2. Install the OSD PowerShell Module:

```powershell
Install-Module OSD -Force
```

3. Install the OSDCloudCustomBuilder module:

```powershell
# From PowerShell Gallery
Install-Module OSDCloudCustomBuilder -Force

# Or from local repository
Import-Module ./OSDCloudCustomBuilder/OSDCloudCustomBuilder.psm1 -Force
```

4. Verify installation:

```powershell
Get-Module OSDCloudCustomBuilder -ListAvailable
```

## Quick Start Guide

1. **Install the Module**
   ```powershell
   Import-Module OSDCloudCustomBuilder
   ```

2. **Customize WinPE**
   Customize your Windows Preinstallation Environment with PowerShell 7:
   ```powershell
   Update-WinPEWithPowerShell7 -Path "PathToWinPE"
   ```

3. **Configure Module Settings**
   Configure PowerShell versions, timeouts, and other settings:
   ```powershell
   Set-OSDCloudCustomBuilderConfig -DefaultPowerShellVersion "7.5.0" -MountTimeout 600
   ```

4. **Enable Telemetry (Optional)**
   Configure telemetry to help identify issues in production environments:
   ```powershell
   Set-OSDCloudTelemetry -Enable $true -DetailLevel Standard
   ```

5. **Generate Documentation**
   Create comprehensive documentation from code comments:
   ```powershell
   ConvertTo-OSDCloudDocumentation -IncludePrivateFunctions -GenerateExampleFiles
   ```

6. **Verbose Logging**
   All operations now include structured logging with timestamps for easier troubleshooting. Example log format:
   ```
   [2025-03-31 10:00:00] [INFO] [OSDCloudCustomBuilder] Starting Update-CustomWimWithPwsh7
   ```

## Using the OSDCloud Custom Interface

The custom interface (`iDcMDMOSDCloudGUI.ps1`) provides a simplified deployment experience specifically tailored for charity organizations. This section walks through how to use this interface.

### Step 1: Preparing the Deployment Environment

1. Boot into Windows PE using an OSDCloud USB drive or ISO
2. Open PowerShell and navigate to the repository folder:

```powershell
cd D:\\iTechDevelopment_Charities\\OSDCloud
```

3. Run the custom OSDCloud GUI script:

```powershell
.\\OSDCloudDeploymentGUI.ps1
```

### Step 2: Using the Deployment Interface

- **Automatic OS Selection**: The script automatically detects hardware compatibility (TPM 2.0 and compatible CPU) and selects the appropriate Windows version (Windows 10 for older hardware, Windows 11 for compatible systems). For unsupported hardware, the script provides a warning message and defaults to Windows 10 if possible, or halts the deployment with detailed instructions for manual intervention.
- **Language Selection**: Choose from available operating system languages (English and German currently supported)
- **Driver Management**: Select from different driver options:
  - Microsoft Update Catalog (recommended for most cases)
  - Manufacturer-specific driver packs (if available)
  - No drivers (for specialized deployments)
- **Custom WIM Support**: Automatically detects and allows selection of custom Windows images if present in X:\\OSDCloud\\custom.wim

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
Import-Module OSDCloudCustomBuilder -Force
```

2. Create a custom OSDCloud environment with PowerShell 7 and a custom WIM:

```powershell
Update-CustomWimWithPwsh7 -WimPath "C:\\Path\\to\\your\\windows.wim" -OutputPath "C:\\OSDCloud"
```

3. Available parameters:
   - `-WimPath`: Path to your custom Windows image file  
     Example: `-WimPath "C:\\Path\\to\\your\\windows.wim"`
   - `-OutputPath`: Destination folder for the OSDCloud workspace  
     Example: `-OutputPath "C:\\OSDCloud"`
   - `-ISOFileName`: Specify a custom ISO filename  
     Example: `-ISOFileName "CustomOSDCloud.iso"`
   - `-IncludeWinRE`: Include WinRE for WiFi support  
     Example: `-IncludeWinRE $true`
   - `-SkipCleanup`: Retain temporary files for troubleshooting  
     Example: `-SkipCleanup $true`
   - `-PowerShellVersion`: Specify PowerShell version to use  
     Example: `-PowerShellVersion "7.5.0"`
   - `-MountTimeout`: Set timeout for mounting operations (in seconds)  
     Example: `-MountTimeout 600`
   - `-DismountTimeout`: Set timeout for dismounting operations (in seconds)  
     Example: `-DismountTimeout 600`
   - `-DownloadTimeout`: Set timeout for download operations (in seconds)  
     Example: `-DownloadTimeout 1200`

### Creating Bootable Media

After creating your custom workspace:

1. Create a bootable USB drive:

```powershell
New-OSDCloudUSB -WorkspacePath C:\\OSDCloud
```

2. Or create a bootable ISO file:

```powershell
New-OSDCloudISO -WorkspacePath C:\\OSDCloud
```

### Configuring Module Settings

The module now includes a configuration system that allows you to customize various settings:

```powershell
Set-OSDCloudCustomBuilderConfig -DefaultPowerShellVersion "7.5.0" -SupportedPowerShellVersions @("7.3.4", "7.4.1", "7.5.0") -MountTimeout 600 -DismountTimeout 600 -DownloadTimeout 1200 -CachePath "C:\\OSDCloudCache"
```

Available configuration options:
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

## Telemetry and Metrics

The module includes an optional telemetry system to help identify issues in production environments:

### Configuring Telemetry

Control what data is collected and where it's stored:

```powershell
# Enable telemetry with standard detail level
Set-OSDCloudTelemetry -Enable $true -DetailLevel Standard

# Collect detailed metrics for advanced troubleshooting
Set-OSDCloudTelemetry -DetailLevel Detailed -StoragePath "D:\OSDTelemetry"

# Disable telemetry collection
Set-OSDCloudTelemetry -Enable $false
```

### Telemetry Detail Levels

- **Basic**: Collects only operation names, duration, and success/failure status
- **Standard**: Adds memory usage and error details (default)
- **Detailed**: Adds system information and detailed metrics for advanced troubleshooting

### Analyzing Telemetry Data

The Examples directory includes scripts to analyze telemetry data:

```powershell
# Analyze telemetry to identify issues
.\Examples\Analyze-TelemetryData.ps1

# Export telemetry for further analysis
.\Examples\Export-TelemetryData.ps1 -OutputFolder "D:\Exports" -ExportFormat CSV,HTML
```

### Privacy and Data Retention

- No personally identifiable information (PII) is collected
- All telemetry is stored locally by default
- Remote telemetry upload is disabled by default and requires explicit opt-in
- Telemetry data is automatically cleaned up after 90 days (configurable)
- Stack traces are automatically sanitized to remove user paths

## Documentation Generation

The module includes a comprehensive documentation generator that creates markdown documentation from PowerShell comment-based help.

### Generating Documentation

Create complete documentation including function references, examples, and parameter details:

```powershell
# Generate basic documentation
ConvertTo-OSDCloudDocumentation

# Include private functions and generate example files
ConvertTo-OSDCloudDocumentation -IncludePrivateFunctions -GenerateExampleFiles

# Use a custom README template
ConvertTo-OSDCloudDocumentation -ReadmeTemplate "path\to\template.md"
```

### Documentation Features

- Automatically creates function reference documentation for all public functions
- Optionally includes internal/private functions for developer reference
- Extracts examples from comment-based help into runnable script files
- Generates parameter details including type, default values, and validation
- Creates formatted markdown that renders well in GitHub and other platforms
- Builds a hierarchical documentation structure with the index, function references, and examples

### Example Script Generation

When the `-GenerateExampleFiles` parameter is used, the documentation generator extracts example code from function documentation into separate, runnable PowerShell scripts in the 'examples' directory.

## Development and Testing

### Running Tests

The module includes a comprehensive test suite built with Pester. To run the tests:

```powershell
# Run all tests with default settings
./Run-Tests.ps1

# Run tests with code coverage report
./Run-Tests.ps1 -ShowCodeCoverageReport

# Run specific tests with custom verbosity
./Run-Tests.ps1 -TestPath './Tests/Unit' -Verbosity 'Minimal'
```

### Continuous Integration

This module uses GitHub Actions for continuous integration and deployment:

1. **Automated Testing**: All pull requests and pushes to main branches are automatically tested
2. **Code Analysis**: PSScriptAnalyzer is run to ensure code quality
3. **Code Coverage**: Test coverage is tracked and reported via Codecov
4. **Automatic Publishing**: When a new release is created, the module is automatically published to the PowerShell Gallery

### Contributing

Contributions to improve the deployment process for charity organizations are welcome:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests to ensure everything works (`./Run-Tests.ps1`)
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Integration Between OSDCloud and OSDCloudCustomBuilder

The repository is structured to provide a complete Windows deployment solution:

1. **OSDCloudCustomBuilder** provides the tools to create custom deployment media:
   - Adds PowerShell 7 to the WinPE environment
   - Injects custom Windows images into deployment media
   - Creates bootable ISOs with optimized size
   - Verifies package integrity with hash validation
   - Implements secure TLS 1.2 communication
   - Caches downloaded packages for improved performance
   - Collects optional telemetry to identify issues
   - Generates comprehensive documentation from code

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
cd D:\\iTechDevelopment_Charities\\OSDCloud\\Autopilot
```
3. Execute the Autopilot registration script:
```powershell
.\\OSDCloud_UploadAutopilot.ps1
```

This process:
- Uses the OA3Tool from Windows ADK to generate a hardware hash
- Uploads the device information to Microsoft Intune
- Registers the device for zero-touch deployment

## Advanced Configuration

### Customizing the Deployment Process

The main configuration files can be found in:
- `OSDCloud\\iDcMDMOSDCloudGUI.ps1`: Contains the GUI configuration and deployment settings
- `OSDCloud\\iDCMDMUI.ps1`: Contains the launcher interface settings

Key configuration elements include:
- OS Edition settings (Enterprise by default)
- UEFI integration settings for tenant lockdown via UEFI variables
- Custom WIM detection and integration
- Hardware compatibility checks

### Telemetry Configuration

The telemetry system can be customized to meet specific organizational needs:

```powershell
# Configure telemetry storage and retention
Set-OSDCloudTelemetry -StoragePath "D:\Telemetry" 

# Configure telemetry data retention (add to your scheduled tasks)
Get-ChildItem -Path "D:\Telemetry" -Filter *.json |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } |
    Remove-Item -Force
```

The module includes automatic telemetry data sanitization to ensure no sensitive information is collected:
- User paths are automatically replaced with `<User>` placeholder
- System-specific identifiers are anonymized
- Error messages are preserved for troubleshooting but sanitized of PII

### PowerShell 7 Integration

The solution includes PowerShell 7 support for enhanced deployment capabilities:
- PowerShell 7 is integrated into the WinPE environment by the OSDCloudCustomBuilder
- Provides improved performance and advanced scripting features
- Enables more complex deployment scenarios
- Includes package verification with SHA-256 hash validation
- Uses TLS 1.2 for secure downloads
- Implements caching for improved performance and reduced bandwidth usage

### Security Enhancements

The module now includes several security enhancements:
- **Package Verification**: All PowerShell 7 packages are verified using SHA-256 hash validation
- **Secure Communication**: TLS 1.2 is enforced for all web requests
- **Command Escaping**: Proper escaping of paths and commands to prevent injection attacks
- **Parameter Validation**: Thorough validation of all input parameters
- **Error Handling**: Comprehensive error handling with proper cleanup of resources

### Performance Optimizations

The module includes several performance optimizations:
- **Parallel Processing**: File operations are performed in parallel when possible
- **Package Caching**: Downloaded PowerShell packages are cached for reuse
- **Memory Management**: Explicit garbage collection to reduce memory usage
- **Configurable Timeouts**: All operations have configurable timeouts

## Troubleshooting

- **Hardware Compatibility Issues**: The script automatically checks for TPM 2.0 and CPU compatibility. If Windows 11 compatibility is not detected, it will default to Windows 10.
- **Driver Problems**: If you experience driver issues, try using a different driver source in the GUI.
- **Log Files**: 
  - WinPE Phase: Logs are stored in `X:\\OSDCloud\\Logs`
  - Windows Phase: Logs are stored in `C:\\Windows\\Logs\\OSDCloud`
  - Module logs: Stored in `%TEMP%\\OSDCloudCustomBuilder\\Logs`
  - Telemetry data: Stored in the configured telemetry path or `<ModuleRoot>\\Logs\\Telemetry` by default
- **Custom WIM Not Detected**: Verify the custom.wim file is placed in one of the supported locations. The deployment interface searches multiple locations and connected USB drives.
- **Package Verification Failures**: If hash verification fails, try clearing the cache or updating the hash values with `Set-OSDCloudCustomBuilderConfig`
- **Analyzing Performance Issues**: Use the telemetry analysis tools to identify bottlenecks:
  ```powershell
  .\Examples\Analyze-TelemetryData.ps1
  ```

## Support and Contribution

For issues or questions, please contact the repository maintainers. Contributions to improve the deployment process for charity organizations are welcome.

## Additional Resources

- [OSDeploy GitHub](https://github.com/OSDeploy/OSD)
- [OSDCloud Documentation](https://www.osdcloud.com)
- [PowerShell 7 Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Windows Autopilot Documentation](https://docs.microsoft.com/en-us/windows/deployment/windows-autopilot/windows-autopilot)
- [PowerShell Comment-Based Help](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help)