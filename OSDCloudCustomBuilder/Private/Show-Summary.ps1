function Show-Summary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        
        [Parameter(Mandatory=$true)]
        [string]$ISOPath,
        
        [Parameter()]
        [switch]$IncludeWinRE
    )
    
    # Get WIM info
    $wimInfo = Get-WindowsImage -ImagePath $WimPath -Index 1
    
    Write-Host "`nSUMMARY:" -ForeColor Yellow
    Write-Host "=========" -ForeColor Yellow
    Write-Host "Custom Windows Image: $($wimInfo.ImageName)" -ForeColor White
    Write-Host "ISO File: $ISOPath" -ForeColor White
    Write-Host "ISO Size: $([math]::Round((Get-Item $ISOPath).Length / 1GB, 2)) GB" -ForeColor White
    Write-Host "`nThe ISO includes:" -ForeColor Yellow
    Write-Host "- Custom Windows Image (custom.wim)" -ForeColor White
    Write-Host "- PowerShell 7 support" -ForeColor White
    Write-Host "- OSDCloud customizations" -ForeColor White
    if ($IncludeWinRE) {
        Write-Host "- WinRE for WiFi support" -ForeColor White
    }
    
    Write-Host "`nTo use this ISO:" -ForeColor Yellow
    Write-Host "1. Burn the ISO to a USB drive using Rufus or similar tool" -ForeColor White
    Write-Host "2. Boot the target computer from the USB drive" -ForeColor White
    Write-Host "3. The UI will automatically start with PowerShell 7" -ForeColor White
    Write-Host "4. Select 'Start-OSDCloud' to deploy the custom Windows image" -ForeColor White
}