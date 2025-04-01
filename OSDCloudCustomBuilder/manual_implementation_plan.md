# Manual Implementation Plan for WinPE-PowerShell7.ps1 Refactoring

## Overview

This document provides a detailed plan for manually implementing the refactoring of the WinPE-PowerShell7.ps1 file. Due to limitations with the change_applier tool, these changes should be implemented manually.

## Implementation Steps

1. **Update File Header**
   - Update the version number to 1.0.0 (from 0.2.0)
   - Keep the existing synopsis and description

2. **Add Missing Functions**
   - Add the `Test-ValidPowerShellVersion` function (from Test-ValidPowerShellVersion.ps1)
   - Add the `Get-PowerShell7Package` function (from Get-PowerShell7Package.ps1)
   - Add the `Find-WinPEBootWim` function (from Find-WinPEBootWim.ps1)
   - Add the `Remove-WinPETemporaryFiles` function (from Remove-WinPETemporaryFiles.ps1)
   - Add the `Save-WinPEDiagnostics` function (from Save-WinPEDiagnostics.ps1)

3. **Fix Existing Functions**
   - Fix the `Initialize-WinPEMountPoint` function by correcting variable names:
     - Change `$TempPath` to `$TemporaryPath`
     - Change `$InstanceId` to `$InstanceIdentifier`

4. **Update Main Function**
   - Replace the current `Update-WinPEWithPowerShell7` function with the refactored version (from Update-WinPEWithPowerShell7.ps1)
   - Ensure all parameter names and aliases are maintained for backward compatibility

5. **Maintain Backward Compatibility**
   - Keep the existing alias for backward compatibility:
     ```powershell
     Set-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7
     ```

6. **Export Functions and Aliases**
   - Keep the existing export statement:
     ```powershell
     Export-ModuleMember -Function * -Alias *
     ```

## Function Placement Order

The functions should be placed in the following order:

1. `Test-ValidPowerShellVersion` (new)
2. `Initialize-WinPEMountPoint` (existing, with fixes)
3. `New-WinPEStartupProfile` (existing)
4. `Mount-WinPEImage` (existing)
5. `Install-PowerShell7ToWinPE` (existing)
6. `Update-WinPERegistry` (existing)
7. `Update-WinPEStartup` (existing)
8. `Dismount-WinPEImage` (existing)
9. `Get-PowerShell7Package` (new)
10. `Find-WinPEBootWim` (new)
11. `Remove-WinPETemporaryFiles` (new)
12. `Save-WinPEDiagnostics` (new)
13. `Update-WinPEWithPowerShell7` (refactored)

## Testing After Implementation

After implementing these changes, the following tests should be performed:

1. Validate that all functions can be imported correctly
2. Test the `Update-WinPEWithPowerShell7` function with the `-WhatIf` parameter
3. Verify backward compatibility by using the `Customize-WinPEWithPowerShell7` alias
4. Test error handling by intentionally providing invalid parameters

## Rollback Plan

Before making any changes, create a backup of the original file:
```powershell
Copy-Item -Path "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1" -Destination "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1.bak"
```

If any issues are encountered, restore from the backup:
```powershell
Copy-Item -Path "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1.bak" -Destination "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1" -Force
```