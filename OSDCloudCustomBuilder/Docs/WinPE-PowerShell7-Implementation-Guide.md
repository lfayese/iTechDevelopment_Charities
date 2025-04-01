# WinPE PowerShell 7 Implementation and Verification Guide

This guide outlines the steps to implement and verify the refactored WinPE PowerShell 7 functionality in the OSDCloudCustomBuilder module.

## 1. Implementation Checklist

### 1.1 Function Implementation Status

| Function Name | Status | Location | Description |
|---------------|--------|----------|-------------|
| `Test-ValidPowerShellVersion` | ✅ Implemented | Root folder | Validates PowerShell version format and compatibility |
| `Get-PowerShell7Package` | ✅ Implemented | Root folder | Downloads or validates PowerShell 7 packages |
| `Find-WinPEBootWim` | ✅ Implemented | Root folder | Locates and validates boot.wim files |
| `Remove-WinPETemporaryFiles` | ✅ Implemented | Root folder | Cleans up temporary files |
| `Save-WinPEDiagnostics` | ✅ Implemented | Root folder | Collects diagnostic information |
| `Write-OSDCloudLog` | ✅ Implemented | Private folder | Logs operations with appropriate severity |
| `Update-WinPEWithPowerShell7` | ✅ Implemented | Root folder | Main orchestration function |

### 1.2 Function Location Moves Required

The following functions need to be moved to their correct locations:

| Function Name | Current Location | Target Location |
|---------------|------------------|----------------|
| `Test-ValidPowerShellVersion` | Root folder | Private folder |
| `Get-PowerShell7Package` | Root & Private folders | Private folder (remove duplicate) |
| `Find-WinPEBootWim` | Root folder | Private folder |
| `Remove-WinPETemporaryFiles` | Root folder | Private folder |
| `Save-WinPEDiagnostics` | Root folder | Private folder |
| `Update-WinPEWithPowerShell7` | Root & Private folders | Private folder (remove duplicate) |

## 2. Implementation Steps

### 2.1 Module Structure Fixes

1. Remove duplicate functions from the root folder
2. Update the module manifest to export the appropriate functions
3. Ensure all private functions are correctly loaded from the Private folder

### 2.2 Required Helper Functions

The refactoring also depends on these helper functions:

- `Initialize-WinPEMountPoint` - Already implemented
- `New-WinPEStartupProfile` - Already implemented
- `Mount-WinPEImage` - Already implemented
- `Install-PowerShell7ToWinPE` - Already implemented
- `Update-WinPERegistry` - Already implemented
- `Update-WinPEStartup` - Already implemented
- `Dismount-WinPEImage` - Already implemented
- `Get-ModuleConfiguration` - Already implemented

## 3. Verification Process

### 3.1 Unit Testing

1. Run the built-in Pester tests:
```powershell
cd d:\iTechDevelopment_Charities\OSDCloudCustomBuilder
.\Run-Tests.ps1
```

### 3.2 Manual Testing

1. **Basic Functionality Test**
   ```powershell
   # Create test directories
   $tempPath = "C:\Temp\OSDCloudTest"
   $workspacePath = "C:\Temp\OSDCloudWorkspace"
   
   # Test with default settings
   Update-WinPEWithPowerShell7 -TempPath $tempPath -WorkspacePath $workspacePath -Verbose -WhatIf
   ```

2. **Package Download Test**
   ```powershell
   # Test package download functionality
   $downloadPath = "C:\Temp\PS7Test\PowerShell-7.3.4-win-x64.zip"
   Get-PowerShell7Package -Version "7.3.4" -DownloadPath $downloadPath -Verbose
   ```

3. **Version Validation Test**
   ```powershell
   # Test version validation
   Test-ValidPowerShellVersion -Version "7.3.4"  # Should return $true
   Test-ValidPowerShellVersion -Version "6.2.5"  # Should return $false (wrong major version)
   Test-ValidPowerShellVersion -Version "7.9.1"  # Should return $false (unsupported minor)
   ```

4. **Error Handling Test**
   ```powershell
   # Test with non-existent paths (should handle errors gracefully)
   Update-WinPEWithPowerShell7 -TempPath "Z:\NonExistentPath" -WorkspacePath "Z:\NonExistentWorkspace" -ErrorAction SilentlyContinue
   ```

5. **Full Integration Test**
   ```powershell
   # Prepare a real WinPE workspace
   $realWorkspacePath = "C:\OSDCloud\WinPE"
   
   # Create a test environment
   $testTempPath = "C:\Temp\OSDCloud\TestRun"
   New-Item -Path $testTempPath -ItemType Directory -Force
   
   # Run the full process with an actual PowerShell 7 package
   Update-WinPEWithPowerShell7 -TempPath $testTempPath -WorkspacePath $realWorkspacePath -SkipCleanup -Verbose
   ```

### 3.3 Logging Verification

1. Check log files in the standard location:
   ```powershell
   Get-Content "$env:ProgramData\OSDCloud\Logs\OSDCloud-Log-$(Get-Date -Format 'yyyyMMdd').log"
   ```

2. Verify log levels and messages:
   - Info messages for normal operations
   - Warning messages for non-critical issues
   - Error messages for critical failures

## 4. Troubleshooting

### 4.1 Common Issues

1. **File Locking Issues**
   - Ensure no processes are using the WIM file before mounting
   - Use `Get-Process | Where-Object { $_.Modules.FileName -like "*dism*" }` to find potential locking processes

2. **Permissions Issues**
   - Run PowerShell as Administrator
   - Check write permissions on temporary and workspace paths

3. **Network Issues**
   - If PowerShell package download fails, check network connectivity
   - Try with a pre-downloaded package using the `-PowerShell7File` parameter

### 4.2 Diagnostic Information

The `Save-WinPEDiagnostics` function can be used to collect diagnostic information:

```powershell
# Collect diagnostics from a mounted WinPE image
Save-WinPEDiagnostics -MountPoint "C:\Mount\WinPE" -TempPath "C:\Temp" -IncludeRegistryExport
```

## 5. Cleanup After Testing

```powershell
# Clean up test directories
Remove-Item -Path "C:\Temp\OSDCloudTest" -Recurse -Force
Remove-Item -Path "C:\Temp\OSDCloudWorkspace" -Recurse -Force
Remove-Item -Path "C:\Temp\PS7Test" -Recurse -Force
```

## 6. Next Steps

1. Update documentation to reflect the refactored functionality
2. Consider adding more unit tests for edge cases
3. Implement additional logging retention policies