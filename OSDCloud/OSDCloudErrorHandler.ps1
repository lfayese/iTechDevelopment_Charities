<#
.SYNOPSIS
    Provides standardized error handling and logging functionality for OSDCloud GUI.
.DESCRIPTION
    The OSDCloud Error Handling and Logging Module implements consistent logging, error handling,
    and diagnostic capabilities across the OSDCloud GUI framework. It provides functions for
    structured logging, error management, and system compatibility checks.
.NOTES
    Module Name: OSDCloud.ErrorHandling
    Author: iTech Development
    Created: March 30, 2025
    Version: 1.0
    License: MIT
#>

# Define global variables for logging
$script:LogLevels = @{"Debug" = 0; "Info" = 1; "Warning" = 2; "Error" = 3; "Fatal" = 4}
$script:LogPath = "$env:TEMP\OSDCloud\Logs"
$script:LogFile = "OSDCloud_GUI_$(Get-Date -Format 'yyyyMMdd').log"
$script:LogLevel = "Info" # Possible values: Debug, Info, Warning, Error, Fatal

# Initialize logging
function Initialize-OSDCloudLogging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogDirectory = "$env:TEMP\OSDCloud\Logs",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFileName = "OSDCloud_GUI_$(Get-Date -Format 'yyyyMMdd').log",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Fatal")]
        [string]$Level = "Info"
    )
    
    try {
        # Set global variables
        $script:LogPath = $LogDirectory
        $script:LogFile = $LogFileName
        $script:LogLevel = $Level
        
        # Create log directory if it doesn't exist
        if (-not (Test-Path -Path $script:LogPath)) {
            New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        }
        
        # Implement log rotation
        $maxLogFiles = 5
        $logFiles = Get-ChildItem -Path $script:LogPath -Filter "OSDCloud_GUI_*.log" | Sort-Object LastWriteTime -Descending
        if ($logFiles.Count -gt $maxLogFiles) {
            $logFiles | Select-Object -Skip $maxLogFiles | Remove-Item -Force
        }
        
        # Create log file if it doesn't exist
        $fullLogPath = Join-Path -Path $script:LogPath -ChildPath $script:LogFile
        if (-not (Test-Path -Path $fullLogPath)) {
            New-Item -Path $fullLogPath -ItemType File -Force | Out-Null
        }
        
        # Log initialization
        Write-Log -Message "OSDCloud GUI Logging initialized at level: $Level" -Level "Info"
        
        return $true
    }
    catch {
        Write-Warning "Failed to initialize logging: $_"
        return $false
    }
}

# Write to log file
function Write-OSDCloudLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Fatal")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )
    
    # Define log levels
    $logLevels = @{
        "Debug"   = 0
        "Info"    = 1
        "Warning" = 2
        "Error"   = 3
        "Fatal"   = 4
    }
    
    # Check if message should be logged based on current log level
    if ($logLevels[$Level] -ge $logLevels[$script:LogLevel]) {
        # Format the log entry
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Write to log file
        $fullLogPath = Join-Path -Path $script:LogPath -ChildPath $script:LogFile
        Add-Content -Path $fullLogPath -Value $logEntry
        
        # Write to console if not suppressed
        if (-not $NoConsole) {
            $consoleColor = switch ($Level) {
                "Debug"   { "Gray" }
                "Info"    { "White" }
                "Warning" { "Yellow" }
                "Error"   { "Red" }
                "Fatal"   { "DarkRed" }
                default   { "White" }
            }
            
            Write-Host $logEntry -ForegroundColor $consoleColor
        }
    }
}

# Handle errors with standardized approach
function Write-OSDCloudError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = "OSDCloud GUI",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Warning", "Error", "Fatal")]
        [string]$Level = "Error",
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowDialog
    )
    
    # Construct error message
    $errorMessage = "$Message"
    
    # Add error record details if available
    if ($ErrorRecord) {
        $errorMessage += " | ErrorDetails: $($ErrorRecord.Exception.Message)"
    }
    
    # Log the error
    Write-OSDCloudLog -Message $errorMessage -Level $Level
    
    # Show error dialog if requested
    if ($ShowDialog) {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            "OSDCloud $Level",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Check for required dependencies
function Test-OSDCloudDependency {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion,
        
        [Parameter(Mandatory = $false)]
        [switch]$Required,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowDialog
    )
    
    $dependencyFound = $false
    
    # Check for PowerShell module
    if ($Name -like "Module:*") {
        $moduleName = $Name.Replace("Module:", "").Trim()
        $module = Get-Module -Name $moduleName -ListAvailable
        
        if ($module) {
            $dependencyFound = $true
            
            if ($MinimumVersion) {
                $dependencyFound = [version]($module | Sort-Object Version -Descending | Select-Object -First 1).Version -ge [version]$MinimumVersion
            }
        }
        
        Write-OSDCloudLog -Message "Dependency check: Module '$moduleName' $(if($dependencyFound){'found'}else{'not found'})$(if($MinimumVersion){" (Required version: $MinimumVersion)"})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
    }
    # Check for executable
    elseif ($Name -like "Exe:*") {
        $exeName = $Name.Replace("Exe:", "").Trim()
        $exePath = Get-Command -Name $exeName -ErrorAction SilentlyContinue
        
        $dependencyFound = $null -ne $exePath
        
        Write-OSDCloudLog -Message "Dependency check: Executable '$exeName' $(if($dependencyFound){'found'}else{'not found'})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
    }
    # Check for default PowerShell module
    else {
        $module = Get-Module -Name $Name -ListAvailable
        
        if ($module) {
            $dependencyFound = $true
            
            if ($MinimumVersion) {
                $dependencyFound = [version]($module | Sort-Object Version -Descending | Select-Object -First 1).Version -ge [version]$MinimumVersion
            }
        }
        
        Write-OSDCloudLog -Message "Dependency check: Module '$Name' $(if($dependencyFound){'found'}else{'not found'})$(if($MinimumVersion){" (Required version: $MinimumVersion)"})" -Level $(if($dependencyFound){"Info"}else{"Warning"})
    }
    
    # Handle required dependency not found
    if ($Required -and -not $dependencyFound) {
        $errorMessage = "Required dependency '$Name' not found."
        
        Write-Error -Message $errorMessage -Level "Fatal" -ShowDialog:$ShowDialog
        
        if ($ShowDialog) {
            [System.Windows.Forms.MessageBox]::Show(
                "OSDCloud GUI requires $Name to function properly. Please install the missing dependency and try again.",
                "Missing Dependency",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
    
    return $dependencyFound
}

# Search for custom WIM files with error handling
function Find-OSDCloudCustomWimFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$SearchPaths = @("X:\OSDCloud\custom.wim", "C:\OSDCloud\custom.wim", "D:\OSDCloud\custom.wim", "E:\OSDCloud\custom.wim"),
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeUSB
    )
    
    Write-OSDCloudLog -Message "Searching for custom WIM files..." -Level "Info"
    
    $customWimFiles = @()
    
    # Search standard paths
    foreach ($path in $SearchPaths) {
        try {
            if (Test-Path $path) {
                Write-OSDCloudLog -Message "Found custom WIM at: $path" -Level "Info"
                
                try {
                    $wimInfo = Get-WindowsImage -ImagePath $path -Index 1 -ErrorAction Stop
                    
                    $customWimFiles += [PSCustomObject]@{
                        Path = $path
                        ImageName = $wimInfo.ImageName
                        ImageDescription = $wimInfo.ImageDescription
                        Size = $wimInfo.ImageSize
                        Valid = $true
                    }
                }
                catch {
                    Write-OSDCloudError -Message "Found WIM file at $path but it appears to be invalid" -ErrorRecord $_ -Level "Warning"
                    
                    $customWimFiles += [PSCustomObject]@{
                        Path = $path
                        ImageName = "Invalid WIM"
                        ImageDescription = "Could not read WIM file"
                        Size = (Get-Item $path).Length
                        Valid = $false
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Error checking path $path" -ErrorRecord $_ -Level "Warning"
        }
    }
    
    # Search USB drives if requested
    if ($IncludeUSB) {
        Write-OSDCloudLog -Message "Searching USB drives for custom WIM files..." -Level "Info"
        
        try {
            $usbDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }
            
            foreach ($drive in $usbDrives) {
                $driveLetter = $drive.DriveLetter
                $usbWimPath = "${driveLetter}:\OSDCloud\custom.wim"
                
                try {
                    if (Test-Path $usbWimPath) {
                        Write-OSDCloudLog -Message "Found custom WIM on USB drive: $usbWimPath" -Level "Info"
                        
                        try {
                            $wimInfo = Get-WindowsImage -ImagePath $usbWimPath -Index 1 -ErrorAction Stop
                            
                            $customWimFiles += [PSCustomObject]@{
                                Path = $usbWimPath
                                ImageName = $wimInfo.ImageName
                                ImageDescription = $wimInfo.ImageDescription
                                Size = $wimInfo.ImageSize
                                Valid = $true
                            }
                        }
                        catch {
                            Write-Error -Message "Found WIM file at $usbWimPath but it appears to be invalid" -ErrorRecord $_ -Level "Warning"
                            
                            $customWimFiles += [PSCustomObject]@{
                                Path = $usbWimPath
                                ImageName = "Invalid WIM"
                                ImageDescription = "Could not read WIM file"
                                Size = (Get-Item $usbWimPath).Length
                                Valid = $false
                            }
                        }
                    }
                }
                catch {
                    Write-Error -Message "Error checking USB path $usbWimPath" -ErrorRecord $_ -Level "Warning"
                }
            }
        }
        catch {
            Write-Error -Message "Error enumerating USB drives" -ErrorRecord $_ -Level "Warning"
        }
    }
    
    Write-OSDCloudLog -Message "Found $($customWimFiles.Count) custom WIM file(s)" -Level "Info"
    return $customWimFiles
}

# Check hardware compatibility with detailed reporting
function Test-OSDCloudHardwareCompatibility {
    [CmdletBinding()]
    param()
    
    Write-Log -Message "Checking hardware compatibility..." -Level "Info"
    
    $compatibility = [PSCustomObject]@{
        IsCompatible = $true
        TPM20 = $false
        SupportedCPU = $true
        SecureBoot = $false
        MinimumRAM = $false
        MinimumStorage = $false
        UEFI = $false
        Details = @()
    }
    
    # Check TPM 2.0
    try {
        $tpmVersion = (Get-WmiObject -Namespace 'root\cimv2\security\microsofttpm' -Query 'Select * from win32_tpm' -ErrorAction Stop).SpecVersion
        $compatibility.TPM20 = $tpmVersion -like "2.*"
        
        $status = if ($compatibility.TPM20) { "✓ Found TPM $tpmVersion" } else { "✗ TPM 2.0 not found (detected: $tpmVersion)" }
        $compatibility.Details += $status
        Write-Log -Message $status -Level $(if($compatibility.TPM20){"Info"}else{"Warning"})
    }
    catch {
        $compatibility.TPM20 = $false
        $compatibility.Details += "✗ Could not detect TPM"
        Write-Log -Message "Could not detect TPM: $_" -Level "Warning"
    }
    
    # Check CPU
    try {
        $cpu = Get-WmiObject -Class Win32_Processor
        if ($cpu.Name -like "Intel*") {
            if ($cpu.Name -like "Intel(R) Core(TM) i?-[2-7]*") {
                $compatibility.SupportedCPU = $false
                $compatibility.Details += "✗ Unsupported Intel CPU: $($cpu.Name)"
                Write-Log -Message "Unsupported Intel CPU: $($cpu.Name)" -Level "Warning"
            }
            else {
                $compatibility.Details += "✓ Supported Intel CPU: $($cpu.Name)"
                Write-Log -Message "Supported Intel CPU: $($cpu.Name)" -Level "Info"
            }
        }
        else {
            $compatibility.Details += "✓ Non-Intel CPU: $($cpu.Name)"
            Write-Log -Message "Non-Intel CPU: $($cpu.Name)" -Level "Info"
        }
    }
    catch {
        $compatibility.SupportedCPU = $false
        $compatibility.Details += "✗ Could not detect CPU"
        Write-Log -Message "Could not detect CPU: $_" -Level "Warning"
    }
    
    # Check SecureBoot
    try {
        $secureBootStatus = Confirm-SecureBootUEFI -ErrorAction Stop
        $compatibility.SecureBoot = $secureBootStatus
        
        $status = if ($secureBootStatus) { "✓ SecureBoot enabled" } else { "✗ SecureBoot disabled" }
        $compatibility.Details += $status
        Write-Log -Message $status -Level $(if($secureBootStatus){"Info"}else{"Warning"})
    }
    catch {
        $compatibility.SecureBoot = $false
        $compatibility.Details += "✗ Could not detect SecureBoot status"
        Write-Log -Message "Could not detect SecureBoot status: $_" -Level "Warning"
    }
    
    # Check RAM
    try {
        $totalRAM = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        $compatibility.MinimumRAM = $totalRAM -ge 4
        
        $status = if ($compatibility.MinimumRAM) { "✓ RAM: $([math]::Round($totalRAM, 2)) GB" } else { "✗ Insufficient RAM: $([math]::Round($totalRAM, 2)) GB (4 GB required)" }
        $compatibility.Details += $status
        Write-Log -Message $status -Level $(if($compatibility.MinimumRAM){"Info"}else{"Warning"})
    }
    catch {
        $compatibility.MinimumRAM = $false
        $compatibility.Details += "✗ Could not detect RAM"
        Write-Log -Message "Could not detect RAM: $_" -Level "Warning"
    }
    
    # Check Storage
    try {
        $systemDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freeSpace = $systemDrive.FreeSpace / 1GB
        $compatibility.MinimumStorage = $freeSpace -ge 64
        
        $status = if ($compatibility.MinimumStorage) { "✓ Free space: $([math]::Round($freeSpace, 2)) GB" } else { "✗ Insufficient free space: $([math]::Round($freeSpace, 2)) GB (64 GB required)" }
        $compatibility.Details += $status
        Write-Log -Message $status -Level $(if($compatibility.MinimumStorage){"Info"}else{"Warning"})
    }
    catch {
        $compatibility.MinimumStorage = $false
        $compatibility.Details += "✗ Could not detect storage"
        Write-Log -Message "Could not detect storage: $_" -Level "Warning"
    }
    
    # Check UEFI
    try {
        $uefi = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State -ErrorAction Stop).UEFISecureBootEnabled
        $compatibility.UEFI = $uefi -eq 1
        
        $status = if ($compatibility.UEFI) { "✓ UEFI boot mode" } else { "✗ Not in UEFI boot mode" }
        $compatibility.Details += $status
        Write-Log -Message $status -Level $(if($compatibility.UEFI){"Info"}else{"Warning"})
    }
    catch {
        $compatibility.UEFI = $false
        $compatibility.Details += "✗ Could not detect boot mode"
        Write-Log -Message "Could not detect boot mode: $_" -Level "Warning"
    }
    
    # Determine overall compatibility
    $compatibility.IsCompatible = $compatibility.TPM20 -and $compatibility.SupportedCPU
    
    $overallStatus = if ($compatibility.IsCompatible) { 
        "Hardware is compatible with Windows 11" 
    } else { 
        "Hardware is not compatible with Windows 11, will use Windows 10 instead" 
    }
    
    Write-Log -Message $overallStatus -Level $(if($compatibility.IsCompatible){"Info"}else{"Warning"})
    
    return $compatibility
}

# Initialize logging
Initialize-OSDCloudLoggingg