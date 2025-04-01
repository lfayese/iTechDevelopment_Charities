function Find-WinPEBootWim {
    <#
    .SYNOPSIS
        Locates and validates the boot.wim file in a WinPE workspace.
    .DESCRIPTION
        This function searches for the boot.wim file in the standard location within a WinPE workspace.
        It performs validation to ensure the file exists and is a valid Windows image file.
    .PARAMETER WorkspacePath
        The base path of the WinPE workspace where the boot.wim file should be located.
        The function will look for the file in the Media\Sources subdirectory.
    .EXAMPLE
        Find-WinPEBootWim -WorkspacePath "C:\OSDCloud\Workspace"
        # Locates and validates the boot.wim file in the specified workspace
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$WorkspacePath
    )
    
    try {
        # Define standard boot.wim path
        $bootWimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        
        Write-OSDCloudLog -Message "Searching for boot.wim at $bootWimPath" -Level Info -Component "Find-WinPEBootWim"
        
        # Check if file exists
        if (-not (Test-Path -Path $bootWimPath -PathType Leaf)) {
            # Try alternative locations
            $alternativePaths = @(
                (Join-Path -Path $WorkspacePath -ChildPath "Sources\boot.wim"),
                (Join-Path -Path $WorkspacePath -ChildPath "boot.wim")
            )
            
            foreach ($altPath in $alternativePaths) {
                if (Test-Path -Path $altPath -PathType Leaf) {
                    Write-OSDCloudLog -Message "Found boot.wim at alternative location: $altPath" -Level Info -Component "Find-WinPEBootWim"
                    $bootWimPath = $altPath
                    break
                }
            }
            
            if (-not (Test-Path -Path $bootWimPath -PathType Leaf)) {
                throw "Boot.wim not found in workspace at: $bootWimPath or any alternative locations"
            }
        }
        
        # Validate that it's a Windows image file
        try {
            $wimInfo = Get-WindowsImage -ImagePath $bootWimPath -Index 1 -ErrorAction Stop
            Write-OSDCloudLog -Message "Validated boot.wim: $($wimInfo.ImageName) ($($wimInfo.Architecture))" -Level Info -Component "Find-WinPEBootWim"
        }
        catch {
            throw "File found at $bootWimPath is not a valid Windows image file: $_"
        }
        
        return $bootWimPath
    }
    catch {
        $errorMessage = "Failed to locate valid boot.wim: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Find-WinPEBootWim" -Exception $_.Exception
        throw
    }
}