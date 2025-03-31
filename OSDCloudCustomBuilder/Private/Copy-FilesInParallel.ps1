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
    
    # Create thread-safe collection for results
    $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
    
    # Check if ThreadJob module is available
    $useThreadJob = $null -ne (Get-Module -ListAvailable -Name ThreadJob)
    
    Write-OSDCloudLog -Message "Starting parallel file copy from $SourcePath to $DestinationPath" -Level Info -Component "Copy-FilesInParallel"
    Write-OSDCloudLog -Message "Using ThreadJob: $useThreadJob, MaxThreads: $MaxThreads, Files to copy: $($files.Count)" -Level Info -Component "Copy-FilesInParallel"
    
    if ($useThreadJob) {
        # Use ThreadJob for parallel processing
        try {
            $totalFiles = $files.Count
            $processedFiles = 0
            $jobs = $files | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
                $script:processedFiles++
                Write-Progress -Activity "Copying Files" -Status "Processing file $script:processedFiles of $using:totalFiles" -PercentComplete (($script:processedFiles / $using:totalFiles) * 100)
                $sourcePath = $_.FullName
                $relativePath = $_.FullName.Substring($using:SourcePath.Length)
                $destPath = Join-Path -Path $using:DestinationPath -ChildPath $relativePath
                
                $destDir = Split-Path -Path $destPath -Parent
                if (-not (Test-Path -Path $destDir)) {
                    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
                }
                
                try {
                    $copyTime = Measure-Command {
                        Copy-Item -Path $sourcePath -Destination $destPath -Force
                        $null = ($using:threadSafeList).Add($destPath)
                    }
                    Write-OSDCloudLog -Message "Copied $sourcePath in $($copyTime.TotalSeconds) seconds" -Level Info -Component "Copy-FilesInParallel"
                    [System.GC]::Collect()
                }
                catch {
                    Write-Error "Failed to copy $sourcePath to $destPath: $_"
                }
            }
        }
        catch {
            Write-OSDCloudLog -Message "Error in ThreadJob parallel processing: $_" -Level Error -Component "Copy-FilesInParallel" -Exception $_.Exception
            throw
        }
    }
    else {
        # Fallback to regular jobs
        $jobs = @()
        $chunks = [System.Collections.ArrayList]::new()
        
        # Split files into chunks
        $chunkSize = [Math]::Ceiling($files.Count / $MaxThreads)
        for ($i = 0; $i -lt $files.Count; $i += $chunkSize) {
            $end = [Math]::Min($i + $chunkSize - 1, $files.Count - 1)
            [void]$chunks.Add($files[$i..$end])
        }
        
        Write-OSDCloudLog -Message "Using standard jobs with $($chunks.Count) chunks" -Level Info -Component "Copy-FilesInParallel"
        
        # Process each chunk in a separate job
        foreach ($chunk in $chunks) {
            $job = Start-Job -ScriptBlock {
                param($files, $sourcePath, $destPath, $list)
                
                foreach ($file in $files) {
                    $relativePath = $file.FullName.Substring($sourcePath.Length)
                    $targetPath = Join-Path -Path $destPath -ChildPath $relativePath
                    
                    $targetDir = Split-Path -Path $targetPath -Parent
                    if (-not (Test-Path -Path $targetDir)) {
                        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                    }
                    
                    try {
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
                                    Write-Error "Failed to copy $($file.FullName) to $targetPath after $maxRetries attempts: $_"
                                    throw
                                }
                                Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
                            }
                        }
                    }
                    catch {
                        Write-Error "Failed to copy $($file.FullName) to $targetPath: $_"
                    }
                }
            } -ArgumentList $chunk, $SourcePath, $DestinationPath, $threadSafeList
            
            $jobs += $job
        }
        
        # Wait for all jobs to complete
        $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job
    }
    
    Write-OSDCloudLog -Message "Parallel file copy completed. Copied $($threadSafeList.Count) of $($files.Count) files." -Level Info -Component "Copy-FilesInParallel"
    
    return $threadSafeList
}

# Export the function
Export-ModuleMember -Function Copy-FilesInParallel