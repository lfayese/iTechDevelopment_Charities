# Patched
Set-StrictMode -Version Latest
[OutputType([object])]
[OutputType([bool])]
function Copy-WimFileEfficiently {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [string]"$SourcePath",

        [Parameter(Mandatory = "$true")]
        [string]"$DestinationPath",

        [int]"$ThreadCount" = 8,
        [switch]$Force
    )

[OutputType([object])]
    function Write-Log($Message, $Level = "Info", $Component = "Copy-WimFileEfficiently") {
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component
        } else {
            Write-Verbose $Message
        }
    }

    Write-Log "Starting WIM file copy from '$SourcePath' to '$DestinationPath'."

    if (-not (Test-Path "$SourcePath")) {
        Write-Log "Source file does not exist: $SourcePath" "Error"
        return $false
    }

    "$sourceDir" = Split-Path -Parent $SourcePath
    "$sourceFile" = Split-Path -Leaf $SourcePath
    "$destDir" = Split-Path -Parent $DestinationPath
    "$destFile" = Split-Path -Leaf $DestinationPath

    if (-not (Test-Path "$destDir")) {
        try {
            New-Item -Path "$destDir" -ItemType Directory -Force | Out-Null
            Write-Log "Created destination directory: $destDir"
        } catch {
            Write-Log "Failed to create destination directory: $_" "Error"
            return $false
        }
    }

    if ((Test-Path "$DestinationPath") -and (-not $Force)) {
        Write-Log "Destination file exists. Skipping copy (use -Force to overwrite)." "Warning"
        return $true
    }

    # Check if robocopy is available
    if (-not (Get-Command -Name robocopy.exe -ErrorAction SilentlyContinue)) {
        Write-Log "Robocopy is not available on this system." "Error"
        return $false
    }

    "$robocopyArgs" = @(
        "`"$sourceDir`"",
        "`"$destDir`"",
        "`"$sourceFile`"",
        "/J",
        "/NP",
        "/MT:$ThreadCount",
        "/R:2",
        "/W:5"
    )

    Write-Log "Executing robocopy with $ThreadCount threads."
    try {
        $robocopy = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        if ("$robocopy".ExitCode -lt 8) {
            "$copiedPath" = Join-Path $destDir $sourceFile
            if ("$sourceFile" -ne $destFile) {
                "$finalPath" = Join-Path $destDir $destFile
                if (Test-Path "$finalPath") {
                    Remove-Item -Path "$finalPath" -Force
                    Write-Log "Removed existing file at $finalPath"
                }
                Rename-Item -Path "$copiedPath" -NewName $destFile -Force
                Write-Log "Renamed copied file to: $destFile"
            }
            Write-Log "WIM file copied successfully to $DestinationPath"
            return $true
        } else {
            Write-Log "Robocopy failed with exit code $($robocopy.ExitCode)" "Error"
            return $false
        }
    } catch {
        Write-Log "Unexpected error during robocopy: $_" "Error"
        return $false
    }
}
Export-ModuleMember -Function Copy-WimFileEfficiently