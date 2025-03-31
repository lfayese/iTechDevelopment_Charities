<#
.SYNOPSIS
    Updates a WinPE image with PowerShell 7 support.
.DESCRIPTION
    This function updates a WinPE image by adding PowerShell 7 support, configuring startup settings,
    and updating environment variables. It handles the entire process of mounting the WIM file,
    making modifications, and dismounting with changes saved.
.PARAMETER TempPath
    The temporary path where working files will be stored.
.PARAMETER WorkspacePath
    The workspace path containing the WinPE image to update.
.PARAMETER PowerShellVersion
    The PowerShell version to install. Default is "7.3.4".
.PARAMETER PowerShell7File
    The path to the PowerShell 7 zip file. If not specified, it will be downloaded.
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4"
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip"
.NOTES
    This function requires administrator privileges and the Windows ADK installed.
#>
function Update-WinPEWithPowerShell7 {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspacePath,
        
        [Parameter()]
        [ValidatePattern('^(\d+\.\d+\.\d+)$')]
        [string]$PowerShellVersion = "7.3.4",
        
        [Parameter()]
        [ValidateScript({
            if ([string]::IsNullOrEmpty($_)) { return $true }
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "The PowerShell 7 file '$_' does not exist or is not a file."
            }
            if (-not ($_ -match '\.zip$')) {
                throw "The file '$_' is not a ZIP file."
            }
            return $true
        })]
        [string]$PowerShell7File
    )
    
    begin {
        # Generate a unique ID for this execution instance
        $instanceId = [Guid]::NewGuid().ToString()
        
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Starting WinPE update with PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
        }
        
        # If PowerShell7File is not specified, download it
        if ([string]::IsNullOrEmpty($PowerShell7File)) {
            try {
                if (Get-Command -Name Get-PowerShell7Package -ErrorAction SilentlyContinue) {
                    $PowerShell7File = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $TempPath
                    
                    if (-not $PowerShell7File -or -not (Test-Path $PowerShell7File)) {
                        throw "Failed to download PowerShell 7 package"
                    }
                }
                else {
                    # Fallback to direct download if Get-PowerShell7Package is not available
                    $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$PowerShellVersion/PowerShell-$PowerShellVersion-win-x64.zip"
                    $PowerShell7File = Join-Path -Path $TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
                    
                    if (-not (Test-Path $PowerShell7File)) {
                        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                            Invoke-OSDCloudLogger -Message "Downloading PowerShell 7 v$PowerShellVersion from $downloadUrl" -Level Info -Component "Update-WinPEWithPowerShell7"
                        }
                        
                        # Create directory if it doesn't exist
                        if (-not (Test-Path -Path $TempPath)) {
                            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
                        }
                        
                        # Download the file
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $PowerShell7File -UseBasicParsing
                    }
                }
            }
            catch {
                $errorMessage = "Failed to download PowerShell 7 package: $_"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                }
                else {
                    Write-Error $errorMessage
                }
                throw
            }
        }
        
        # Verify PowerShell 7 file exists
        if (-not (Test-Path -Path $PowerShell7File)) {
            $errorMessage = "PowerShell 7 file not found at path: $PowerShell7File"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7"
            }
            else {
                Write-Error $errorMessage
            }
            throw $errorMessage
        }
    }
    
    process {
        $mountInfo = $null
        
        try {
            # Step 1: Initialize mount point and temporary directories
            $mountInfo = Initialize-WinPEMountPoint -TempPath $TempPath -InstanceId $instanceId
            $uniqueMountPoint = $mountInfo.MountPoint
            $ps7TempPath = $mountInfo.PS7TempPath
            
            # Step 2: Create startup profile directory
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Create startup profile directory")) {
                New-WinPEStartupProfile -MountPoint $uniqueMountPoint
            }
            
            # Step 3: Mount WinPE Image
            $wimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
            if (-not (Test-Path -Path $wimPath)) {
                $errorMessage = "WinPE image not found at path: $wimPath"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7"
                }
                else {
                    Write-Error $errorMessage
                }
                throw $errorMessage
            }
            
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Mount image for customization")) {
                Mount-WinPEImage -ImagePath $wimPath -MountPath $uniqueMountPoint
            }
            
            # Step 4: Install PowerShell 7
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Install PowerShell 7")) {
                Install-PowerShell7ToWinPE -PowerShell7File $PowerShell7File -TempPath $ps7TempPath -MountPoint $uniqueMountPoint
            }
            
            # Step 5: Update registry
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Update registry settings")) {
                Update-WinPERegistry -MountPoint $uniqueMountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 6: Update startup configuration
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Update startup configuration")) {
                Update-WinPEStartup -MountPoint $uniqueMountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 7: Dismount WinPE Image
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Dismount image and save changes")) {
                Dismount-WinPEImage -MountPath $uniqueMountPoint -Save
            }
            
            # Log success
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "WinPE update with PowerShell 7 completed successfully" -Level Info -Component "Update-WinPEWithPowerShell7"
            }
            
            # Return the boot.wim path
            return $wimPath
        }
        catch {
            $errorMessage = "Failed to update WinPE: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            
            # Try to dismount if mounted (don't save changes)
            try {
                if ($mountInfo -and (Test-Path -Path $mountInfo.MountPoint)) {
                    if ($PSCmdlet.ShouldProcess("WinPE Image", "Dismount image and discard changes due to error")) {
                        Dismount-WinPEImage -MountPath $mountInfo.MountPoint -Discard
                    }
                }
            }
            catch {
                $cleanupError = "Error during cleanup: $_"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                }
                else {
                    Write-Warning $cleanupError
                }
            }
            
            throw
        }
        finally {
            # Clean up temporary resources
            try {
                if ($mountInfo) {
                    # Clean up mount point
                    if (Test-Path -Path $mountInfo.MountPoint) {
                        Remove-Item -Path $mountInfo.MountPoint -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                    # Clean up PowerShell 7 temp path
                    if (Test-Path -Path $mountInfo.PS7TempPath) {
                        Remove-Item -Path $mountInfo.PS7TempPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                $cleanupError = "Error cleaning up temporary resources: $_"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                }
                else {
                    Write-Warning $cleanupError
                }
            }
        }
    }
}

# Add an alias for backward compatibility
New-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7 -Description "Backward compatibility alias" -Force

# Export both the function and the alias
Export-ModuleMember -Function Update-WinPEWithPowerShell7 -Alias Customize-WinPEWithPowerShell7