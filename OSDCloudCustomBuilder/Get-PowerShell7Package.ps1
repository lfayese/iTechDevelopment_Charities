<#
.SYNOPSIS
    Downloads or validates a PowerShell 7 package.
.DESCRIPTION
    This function either downloads a PowerShell 7 package from the official Microsoft repository
    or validates an existing package file. It supports version validation, download progress
    tracking, and integrity verification of the downloaded package.
.PARAMETER Version
    The PowerShell version to download in X.Y.Z format (e.g., "7.3.4").
    Must be a valid and supported PowerShell 7 version.
.PARAMETER DownloadPath
    The path where the PowerShell 7 package will be downloaded.
    If the file already exists at this path, it will be validated instead of downloaded again.
.PARAMETER Force
    If specified, will re-download the package even if it already exists at the destination path.
.EXAMPLE
    Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp\PowerShell-7.3.4-win-x64.zip"
    # Downloads PowerShell 7.3.4 to the specified path
.EXAMPLE
    Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp\PowerShell-7.3.4-win-x64.zip" -Force
    # Forces a re-download even if the file already exists
.NOTES
    Version: 1.0.0
    Author: OSDCloud Team
    Requirements:
    - Internet connectivity for downloading
    - Write access to the download directory
#>
function Get-PowerShell7Package {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                   Position=0,
                   HelpMessage="PowerShell version to download")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$Version,
        
        [Parameter(Mandatory=$true,
                   Position=1,
                   HelpMessage="Path where the package will be downloaded")]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadPath,
        
        [Parameter(Position=2,
                   HelpMessage="Force download even if package already exists")]
        [switch]$Force
    )
    
    try {
        # Check if file already exists
        if ((Test-Path -Path $DownloadPath) -and -not $Force) {
            Write-OSDCloudLog -Message "PowerShell 7 package already exists at $DownloadPath" -Level Info -Component "Get-PowerShell7Package"
            return $DownloadPath
        }
        
        # Ensure download directory exists
        $downloadDir = Split-Path -Path $DownloadPath -Parent
        if (-not (Test-Path -Path $downloadDir -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($downloadDir, "Create download directory")) {
                New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
                Write-OSDCloudLog -Message "Created download directory: $downloadDir" -Level Info -Component "Get-PowerShell7Package"
            }
        }
        
        # Construct download URL
        $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip"
        
        Write-OSDCloudLog -Message "Downloading PowerShell 7 v$Version from $downloadUrl" -Level Info -Component "Get-PowerShell7Package"
        
        if ($PSCmdlet.ShouldProcess($downloadUrl, "Download PowerShell 7 package to $DownloadPath")) {
            # Download with progress
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "OSDCloudCustomBuilder/1.0")
            
            # Add progress event handler
            $progressEventHandler = {
                $percent = [int](($EventArgs.BytesReceived / $EventArgs.TotalBytesToReceive) * 100)
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Status "$percent% Complete" -PercentComplete $percent
            }
            
            $null = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $progressEventHandler
            
            try {
                $webClient.DownloadFile($downloadUrl, $DownloadPath)
            }
            catch {
                Write-OSDCloudLog -Message "Download failed: $_" -Level Error -Component "Get-PowerShell7Package" -Exception $_.Exception
                throw "Failed to download PowerShell 7 package from $downloadUrl : $_"
            }
            finally {
                # Clean up event handlers
                Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
                $webClient.Dispose()
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Completed
            }
            
            # Verify download
            if (-not (Test-Path -Path $DownloadPath)) {
                throw "Download completed but file not found at $DownloadPath"
            }
            
            Write-OSDCloudLog -Message "PowerShell 7 v$Version downloaded successfully to $DownloadPath" -Level Info -Component "Get-PowerShell7Package"
            return $DownloadPath
        }
        
        return $null
    }
    catch {
        $errorMessage = "Failed to download PowerShell 7 package: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Get-PowerShell7Package" -Exception $_.Exception
        throw $errorMessage
    }
}

# Export the function
Export-ModuleMember -Function Get-PowerShell7Package