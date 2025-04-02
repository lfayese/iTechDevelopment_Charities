<#
.SYNOPSIS
    Provides validation helper functions for the OSDCloudCustomBuilder module.
.DESCRIPTION
    Contains standardized validation functions for paths, admin privileges, 
    network connectivity, and other common checks used throughout the module.
.NOTES
    Version: 0.3.0
    Author: OSDCloud Team
#>

<#
.SYNOPSIS
    Validates if the current user has administrator privileges.
.DESCRIPTION
    Checks if the current PowerShell session is running with elevated privileges.
.EXAMPLE
    if (-not (Test-IsAdmin)) {
        Write-Error "This operation requires administrator privileges."
        return
    }
#>
function Test-IsAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Validates if a path is valid and optionally if it exists.
.DESCRIPTION
    Checks if a given path is in a valid format and, if specified, verifies
    that it actually exists. Can create the path if needed.
.PARAMETER Path
    The file or directory path to validate.
.PARAMETER MustExist
    If specified, the path must exist to be considered valid.
.PARAMETER CreateIfNotExist
    If specified and the path doesn't exist, attempts to create it.
.PARAMETER IsFile
    If specified, validates that the path exists and is a file.
.PARAMETER IsDirectory
    If specified, validates that the path exists and is a directory.
.EXAMPLE
    if (-not (Test-ValidPath -Path $filePath -MustExist)) {
        throw "The specified file does not exist: $filePath"
    }
.EXAMPLE
    Test-ValidPath -Path $dirPath -MustExist -CreateIfNotExist
#>
function Test-ValidPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        
        [Parameter()]
        [switch]$MustExist,
        
        [Parameter()]
        [switch]$CreateIfNotExist,
        
        [Parameter()]
        [switch]$IsFile,
        
        [Parameter()]
        [switch]$IsDirectory
    )
    
    # Check for invalid characters in the path
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    $invalidCharsFound = $false
    
    foreach ($char in $invalidChars) {
        if ($Path.Contains($char)) {
            $invalidCharsFound = $true
            break
        }
    }
    
    # Also check for other problematic characters/patterns
    if ($Path -match '[<>"|?*]') {
        $invalidCharsFound = $true
    }
    
    # Return false if invalid characters were found
    if ($invalidCharsFound) {
        return $false
    }
    
    # If MustExist is specified, check existence
    if ($MustExist) {
        $exists = Test-Path -Path $Path
        
        # If it doesn't exist but CreateIfNotExist is specified, try to create it
        if (-not $exists -and $CreateIfNotExist) {
            # Determine if we're creating a file or directory
            try {
                if ($IsFile) {
                    # Ensure parent directory exists
                    $parent = Split-Path -Path $Path -Parent
                    if (-not (Test-Path -Path $parent)) {
                        New-Item -Path $parent -ItemType Directory -Force | Out-Null
                    }
                    
                    # Create empty file
                    New-Item -Path $Path -ItemType File -Force | Out-Null
                }
                else {
                    # Default to creating a directory
                    New-Item -Path $Path -ItemType Directory -Force | Out-Null
                }
                
                $exists = Test-Path -Path $Path
            }
            catch {
                return $false
            }
        }
        
        # If the path still doesn't exist, return false
        if (-not $exists) {
            return $false
        }
        
        # If path exists, check if it's the correct type (file or directory)
        if ($IsFile -or $IsDirectory) {
            $item = Get-Item -Path $Path
            
            if ($IsFile -and -not $item.PSIsContainer) {
                return $true
            }
            
            if ($IsDirectory -and $item.PSIsContainer) {
                return $true
            }
            
            # Not the requested type
            return $false
        }
    }
    
    # If we got this far, the path is syntactically valid and exists if required
    return $true
}

<#
.SYNOPSIS
    Validates network connectivity to a specified endpoint.
.DESCRIPTION
    Tests if the current system can reach a specified network endpoint.
    Useful for validating connectivity before attempting downloads.
.PARAMETER Uri
    The URI to test connectivity to.
.PARAMETER Timeout
    The timeout in milliseconds. Default is 5000 (5 seconds).
.EXAMPLE
    if (-not (Test-NetworkConnectivity -Uri "https://github.com")) {
        Write-Error "Unable to connect to GitHub. Check your internet connection."
        return
    }
#>
function Test-NetworkConnectivity {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter()]
        [int]$Timeout = 5000
    )
    
    try {
        # Extract hostname from URI
        $uriObj = [System.Uri]$Uri
        $hostname = $uriObj.Host
        
        # First, try a simple ping test
        $ping = New-Object System.Net.NetworkInformation.Ping
        $pingResult = $ping.Send($hostname, $Timeout)
        
        if ($pingResult.Status -eq 'Success') {
            return $true
        }
        
        # If ping fails, try an HTTP request as some servers block ICMP
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = "HEAD"
        $request.Timeout = $Timeout
        $request.AllowAutoRedirect = $true
        
        try {
            $response = $request.GetResponse()
            $response.Close()
            return $true
        }
        catch {
            # HTTP request failed
            return $false
        }
    }
    catch {
        # Something went wrong with the validation process
        return $false
    }
}

<#
.SYNOPSIS
    Validates if a WIM file is accessible and can be mounted.
.DESCRIPTION
    Tests if a WIM file exists, is accessible for reading/writing, and
    can potentially be mounted without actually mounting it.
.PARAMETER WimPath
    The path to the WIM file to validate.
.EXAMPLE
    if (-not (Test-WimFileAccessible -WimPath $wimPath)) {
        Write-Error "The WIM file is not accessible: $wimPath"
        return
    }
#>
function Test-WimFileAccessible {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$WimPath
    )
    
    # Check if file exists and is a valid path
    if (-not (Test-ValidPath -Path $WimPath -MustExist -IsFile)) {
        return $false
    }
    
    try {
        # Check if file can be opened for reading
        $fileStream = [System.IO.File]::Open($WimPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $fileStream.Close()
        $fileStream.Dispose()
        
        # Check if it has the WIM file header
        $bytes = New-Object byte[] 8
        $fileStream = [System.IO.File]::Open($WimPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $fileStream.Read($bytes, 0, 8) | Out-Null
        $fileStream.Close()
        $fileStream.Dispose()
        
        # Check for WIM header - MSWIM\0\0
        $expectedHeader = [byte[]]@(77, 83, 87, 73, 77, 0, 0, 0)
        $isWimFile = $true
        
        for ($i = 0; $i -lt 8; $i++) {
            if ($bytes[$i] -ne $expectedHeader[$i]) {
                $isWimFile = $false
                break
            }
        }
        
        if (-not $isWimFile) {
            return $false
        }
        
        # Check DISM compatibility in a non-invasive way
        $dismInfo = Get-WindowsImage -ImagePath $WimPath -ErrorAction SilentlyContinue
        return ($null -ne $dismInfo)
    }
    catch {
        # Any exception means the file is not accessible or not a valid WIM
        return $false
    }
}

<#
.SYNOPSIS
    Validates if the PowerShell version is supported.
.DESCRIPTION
    Checks if the current PowerShell version meets the minimum requirements.
.PARAMETER MinimumVersion
    The minimum required PowerShell version.
.EXAMPLE
    if (-not (Test-PowerShellVersion -MinimumVersion "5.1")) {
        Write-Error "PowerShell 5.1 or higher is required."
        return
    }
#>
function Test-PowerShellVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MinimumVersion
    )
    
    try {
        $minimumRequired = [Version]$MinimumVersion
        $current = $PSVersionTable.PSVersion
        
        return ($current -ge $minimumRequired)
    }
    catch {
        # If parsing fails, assume the version check fails
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Test-IsAdmin, Test-ValidPath, Test-NetworkConnectivity, Test-WimFileAccessible, Test-PowerShellVersion