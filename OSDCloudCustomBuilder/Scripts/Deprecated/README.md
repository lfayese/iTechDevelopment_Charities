# Deprecated Scripts

This folder contains scripts that are no longer used in the updated OSDCloudCustomBuilder module logic. These scripts have been replaced by newer, more efficient implementations or their functionality has been merged into other components.

## Scripts Moved from Main Module

The following scripts were moved from the main module structure as they are no longer directly used:

1. **Mutex-CriticalSection.ps1** - Replaced by more robust locking mechanisms in the updated module
2. **New-WorkspaceDirectory.ps1** - Functionality integrated into Initialize-BuildEnvironment.ps1
3. **Remove-TempFiles.ps1** - Functionality integrated into more comprehensive cleanup routines
4. **Test-WimFile.ps1** - Functionality integrated into Copy-CustomWimToWorkspace.ps1 with better error handling

These scripts are kept for reference purposes but are no longer actively used in the module.