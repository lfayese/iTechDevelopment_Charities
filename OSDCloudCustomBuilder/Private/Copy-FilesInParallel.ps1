# Patched
Set-StrictMode -Version Latest
[OutputType([object])]
<#
.SYNOPSIS
    Copies files in parallel using PowerShell jobs.
.DESCRIPTION
    This function takes a list of files and copies them to a destination using parallel threads.
    Includes improved error handling, cancellation support, and performance optimizations.
.PARAMETER SourcePath
    The source directory path.
.PARAMETER DestinationPath
    The destination directory path.
.PARAMETER MaxThreads
    The maximum number of threads to use.
.PARAMETER CancellationToken
    Optional cancellation token to support cancelling long-running operations.
#>
function Copy-FilesInParallel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,
        
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,
        
        [Parameter()]
        [ValidateRange(1, 32)]
        [int]$MaxThreads = 8,
        
        [Parameter()]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    begin {
        # Validate paths to prevent path traversal
        try {
            $validatedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
            if (-not (Test-Path -Path $validatedSourcePath -PathType Container)) {
                throw "Source directory not found: $SourcePath"
            }
            $SourcePath = $validatedSourcePath
            
            $validatedDestPath = [System.IO.Path]::GetFullPath($DestinationPath)
            if (-not (Test-Path -Path $validatedDestPath -PathType Container)) {
                throw "Destination directory not found: $DestinationPath"
            }
            $DestinationPath = $validatedDestPath
        }
        catch {
            Write-Error "Path validation failed: $_"
            throw
        }
        
        # Function to get relative path - moved to begin block for better performance
        function Get-RelativePath {
            param ($base, $full)
            # More efficient string handling without interpolation
            return $full.Substring($base.Length)
        }
    }

    process {
        try {
            # Initialize logging
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Starting parallel file copy from $SourcePath to $DestinationPath" -Level Info -Component "Copy-FilesInParallel"
            }
            
            # Get all files to copy
            $files = Get-ChildItem -Path $SourcePath -Recurse -File
            if ($files.Count -eq 0) {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "No files found in $SourcePath." -Level Info -Component "Copy-FilesInParallel"
                }
                return @()
            }
            
            # Pre-create destination directories
            $destDirs = $files | ForEach-Object {
                $relativePath = Get-RelativePath -base $SourcePath -full $_.FullName
                Split-Path -Path (Join-Path -Path $DestinationPath -ChildPath $relativePath) -Parent
            } | Sort-Object -Unique
            
            foreach ($dir in $destDirs) {
                if (-not (Test-Path -Path $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }
            }
            
            # Thread-safe collection to track copied files
            $threadSafeList = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            # Check if ThreadJob module is available
            $useThreadJob = $null -ne (Get-Module -ListAvailable -Name ThreadJob)
            
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message ("Using ThreadJob: {0}, MaxThreads: {1}, Files to copy: {2}" -f $useThreadJob, $MaxThreads, $files.Count) -Level Info -Component "Copy-FilesInParallel"
            }
            
            # Create an error collection to track all errors
            $errorCollection = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            if ($useThreadJob) {
                try {
                    $jobs = $files | ForEach-Object -ThrottleLimit $MaxThreads -Parallel {
                        # Check for cancellation
                        if ($using:CancellationToken.IsCancellationRequested) {
                            return
                        }
                        
                        $sourceFile = $_.FullName
                        $relativePath = $sourceFile.Substring($using:SourcePath.Length)
                        $destFile = Join-Path -Path $using:DestinationPath -ChildPath $relativePath
                        
                        try {
                            Copy-Item -Path $sourceFile -Destination $destFile -Force
                            $using:threadSafeList.Add($destFile)
                        }
                        catch {
                            $errorMsg = "Failed to copy {0} to {1}. Error: {2}" -f $sourceFile, $destFile, $_
                            $using:errorCollection.Add($errorMsg)
                            Write-Error $errorMsg
                        }
                    }
                }
                catch {
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message ("Error during ThreadJob processing: $_") -Level Error -Component "Copy-FilesInParallel" -Exception $_.Exception
                    }
                    throw
                }
            }
            else {
                $chunkSize = [Math]::Ceiling($files.Count / $MaxThreads)
                $chunks = [System.Collections.ArrayList]::new()
                
                for ($i = 0; $i -lt $files.Count; $i += $chunkSize) {
                    $end = [Math]::Min($i + $chunkSize - 1, $files.Count - 1)
                    [void]$chunks.Add($files[$i..$end])
                }
                
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message ("Using standard jobs with {0} chunks." -f $chunks.Count) -Level Info -Component "Copy-FilesInParallel"
                }
                
                $jobs = foreach ($chunk in $chunks) {
                    # Pass CancellationToken to job
                    Start-Job -ScriptBlock {
                        param($files, $src, $dst, $list, $errors, $token)
                        
                        foreach ($file in $files) {
                            # Check for cancellation
                            if ($token.IsCancellationRequested) {
                                break
                            }
                            
                            $relativePath = $file.FullName.Substring($src.Length)
                            $targetPath = Join-Path -Path $dst -ChildPath $relativePath
                            
                            try {
                                $maxRetries = 3
                                for ($r = 0; $r -lt $maxRetries; $r++) {
                                    try {
                                        Copy-Item -Path $file.FullName -Destination $targetPath -Force
                                        $list.Add($targetPath)
                                        break
                                    }
                                    catch {
                                        if ($r -eq $maxRetries - 1) {
                                            $errorMsg = "Failed to copy {0} after {1} attempts. Error: {2}" -f $file.FullName, $maxRetries, $_
                                            $errors.Add($errorMsg)
                                            Write-Error $errorMsg
                                            throw
                                        }
                                        Start-Sleep -Seconds ([Math]::Pow(2, $r))
                                    }
                                }
                            }
                            catch {
                                $errorMsg = "Error in job copying {0}: {1}" -f $file.FullName, $_
                                $errors.Add($errorMsg)
                                Write-Error $errorMsg
                            }
                        }
                    } -ArgumentList $chunk, $SourcePath, $DestinationPath, $threadSafeList, $errorCollection, $CancellationToken
                }
                
                $jobs | Wait-Job | ForEach-Object { Receive-Job -Job $_ } | Out-Null
                $jobs | Remove-Job
            }
            
            # Check if there were any errors
            if ($errorCollection.Count -gt 0) {
                $errorSummary = "Encountered {0} errors during file copying" -f $errorCollection.Count
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorSummary -Level Warning -Component "Copy-FilesInParallel"
                    
                    # Log the first 5 errors (to avoid excessive logging)
                    $errorCollection | Select-Object -First 5 | ForEach-Object {
                        Invoke-OSDCloudLogger -Message $_ -Level Error -Component "Copy-FilesInParallel"
                    }
                }
                Write-Warning $errorSummary
            }
            
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message ("Parallel file copy completed. Copied {0} of {1} files." -f $threadSafeList.Count, $files.Count) -Level Info -Component "Copy-FilesInParallel"
            }
            
            return $threadSafeList
        }
        catch {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Error in Copy-FilesInParallel: $_" -Level Error -Component "Copy-FilesInParallel" -Exception $_.Exception
            }
            throw
        }
    }
}
Export-ModuleMember -Function Copy-FilesInParallel