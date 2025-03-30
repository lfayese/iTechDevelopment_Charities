<#
.SYNOPSIS
    Creates an OSDCloud ISO with a custom Windows Image (WIM) file and PowerShell 7 support.
.DESCRIPTION
    This function creates a complete OSDCloud ISO with a custom Windows Image (WIM) file,
    PowerShell 7 support, and customizations. It handles the entire process from
    template creation to ISO generation.
.PARAMETER WimPath
    The path to the Windows Image (WIM) file to include in the ISO.
.PARAMETER OutputPath
    The directory path where the ISO file will be created.
.PARAMETER ISOFileName
    The name of the ISO file to create. Default is "OSDCloudCustomWIM.iso".
.PARAMETER TempPath
    The path where temporary files will be stored. Default is "$env:TEMP\OSDCloudCustomBuilder".
.PARAMETER PowerShellVersion
    The PowerShell version to include. Default is "7.3.4".
.PARAMETER IncludeWinRE
    If specified, includes Windows Recovery Environment (WinRE) in the ISO.
.PARAMETER SkipCleanup
    If specified, skips cleanup of temporary files after ISO creation.
.EXAMPLE
    Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
.EXAMPLE
    Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"
.EXAMPLE
    Add-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -IncludeWinRE
.NOTES
    Requires administrator privileges and Windows ADK installed.
#>
function Add-CustomWimWithPwsh7 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "The WIM file '$_' does not exist or is not a file."
            }
            if (-not ($_ -match '\.wim$')) {
                throw "The file '$_' is not a WIM file."
            }
            return $true
        })]
        [string]$WimPath,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ISOFileName = "OSDCloudCustomWIM.iso",
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath = "$env:TEMP\OSDCloudCustomBuilder",
        [Parameter()]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$PowerShellVersion = "7.3.4",
        [Parameter()]
        [switch]$IncludeWinRE,
        [Parameter()]
        [switch]$SkipCleanup,
        [Parameter()]
        [int]$TimeoutMinutes = 60
    )
    begin {
        $errorCollection = @()
        $operationTimeout = (Get-Date).AddMinutes($TimeoutMinutes)
        
        # Check for administrator privileges once
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "This function requires administrator privileges to run properly."
            }
        }
        catch {
            Write-Error "Failed to check administrator privileges: $_"
            throw "Administrator privilege check failed. Please run as administrator."
        }
        
        # Cache the drive letter once to reduce repeated lookups
        try {
            $tempDrive = (Split-Path -Path $TempPath -Qualifier)
            # Assume drive letter is the first character of the qualifier
            $driveLetter = $tempDrive.Substring(0,1)
            $psDrive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
            $freeSpace = $psDrive.Free
            $requiredSpace = 15GB
            if ($freeSpace -lt $requiredSpace) {
                throw "Insufficient disk space. Need at least $(($requiredSpace / 1GB).ToString('N2')) GB, but only $(($freeSpace / 1GB).ToString('N2')) GB available on drive $tempDrive."
            }
            Write-Verbose "Sufficient disk space available: $(($freeSpace / 1GB).ToString('N2')) GB"
        }
        catch {
            $errorCollection += "Disk space check failed: $_"
            Write-Warning "Could not verify disk space. Proceeding anyway, but may encounter space issues."
        }
        
        # Set up workspace paths and output ISO file path
        $workspacePath = Join-Path -Path $TempPath -ChildPath "Workspace"
        $tempWorkspacePath = Join-Path -Path $TempPath -ChildPath "TempWorkspace"
        if (-not $OutputPath.EndsWith(".iso")) {
            $OutputPath = Join-Path -Path $OutputPath -ChildPath $ISOFileName
        }
        $outputDirectory = Split-Path -Path $OutputPath -Parent
        
        # Create necessary directories in a single loop
        try {
            foreach ($dir in @($workspacePath, $tempWorkspacePath, $outputDirectory)) {
                if (-not (Test-Path $dir)) {
                    Write-Verbose "Creating directory: $dir"
                    New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
            }
        }
        catch {
            $errorCollection += "Failed to create required directories: $_"
            throw "Directory creation failed: $_"
        }
    }
    process {
        try {
            Write-Verbose "Starting OSDCloud ISO creation process"
            if ((Get-Date) -gt $operationTimeout) {
                throw "Operation timed out before completion."
            }
            
            # Copy the WIM file to the workspace
            $currentOperation = "Copying WIM file"
            Write-Host "Copying custom WIM to workspace..." -ForegroundColor Cyan
            try {
                Copy-CustomWimToWorkspace -WimPath $WimPath -WorkspacePath $workspacePath -UseRobocopy -ErrorAction Stop
                Write-Verbose "WIM file copied successfully"
            }
            catch {
                $errorCollection += "Error copying WIM file: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            
            # Launch background tasks in parallel to reduce overall processing time.
            # Note: For very limited parallel tasks, the overhead of Start-Job is minimal.
            $jobs = @()
            $currentOperation = "Adding PowerShell 7 and Optimizing ISO Size"
            Write-Host "Starting background tasks..." -ForegroundColor Cyan
            
            $jobs += Start-Job -ScriptBlock {
                param($tempPath, $workspacePath, $psVersion)
                try {
                    Customize-WinPEWithPowerShell7 -TempPath $tempPath -WorkspacePath $workspacePath -PowerShellVersion $psVersion -ErrorAction Stop
                    return @{ Success = $true; Message = "PowerShell 7 customization completed successfully" }
                }
                catch {
                    return @{ Success = $false; Message = "PowerShell 7 customization failed: $_" }
                }
            } -ArgumentList $tempWorkspacePath, $workspacePath, $PowerShellVersion
            
            $jobs += Start-Job -ScriptBlock {
                param($workspacePath)
                try {
                    Optimize-ISOSize -WorkspacePath $workspacePath -ErrorAction Stop
                    return @{ Success = $true; Message = "ISO size optimization completed successfully" }
                }
                catch {
                    return @{ Success = $false; Message = "ISO size optimization failed: $_" }
                }
            } -ArgumentList $workspacePath
            
            $currentOperation = "Processing background jobs"
            $jobTimeoutSeconds = 20 * 60
            if (-not (Wait-Job -Job $jobs -Timeout $jobTimeoutSeconds)) {
                throw "Background jobs timed out after 20 minutes."
            }
            foreach ($job in $jobs) {
                $result = Receive-Job -Job $job
                if (-not $result.Success) {
                    $errorCollection += $result.Message
                }
            }
            Remove-Job -Job $jobs -Force
            
            if ($errorCollection.Count -gt 0) {
                throw "One or more background tasks failed: $($errorCollection -join ', ')"
            }
            
            # Create the ISO file
            $currentOperation = "Creating ISO file"
            Write-Host "Creating custom ISO: $OutputPath" -ForegroundColor Cyan
            try {
                New-CustomISO -WorkspacePath $workspacePath -OutputPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
                Write-Verbose "ISO creation completed"
                if (-not (Test-Path -Path $OutputPath)) {
                    throw "ISO file was not created at $OutputPath"
                }
            }
            catch {
                $errorCollection += "Error creating ISO file: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            
            # Generate a summary
            $currentOperation = "Generating summary"
            try {
                Show-Summary -WindowsImage $WimPath -ISOPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
            }
            catch {
                $errorCollection += "Error generating summary: $_"
                Write-Warning "Could not generate summary: $_"
            }
            
            Write-Host "✅ ISO created successfully at: $OutputPath" -ForegroundColor Green
        }
        catch {
            Write-Error "An error occurred during '$currentOperation': $_"
            throw $_
        }
        finally {
            if (-not $SkipCleanup) {
                try {
                    if (Test-Path $TempPath) {
                        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Verbose "Cleaned up temporary files at $TempPath"
                    }
                }
                catch {
                    Write-Warning "Cleanup failed: $_"
                }
            }
        }
    }
}