<#
.SYNOPSIS
    Provides standardized error handling functions for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This script contains functions for consistent error handling, including custom error types,
    standardized error reporting, and error collection for telemetry and logging.
.NOTES
    Version: 0.3.0
    Author: OSDCloud Team
#>

# Define custom error categories for better classification
enum ErrorCategory {
    Configuration
    Network
    Permission
    FileSystem
    WimProcessing
    PowerShell7
    Deployment
    Image
    ResourceBusy
    Validation
    Timeout
    Unknown
}

class OSDCloudCustomBuilderError {
    [string]$ErrorId
    [string]$Message
    [ErrorCategory]$Category
    [string]$Source
    [datetime]$Timestamp
    [System.Management.Automation.ErrorRecord]$OriginalError
    [string]$FunctionName
    [int]$LineNumber
    [hashtable]$AdditionalData

    OSDCloudCustomBuilderError([string]$message, [ErrorCategory]$category, [string]$source) {
        $this.ErrorId = [Guid]::NewGuid().ToString()
        $this.Message = $message
        $this.Category = $category
        $this.Source = $source
        $this.Timestamp = [datetime]::Now
        $this.AdditionalData = @{}
        
        # Get caller information if possible
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $caller = $callStack[1]
            $this.FunctionName = $caller.FunctionName
            $this.LineNumber = $caller.ScriptLineNumber
        }
    }

    OSDCloudCustomBuilderError([string]$message, [ErrorCategory]$category, [string]$source, [System.Management.Automation.ErrorRecord]$originalError) {
        $this.ErrorId = [Guid]::NewGuid().ToString()
        $this.Message = $message
        $this.Category = $category
        $this.Source = $source
        $this.OriginalError = $originalError
        $this.Timestamp = [datetime]::Now
        $this.AdditionalData = @{}
        
        # Get caller information if possible
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $caller = $callStack[1]
            $this.FunctionName = $caller.FunctionName
            $this.LineNumber = $caller.ScriptLineNumber
        }
    }

    [string] ToString() {
        $result = "[{0}] {1}: {2}" -f $this.Category, $this.Source, $this.Message
        
        if ($this.OriginalError) {
            $result += "`nOriginal Error: $($this.OriginalError.Exception.Message)"
        }
        
        if ($this.FunctionName) {
            $result += "`nFunction: $($this.FunctionName), Line: $($this.LineNumber)"
        }

        return $result
    }
}

# Module-wide error collection for telemetry and reporting
$script:ErrorCollection = [System.Collections.Generic.List[OSDCloudCustomBuilderError]]::new()

<#
.SYNOPSIS
    Handles exceptions in a standardized way across the module.
.DESCRIPTION
    Processes exceptions into standardized error objects, logs them appropriately,
    and optionally rethrows them based on settings.
.PARAMETER ErrorRecord
    The original error record to process.
.PARAMETER Message
    A custom message to describe the error context.
.PARAMETER Category
    The category of the error for better classification.
.PARAMETER Source
    The source component or function where the error occurred.
.PARAMETER SuppressError
    If set, the error is logged but not thrown, allowing execution to continue.
.PARAMETER AdditionalData
    Additional contextual data related to the error, stored as key-value pairs.
.EXAMPLE
    try {
        # Some code that might fail
    }
    catch {
        Write-OSDCloudError -ErrorRecord $_ -Message "Failed to process WIM file" -Category WimProcessing -Source "Update-CustomWimWithPwsh7"
    }
#>
function Write-OSDCloudError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Message,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [ErrorCategory]$Category,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [string]$Source,
        
        [Parameter()]
        [switch]$SuppressError,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    # Create standardized error object
    $osdError = [OSDCloudCustomBuilderError]::new($Message, $Category, $Source, $ErrorRecord)
    
    # Add any additional data
    if ($AdditionalData) {
        foreach ($key in $AdditionalData.Keys) {
            $osdError.AdditionalData[$key] = $AdditionalData[$key]
        }
    }
    
    # Add to collection for telemetry
    $script:ErrorCollection.Add($osdError)
    
    # Log the error
    $errorMessage = $osdError.ToString()
    
    # Check if OSDCloud logger exists
    $loggerExists = Get-Command -Name Write-OSDCloudLog -ErrorAction SilentlyContinue
    if ($loggerExists) {
        Write-OSDCloudLog -Message $errorMessage -Level Error
    }
    else {
        Write-Error $errorMessage
    }
    
    # Configure error handling behavior based on module config
    $errorConfig = Get-ModuleConfiguration -Setting "ErrorHandling" -ErrorAction SilentlyContinue
    
    $continueOnError = $false
    if ($errorConfig -and $errorConfig.ContainsKey("ContinueOnError")) {
        $continueOnError = $errorConfig.ContinueOnError
    }
    
    # If not suppressing and configuration doesn't specify to continue, re-throw the error
    if (-not $SuppressError -and -not $continueOnError) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($errorMessage, $ErrorRecord.Exception),
                "OSDCloudCustomBuilder_$($Category)",
                [System.Management.Automation.ErrorCategory]::FromStdErr,
                $Source
            )
        )
    }
}

<#
.SYNOPSIS
    Creates a new custom exception.
.DESCRIPTION
    Creates a new custom exception with standardized format without throwing it.
    Useful for creating exceptions to be thrown later or conditionally.
.PARAMETER Message
    A custom message to describe the error context.
.PARAMETER Category
    The category of the error for better classification.
.PARAMETER Source
    The source component or function where the error occurred.
.PARAMETER AdditionalData
    Additional contextual data related to the error, stored as key-value pairs.
.EXAMPLE
    $error = New-OSDCloudException -Message "Invalid file path" -Category FileSystem -Source "Copy-WimFileEfficiently"
    throw $error
#>
function New-OSDCloudException {
    [CmdletBinding()]
    [OutputType([OSDCloudCustomBuilderError])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [ErrorCategory]$Category,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$Source,
        
        [Parameter()]
        [hashtable]$AdditionalData
    )
    
    # Create standardized error object
    $osdError = [OSDCloudCustomBuilderError]::new($Message, $Category, $Source)
    
    # Add any additional data
    if ($AdditionalData) {
        foreach ($key in $AdditionalData.Keys) {
            $osdError.AdditionalData[$key] = $AdditionalData[$key]
        }
    }
    
    return $osdError
}

<#
.SYNOPSIS
    Gets all errors collected during module operation.
.DESCRIPTION
    Retrieves the list of all errors that have been collected since module load.
    Useful for reporting, troubleshooting, and telemetry.
.PARAMETER Clear
    If specified, clears the error collection after retrieving it.
.EXAMPLE
    $errors = Get-OSDCloudErrors -Clear
    $errors | Group-Object -Property Category | Format-Table Name, Count
#>
function Get-OSDCloudErrors {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[OSDCloudCustomBuilderError]])]
    param (
        [Parameter()]
        [switch]$Clear
    )
    
    $result = $script:ErrorCollection
    
    if ($Clear) {
        $script:ErrorCollection = [System.Collections.Generic.List[OSDCloudCustomBuilderError]]::new()
    }
    
    return $result
}

# Export functions
Export-ModuleMember -Function Write-OSDCloudError, New-OSDCloudException, Get-OSDCloudErrors
