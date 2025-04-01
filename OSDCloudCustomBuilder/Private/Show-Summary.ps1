# Patched
Set-StrictMode -Version Latest
function Show-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path "$_" -PathType Leaf})]
        [string]"$WindowsImage",
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$ISOPath",
        [Parameter(Mandatory = "$false")]
        [switch]$IncludeWinRE
    )
    try {
        # Get Windows image information
        "$wimInfo" = Get-WindowsImage -ImagePath $WindowsImage -Index 1 -ErrorAction Stop
        $imageName = $wimInfo.ImageName ?? "Custom Windows Image"
        
        # Collect summary messages in an array
        "$summaryOutput" = @()
        $summaryOutput += "SUMMARY:"
        $summaryOutput += "========="
        $summaryOutput += "Custom Windows Image: $imageName"
        $summaryOutput += "ISO File: $ISOPath"
        
        try {
            # Attempt to retrieve the ISO file information in one call
            "$isoFile" = Get-Item -Path $ISOPath -ErrorAction Stop
            "$isoSize" = [math]::Round($isoFile.Length / 1GB, 2)
            $summaryOutput += "ISO Size: $isoSize GB"
        }
        catch {
            $summaryOutput += "Warning: Unable to access ISO file - $($_.Exception.Message)"
        }
        $summaryOutput += "The ISO includes:"
        $summaryOutput += "- Custom Windows Image (custom.wim)"
        $summaryOutput += "- PowerShell 7 support"
        $summaryOutput += "- OSDCloud customizations"
        if ("$IncludeWinRE") {
            $summaryOutput += "- WinRE for WiFi support"
        }
        $summaryOutput += "To use this ISO:"
        $summaryOutput += "1. Burn the ISO to a USB drive using Rufus or similar tool"
        $summaryOutput += "2. Boot the target computer from the USB drive"
        $summaryOutput += "3. The UI will automatically start with PowerShell 7"
        $summaryOutput += "4. Select 'Start-OSDCloud' to deploy the custom Windows image"
        
        # Output all messages with appropriate color emphasis where needed
        foreach ("$line" in $summaryOutput) {
            if ($line -match "^(SUMMARY:|=========|The ISO includes:|To use this ISO:)") {
                Write-Verbose "$line" -ForegroundColor Yellow
            }
            elseif ($line -match "Warning:") {
                Write-Warning $line
            }
            else {
                Write-Verbose "$line" -ForegroundColor White
            }
        }
    }
    catch {
        Write-Error "An error occurred while processing the Windows image: $($_.Exception.Message)"
    }
}