function New-CustomOSDCloudISO {
    [CmdletBinding()]
    param (
        [string]$PwshVersion = "7.5.0",
        [switch]$SkipCleanup
    )

    Write-Verbose "Starting custom OSDCloud ISO build..."

    Initialize-OSDEnvironment
    Customize-WinPE -PwshVersion $PwshVersion
    Inject-Scripts
    Build-ISO
    if (-not $SkipCleanup) {
        Cleanup-Workspace
    }
}
