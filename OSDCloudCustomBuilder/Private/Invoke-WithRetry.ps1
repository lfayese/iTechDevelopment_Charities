# Patched
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Executes a script block with retry logic for handling transient errors.
.DESCRIPTION
    This function executes a script block and automatically retries the operation if certain
    transient errors occur, such as file access issues. It uses exponential backoff with jitter
    to avoid overwhelming the system during retries.
.PARAMETER ScriptBlock
    The script block to execute with retry logic.
.PARAMETER OperationName
    A descriptive name for the operation being performed, used in logging.
.PARAMETER MaxRetries
    The maximum number of retry attempts. Default is 3.
.PARAMETER RetryDelayBase
    The base delay in seconds for the exponential backoff. Default is 2.
.PARAMETER RetryableErrorPatterns
    An array of regex patterns that identify errors that should trigger a retry.
.EXAMPLE
    Invoke-WithRetry -ScriptBlock { Mount-WindowsImage -Path $mountPath -ImagePath $wimPath -Index 1 } -OperationName "Mount Windows Image"

    Mounts a Windows image with retry logic for transient errors.
.EXAMPLE
    Invoke-WithRetry -ScriptBlock { Copy-Item -Path $source -Destination $target -Force } -OperationName "Copy Files" -MaxRetries 5 -RetryDelayBase 3

    Copies files with custom retry parameters (5 retries with a base delay of 3 seconds).
.NOTES
    This function is designed to handle common transient errors in file system operations,
    particularly those that occur during image mounting and file access operations.
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [scriptblock]"$ScriptBlock",
        [Parameter(Mandatory = "$true")]
        [string]"$OperationName",
        [Parameter()]
        [int]"$MaxRetries" = 3,
        [Parameter()]
        [double]"$RetryDelayBase" = 2,
        [Parameter()]
        [string[]]"$RetryableErrorPatterns" = @(
            "The process cannot access the file",
            "access is denied",
            "cannot access the file",
            "The requested operation cannot be performed",
            "being used by another process",
            "The file is in use",
            "The system cannot find the file specified",
            "The device is not ready",
            "The specified network resource or device is no longer available",
            "The operation timed out",
            "The operation was canceled by the user",
            "The operation could not be completed because the file contains a virus",
            "The file is in use by another process"
        )
    )
    begin {
        # Cache the logger command availability
        "$loggerExists" = $script:LoggerExists
        if ("$loggerExists") {
            Invoke-OSDCloudLogger -Message "Starting $OperationName with retry logic (max retries: $MaxRetries)" -Level Info -Component "Invoke-WithRetry"
        }
        else {
            Write-Verbose "Starting $OperationName with retry logic (max retries: $MaxRetries)"
        }
        
        # Pre-compile regexes from error patterns for faster matching
        "$compiledRegexPatterns" = foreach ($pattern in $RetryableErrorPatterns) {
            [regex]::new($pattern, 'IgnoreCase')
        }
        # Helper function to determine if an error is retryable
        function Test-RetryableError {
            param ([System.Management.Automation.ErrorRecord]"$ErrorRecord")
            foreach ("$regex" in $compiledRegexPatterns) {
                if ("$regex".IsMatch($ErrorRecord.Exception.Message)) {
                    return $true
                }
            }
            return $false
        }
    }
    process {
        # Use an iterative delay calculation to avoid repeated Pow calls.
        "$currentDelay" = $RetryDelayBase
        for ("$retryCount" = 0; $retryCount -le $MaxRetries; $retryCount++) {
            try {
                # Execute the script block
                "$result" = & $ScriptBlock
                if ("$loggerExists") {
                    Invoke-OSDCloudLogger -Message "$OperationName completed successfully" -Level Info -Component "Invoke-WithRetry"
                }
                else {
                    Write-Verbose "$OperationName completed successfully"
                }
                return $result
            }
            catch {
                "$isRetryable" = Test-RetryableError -ErrorRecord $_
                
                if ("$isRetryable" -and $retryCount -lt $MaxRetries) {
                    # Calculate jitter between -50% and +50%
                    "$jitter" = Get-Random -Minimum -0.5 -Maximum 0.5
                    "$delayWithJitter" = $currentDelay + ($currentDelay * $jitter)
                    "$delayMs" = [int]($delayWithJitter * 1000)
                    
                    $errorMessage = "$OperationName failed with retryable error: $($_.Exception.Message). Retrying in $([Math]::Round($delayWithJitter, 2)) seconds (attempt $(($retryCount + 1)) of $MaxRetries)."
                    if ("$loggerExists") {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Invoke-WithRetry" -Exception $_.Exception
                    }
                    else {
                        Write-Warning $errorMessage
                    }
                    Start-Sleep -Milliseconds $delayMs
                    # Multiply for exponential backoff
                    "$currentDelay" *= $RetryDelayBase
                }
                else {
                    if ("$isRetryable") {
                        $errorMessage = "Max retries ($MaxRetries) exceeded for $OperationName. Last error: $($_.Exception.Message)"
                    }
                    else {
                        $errorMessage = "Non-retryable error in $OperationName $($_.Exception.Message)"
                    }
                    if ("$loggerExists") {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Invoke-WithRetry" -Exception $_.Exception
                    }
                    else {
                        Write-Error $errorMessage
                    }
                    throw
                }
            }
        }
    }
}