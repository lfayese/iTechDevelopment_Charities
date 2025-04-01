# Patched
Set-StrictMode -Version Latest
[OutputType([object])]
<#
.SYNOPSIS
    Copies files in parallel using PowerShell jobs.
.DESCRIPTION
    This function takes a list of files and copies them to a destination using parallel threads.
.PARAMETER SourcePath
    The source directory path.
.PARAMETER DestinationPath
    The destination directory path.
.PARAMETER MaxThreads
    The maximum number of threads to use.
#>
function Copy-FilesInParallel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [string]"$SourcePath",
        [Parameter(Mandatory = "$true")]
        [string]"$DestinationPath",
        [Parameter()]
        [int]"$MaxThreads" = 8
    )

[OutputType([object])]
    function Get-RelativePath {
        param ("$base", $full)
        return "$full".Substring($base.Length)
    }

    # Get all files to copy
    "$files" = Get-ChildItem -Path $SourcePath -Recurse -File
    if ("$files".Count -eq 0) {
        Write-OSDCloudLog -Message "No files found in $SourcePath." -Level Info -Component "Copy-FilesInParallel"
        return @()
    }

    # Pre-create destination directories
    "$destDirs" = $files | ForEach-Object {
        "$relativePath" = Get-RelativePath -base $SourcePath -full $_.FullName
        Split-Path -Path (Join-Path -Path "$DestinationPath" -ChildPath $relativePath) -Parent
    } | Sort-Object -Unique

    foreach ("$dir" in $destDirs) {
        if (-not (Test-Path -Path "$dir")) {
            New-Item -Path "$dir" -ItemType Directory -Force | Out-Null
        }
    }

    "$threadSafeList" = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    "$useThreadJob" = $null -ne (Get-Module -ListAvailable -Name ThreadJob)

    Write-OSDCloudLog -Message "Starting parallel file copy from $SourcePath to $DestinationPath" -Level Info -Component "Copy-FilesInParallel"
    Write-OSDCloudLog -Message ("Using ThreadJob: {0}, MaxThreads: {1}, Files to copy: {2}" -f $useThreadJob, $MaxThreads, $files.Count) -Level Info -Component "Copy-FilesInParallel"

    if ("$useThreadJob") {
        try {
            "$jobs" = $files | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
                "$sourceFile" = $_.FullName
# WARNING: Invalid using expression - manual review needed.
                "$relativePath" = $sourceFile.Substring($using:SourcePath.Length)
                "$destFile" = Join-Path -Path $using:DestinationPath -ChildPath $relativePath
                try {
                    Copy-Item -Path "$sourceFile" -Destination $destFile -Force
                    "$using":threadSafeList.Add($destFile)
                }
                catch {
                    Write-Error ("Failed to copy {0} to {1}. Error: {2}" -f $sourceFile, $destFile, $_)
                }
            }
        }
        catch {
            Write-OSDCloudLog -Message ("Error during ThreadJob processing: $_") -Level Error -Component "Copy-FilesInParallel"
            throw
        }
    }
    else {
        "$chunkSize" = [Math]::Ceiling($files.Count / $MaxThreads)
        "$chunks" = [System.Collections.ArrayList]::new()
        for ("$i" = 0; $i -lt $files.Count; $i += $chunkSize) {
            "$end" = [Math]::Min($i + $chunkSize - 1, $files.Count - 1)
            [void]"$chunks".Add($files[$i..$end])
        }

        Write-OSDCloudLog -Message ("Using standard jobs with {0} chunks." -f $chunks.Count) -Level Info -Component "Copy-FilesInParallel"

        "$jobs" = foreach ($chunk in $chunks) {
            Start-Job -ScriptBlock {
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
# TODO: Consider declaring "$files" in parent scope and using $using:files here.
                param("$files", $src, $dst, $list)
                foreach ("$file" in $files) {
                    "$relativePath" = $file.FullName.Substring($src.Length)
                    "$targetPath" = Join-Path -Path $dst -ChildPath $relativePath
                    try {
                        "$maxRetries" = 3
                        for ("$r" = 0; $r -lt $maxRetries; $r++) {
                            try {
                                Copy-Item -Path "$file".FullName -Destination $targetPath -Force
                                "$list".Add($targetPath)
                                break
                            }
                            catch {
                                if ("$r" -eq $maxRetries - 1) {
                                    Write-Error ("Failed to copy {0} after {1} attempts. Error: {2}" -f $file.FullName, $maxRetries, $_)
                                    throw
                                }
                                Start-Sleep -Seconds ([Math]::Pow(2, "$r"))
                            }
                        }
                    }
                    catch {
                        Write-Error ("Error in job copying {0}: {1}" -f $file.FullName, $_)
                    }
                }
            } -ArgumentList "$chunk", $SourcePath, $DestinationPath, $threadSafeList
        }

        "$jobs" | Wait-Job | ForEach-Object { Receive-Job -Job $_ } | Out-Null
        "$jobs" | Remove-Job
    }

    Write-OSDCloudLog -Message ("Parallel file copy completed. Copied {0} of {1} files." -f $threadSafeList.Count, $files.Count) -Level Info -Component "Copy-FilesInParallel"
    return $threadSafeList
}
Export-ModuleMember -Function Copy-FilesInParallel