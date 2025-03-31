<#
.SYNOPSIS
    Creates an OSDCloud ISO with a custom Windows Image (WIM) file and PowerShell 7 support.
.DESCRIPTION
    This function creates a complete OSDCloud ISO with a custom Windows Image (WIM) file,
    PowerShell 7 support, and customizations. It handles the entire process from
    template creation to ISO generation. The function includes comprehensive error handling,
    logging support via Invoke-OSDCloudLogger, and WhatIf support for all major file operations.
    It validates input parameters thoroughly and provides detailed feedback throughout the process.
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
.PARAMETER TimeoutMinutes
    Maximum time in minutes to wait for the operation to complete. Default is 60 minutes.
.PARAMETER MaxThreads
    Maximum number of threads to use for parallel operations. Default is 4.
.EXAMPLE
    Update-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
.EXAMPLE
    Update-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"
.EXAMPLE
    Update-CustomWimWithPwsh7 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -IncludeWinRE
.NOTES
    Requires administrator privileges and Windows ADK installed.
#>
function Update-CustomWimWithPwsh7 {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "The WIM file '$_' does not exist or is not a file."
            }
            if (-not ($_ -match '\.wim$')) {
                throw "The file '$_' is not a WIM file."
            }
            if ((Get-Item $_).Length -eq 0) {
                throw "The WIM file '$_' is empty."
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
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$PowerShellVersion = "7.3.4",
        
        [Parameter()]
        [switch]$IncludeWinRE,
        
        [Parameter()]
        [switch]$SkipCleanup,
        
        [Parameter()]
        [int]$TimeoutMinutes = 60,
        
        [Parameter()]
        [int]$MaxThreads = 4
    )
    
    begin {
        $errorCollection = @()
        $operationTimeout = (Get-Date).AddMinutes($TimeoutMinutes)
        
        # Get module configuration
        $config = Get-ModuleConfiguration
        
        # Log operation start
        Write-OSDCloudLog -Message "TLS 1.2 enforced for secure communications" -Level Info -Component "Update-CustomWimWithPwsh7"
        Write-OSDCloudLog -Message "Starting OSDCloud ISO creation with custom WIM and PowerShell $PowerShellVersion" -Level Info -Component "Update-CustomWimWithPwsh7"
        
        # Check for administrator privileges once
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                $errorMessage = "This function requires administrator privileges to run properly."
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }
        }
        catch {
            $errorMessage = "Failed to check administrator privileges: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
            throw "Administrator privilege check failed. Please run as administrator."
        }
        
        # Enforce TLS 1.2
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-OSDCloudLog -Message "TLS 1.2 enforced for secure communications" -Level Info -Component "Update-CustomWimWithPwsh7"
        }
        catch {
            $errorMessage = "Failed to enforce TLS 1.2: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
            throw $errorMessage
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
                $errorMessage = "Insufficient disk space. Need at least $(($requiredSpace / 1GB).ToString('N2')) GB, but only $(($freeSpace / 1GB).ToString('N2')) GB available on drive $tempDrive."
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }
            Write-OSDCloudLog -Message "Sufficient disk space available: $(($freeSpace / 1GB).ToString('N2')) GB" -Level Info -Component "Update-CustomWimWithPwsh7"
        }
        catch {
            $warningMessage = "Disk space check failed: $_"
            Write-OSDCloudLog -Message $warningMessage -Level Warning -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
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
                    Write-OSDCloudLog -Message "Creating directory: $dir" -Level Info -Component "Update-CustomWimWithPwsh7"
                    New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
            }
        }
        catch {
            $errorMessage = "Failed to create required directories: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
            throw "Directory creation failed: $_"
        }
        
        # Check if ThreadJob module is available and try to import if needed
        $useThreadJobs = $false
        try {
            if (-not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
                if (Get-Module -Name ThreadJob -ListAvailable) {
                    Import-Module -Name ThreadJob -ErrorAction Stop
                    $useThreadJobs = $true
                    Write-OSDCloudLog -Message "Successfully imported ThreadJob module" -Level Info -Component "Update-CustomWimWithPwsh7"
                } else {
                    Write-OSDCloudLog -Message "ThreadJob module not available, falling back to standard Jobs" -Level Info -Component "Update-CustomWimWithPwsh7"
                }
            } else {
                $useThreadJobs = $true
                Write-OSDCloudLog -Message "Using existing ThreadJob module" -Level Info -Component "Update-CustomWimWithPwsh7"
            }
        } catch {
            $warningMessage = "Could not import ThreadJob module: $_. Using standard Jobs instead."
            Write-OSDCloudLog -Message $warningMessage -Level Warning -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
            Write-Warning $warningMessage
        }
    }
    
    process {
        try {
            Write-OSDCloudLog -Message "Starting OSDCloud ISO creation process" -Level Info -Component "Update-CustomWimWithPwsh7"
            
            if ((Get-Date) -gt $operationTimeout) {
                $errorMessage = "Operation timed out before completion."
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }
            
            # Verify PowerShell 7 package availability
            $currentOperation = "Verifying PowerShell 7 package"
            Write-Host "Verifying PowerShell 7 package availability..." -ForegroundColor Cyan
            
            # Check if we have a cached package
            $ps7PackagePath = $null
            $cachedPackage = Get-CachedPowerShellPackage -Version $PowerShellVersion
            
            if ($cachedPackage) {
                $ps7PackagePath = $cachedPackage
                Write-OSDCloudLog -Message "Using cached PowerShell 7 package: $ps7PackagePath" -Level Info -Component "Update-CustomWimWithPwsh7"
            }
            else {
                # Download PowerShell 7 package
                $ps7PackagePath = Join-Path -Path $tempWorkspacePath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
                Write-OSDCloudLog -Message "Downloading PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-CustomWimWithPwsh7"
                
                try {
                    $ps7PackagePath = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $ps7PackagePath
                }
                catch {
                    $errorMessage = "Failed to download PowerShell 7 package: $_"
                    Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                    throw $errorMessage
                }
            }
            
            # Copy the WIM file to the workspace
            $currentOperation = "Copying WIM file"
            Write-Host "Copying custom WIM to workspace..." -ForegroundColor Cyan
            
            try {
                if ($PSCmdlet.ShouldProcess("Copy WIM file to workspace", "Copy-CustomWimToWorkspace")) {
                    Write-OSDCloudLog -Message "Copying WIM file from $WimPath to workspace" -Level Info -Component "Update-CustomWimWithPwsh7"
                    Copy-CustomWimToWorkspace -WimPath $WimPath -WorkspacePath $workspacePath -UseRobocopy -ErrorAction Stop
                    Write-OSDCloudLog -Message "WIM file copied successfully" -Level Info -Component "Update-CustomWimWithPwsh7"
                }
            }
            catch {
                $errorMessage = "Error copying WIM file: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                throw "Failed during operation '$currentOperation': $_"
            }
            
            # Define script blocks for background tasks
            $ps7CustomizationScript = {
                param($tempPath, $workspacePath, $psVersion, $ps7PackagePath)
                try {
                    # Import required modules and functions
                    $modulePath = Join-Path -Path (Split-Path -Path $workspacePath -Parent) -ChildPath "..\OSDCloudCustomBuilder.psm1"
                    Import-Module $modulePath -Force -ErrorAction Stop
                    
                    # Use the PS7 package we already verified/downloaded
                    Update-WinPEWithPowerShell7 -TempPath $tempPath -WorkspacePath $workspacePath -PowerShellVersion $psVersion -PowerShell7File $ps7PackagePath -ErrorAction Stop
                    return @{ Success = $true; Message = "PowerShell 7 customization completed successfully" }
                }
                catch {
                    return @{ Success = $false; Message = "PowerShell 7 customization failed: $_" }
                }
            }
            
            $isoOptimizationScript = {
                param($workspacePath)
                try {
                    # Import required modules and functions
                    $modulePath = Join-Path -Path (Split-Path -Path $workspacePath -Parent) -ChildPath "..\OSDCloudCustomBuilder.psm1"
                    Import-Module $modulePath -Force -ErrorAction Stop
                    
                    Optimize-ISOSize -WorkspacePath $workspacePath -ErrorAction Stop
                    return @{ Success = $true; Message = "ISO size optimization completed successfully" }
                }
                catch {
                    return @{ Success = $false; Message = "ISO size optimization failed: $_" }
                }
            }
            
            # Start jobs using appropriate method based on module availability
            $jobs = @()
            $currentOperation = "Adding PowerShell 7 and Optimizing ISO Size"
            Write-Host "Starting background tasks..." -ForegroundColor Cyan
            Write-OSDCloudLog -Message "Starting background tasks for PowerShell 7 integration and ISO optimization" -Level Info -Component "Update-CustomWimWithPwsh7"

            if ($useThreadJobs) {
                Write-OSDCloudLog -Message "Using ThreadJob for parallel processing" -Level Info -Component "Update-CustomWimWithPwsh7"
                try {
                    $jobs += Start-ThreadJob -ScriptBlock $ps7CustomizationScript -ArgumentList $tempWorkspacePath, $workspacePath, $PowerShellVersion, $ps7PackagePath
                    $jobs += Start-ThreadJob -ScriptBlock $isoOptimizationScript -ArgumentList $workspacePath
                }
                catch {
                    $warningMessage = "Error starting ThreadJob: $_. Falling back to standard Jobs."
                    Write-OSDCloudLog -Message $warningMessage -Level Warning -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                    Write-Warning $warningMessage
                    $useThreadJobs = $false
                }
            }

            # If ThreadJobs aren't available or failed, use standard jobs
            if (-not $useThreadJobs -or $jobs.Count -eq 0) {
                Write-OSDCloudLog -Message "Using standard Jobs for parallel processing" -Level Info -Component "Update-CustomWimWithPwsh7"
                try {
                    $jobs += Start-Job -ScriptBlock $ps7CustomizationScript -ArgumentList $tempWorkspacePath, $workspacePath, $PowerShellVersion, $ps7PackagePath
                    $jobs += Start-Job -ScriptBlock $isoOptimizationScript -ArgumentList $workspacePath
                }
                catch {
                    $errorMessage = "Failed to create background jobs: $_"
                    Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                    throw $errorMessage
                }
            }

            $currentOperation = "Processing background jobs"
            $jobTimeoutSeconds = $config.Timeouts.Job
            Write-OSDCloudLog -Message "Waiting for background jobs to complete (timeout: $jobTimeoutSeconds seconds)" -Level Info -Component "Update-CustomWimWithPwsh7"

            # Ensure we have jobs to process before waiting
            if ($jobs.Count -eq 0) {
                $errorMessage = "No background jobs were created successfully."
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }

            if (-not (Wait-Job -Job $jobs -Timeout $jobTimeoutSeconds)) {
                $errorMessage = "Background jobs timed out after $($jobTimeoutSeconds / 60) minutes."
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }

            foreach ($job in $jobs) {
                $result = Receive-Job -Job $job
                if ($null -eq $result) {
                    $errorMsg = "Job $($job.Id) returned null result"
                    $errorCollection += $errorMsg
                    Write-OSDCloudLog -Message $errorMsg -Level Error -Component "Update-CustomWimWithPwsh7"
                }
                elseif (-not $result.Success) {
                    $errorCollection += $result.Message
                    Write-OSDCloudLog -Message $result.Message -Level Error -Component "Update-CustomWimWithPwsh7"
                }
                else {
                    Write-OSDCloudLog -Message $result.Message -Level Info -Component "Update-CustomWimWithPwsh7"
                }
            }

            # Clean up jobs
            Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
            
            if ($errorCollection.Count -gt 0) {
                $errorMessage = "One or more background tasks failed: $($errorCollection -join ', ')"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                throw $errorMessage
            }
            
            # Create the ISO file
            $currentOperation = "Creating ISO file"
            Write-Host "Creating custom ISO: $OutputPath" -ForegroundColor Cyan
            Write-OSDCloudLog -Message "Creating ISO file at $OutputPath" -Level Info -Component "Update-CustomWimWithPwsh7"
            
            try {
                New-CustomISO -WorkspacePath $workspacePath -OutputPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
                
                if (-not (Test-Path -Path $OutputPath)) {
                    $errorMessage = "ISO file was not created at $OutputPath"
                    Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7"
                    throw $errorMessage
                }
                
                Write-OSDCloudLog -Message "ISO creation completed successfully" -Level Info -Component "Update-CustomWimWithPwsh7"
            }
            catch {
                $errorMessage = "Error creating ISO file: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                throw "Failed during operation '$currentOperation': $_"
            }
            
            # Generate a summary
            $currentOperation = "Generating summary"
            try {
                Show-Summary -WindowsImage $WimPath -ISOPath $OutputPath -IncludeWinRE:$IncludeWinRE -ErrorAction Stop
                Write-OSDCloudLog -Message "Summary generated successfully" -Level Info -Component "Update-CustomWimWithPwsh7"
            }
            catch {
                $warningMessage = "Error generating summary: $_"
                Write-OSDCloudLog -Message $warningMessage -Level Warning -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                Write-Warning "Could not generate summary: $_"
            }
            
            Write-Host "✅ ISO created successfully at: $OutputPath" -ForegroundColor Green
            Write-OSDCloudLog -Message "ISO created successfully at: $OutputPath" -Level Info -Component "Update-CustomWimWithPwsh7"
            
            # Force garbage collection to free up memory
            [System.GC]::Collect()
        }
        catch {
            $errorMessage = "An error occurred during '$currentOperation': $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
            Write-Error $errorMessage
            throw $_
        }
        finally {
            # Clean up temporary files unless skipping cleanup.
            if (-not $SkipCleanup) {
                try {
                    if (Test-Path $TempPath) {
                        Write-OSDCloudLog -Message "Cleaning up temporary files at $TempPath" -Level Info -Component "Update-CustomWimWithPwsh7"
                        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    $warningMessage = "Cleanup failed: $_"
                    Write-OSDCloudLog -Message $warningMessage -Level Warning -Component "Update-CustomWimWithPwsh7" -Exception $_.Exception
                    Write-Warning $warningMessage
                }
            }
            else {
                Write-OSDCloudLog -Message "Skipping cleanup as requested" -Level Info -Component "Update-CustomWimWithPwsh7"
            }
        }
    }
}

# Add an alias for backward compatibility
New-Alias -Name Add-CustomWimWithPwsh7 -Value Update-CustomWimWithPwsh7 -Description "Backward compatibility alias" -Force

# Export both the function and the alias
Export-ModuleMember -Function Update-CustomWimWithPwsh7 -Alias Add-CustomWimWithPwsh7