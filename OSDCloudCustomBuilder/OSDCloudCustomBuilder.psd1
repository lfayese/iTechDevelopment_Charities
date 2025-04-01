# Patched
Set-StrictMode -Version Latest
@{
    RootModule        = 'OSDCloudCustomBuilder.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = 'e1e0a9c5-7b38-4b1a-9f9c-32743e2a6613'
    Author            = 'OSDCloud Team'
    CompanyName       = 'OSDCloud'
    Copyright         = '(c) 2025 OSDCloud. All rights reserved.'
    Description       = 'Module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support. Includes comprehensive error handling, logging, and configuration management.'
    PowerShellVersion = '5.1'
FunctionsToExport = @(
    'ConvertTo-OSDCloudDocumentation'
    'Enable-OSDCloudTelemetry'
    'Escape-Markdown'
    'Export-ModuleMember'
    'Get-TelemetryDefaults'
    'New-CustomOSDCloudISO'
    'Set-OSDCloudCustomBuilderConfig'
    'Set-OSDCloudTelemetry'
    'Update-CustomWimWithPwsh7'
    'Write-Log'
)
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @(
        'Add-CustomWimWithPwsh7',
        'Customize-WinPEWithPowerShell7'
    )
    PrivateData       = @{
        PSData = @{
            Tags         = @('OSDCloud', 'WinPE', 'Deployment', 'Windows', 'PowerShell7', 'ISO', 'WIM')
            LicenseUri   = 'https://github.com/ofayese/OSDCloudCustomBuilder/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ofayese/OSDCloudCustomBuilder'
            ReleaseNotes = @'
# Version 0.3.0
- Added optional telemetry system to help identify issues in production environments
- Added documentation generation from code comments with ConvertTo-OSDCloudDocumentation
- Added example scripts that demonstrate new capabilities
- Added Set-OSDCloudTelemetry for configuring telemetry options
- Enhanced Measure-OSDCloudOperation with detailed process and system metrics
- Added telemetry privacy controls and storage path configuration
- Improved documentation with comprehensive examples and parameter descriptions
- Added support for converting code comments to Markdown documentation

# Version 0.2.0
- Added comprehensive error handling with try/catch blocks
- Implemented centralized logging system with Write-OSDCloudLog and Invoke-OSDCloudLogger
- Enhanced configuration management with OSDCloudConfig and Get-ModuleConfiguration
- Added PowerShell 7 package verification with hash validation
- Improved security with proper command escaping and TLS 1.2 enforcement
- Added caching mechanism for PowerShell 7 packages
- Enhanced parallel processing with Copy-FilesInParallel
- Added configurable timeouts for mount, dismount, and download operations
- Implemented telemetry with Measure-OSDCloudOperation
- Added SupportsShouldProcess to system-modifying functions
- Improved parameter validation with Test-ValidPowerShellVersion
- Added thorough documentation and examples
- Optimized complex functions by breaking them into smaller, more manageable components
- Increased test coverage with additional Pester tests
- Enhanced integration between OSDCloud and OSDCloudCustomBuilder
- Improved memory management with explicit garbage collection
- Added backward compatibility aliases for renamed functions
- Renamed Customize-WinPEWithPowerShell7 to Update-WinPEWithPowerShell7 for better verb-noun consistency
- Renamed Add-CustomWimWithPwsh7 to Update-CustomWimWithPwsh7 for better verb-noun consistency

# Version 0.1.0
- Initial release of OSDCloudCustomBuilder
'@
        }
    }
}