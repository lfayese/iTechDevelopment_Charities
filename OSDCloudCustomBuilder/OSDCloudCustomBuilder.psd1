@{
    RootModule        = 'OSDCloudCustomBuilder.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'e1e0a9c5-7b38-4b1a-9f9c-32743e2a6613'
    Author            = 'OSDCloud Team'
    CompanyName       = 'OSDCloud'
    Copyright         = '(c) 2025 OSDCloud. All rights reserved.'
    Description       = 'Module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support. Includes comprehensive error handling, logging, and configuration management.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Add-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO',
        'Get-OSDCloudConfig',
        'Import-OSDCloudConfig',
        'Export-OSDCloudConfig',
        'Update-OSDCloudConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('OSDCloud', 'WinPE', 'Deployment', 'Windows', 'PowerShell7', 'ISO', 'WIM')
            LicenseUri   = 'https://github.com/ofayese/OSDCloudCustomBuilder/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ofayese/OSDCloudCustomBuilder'
            ReleaseNotes = @'
# Version 0.2.0
- Added comprehensive error handling with try/catch blocks
- Implemented centralized logging system with Invoke-OSDCloudLogger
- Enhanced configuration management with OSDCloudConfig
- Added SupportsShouldProcess to system-modifying functions
- Improved parameter validation
- Added thorough documentation and examples
- Optimized complex functions by breaking them into smaller, more manageable components
- Increased test coverage with additional Pester tests
- Enhanced integration between OSDCloud and OSDCloudCustomBuilder

# Version 0.1.0
- Initial release of OSDCloudCustomBuilder
'@
        }
    }
}