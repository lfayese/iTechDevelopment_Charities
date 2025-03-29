@{
    RootModule = 'OSDCloudCustomBuilder.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'e1e0a9c5-7b38-4b1a-9f9c-32743e2a6613'
    Author = 'OSDCloud Team'
    CompanyName = 'OSDCloud'
    Copyright = '(c) 2025 OSDCloud. All rights reserved.'
    Description = 'Module for creating custom OSDCloud ISOs with Windows Image (WIM) files and PowerShell 7 support'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Add-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO'
    )
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('OSDCloud', 'WinPE', 'Deployment', 'Windows', 'PowerShell7')
            LicenseUri = 'https://github.com/ofayese/OSDCloudCustomBuilder/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ofayese/OSDCloudCustomBuilder'
            ReleaseNotes = 'Initial release of OSDCloudCustomBuilder'
        }
    }
}