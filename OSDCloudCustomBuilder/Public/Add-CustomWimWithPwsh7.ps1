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
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$WimPath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$TempPath = "$env:TEMP\OSDCloudCustomBuilder",
        
        [Parameter(Mandatory = $false)]
        [string]$PowerShellVersion = "7.3.4",
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeWinRE
    )
    
    try {
        # Create a proper workspace path
        $workspacePath = Join-Path -Path $TempPath -ChildPath "Workspace"
        
        # Create the workspace directory if it doesn't exist
        if (-not (Test-Path -Path $workspacePath)) {
            New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null
        }
        
        # Get the script path
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = $PSScriptRoot
            if (-not $scriptPath) {
                throw "Unable to determine script path"
            }
        }
        
        # Create a temporary workspace
        $tempWorkspacePath = Join-Path -Path $TempPath -ChildPath "TempWorkspace"
        if (-not (Test-Path -Path $tempWorkspacePath)) {
            New-Item -Path $tempWorkspacePath -ItemType Directory -Force | Out-Null
        }
        
        # Ensure the output directory exists
        $outputDirectory = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDirectory)) {
            New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
        }
        
        # Copy the WIM file to the workspace
        Write-Host "Copying custom WIM to workspace..." -ForegroundColor Cyan
        Copy-CustomWimToWorkspace -WimPath $WimPath -WorkspacePath $workspacePath -ScriptPath $scriptPath
        
        # Customize WinPE with PowerShell 7
        Write-Host "Adding PowerShell 7 support to WinPE..." -ForegroundColor Cyan
        Customize-WinPEWithPowerShell7 -TempPath $tempWorkspacePath -WorkspacePath $workspacePath -PowerShellVersion $PowerShellVersion
        
        # Optimize ISO size
        Write-Host "Optimizing ISO size..." -ForegroundColor Cyan
        Optimize-ISOSize -WorkspacePath $workspacePath
        
        # Create the ISO
        Write-Host "Creating custom ISO..." -ForegroundColor Cyan
        New-CustomISO -WorkspacePath $workspacePath -OutputPath $OutputPath -IncludeWinRE:$IncludeWinRE
        
        # Clean up
        Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
        if (Test-Path -Path $tempWorkspacePath) {
            Remove-Item -Path $tempWorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Temporary files cleaned up" -ForegroundColor Green
        
        # Show summary
        Show-Summary -WindowsImage $WimPath -ISOPath $OutputPath -IncludeWinRE:$IncludeWinRE
    }
    catch {
        Write-Error "An error occurred: $_"
        throw
    }
}