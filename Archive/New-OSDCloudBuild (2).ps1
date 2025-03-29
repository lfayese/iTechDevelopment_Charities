<#
.SYNOPSIS
  Optimized OSDCloud Deployment Script for Windows 11 24H2
.DESCRIPTION
  Automates OSDCloud template/workspace creation, module installations, WinPE
  customization, RAM disk setup, and ISO/USB generation using efficient PowerShell practices.
.Example
  .\New-OSDCloudBuild.ps1 -WorkspacePath "F:\OSDCloudProd_v6" -CustomFilesPath "G:\CustomFiles" -compressIso
.NOTES
  Module:         OSDCloud
  Script Name:    New-OSDCloudBuild.ps1
  Script Author:  iTechDC
  Script Version: 2.4
  Last Updated:   2025-03-24
  Description:    Optimized script for creating OSDCloud templates and workspaces
                  with improved error handling, logging, and modularization.
  Environment:    PowerShell 7.5.0, Windows ADK, OSDCloud module
  Tested on:      Windows 11 24H2
  Author:         iTechDC
  Creation Date:  2025-03-24
  Purpose/Change: Added module version management, disk space validation, consistent exit strategy,
                  timeout handling, and script validation
  Dependencies:   OSDCloud module, PowerShell 7.5.0, Windows ADK
  Tested on:      Windows 11 24H2

.LINK

#>
[CmdletBinding()]
param(
    [string]$WorkspacePath = "G:\OSDCloudProd",
    [string]$CustomFilesPath = "G:\CustomFiles",
    [string]$LogPath = "",
    [string]$TemplateName = "WinRE_prod",
    [switch]$CompressISO
)

# Set exit codes
$SCRIPT_EXIT_SUCCESS = 0
$SCRIPT_EXIT_FAILURE = 1
$SCRIPT_EXIT_INVALID_PARAMS = 2
$SCRIPT_EXIT_MISSING_PREREQS = 3
$SCRIPT_EXIT_INSUFFICIENT_SPACE = 4

# Define module requirements with specific versions
$requiredModulesWithVersions = @{
    'OSD' = '23.5.26'
    'PackageManagement' = '1.4.8.1'
    'PSWindowsUpdate' = '2.2.0.3'
    'PowerShellGet' = '2.2.5'
    'Az' = '9.3.0'
    'Microsoft.Graph' = '1.27.0'
    'Microsoft.Entra' = '1.0.0'
    'Microsoft.Graph.Beta' = '1.0.1'
    'Microsoft.Entra.Beta' = '1.0.0'
}

# Set timeouts
$PARALLEL_OP_TIMEOUT_SEC = 1200    # 20 minutes for parallel operations
$DISM_OPERATION_TIMEOUT_SEC = 7200 # 2 hours for DISM operations with large WIM files

# Set minimum space requirements (in GB)
$MIN_WORKSPACE_SPACE_GB = 90  # Increased from 50 to accommodate large WIM files
$MIN_TEMP_SPACE_GB = 90       # Increased from 50 to accommodate large WIM operations

# Disk space requirements for specific operations (in GB)
$SPACE_REQUIREMENTS = @{
	"WimMount"      = 5
	"ISO"           = 7
	"WorkspaceBase" = 10
	"Backup"        = 15
	"CustomWim"     = 40          # Added new entry for 40GB custom WIM file
	"WimProcessing" = 45      # Added for WIM processing (slightly more than the WIM itself)
}

# Initialize StringBuilder for efficient logging
$script:logBuilder = [System.Text.StringBuilder]::new()
$script:logBuffer = [System.Collections.Generic.List[string]]::new()
$script:lastProgressUpdate = [DateTime]::MinValue
$script:progressThrottleMs = 500 # Throttle progress updates
# Initialize error handling and tracking
$ErrorActionPreference = "Stop"
$script:startTime = Get-Date
$script:errorOccurred = $false
$script:mountedWimPath = $null
# Calculate log path if not specified
if ([string]::IsNullOrEmpty($LogPath)) {
    $LogPath = Join-Path $WorkspacePath "OSDCloud_Build.log"
}

# ============================
# [0] Helper Functions
# ============================
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    # Add to StringBuilder for efficient string operations
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    [void]$script:logBuilder.AppendLine($logMessage)

    # Buffer log messages and flush periodically
    $script:logBuffer.Add($logMessage)
    if ($script:logBuffer.Count -ge 100) {
        Write-LogBuffer
    }
    # Console output with throttled progress updates
    $now = [DateTime]::Now
    if (($Level -ne "INFO") -or ($now - $script:lastProgressUpdate).TotalMilliseconds -ge $script:progressThrottleMs) {
        switch ($Level) {
            "INFO"    { Write-Host $logMessage -ForegroundColor Gray }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "ERROR"   {
                Write-Host $logMessage -ForegroundColor Red
                $script:errorOccurred = $true
            }
            "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        }
        $script:lastProgressUpdate = $now
    }
}

function Write-LogBuffer {
    if ($script:logBuffer.Count -gt 0) {
        $logDir = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $script:logBuffer -ErrorAction SilentlyContinue
        $script:logBuffer.Clear()
    }
}

# Improved exit function for consistent exit strategy
function Exit-Script {
    param (
        [int]$ExitCode = $SCRIPT_EXIT_SUCCESS,
        [string]$Message = ""
    )

    # Ensure all logs are written before exit
    if (-not [string]::IsNullOrEmpty($Message)) {
        $levelMap = @{
            $SCRIPT_EXIT_SUCCESS = "SUCCESS"
            $SCRIPT_EXIT_FAILURE = "ERROR"
            $SCRIPT_EXIT_INVALID_PARAMS = "ERROR"
            $SCRIPT_EXIT_MISSING_PREREQS = "ERROR"
            $SCRIPT_EXIT_INSUFFICIENT_SPACE = "ERROR"
        }
        $level = $levelMap[$ExitCode]
        if (-not $level) { $level = "ERROR" }
        Write-Log -Message $Message -Level $level
    }

    # Final cleanup
    Write-LogBuffer

    # Dismount any WIMs if still mounted
    if ($script:mountedWimPath -and (Test-Path $script:mountedWimPath)) {
        try {
            Write-Log "Cleaning up mounted WIM at: $script:mountedWimPath" -Level "INFO"
            Dismount-WindowsImage -Path $script:mountedWimPath -Discard -ErrorAction SilentlyContinue
        } catch {
            Write-Log "Failed to dismount WIM during cleanup: $($_.Exception.Message)" -Level "WARNING"
        }
    }

    # Calculate and log execution time
    $elapsedTime = New-TimeSpan -Start $script:startTime -End (Get-Date)
    $formattedTime = "{0:D2}h:{1:D2}m:{2:D2}s" -f $elapsedTime.Hours, $elapsedTime.Minutes, $elapsedTime.Seconds
    Write-Log "Total execution time: $formattedTime" -Level "INFO"
    Write-Log "Script exiting with code: $ExitCode" -Level $(if ($ExitCode -eq 0) { "SUCCESS" } else { "ERROR" })

    exit $ExitCode
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Dependencies {
    $missingDeps = @()

    # Check for Windows ADK components
    if (-not (Get-Command Dism.exe -ErrorAction SilentlyContinue)) {
        $missingDeps += "Windows ADK (Deployment Tools)"
    }

    # Check for PowerShell 7+ for optimal performance
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Log "PowerShell 7+ is recommended for optimal performance (current: $($PSVersionTable.PSVersion))" -Level "WARNING"
    }

    if ($missingDeps.Count -gt 0) {
        Write-Log "Missing dependencies: $($missingDeps -join ', ')" -Level "ERROR"
        return $false
    }
    return $true
}

function Test-ComponentVersions {
    [CmdletBinding()]
    param()

    $versionInfo = @()

    # Check Windows ADK version
    $adkRegPath = "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots"
    $adkVersion = if (Test-Path $adkRegPath) {
        $kitRoot = Get-ItemProperty -Path $adkRegPath -Name "KitsRoot10" -ErrorAction SilentlyContinue
        if ($kitRoot) {
            $adkVer = Get-ItemProperty -Path "$adkRegPath\$($kitRoot.KitsRoot10 -replace '\\$','')" -Name ProductVersion -ErrorAction SilentlyContinue
            if ($adkVer) { $adkVer.ProductVersion } else { "Unknown" }
        } else { "Not detected" }
    } else { "Not installed" }

    $versionInfo += [PSCustomObject]@{
        Component = "Windows ADK"
        Version = $adkVersion
        Required = "Recommended: 10.1.22621.1 or newer"
        Status = if ($adkVersion -eq "Not installed") { "❌ Missing" } else { "✅ Available" }
    }

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $versionInfo += [PSCustomObject]@{
        Component = "PowerShell"
        Version = $psVersion
        Required = "7.0 or higher"
        Status = if ([version]$psVersion -lt [version]"7.0") { "⚠️ Warning" } else { "✅ OK" }
    }

    # Display version table
    Write-Log "Component Version Information:" -Level "INFO"
    $versionInfo | ForEach-Object {
        Write-Log "  $($_.Component): $($_.Version) ($($_.Status))" -Level $(
            if ($_.Status -like "*Missing*") { "ERROR" }
            elseif ($_.Status -like "*Warning*") { "WARNING" }
            else { "INFO" }
        )
    }

    # Return true if all required components are available
    return -not ($versionInfo | Where-Object Status -like "*Missing*").Count -gt 0
}

function Test-DiskSpace {
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [double]$RequiredGB,
        [string]$Operation = "Operation"
    )

    if (-not (Test-Path $Path)) {
        $Path = Split-Path -Path $Path -Parent
        if (-not (Test-Path $Path)) {
            $Path = Split-Path -Path $Path -Parent
            if (-not (Test-Path $Path)) {
                $driveLetter = $Path.Substring(0, 2)
                if (-not (Test-Path $driveLetter)) {
                    Write-Log "Cannot determine drive for path: $Path" -Level "ERROR"
                    return $false
                }
                $Path = $driveLetter
            }
        }
    }

    try {
        $drive = (Get-Item $Path).PSDrive
        $freeSpaceGB = [math]::Round(($drive.Free / 1GB), 2)

        if ($freeSpaceGB -lt $RequiredGB) {
            Write-Log "Insufficient disk space for $Operation on $($drive.Name): $freeSpaceGB GB available, $RequiredGB GB required" -Level "ERROR"
            return $false
        }

        Write-Log "Sufficient disk space for $Operation on $($drive.Name): $freeSpaceGB GB available" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Error checking disk space: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function New-Folder {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Created folder: $Path" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to create folder $Path : $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
}

function Copy-IfDifferent {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -Path $Source)) {
        Write-Log "Source file not found: $Source" -Level "ERROR"
        return $false
    }

    $destDir = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -Path $destDir)) {
        New-Folder -Path $destDir
    }

    if (-not (Test-Path -Path $Destination) -or
        (Get-FileHash -Path $Source).Hash -ne (Get-FileHash -Path $Destination).Hash) {
        try {
            Copy-Item -Path $Source -Destination $Destination -Force
            Write-Log "Copied file: $Source -> $Destination" -Level "SUCCESS"
            return $true
        }
        catch {
            Write-Log "Failed to copy file: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    else {
        Write-Log "Files identical, skipping copy: $Source" -Level "INFO"
        return $true
    }
}

function Confirm-Yes {
    param([string]$Message)

    $response = Read-Host -Prompt "$Message"
    return $response -match "^[Yy]"
}

# Improved parallel processing helper with timeout
function Invoke-Parallel {
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        [Parameter(Mandatory)]
        [object[]]$InputObject,
        [int]$ThrottleLimit = 5,
        [int]$TimeoutSeconds = $PARALLEL_OP_TIMEOUT_SEC
    )

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7+ has built-in parallel processing with timeout
        try {
            $parallelParams = @{
                ThrottleLimit = $ThrottleLimit
                TimeoutSeconds = $TimeoutSeconds
                Parallel = $ScriptBlock
            }
            return $InputObject | ForEach-Object @parallelParams
        }
        catch {
            if ($_.Exception.Message -like "*timed out*") {
                Write-Log "Parallel operation timed out after $TimeoutSeconds seconds" -Level "WARNING"
            }
            else {
                throw
            }
        }
    }
    else {
        # In PowerShell 5.1, implement timeout for jobs
        $jobs = @()
        $results = @()

        foreach ($item in $InputObject) {
            while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
                Start-Sleep -Milliseconds 100
                # Check for timed out jobs
                $runningJobs = Get-Job -State Running
                foreach ($job in $runningJobs) {
                    if ((New-TimeSpan -Start $job.PSBeginTime -End (Get-Date)).TotalSeconds -gt $TimeoutSeconds) {
                        Write-Log "Job $($job.Id) timed out after $TimeoutSeconds seconds" -Level "WARNING"
                        Stop-Job -Job $job
                        Remove-Job -Job $job -Force
                    }
                }
            }
            $jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList $item
        }

        # Wait for jobs with timeout
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (Get-Job -State Running) {
            Start-Sleep -Milliseconds 500
            if ($stopwatch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                Write-Log "Parallel operation timed out after $TimeoutSeconds seconds" -Level "WARNING"
                Get-Job -State Running | Stop-Job
                break
            }
        }
        $stopwatch.Stop()

        foreach ($job in $jobs) {
            if ($job.State -eq "Completed") {
                $results += Receive-Job -Job $job
            }
            else {
                Write-Log "Job $($job.Id) did not complete successfully (State: $($job.State))" -Level "WARNING"
            }
            Remove-Job -Job $job -Force
        }
        return $results
    }
}

# Improved module installation with version control
function Install-ModulesParallel {
    param([hashtable]$ModuleVersions)

    Write-Log "Starting parallel module installations..." -Level "INFO"

    $installBlock = {
        param($moduleInfo)
        $module = $moduleInfo.Name
        $version = $moduleInfo.Version
        try {
            if (-not (Get-Module -Name $module -ListAvailable)) {
                if ([string]::IsNullOrEmpty($version)) {
                    Install-Module -Name $module -Force -AllowClobber -Scope AllUsers
                } else {
                    Install-Module -Name $module -RequiredVersion $version -Force -AllowClobber -Scope AllUsers
                }
                Import-Module -Name $module -Force
                return "✅ Installed: $module $(if($version){"v$version"})"
            } else {
                $installedModule = Get-Module -Name $module -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
                if (-not [string]::IsNullOrEmpty($version) -and $installedModule.Version -ne $version) {
                    Install-Module -Name $module -RequiredVersion $version -Force -AllowClobber -Scope AllUsers
                    Import-Module -Name $module -RequiredVersion $version -Force
                    return "🔄 Updated: $module to v$version"
                }
                Import-Module -Name $module -Force
                return "ℹ️ Using: $module v$($installedModule.Version)"
            }
        } catch {
            return "⚠️ Failed: $module - $($_.Exception.Message)"
        }
    }

    $moduleInfoList = $ModuleVersions.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Key
            Version = $_.Value
        }
    }

    $results = Invoke-Parallel -ScriptBlock $installBlock -InputObject $moduleInfoList -ThrottleLimit 4 -TimeoutSeconds $PARALLEL_OP_TIMEOUT_SEC
    foreach ($result in $results) {
        $level = switch -Wildcard ($result) {
            "✅*" { "SUCCESS" }
            "🔄*" { "SUCCESS" }
            "ℹ️*" { "INFO" }
            default { "WARNING" }
        }
        Write-Log $result -Level $level
    }
}

# Validate PowerShell script syntax
function Test-PowerShellSyntax {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $ScriptPath -Raw), [ref]$null)
        return $true
    } catch {
        return $false
    }
}

# Add this function for checkpoint support
function Save-BuildCheckpoint {
    param(
        [string]$Stage,
        [hashtable]$StateData
    )

    $checkpointFile = Join-Path $WorkspacePath "OSDCloud_checkpoint.json"
    $checkpoint = @{
        Stage = $Stage
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        StateData = $StateData
    }

    $checkpoint | ConvertTo-Json -Depth 4 | Set-Content -Path $checkpointFile -Force
    Write-Log "Checkpoint saved: $Stage" -Level "INFO"
}

function Get-BuildCheckpoint {
    $checkpointFile = Join-Path $WorkspacePath "OSDCloud_checkpoint.json"
    if (Test-Path $checkpointFile) {
        $checkpoint = Get-Content -Path $checkpointFile -Raw | ConvertFrom-Json
        return $checkpoint
    }
    return $null
}

# Add this function to validate network connectivity
function Test-NetworkConnectivity {
    [CmdletBinding()]
    param(
        [string[]]$TestUrls = @(
            "https://www.microsoft.com",
            "https://www.powershellgallery.com",
            "https://github.com"
        )
    )

    $results = @()
    foreach ($url in $TestUrls) {
        $testResult = Test-Connection -TargetName ($url -replace 'https?://') -Count 1 -Quiet
        $results += [PSCustomObject]@{
            Url = $url
            Status = if ($testResult) { "✅ Reachable" } else { "❌ Unreachable" }
        }
    }

    # Log results
    Write-Log "Network connectivity test results:" -Level "INFO"
    $results | ForEach-Object {
        $level = if ($_.Status -like "*Unreachable*") { "WARNING" } else { "INFO" }
        Write-Log "  $($_.Url): $($_.Status)" -Level $level
    }

    # Return true if at least PowerShell Gallery is reachable
    return ($results | Where-Object { $_.Url -like "*powershellgallery*" -and $_.Status -like "*Reachable*" }).Count -gt 0
}

# Add this function before your WIM processing section
function Optimize-WimOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WimPath,
        [switch]$Compress,
        [ValidateSet("Max", "Fast", "None")]
        [string]$CompressionType = "Fast",
        [switch]$CheckIntegrity
    )

    if (-not (Test-Path $WimPath)) {
        Write-Log "WIM file not found: $WimPath" -Level "ERROR"
        return $false
    }

    try {
        # Set process priority to improve performance
        $currentProcess = Get-Process -Id $PID
        $originalPriority = $currentProcess.PriorityClass
        $currentProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High

        # Optimize memory usage for large file operations
        [System.GC]::Collect()

        if ($CheckIntegrity) {
            Write-Log "Checking WIM integrity: $WimPath" -Level "INFO"
            $checkParams = @("/CheckIntegrity", "/Wimfile:$WimPath")
            $checkProcess = Start-Process -FilePath "DISM.exe" -ArgumentList $checkParams -Wait -PassThru -NoNewWindow

            if ($checkProcess.ExitCode -ne 0) {
                Write-Log "WIM integrity check failed with code: $($checkProcess.ExitCode)" -Level "WARNING"
                return $false
            }
            Write-Log "WIM integrity verified" -Level "SUCCESS"
        }

        if ($Compress) {
            Write-Log "Optimizing WIM compression: $WimPath" -Level "INFO"
            $tempWim = "$($WimPath).temp"

            $compressArgs = switch ($CompressionType) {
                "Max" { "maximum" }
                "Fast" { "fast" }
                "None" { "none" }
                default { "fast" }
            }

            $exportParams = @("/Export-Image", "/SourceImageFile:$WimPath", "/SourceIndex:1",
                             "/DestinationImageFile:$tempWim", "/Compress:$compressArgs")

            $exportProcess = Start-Process -FilePath "DISM.exe" -ArgumentList $exportParams -Wait -PassThru -NoNewWindow

            if ($exportProcess.ExitCode -ne 0) {
                Write-Log "WIM compression failed with code: $($exportProcess.ExitCode)" -Level "ERROR"
                return $false
            }

            # Replace original with optimized version
            Move-Item -Path $tempWim -Destination $WimPath -Force
            Write-Log "WIM optimized with $CompressionType compression" -Level "SUCCESS"
        }

        return $true
    }
    catch {
        Write-Log "WIM optimization error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    finally {
        # Restore process priority
        if ($currentProcess -and $originalPriority) {
            $currentProcess.PriorityClass = $originalPriority
        }
    }
}

# ============================
# [1] Initial Validation
# ============================
if (-not (Test-Administrator)) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INVALID_PARAMS -Message "This script requires administrative privileges. Please restart as administrator."
}

if (-not (Test-Dependencies)) {
    Exit-Script -ExitCode $SCRIPT_EXIT_MISSING_PREREQS -Message "Prerequisite check failed. Please install required components before continuing."
}

# Validate parameters
if (-not $WorkspacePath -or -not $CustomFilesPath) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INVALID_PARAMS -Message "WorkspacePath and CustomFilesPath must be provided and valid."
}

# Check disk space for workspace path
if (-not (Test-DiskSpace -Path $WorkspacePath -RequiredGB $MIN_WORKSPACE_SPACE_GB -Operation "Workspace Creation")) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INSUFFICIENT_SPACE -Message "Insufficient disk space for workspace operations."
}

# Check disk space for temp operations
$tempPath = [System.IO.Path]::GetTempPath()
if (-not (Test-DiskSpace -Path $tempPath -RequiredGB $MIN_TEMP_SPACE_GB -Operation "Temporary Operations")) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INSUFFICIENT_SPACE -Message "Insufficient disk space for temporary operations."
}

# ============================
# [2] Initialize & Report Basic Info
# ============================
Write-Log "=======================================================" -Level "INFO"
Write-Log "Starting OSDCloud Modular Deployment v2.0" -Level "INFO"
Write-Log "Workspace Path: $WorkspacePath" -Level "INFO"
Write-Log "Custom Files Path: $CustomFilesPath" -Level "INFO"
Write-Log "Log Path: $LogPath" -Level "INFO"
Write-Log "Template Name: $TemplateName" -Level "INFO"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
Write-Log "=======================================================" -Level "INFO"

# ============================
# [3] Pre-Setup & Install Modules
# ============================
Write-Log "Starting module installations..." -Level "INFO"
try {
    Install-Script -Name Get-WindowsAutoPilotInfo -Force -Scope AllUsers -ErrorAction Stop
    Write-Log "Installed Get-WindowsAutoPilotInfo script" -Level "SUCCESS"
} catch {
    Write-Log "Could not install Get-WindowsAutoPilotInfo: $($_.Exception.Message)" -Level "WARNING"
}

Install-ModulesParallel -ModuleVersions $requiredModulesWithVersions

if (Get-Module -ListAvailable -Name 'OSD') {
    Import-Module OSD -Global -Force
    Write-Log "OSD module loaded successfully" -Level "SUCCESS"
} else {
    Exit-Script -ExitCode $SCRIPT_EXIT_MISSING_PREREQS -Message "OSD module is not available. Aborting."
}

# ============================
# [4] Define Paths & Variables
# ============================
$templateBasePath = "$env:ProgramData\OSDCloud\Templates"
$templatePath     = Join-Path $templateBasePath $TemplateName
$bootWimPath      = "$templatePath\Media\sources\boot.wim"
$pwsh7ZipPath     = "$PSScriptRoot\PowerShell-7.5.0-win-x64.zip"
$pwsh7ScriptPath  = "$PSScriptRoot\winpe_pwsh7_add.ps1"
$wimFile          = "$CustomFilesPath\Windows11_24H2_Custom.wim"
$mediaFolder      = "$WorkspacePath\Media"
$osFolder         = "$mediaFolder\OSDCloud\OS"
$automateFolder   = "$mediaFolder\OSDCloud\Automate"
$modularFolders   = @("Main", "Autopilot", "Modules", "Assets")
$modularPaths     = @()
$foldersToCreate  = @($WorkspacePath, $mediaFolder, $CustomFilesPath, $osFolder, $automateFolder)

# Create required folders
foreach ($folder in $foldersToCreate) {
    New-Folder -Path $folder
}

# ============================
# [5] Create Template with WinRE + PowerShell 7 + Module Injection
# ============================
Write-Log "Creating OSDCloud Template: $TemplateName" -Level "INFO"
try {
    New-Folder -Path $templateBasePath
    Write-Progress -Activity "Creating Template" -Status "Creating base template with WinRE" -PercentComplete 20
    New-OSDCloudTemplate -Name $TemplateName -WinRE -Add7Zip
    Write-Log "Template created successfully" -Level "SUCCESS"
    if (-not (Test-Path $bootWimPath)) {
        throw "boot.wim not found at: $bootWimPath"
    }

    $tempFolder  = "$env:TEMP\OSDCloud_PWSH7_Temp"
    $mountFolder = "$tempFolder\Mount"
    New-Folder -Path $tempFolder
    New-Folder -Path $mountFolder
    $script:mountedWimPath = $mountFolder  # For cleanup trap

    # Verify disk space for WIM mounting
    if (-not (Test-DiskSpace -Path $tempFolder -RequiredGB $SPACE_REQUIREMENTS["WimMount"] -Operation "WIM Mounting")) {
        throw "Insufficient disk space for WIM mounting operations."
    }

    Write-Progress -Activity "Creating Template" -Status "Copying boot.wim for modification" -PercentComplete 40
    Copy-IfDifferent -Source $bootWimPath -Destination "$tempFolder\boot.wim"

    if (-not (Test-Path $pwsh7ZipPath)) {
        throw "PowerShell 7 ZIP not found at: $pwsh7ZipPath"
    }

    if (Test-Path $pwsh7ScriptPath) {
        Write-Log "Adding PowerShell 7 to boot.wim..." -Level "INFO"
        if (-not (Get-Command Dism.exe -ErrorAction SilentlyContinue)) {
            throw "DISM not found. Please ensure Windows ADK is installed."
        }

        # Add this to the PowerShell 7 installation section
        if (Test-Path $pwsh7ZipPath) {
            # Validate PowerShell 7 zip file hash
            $expectedHash = "91A61A363ECB8F40A20E7CEFCA6BAC9ACBE9BC16FD40EAB9D1BE674A148C68F3" # Update with actual hash
            $actualHash = (Get-FileHash -Path $pwsh7ZipPath -Algorithm SHA256).Hash

            if ($actualHash -ne $expectedHash) {
                Write-Log "WARNING: PowerShell 7 ZIP file hash doesn't match expected value!" -Level "WARNING"
                Write-Log "Expected: $expectedHash" -Level "WARNING"
                Write-Log "Actual:   $actualHash" -Level "WARNING"

                if (-not (Confirm-Yes "Continue with potentially modified PowerShell 7 package? (Y/N)")) {
                    throw "PowerShell 7 package integrity check failed"
                }
            } else {
                Write-Log "PowerShell 7 package integrity verified" -Level "SUCCESS"
            }
        }

        Write-Progress -Activity "Creating Template" -Status "Mounting boot.wim" -PercentComplete 50
        $mountProcess = Start-Process -FilePath "Dism.exe" -ArgumentList "/Mount-Wim /WimFile:`"$tempFolder\boot.wim`" /index:1 /MountDir:`"$mountFolder`"" -NoNewWindow -PassThru -Wait
        if ($mountProcess.ExitCode -ne 0) {
            throw "Failed to mount WIM file. DISM exit code: $($mountProcess.ExitCode)"
        }

        $ps7MountDir = "$mountFolder\Program Files\PowerShell\7"
        New-Folder -Path $ps7MountDir

        try {
            Write-Progress -Activity "Creating Template" -Status "Extracting PowerShell 7" -PercentComplete 60
            Expand-Archive -Path $pwsh7ZipPath -DestinationPath $ps7MountDir -Force
            Write-Log "PowerShell 7 extracted to WIM" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to extract PowerShell 7: $($_.Exception.Message)" -Level "ERROR"
            Start-Process -FilePath "Dism.exe" -ArgumentList "/Unmount-Wim /MountDir:`"$mountFolder`" /discard" -NoNewWindow -Wait
            $script:mountedWimPath = $null
            throw
        }

        # Inject PowerShell modules into the mounted image
        $modulesToInject = @("OSD", "Microsoft.Graph", "Az", "PackageManagement", "PSWindowsUpdate",
            "PowerShellGet", "Microsoft.Entra", "Microsoft.Graph.Beta", "Microsoft.Entra.Beta")
        Write-Log "Injecting PowerShell modules into boot.wim..." -Level "INFO"
        Write-Progress -Activity "Creating Template" -Status "Injecting modules" -PercentComplete 70
        $moduleCounter = 0

        foreach ($module in $modulesToInject) {
            $moduleCounter++
            $modulePercent = 70 + (10 * ($moduleCounter / $modulesToInject.Count))
            Write-Progress -Activity "Creating Template" -Status "Injecting module: $module" -PercentComplete $modulePercent

            $requiredVersion = $requiredModulesWithVersions[$module]
            if ($requiredVersion) {
                $modulePath = (Get-Module -Name $module -RequiredVersion $requiredVersion -ListAvailable | Select-Object -First 1).ModuleBase
            } else {
                $modulePath = (Get-Module -Name $module -ListAvailable | Select-Object -First 1).ModuleBase
            }

            if ($modulePath) {
                $moduleParentPath = Split-Path -Parent $modulePath
                $moduleName = Split-Path -Leaf $modulePath
                $destPath = "$mountFolder\Program Files\WindowsPowerShell\Modules\$moduleName"
                try {
                    New-Folder -Path $destPath
                    Copy-Item -Path "$moduleParentPath\$moduleName\*" -Destination $destPath -Recurse -Force
                    Write-Log "Injected module: $moduleName $(if($requiredVersion){"v$requiredVersion"})" -Level "SUCCESS"
                } catch {
                    Write-Log "Failed to inject module $moduleName $($_.Exception.Message)" -Level "WARNING"
                }
            } else {
                Write-Log "Module not found: $module $(if($requiredVersion){"v$requiredVersion"})" -Level "WARNING"
            }
        }

        # ============================
        # Copy Modular Scripts into WinPE with validation
        # ============================
        Write-Log "Adding Modular Scripts to boot.wim..." -Level "INFO"
        Write-Progress -Activity "Creating Template" -Status "Adding modular scripts" -PercentComplete 85
        $winpePath = "$mountFolder\OSDCloud\Automate"
        New-Folder -Path $winpePath
        $scriptCounter = 0

        foreach ($folder in $modularFolders) {
            $scriptCounter++
            $scriptPercent = 85 + (5 * ($scriptCounter / $modularFolders.Count))
            Write-Progress -Activity "Creating Template" -Status "Adding scripts: $folder" -PercentComplete $scriptPercent

            $src = Join-Path $CustomFilesPath $folder
            $dst = Join-Path $winpePath $folder
            New-Folder -Path $dst

            if (Test-Path $src) {
                # Validate PowerShell scripts before copying
                $psScripts = Get-ChildItem -Path $src -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
                $invalidScripts = @()

                foreach ($script in $psScripts) {
                    if (-not (Test-PowerShellSyntax -ScriptPath $script.FullName)) {
                        $invalidScripts += $script.Name
                        Write-Log "Invalid script syntax: $($script.FullName)" -Level "WARNING"
                    }

                    # Basic malware scan - check for suspicious commands
                    $scriptContent = Get-Content -Path $script.FullName -Raw
                    $suspiciousPatterns = @(
                        'Invoke-Expression.*\$\(',
                        'IEX.*\$\(',
                        'Download-File.*http://',
                        'New-Object.*Net.WebClient',
                        'Start-Process.*-WindowStyle Hidden'
                    )

                    foreach ($pattern in $suspiciousPatterns) {
                        if ($scriptContent -match $pattern) {
                            Write-Log "Potentially suspicious code in $($script.Name): $pattern" -Level "WARNING"
                        }
                    }
                }

                if ($invalidScripts.Count -gt 0) {
                    Write-Log "Found $($invalidScripts.Count) potentially problematic scripts in $folder" -Level "WARNING"
                    if (-not (Confirm-Yes "Continue copying scripts with potential issues? (Y/N)")) {
                        Write-Log "Script validation failed for folder: $folder - aborting" -Level "ERROR"
                        throw "Script validation failed for folder: $folder"
                    }
                }

                Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force
                Write-Log "Injected modular scripts: $folder" -Level "SUCCESS"
            } else {
                Write-Log "Missing folder: $src" -Level "WARNING"
            }
        }

        try {
                    Write-Progress -Activity "Creating Template" -Status "Saving WIM file" -PercentComplete 95
            # Use timeout parameter for DISM operation
            $dismProcess = Start-Process -FilePath "Dism.exe" -ArgumentList "/Unmount-Wim /MountDir:`"$mountFolder`" /commit" -NoNewWindow -PassThru
            $dismTimeout = New-TimeSpan -Seconds $DISM_OPERATION_TIMEOUT_SEC
            $dismComplete = $dismProcess.WaitForExit($dismTimeout.TotalMilliseconds)

            if (-not $dismComplete) {
                Write-Log "DISM operation timed out after $DISM_OPERATION_TIMEOUT_SEC seconds" -Level "ERROR"
                Stop-Process -Id $dismProcess.Id -Force -ErrorAction SilentlyContinue
                $script:mountedWimPath = $null
                throw "DISM operation timed out"
            }

            if ($dismProcess.ExitCode -ne 0) {
                throw "Failed to save WIM. DISM exit code: $($dismProcess.ExitCode)"
            }

            $script:mountedWimPath = $null
            Write-Log "WIM file saved with PowerShell 7, modules, and modular scripts" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to save WIM: $($_.Exception.Message)" -Level "ERROR"
            if ($script:mountedWimPath) {
                Start-Process -FilePath "Dism.exe" -ArgumentList "/Unmount-Wim /MountDir:`"$mountFolder`" /discard" -NoNewWindow -Wait
                $script:mountedWimPath = $null
            }
            throw
        }

        Write-Progress -Activity "Creating Template" -Status "Finalizing template" -PercentComplete 98
        Copy-IfDifferent -Source "$tempFolder\boot.wim" -Destination $bootWimPath
        Write-Log "Updated boot.wim with PS7, modules, and modular scripts" -Level "SUCCESS"
    } else {
        Write-Log "PS7 script not found: $pwsh7ScriptPath" -Level "WARNING"
    }
    Write-Progress -Activity "Creating Template" -Completed
} catch {
    Write-Log "Template build failed: $($_.Exception.Message)" -Level "ERROR"
    Write-Progress -Activity "Creating Template" -Completed
    Exit-Script -ExitCode $SCRIPT_EXIT_FAILURE -Message "Template build failed"
} finally {
    if ($script:mountedWimPath -and (Test-Path $script:mountedWimPath)) {
        try {
            Start-Process -FilePath "Dism.exe" -ArgumentList "/Unmount-Wim /MountDir:`"$script:mountedWimPath`" /discard" -NoNewWindow -Wait
        } catch { }
        $script:mountedWimPath = $null
    }
    if (Test-Path $tempFolder) {
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Temp folder cleanup completed" -Level "INFO"
    }
}

# ============================
# [6] Create Workspace & Clean
# ============================
Write-Log "Creating OSDCloud Workspace..." -Level "INFO"
Write-Progress -Activity "Creating Workspace" -Status "Initializing workspace" -PercentComplete 10

# Check disk space before workspace creation
if (-not (Test-DiskSpace -Path $WorkspacePath -RequiredGB $SPACE_REQUIREMENTS["WorkspaceBase"] -Operation "Workspace Creation")) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INSUFFICIENT_SPACE -Message "Insufficient disk space for workspace creation"
}

try {
    New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
    Write-Log "Workspace created" -Level "SUCCESS"
} catch {
    Write-Log "Failed with custom template, retrying default..." -Level "WARNING"
    try {
        New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
        Write-Log "Workspace created using default template" -Level "SUCCESS"
    } catch {
        Write-Log "Could not create workspace: $($_.Exception.Message)" -Level "ERROR"
        Write-Progress -Activity "Creating Workspace" -Completed
        Exit-Script -ExitCode $SCRIPT_EXIT_FAILURE -Message "Workspace creation failed"
    }
}

Write-Progress -Activity "Creating Workspace" -Status "Cleaning workspace" -PercentComplete 50
$keepDirs  = @('boot','efi','en-us','sources','fonts','resources','OSDCloud')
$mediaPaths = @(
    "$WorkspacePath\Media",
    "$WorkspacePath\Media\Boot",
    "$WorkspacePath\Media\EFI\Microsoft\Boot"
)
foreach ($p in $mediaPaths) {
    if (Test-Path $p) {
        Get-ChildItem -Path $p -Directory -Exclude $keepDirs -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Progress -Activity "Creating Workspace" -Completed
Write-Log "Workspace cleaning completed" -Level "INFO"

# ============================
# [7] Define Modular Scripts Paths
# ============================
Write-Log "Setting up Modular Scripts paths..." -Level "INFO"
$modularPaths = @()
foreach ($folder in $modularFolders) {
    $dst = Join-Path $automateFolder $folder
    New-Folder -Path $dst
    $modularPaths += $dst
    Write-Log "Modular script path defined: $dst" -Level "SUCCESS"
}

# ============================
# [8] Create startnet.cmd
# ============================
Write-Log "Creating startnet.cmd..." -Level "INFO"
$startnetContent = @"
@echo off
wpeinit
set ENTRY_SCRIPT=
IF EXIST X:\OSDCloud\Automate\Main\iTechDcUI.ps1 (set ENTRY_SCRIPT=X:\OSDCloud\Automate\Main\iTechDcUI.ps1)
IF NOT "%ENTRY_SCRIPT%"=="" (
    IF EXIST %ProgramFiles%\PowerShell\7\pwsh.exe (
        %ProgramFiles%\PowerShell\7\pwsh.exe -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    ) ELSE (
        PowerShell -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    )
)
"@
$script:startnetContent = $startnetContent
Write-Log "startnet.cmd created" -Level "SUCCESS"

# ============================
# [9] Process Custom OS WIM File (if any)
# ============================
$useCustomWim = $false
Write-Progress -Activity "Processing WIM" -Status "Checking for custom WIM" -PercentComplete 50
if (Test-Path $wimFile) {
    # Check disk space before WIM processing - updated for large WIM files
    if (-not (Test-DiskSpace -Path $osFolder -RequiredGB $SPACE_REQUIREMENTS["WimProcessing"] -Operation "WIM Processing")) {
        Exit-Script -ExitCode $SCRIPT_EXIT_INSUFFICIENT_SPACE -Message "Insufficient disk space for processing 40GB+ custom WIM file"
    }

    Write-Progress -Activity "Processing WIM" -Status "Building custom OS WIM file" -PercentComplete 75
    try {
        # Instead of a simple file copy, invoke New-OSDCloudOSWimFile per OSD-help.xml documentation
        # Adding timeout handling
        $newWimJob = Start-Job -ScriptBlock {
            param($osName, $osEdition, $osLanguage, $osActivation, $outputFile)
            New-OSDCloudOSWimFile -OSName $osName -OSEdition $osEdition -OSLanguage $osLanguage -OSActivation $osActivation -OutputFile $outputFile
        } -ArgumentList "Windows 11 24H2 x64", "Enterprise", "en-us", "Volume", "$osFolder\CustomImage.wim"

        # Increase timeout for large WIM processing
        $extendedTimeout = $DISM_OPERATION_TIMEOUT_SEC * 2  # Double the timeout for large WIM operations
        $waitResult = Wait-Job -Job $newWimJob -Timeout $extendedTimeout
        if ($null -eq $waitResult) {
            Write-Log "WIM creation operation timed out after $extendedTimeout seconds" -Level "WARNING"
            Stop-Job -Job $newWimJob
            throw "WIM creation operation timed out - consider increasing timeout for large WIM files"
        }

        Receive-Job -Job $newWimJob
        $useCustomWim = $true
        Write-Log "Custom OS WIM file (40GB+) created using New-OSDCloudOSWimFile" -Level "SUCCESS"
    } catch {
        Write-Log "Failed to create Custom OS WIM file: $($_.Exception.Message)" -Level "ERROR"
        $useCustomWim = $false
    } finally {
        Remove-Job -Job $newWimJob -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Log "No Custom WIM provided, using default OS image" -Level "INFO"
}
Write-Progress -Activity "Processing WIM" -Completed

# ============================
# [10] Final WinPE Customization
# ============================
Write-Log "Finalizing WinPE..." -Level "INFO"
Write-Progress -Activity "Customizing WinPE" -Status "Applying customizations" -PercentComplete 25
try {
    # Updated per documentation: passing only the required parameters
    Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath -Startnet $script:startnetContent -CloudDriver "*" -Add7Zip -WirelessConnect -Verbose
    Write-Log "WinPE customized" -Level "SUCCESS"
} catch {
    Write-Log "WinPE customization failed: $($_.Exception.Message)" -Level "ERROR"
    Exit-Script -ExitCode $SCRIPT_EXIT_FAILURE -Message "WinPE customization failed"
}
Write-Progress -Activity "Customizing WinPE" -Completed

# ============================
# [11] ISO Generation
# ============================
Write-Log "Generating ISO..." -Level "INFO"
Write-Progress -Activity "Creating ISO" -Status "Building ISO file" -PercentComplete 50

# Check disk space before ISO creation
if (-not (Test-DiskSpace -Path $WorkspacePath -RequiredGB $SPACE_REQUIREMENTS["ISO"] -Operation "ISO Creation")) {
    Exit-Script -ExitCode $SCRIPT_EXIT_INSUFFICIENT_SPACE -Message "Insufficient disk space for ISO creation"
}

try {
    $isoJob = Start-Job -ScriptBlock {
        param($workspacePath)
        New-OSDCloudISO -WorkspacePath $workspacePath
    } -ArgumentList $WorkspacePath

    $waitResult = Wait-Job -Job $isoJob -Timeout ($DISM_OPERATION_TIMEOUT_SEC * 2)
    if ($null -eq $waitResult) {
        Write-Log "ISO creation timed out after $($DISM_OPERATION_TIMEOUT_SEC * 2) seconds" -Level "WARNING"
        Stop-Job -Job $isoJob
        throw "ISO creation timed out"
    }

    Receive-Job -Job $isoJob
    Write-Log "ISO created at: $WorkspacePath\OSDCloud.iso" -Level "SUCCESS"
} catch {
    Write-Log "ISO generation failed: $($_.Exception.Message)" -Level "ERROR"
    Exit-Script -ExitCode $SCRIPT_EXIT_FAILURE -Message "ISO generation failed"
} finally {
    Remove-Job -Job $isoJob -Force -ErrorAction SilentlyContinue
}
Write-Progress -Activity "Creating ISO" -Completed

# Add parameter for ISO compression
if ($CompressISO -and (Test-Path "$WorkspacePath\OSDCloud.iso")) {
    Write-Log "Compressing ISO file..." -Level "INFO"
    try {
        $compressedISO = "$WorkspacePath\OSDCloud_compressed.iso"

        # Use 7-Zip if available, otherwise use Windows built-in compression
        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            $compressionProcess = Start-Process -FilePath "7z.exe" -ArgumentList "a -tzip `"$compressedISO`" `"$WorkspacePath\OSDCloud.iso`"" -NoNewWindow -PassThru -Wait
            if ($compressionProcess.ExitCode -eq 0) {
                Write-Log "ISO compressed successfully with 7-Zip" -Level "SUCCESS"
                Move-Item -Path $compressedISO -Destination "$WorkspacePath\OSDCloud.iso" -Force
            }
        } else {
            # Use built-in compression
            $originalSize = (Get-Item "$WorkspacePath\OSDCloud.iso").Length
            Compress-Archive -Path "$WorkspacePath\OSDCloud.iso" -DestinationPath "$WorkspacePath\OSDCloud.zip" -Force
            Rename-Item -Path "$WorkspacePath\OSDCloud.zip" -NewName "OSDCloud_compressed.iso" -Force
            $compressedSize = (Get-Item "$WorkspacePath\OSDCloud_compressed.iso").Length
            $savingsPercent = [math]::Round((1 - ($compressedSize / $originalSize)) * 100, 2)

            Write-Log "ISO compressed successfully. Space savings: $savingsPercent%" -Level "SUCCESS"
            Move-Item -Path "$WorkspacePath\OSDCloud_compressed.iso" -Destination "$WorkspacePath\OSDCloud.iso" -Force
        }
    } catch {
        Write-Log "ISO compression failed: $($_.Exception.Message)" -Level "WARNING"
    }
}

# ============================
# [12] USB Boot Creation
# ============================
Write-Log "USB Creation Optional..." -Level "INFO"
if (Confirm-Yes "Would you like to create a USB boot media now? (Y/N)") {
    # Check disk space before USB creation
    $usbDrive = Read-Host "Enter USB drive letter (e.g., E:)"
    if (-not (Test-Path -Path $usbDrive)) {
        Write-Log "USB drive $usbDrive not found" -Level "ERROR"
    } else {
        if (-not (Test-DiskSpace -Path $usbDrive -RequiredGB $SPACE_REQUIREMENTS["ISO"] -Operation "USB Creation")) {
            Write-Log "Insufficient disk space for USB creation" -Level "ERROR"
        } else {
            Write-Progress -Activity "Creating USB" -Status "Preparing USB media" -PercentComplete 25
            try {
                $usbJob = Start-Job -ScriptBlock {
                    param($workspacePath, $startnet)
                    New-OSDCloudUSB -WorkspacePath $workspacePath -Startnet $startnet -CloudDriver "*" -Add7Zip -WirelessConnect -Verbose
                } -ArgumentList $WorkspacePath, $script:startnetContent

                $waitResult = Wait-Job -Job $usbJob -Timeout ($DISM_OPERATION_TIMEOUT_SEC * 2)
                if ($null -eq $waitResult) {
                    Write-Log "USB creation timed out after $($DISM_OPERATION_TIMEOUT_SEC * 2) seconds" -Level "WARNING"
                    Stop-Job -Job $usbJob
                    throw "USB creation timed out"
                }

                Receive-Job -Job $usbJob
                Write-Log "USB boot media created!" -Level "SUCCESS"
            } catch {
                Write-Log "USB creation failed: $($_.Exception.Message)" -Level "ERROR"
            } finally {
                Remove-Job -Job $usbJob -Force -ErrorAction SilentlyContinue
            }
            Write-Progress -Activity "Creating USB" -Completed
        }
    }
}

# ============================
# [13] Final Summary
# ============================
$elapsedTime = New-TimeSpan -Start $script:startTime -End (Get-Date)
$formattedTime = "{0:D2}h:{1:D2}m:{2:D2}s" -f $elapsedTime.Hours, $elapsedTime.Minutes, $elapsedTime.Seconds
Write-Log "=======================================================" -Level "INFO"
Write-Log "✅ Deployment Complete!" -Level "SUCCESS"
Write-Log "ISO Path: $WorkspacePath\OSDCloud.iso" -Level "INFO"
Write-Log "Custom WIM Used: $useCustomWim" -Level "INFO"
Write-Log "Modular Scripts Injected: $($modularPaths.Count) folders" -Level "INFO"
Write-Log "Execution Time: $formattedTime" -Level "INFO"
Write-Log "Log File: $LogPath" -Level "INFO"
Write-Log "=======================================================" -Level "INFO"

# Verify all logs are written to disk
Write-LogBuffer

# Check for the OSDCloud.iso file to confirm success
$isoExists = Test-Path "$WorkspacePath\OSDCloud.iso"
if (-not $isoExists) {
    Write-Log "Warning: OSDCloud.iso file not found at expected location. Process may have failed." -Level "WARNING"
}

# Final status based on error state and ISO file existence
if ($script:errorOccurred -or -not $isoExists) {
    Exit-Script -ExitCode $SCRIPT_EXIT_FAILURE -Message "Script completed with errors. Check the log file for details."
} else {
    Exit-Script -ExitCode $SCRIPT_EXIT_SUCCESS -Message "Script completed successfully."
}