function Show-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$WindowsImage,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ISOPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeWinRE
    )
    
    try {
        # Get Windows image information
        $wimInfo = Get-WindowsImage -ImagePath $WindowsImage -Index 1 -ErrorAction Stop
        $imageName = $wimInfo.ImageName ?? "Custom Windows Image"
        
        Write-Host "SUMMARY:" -ForegroundColor Yellow
        Write-Host "=========" -ForegroundColor Yellow
        Write-Host "Custom Windows Image: $imageName" -ForegroundColor White
        Write-Host "ISO File: $ISOPath" -ForegroundColor White
        
        # Check if ISO exists and has write permissions
        if (Test-Path $ISOPath) {
            try {
                $isoSize = [math]::Round((Get-Item $ISOPath -ErrorAction Stop).Length / 1GB, 2)
                Write-Host "ISO Size: $isoSize GB" -ForegroundColor White
            }
            catch {
                Write-Warning "Unable to access ISO file: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "ISO File not found at path: $ISOPath"
        }
        
        Write-Host "The ISO includes:" -ForegroundColor Yellow
        Write-Host "- Custom Windows Image (custom.wim)" -ForegroundColor White
        Write-Host "- PowerShell 7 support" -ForegroundColor White
        Write-Host "- OSDCloud customizations" -ForegroundColor White
        if ($IncludeWinRE) {
            Write-Host "- WinRE for WiFi support" -ForegroundColor White
        }
        
        Write-Host "To use this ISO:" -ForegroundColor Yellow
        Write-Host "1. Burn the ISO to a USB drive using Rufus or similar tool" -ForegroundColor White
        Write-Host "2. Boot the target computer from the USB drive" -ForegroundColor White
        Write-Host "3. The UI will automatically start with PowerShell 7" -ForegroundColor White
        Write-Host "4. Select 'Start-OSDCloud' to deploy the custom Windows image" -ForegroundColor White
    }
    catch {
        Write-Error "An error occurred while processing the Windows image: $($_.Exception.Message)"
    }
}