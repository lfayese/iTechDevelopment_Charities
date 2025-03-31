# OSDCloudCustomBuilder Private Functions

This directory contains the private functions used internally by the OSDCloudCustomBuilder module. These functions are not exported but provide essential functionality for the module.

## Core Utility Functions

### Get-ModuleConfiguration
Retrieves the module configuration from user settings or defaults.

### Write-OSDCloudLog
Provides a centralized logging mechanism for the module.

### Measure-OSDCloudOperation
Measures and records performance metrics for operations.

### Test-ValidPowerShellVersion
Validates PowerShell version format and availability.

### Get-CachedPowerShellPackage
Retrieves cached PowerShell packages to avoid redundant downloads.

### Get-PowerShell7Package
Downloads and verifies PowerShell 7 packages with hash validation.

### Copy-FilesInParallel
Performs parallel file copy operations for improved performance.

## WinPE Customization Functions

### Update-WinPEWithPowerShell7
Adds PowerShell 7 to a Windows PE image.

### Update-WinPEStartup
Updates the WinPE startup script to initialize PowerShell 7.

### WinPE-PowerShell7
Contains functions for PowerShell 7 integration in WinPE.

### WinPE-Customization
Contains general WinPE customization functions.

## File Operations

### Copy-CustomWimToWorkspace
Copies a WIM file to the workspace.

### Copy-WimFileEfficiently
Efficiently copies large WIM files with progress reporting.

### Copy-CustomizationScripts
Copies customization scripts to the workspace.

## Environment Management

### Initialize-BuildEnvironment
Sets up the build environment.

### Initialize-OSDCloudTemplate
Initializes the OSDCloud template.

### Initialize-OSDEnvironment
Initializes the OSD environment.

## Utility Functions

### Invoke-WithRetry
Executes commands with retry logic for transient failures.

### Invoke-OSDCloudLogger
Provides structured logging for the module.

### Mutex-CriticalSection
Handles critical sections with proper locking.

### Test-WimFile
Tests WIM file integrity.

### New-WorkspaceDirectory
Creates workspace directories.

### Remove-TempFiles
Cleans up temporary files.

### Show-Summary
Displays a summary of operations.

## Security Features

All private functions include:
- Error handling with try/catch blocks
- Proper resource cleanup
- Secure parameter handling
- Hash verification for downloaded packages
- TLS 1.2 enforcement for secure downloads
- Command escaping to prevent injection attacks