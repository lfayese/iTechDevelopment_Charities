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
    param (
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
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ISOFileName = "OSDCloudCustomWIM.iso",
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath = "$env:TEMP\OSDCloudCustomBuilder",
        [Parameter(Mandatory = $false)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$PowerShellVersion = "7.3.4",
        [Parameter(Mandatory = $false)]
        [switch]$IncludeWinRE,
        [Parameter(Mandatory = $false)]
        [switch]$SkipCleanup,
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 60
    )
    begin {
        $errorCollection = @()
        $operationTimeout = (Get-Date).AddMinutes($TimeoutMinutes)
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "This function requires administrator privileges to run properly."
            }
        } catch {
            Write-Error "Failed to check administrator privileges: $_"
            throw "Administrator privilege check failed. Please run as administrator."
        }
        try {
            $drive = (Split-Path -Path $TempPath -Qualifier) + '\'
            $freeSpace = (Get-PSDrive -Name $drive[0] -ErrorAction Stop).Free
            $requiredSpace = 15GB
            if ($freeSpace -lt $requiredSpace) {
                throw "Insufficient disk space. Need at least $(($requiredSpace/1GB).ToString('N2')) GB, but only $(($freeSpace/1GB).ToString('N2')) GB available on $drive."
            }
            Write-Verbose "Sufficient disk space available: $(($freeSpace/1GB).ToString('N2')) GB"
        } catch {
            $errorCollection += "Disk space check failed: $_"
            Write-Warning "Could not verify disk space. Proceeding anyway, but may encounter space issues."
        }
        $workspacePath = Join-Path -Path $TempPath -ChildPath "Workspace"
        $tempWorkspacePath = Join-Path -Path $TempPath -ChildPath "TempWorkspace"
        if (-not $OutputPath.EndsWith(".iso")) {
            $OutputPath = Join-Path -Path $OutputPath -ChildPath $ISOFileName
        }
        $outputDirectory = Split-Path -Path $OutputPath -Parent
        try {
            $dirsToCreate = @(
                $workspacePath,
                $tempWorkspacePath,
                $outputDirectory
            ) | Where-Object { -not (Test-Path $_) }
            if ($dirsToCreate.Count -gt 0) {
                $dirsToCreate | ForEach-Object {
                    Write-Verbose "Creating directory: $_"
                    New-Item -Path $_ -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
            }
        } catch {
            $errorCollection += "Failed to create required directories: $_"
            throw "Directory creation failed: $_"
        }
    }
    process {
        $jobs = @()
        try {
            Write-Verbose "Starting OSDCloud ISO creation process"
            if ((Get-Date) -gt $operationTimeout) {
                throw "Operation timed out before completion."
            }
            $currentOperation = "Copying WIM file"
            try {
                Write-Host "Copying custom WIM to workspace..." -ForegroundColor Cyan
                Copy-CustomWimToWorkspace -WimPath $WimPath -WorkspacePath $workspacePath -UseRobocopy -ErrorAction Stop
                Write-Verbose "WIM file copied successfully"
            } catch {
                $errorCollection += "Error copying WIM file: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            $currentOperation = "Preparing parallel tasks"
            try {
                $currentOperation = "Adding PowerShell 7"
                Write-Host "Adding PowerShell $PowerShellVersion support to WinPE..." -ForegroundColor Cyan
                $jobs += Start-Job -ScriptBlock {
                    param($tempPath, $workspacePath, $psVersion)
                    try {
                        Customize-WinPEWithPowerShell7 -TempPath $tempPath -WorkspacePath $workspacePath -PowerShellVersion $psVersion -ErrorAction Stop
                        return @{ Success = $true; Message = "PowerShell 7 customization completed successfully" }
                    } catch {
                        return @{ Success = $false; Message = "PowerShell 7 customization failed: $_" }
                    }
                } -ArgumentList $tempWorkspacePath, $workspacePath, $PowerShellVersion
                $currentOperation = "Optimizing ISO size"
                Write-Host "Optimizing ISO size..." -ForegroundColor Cyan
                $jobs += Start-Job -ScriptBlock {
                    param($workspacePath)
                    try {
                        Optimize-ISOSize -WorkspacePath $workspacePath -ErrorAction Stop
                        return @{ Success = $true; Message = "ISO size optimization completed successfully" }
                    } catch {
                        return @{ Success = $false; Message = "ISO size optimization failed: $_" }
                    }
                } -ArgumentList $workspacePath
            } catch {
                $errorCollection += "Error starting background jobs: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            $currentOperation = "Processing background jobs"
            try {
                # Use Wait-Job to efficiently wait for job completion with a timeout
                $jobTimeoutSeconds = 20 * 60
                if (-not (Wait-Job -Job $jobs -Timeout $jobTimeoutSeconds)) {
                    throw "Background jobs timed out after 20 minutes."
                }
                $jobResults = $jobs | ForEach-Object {
                    $result = Receive-Job -Job $_
                    if (-not $result.Success) {
                        $errorCollection += $result.Message
                    }
                    $result
                }
                $failedJobs = $jobResults | Where-Object { $_.Success -eq $false }
                if ($failedJobs) {
                    throw "One or more background tasks failed: $($failedJobs.Message -join ', ')"
                }
                $jobs | Remove-Job -Force
            } catch {
                $jobs | Where-Object { $_ } | Remove-Job -Force -ErrorAction SilentlyContinue
                $errorCollection += "Error processing background jobs: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            $currentOperation = "Creating ISO file"
            try {
                Write-Host "Creating custom ISO: $OutputPath" -ForegroundColor Cyan
                New-CustomISO -WorkspacePath $workspacePath -OutputPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
                Write-Verbose "ISO creation completed"
                if (-not (Test-Path -Path $OutputPath)) {
                    throw "ISO file was not created at $OutputPath"
                }
            } catch {
                $errorCollection += "Error creating ISO file: $_"
                throw "Failed during operation '$currentOperation': $_"
            }
            $currentOperation = "Generating summary"
            try {
                Show-Summary -WindowsImage $WimPath -ISOPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
            } catch {
                $errorCollection += "Error generating summary: $_"
                Write-Warning "Could not generate summary: $_"
            }
            Write-Host "✅ ISO created successfully at: $OutputPath" -ForegroundColor Green
        } catch {
            $mainError = $_
            Write-Error "An error occurred during '$currentOperation': $_"
            if ($errorCollection.Count -gt 0) {
                Write-Host "Error details:" -ForegroundColor Red
                $errorCollection | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            }
            throw $mainError
        } finally {
            if (-not $SkipCleanup) {
                Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
                try {
                    @($tempWorkspacePath, $workspacePath) | 
                    Where-Object { Test-Path -Path $_ } |
                    ForEach-Object {
                        Write-Verbose "Removing directory: $_"
                        Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
                        if (Test-Path -Path $_) {
                            Write-Warning "Could not completely remove directory: $_"
                        }
                    }
                    Write-Host "Temporary files cleaned up" -ForegroundColor Green
                } catch {
                    Write-Warning "Error during cleanup: $_"
                }
            } else {
                Write-Host "Skipping cleanup as requested" -ForegroundColor Yellow
                Write-Host "Temporary files remain at: $TempPath" -ForegroundColor Yellow
            }
            if ($jobs.Count -gt 0) {
                try {
                    $jobs | Where-Object { $_ -and $_.State -ne 'Completed' } | 
                    ForEach-Object {
                        Stop-Job -Job $_ -ErrorAction SilentlyContinue
                        Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Warning "Error cleaning up background jobs: $_"
                }
            }
            # Removed [System.GC]::Collect() to avoid unnecessary forced garbage collection
        }
    }
    end {
        if ($errorCollection.Count -gt 0) {
            Write-Warning "Completed with $($errorCollection.Count) warning(s)/error(s)"
        }
    }
}