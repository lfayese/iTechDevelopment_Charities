<# 
.SYNOPSIS
    Enables and configures telemetry for OSDCloudCustomBuilder.
.DESCRIPTION
    This function enables telemetry collection for the OSDCloudCustomBuilder module.
    It provides options to configure what data is collected, where it's stored, and how
    it's transmitted. Telemetry helps identify issues in production environments and
    improves the module over time.
.PARAMETER Enable
    Enables or disables telemetry collection. Default is $true.
.PARAMETER DetailLevel
    Controls the level of detail collected in telemetry. Options are:
    - Basic: Only collects operation names, duration, and success/failure
    - Standard: Adds memory usage and error messages (default)
    - Detailed: Adds system information and more detailed operation metrics
.PARAMETER StoragePath
    Path where telemetry data is stored locally. Default is the module's log directory.
.PARAMETER AllowRemoteUpload
    When enabled, allows telemetry data to be uploaded to a central repository when specified.
    Default is $false to ensure privacy.
.PARAMETER RemoteEndpoint
    Optional URL endpoint for uploading telemetry data. Only used if AllowRemoteUpload is $true.
.EXAMPLE
    Enable-OSDCloudTelemetry -Enable $true -DetailLevel Standard
    Enables standard telemetry collection for the module.
.EXAMPLE
    Enable-OSDCloudTelemetry -DetailLevel Detailed -StoragePath "D:\OSDLogs\Telemetry"
    Enables detailed telemetry collection and stores data in the specified path.
.NOTES
    Telemetry is always opt-in and can be disabled at any time.
    No personally identifiable information is collected.
#>
function Enable-OSDCloudTelemetry {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$Enable = $true,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Basic', 'Standard', 'Detailed')]
        [string]$DetailLevel = 'Standard',
        [Parameter(Mandatory = $false)]
        [string]$StoragePath,
        [Parameter(Mandatory = $false)]
        [bool]$AllowRemoteUpload = $false,
        [Parameter(Mandatory = $false)]
        [string]$RemoteEndpoint
    )
    # Cache the module root and default storage path
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $defaultPath = Join-Path -Path $moduleRoot -ChildPath "Logs\Telemetry"
    # Get current configuration or initialize a new one
    try {
        $getConfigCmd = Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue
        if ($getConfigCmd) {
            $config = Get-ModuleConfiguration
            if (-not $config.ContainsKey('Telemetry')) {
                $config['Telemetry'] = @{}
            }
        }
        else {
            Write-Warning "Module configuration not available. Creating new telemetry configuration."
            $config = @{ Telemetry = @{} }
        }
    }
    catch {
        Write-Warning "Failed to retrieve module configuration: $_"
        $config = @{ Telemetry = @{} }
    }
    # Prepare configuration update
    $telemetryConfig = @{
        Enabled         = $Enable
        DetailLevel     = $DetailLevel
        AllowRemoteUpload = $AllowRemoteUpload
    }
    # Set storage path if provided
    if ($StoragePath) {
        if (-not (Test-Path -Path $StoragePath -IsValid)) {
            Write-Warning "Invalid storage path provided: $StoragePath"
        }
        elseif (-not (Test-Path -Path $StoragePath)) {
            if ($PSCmdlet.ShouldProcess($StoragePath, "Create telemetry storage directory")) {
                try {
                    New-Item -Path $StoragePath -ItemType Directory -Force | Out-Null
                    $telemetryConfig['StoragePath'] = $StoragePath
                }
                catch {
                    Write-Warning "Failed to create telemetry storage directory: $_"
                }
            }
        }
        else {
            $telemetryConfig['StoragePath'] = $StoragePath
        }
    }
    else {
        # Use default storage path
        if (-not (Test-Path -Path $defaultPath)) {
            if ($PSCmdlet.ShouldProcess($defaultPath, "Create default telemetry storage directory")) {
                try {
                    New-Item -Path $defaultPath -ItemType Directory -Force | Out-Null
                }
                catch {
                    Write-Warning "Failed to create default telemetry storage directory: $_"
                }
            }
        }
        $telemetryConfig['StoragePath'] = $defaultPath
    }
    # Set remote endpoint if provided and uploads are allowed
    if ($AllowRemoteUpload -and $RemoteEndpoint) {
        $telemetryConfig['RemoteEndpoint'] = $RemoteEndpoint
    }
    # Generate unique anonymous identifier if not already there
    if (-not $config.Telemetry.ContainsKey('InstallationId')) {
        $telemetryConfig['InstallationId'] = [guid]::NewGuid().ToString()
    }
    # Include system info if detailed level is required
    if ($DetailLevel -eq 'Detailed') {
        $sysInfo = @{
            PSVersion    = $PSVersionTable.PSVersion.ToString()
            OSVersion    = [System.Environment]::OSVersion.Version.ToString()
            Platform     = $PSVersionTable.Platform
            Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        }
        $telemetryConfig['SystemInfo'] = $sysInfo
    }
    # Update the configuration with new telemetry settings
    foreach ($key in $telemetryConfig.Keys) {
        $config.Telemetry[$key] = $telemetryConfig[$key]
    }
    $config.Telemetry['LastConfigured'] = (Get-Date).ToString('o')
    # Update the module configuration using Update-OSDCloudConfig (if available)
    if (Get-Command -Name Update-OSDCloudConfig -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess("OSDCloudCustomBuilder", "Update telemetry configuration")) {
            try {
                Update-OSDCloudConfig -ConfigData $config
                $status = if ($Enable) { "enabled" } else { "disabled" }
                Write-OSDCloudLog -Message "Telemetry $status with $DetailLevel detail level" -Level Info
                # Create telemetry file (NDJSON file for improved performance)
                $telemetryFile = Join-Path -Path $config.Telemetry.StoragePath -ChildPath "telemetry.ndjson"
                if (-not (Test-Path -Path $telemetryFile) -and $Enable) {
                    # Create an empty file (header info can be stored in a separate log if needed)
                    New-Item -Path $telemetryFile -ItemType File -Force | Out-Null
                }
                return $true
            }
            catch {
                Write-Warning "Failed to update telemetry configuration: $_"
                return $false
            }
        }
    }
    else {
        Write-Warning "Update-OSDCloudConfig function not available. Telemetry configuration not saved."
        return $false
    }
}
function Send-OSDCloudTelemetry {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationName,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$TelemetryData,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    # Cache default module root and storage path (if needed)
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $defaultStoragePath = Join-Path -Path $moduleRoot -ChildPath "Logs\Telemetry"
    # Retrieve module configuration
    try {
        $getConfigCmd = Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue
        if ($getConfigCmd) {
            $config = Get-ModuleConfiguration
            if (-not ($config.ContainsKey('Telemetry') -and $config.Telemetry.Enabled)) {
                if (-not $Force) {
                    Write-Verbose "Telemetry is disabled. Use -Force to send anyway."
                    return $false
                }
            }
            $storagePath = if ($config.Telemetry.ContainsKey('StoragePath')) {
                $config.Telemetry.StoragePath
            }
            else {
                $defaultStoragePath
            }
        }
        else {
            Write-Verbose "Module configuration not available."
            if (-not $Force) { return $false }
            $storagePath = $defaultStoragePath
        }
    }
    catch {
        Write-Verbose "Failed to retrieve telemetry configuration: $_"
        if (-not $Force) { return $false }
        $storagePath = $defaultStoragePath
    }
    # Ensure the storage directory exists
    if (-not (Test-Path -Path $storagePath)) {
        try {
            New-Item -Path $storagePath -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-Warning "Failed to create telemetry storage directory: $_"
            return $false
        }
    }
    # Enrich telemetry data with timestamp and operation name
    $TelemetryData['Timestamp'] = (Get-Date).ToString('o')
    $TelemetryData['OperationName'] = $OperationName
    if ($config.Telemetry.ContainsKey('InstallationId')) {
        $TelemetryData['InstallationId'] = $config.Telemetry.InstallationId
    }
    # Determine new telemetry file path (NDJSON)
    $telemetryFile = Join-Path -Path $storagePath -ChildPath "telemetry.ndjson"
    if ($PSCmdlet.ShouldProcess($telemetryFile, "Append telemetry entry")) {
        try {
            $jsonEntry = $TelemetryData | ConvertTo-Json -Depth 6
            # Append the new telemetry entry as a single line of JSON
            Add-Content -Path $telemetryFile -Value $jsonEntry
            # If remote upload is allowed, do the remote upload here (if implemented)
            if ($config.Telemetry.ContainsKey('AllowRemoteUpload') -and 
                $config.Telemetry.AllowRemoteUpload -and
                $config.Telemetry.ContainsKey('RemoteEndpoint')) {
                Write-Verbose "Would upload telemetry to $($config.Telemetry.RemoteEndpoint)"
            }
            return $true
        }
        catch {
            Write-Warning "Failed to save telemetry data: $_"
            return $false
        }
    }
    return $false
}
# Export the functions
if ($MyInvocation.ScriptName -ne '') {
    # Only export functions when the script is part of a module
    Export-ModuleMember -Function Enable-OSDCloudTelemetry, Send-OSDCloudTelemetry
}