function Copy-FilesInParallel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter()]
        [int]$MaxThreads = 8
    )
    # Get all files to copy
    $files = Get-ChildItem -Path $SourcePath -Recurse -File
    if ($files.Count -eq 0) {
        Write-OSDCloudLog -Message "No files found in $SourcePath." -Level Info -Component "Copy-FilesInParallel"
        return @()
    }
    # Pre-create all destination directories to avoid per-file Test-Path/New-Item overhead.
    $destDirs = $files |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($SourcePath.Length)
            $destDir = Split-Path -Path (Join-Path -Path $DestinationPath -ChildPath $relativePath) -Parent
            $destDir
        } | Sort-Object -Unique
    foreach ($dir in $destDirs) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    # Create thread-safe collection for results
    $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    # Determine available parallelization engine
    $useThreadJob = $null -ne (Get-Module -ListAvailable -Name ThreadJob)
    Write-OSDCloudLog -Message "Starting parallel file copy from $SourcePath to $DestinationPath" -Level Info -Component "Copy-FilesInParallel"
    Write-OSDCloudLog -Message ("Using ThreadJob: {0}, MaxThreads: {1}, Files to copy: {2}" -f $useThreadJob, $MaxThreads, $files.Count) -Level Info -Component "Copy-FilesInParallel"
    if ($useThreadJob) {
        # Using ThreadJob for parallel processing.
        try {
            $jobs = $files | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
                $sourceFile = $_.FullName
                $relativePath = $sourceFile.Substring($using:SourcePath.Length)
                $destFile = Join-Path -Path $using:DestinationPath -ChildPath $relativePath
                try {
                    # Actual copy command without per-file directory check (directories already exist)
                    Copy-Item -Path $sourceFile -Destination $destFile -Force
                    $threadSafeListLocal = $using:threadSafeList
                    $null = $threadSafeListLocal.Add($destFile)
                    # Log minimal summary info
                    Write-OSDCloudLog -Message ("Copied file: {0}" -f $sourceFile) -Level Debug -Component "Copy-FilesInParallel"
                }
                catch {
                    Write-Error ("Failed to copy {0} to {1}. Error: {2}" -f $sourceFile, $destFile, $_)
                }
            }
        }
        catch {
            Write-OSDCloudLog -Message ("Error during ThreadJob parallel processing: {0}" -f $_) -Level Error -Component "Copy-FilesInParallel" -Exception $_.Exception
            throw
        }
    }
    else {
        # Fallback: use standard background jobs with minimal per-file overhead.
        $jobs = @()
        # Divide file list into approximately equal chunks
        $chunkSize = [Math]::Ceiling($files.Count / $MaxThreads)
        $chunks = [System.Collections.ArrayList]::new()
        
        for ($i = 0; $i -lt $files.Count; $i += $chunkSize) {
            $end = [Math]::Min($i + $chunkSize - 1, $files.Count - 1)
            [void]$chunks.Add($files[$i..$end])
        }
        
        Write-OSDCloudLog -Message ("Using standard jobs with {0} chunks." -f $chunks.Count) -Level Info -Component "Copy-FilesInParallel"
        foreach ($chunk in $chunks) {
            $job = Start-Job -ScriptBlock {
                param($files, $sourcePath, $destPath, $list)
                foreach ($file in $files) {
                    $relativePath = $file.FullName.Substring($sourcePath.Length)
                    $targetPath = Join-Path -Path $destPath -ChildPath $relativePath
                    try {
                        # Retry logic if needed.
                        $maxRetries = 3
                        $retryCount = 0
                        $success = $false
                        while (-not $success -and $retryCount -lt $maxRetries) {
                            try {
                                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                                $list.Add($targetPath)
                                $success = $true
                            }
                            catch {
                                $retryCount++
                                if ($retryCount -eq $maxRetries) {
                                    Write-Error ("Failed to copy {0} to {1} after {2} attempts. Error: {3}" -f $file.FullName, $targetPath, $maxRetries, $_)
                                    throw
                                }
                                Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
                            }
                        }
                    }
                    catch {
                        Write-Error ("Failed to copy {0} from job. Error: {1}" -f $file.FullName, $_)
                    }
                }
            } -ArgumentList $chunk, $SourcePath, $DestinationPath, $threadSafeList
            $jobs += $job
        }
        $jobs | Wait-Job | ForEach-Object { Receive-Job -Job $_ } | Out-Null
        $jobs | Remove-Job
    }
    
    Write-OSDCloudLog -Message ("Parallel file copy completed. Copied {0} of {1} files." -f $threadSafeList.Count, $files.Count) -Level Info -Component "Copy-FilesInParallel"
    return $threadSafeList
}
# Export the function
Export-ModuleMember -Function Copy-FilesInParallel