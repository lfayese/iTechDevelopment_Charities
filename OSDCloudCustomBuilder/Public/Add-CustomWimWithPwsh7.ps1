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
.PARAMETER PowerShell7Url
    The URL to download PowerShell 7 from. Default is the v7.5.0 release.
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
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory=$false)]
        [string]$ISOFileName = "OSDCloudCustomWIM.iso",
        
        [Parameter(Mandatory=$false)]
        [string]$PowerShell7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip",
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeWinRE,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipCleanup,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipAdminCheck
    )
    
    if (-not $SkipAdminCheck) {
        # Check for administrator privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            throw "This function requires administrator privileges to run."
        }
    }
    
    # Call the internal functions to perform the work
    Initialize-BuildEnvironment -OutputPath $OutputPath
    Test-WimFile -WimPath $WimPath
    $tempWorkspacePath = New-WorkspaceDirectory -OutputPath $OutputPath
    $PowerShell7File = Get-PowerShell7Package -PowerShell7Url $PowerShell7Url -TempPath $tempWorkspacePath
    $workspacePath = Initialize-OSDCloudTemplate -TempPath $tempWorkspacePath
    Copy-CustomWimToWorkspace -WimPath $WimPath -WorkspacePath $workspacePath
    Copy-CustomizationScripts -WorkspacePath $workspacePath -ScriptPath (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $bootWimPath = Customize-WinPEWithPowerShell7 -TempPath $tempWorkspacePath -WorkspacePath $workspacePath -PowerShell7File $PowerShell7File
    Optimize-ISOSize -WorkspacePath $workspacePath
    New-CustomISO -WorkspacePath $workspacePath -OutputPath $OutputPath -ISOFileName $ISOFileName -IncludeWinRE:$IncludeWinRE
    
    if (-not $SkipCleanup) {
        Remove-TempFiles -TempPath $tempWorkspacePath
    }
    
    Show-Summary -WimPath $WimPath -ISOPath (Join-Path $OutputPath $ISOFileName) -IncludeWinRE:$IncludeWinRE
}