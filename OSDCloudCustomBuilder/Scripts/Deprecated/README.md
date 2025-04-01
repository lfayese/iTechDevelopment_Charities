# Deprecated Scripts

This folder contains scripts that are no longer used in the updated OSDCloudCustomBuilder module logic. These scripts have been replaced by newer, more efficient implementations or their functionality has been merged into other components.

## Scripts Moved from Main Module

The following scripts were moved from the main module structure as they are no longer directly used:

1. **Mutex-CriticalSection.ps1** - Replaced by more robust locking mechanisms in the updated module
2. **New-WorkspaceDirectory.ps1** - Functionality integrated into Initialize-BuildEnvironment.ps1
3. **Remove-TempFiles.ps1** - Functionality integrated into more comprehensive cleanup routines
4. **Test-WimFile.ps1** - Functionality integrated into Copy-CustomWimToWorkspace.ps1 with better error handling

## Recently Deprecated Scripts (April 2025)

The following scripts were moved to the Deprecated folder as part of the April 2025 refactoring:

1. **Find-WinPEBootWim.ps1** - Functionality moved to Private\WinPE-PowerShell7.ps1
2. **Get-PowerShell7Package.ps1** - Functionality moved to Private\WinPE-PowerShell7.ps1
3. **Remove-WinPETemporaryFiles.ps1** - Functionality moved to Private\WinPE-PowerShell7.ps1
4. **Save-WinPEDiagnostics.ps1** - Functionality moved to Private\WinPE-PowerShell7.ps1
5. **Update-WinPEWithPowerShell7.ps1** - Functionality moved to Private\Update-WinPEWithPowerShell7.ps1 and Private\WinPE-PowerShell7.ps1

These scripts were moved as part of the major refactoring effort to improve modularity and maintainability of the codebase. Their functionality is now available through the module's Private functions, which provide more consistent error handling, better performance, and improved security.

All scripts are kept for reference purposes but are no longer actively used in the module.