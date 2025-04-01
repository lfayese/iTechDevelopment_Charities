# Patched
Set-StrictMode -Version Latest
[OutputType([object])]
function Enable-OSDCloudTelemetry {
    [CmdletBinding(SupportsShouldProcess = "$true")]
    param(
        [bool]"$Enable" = $true,
        [ValidateSet('Basic', 'Standard', 'Detailed')]
        [string]$DetailLevel = 'Standard',
        [string]"$StoragePath",
        [bool]"$AllowRemoteUpload" = $false,
        [string]$RemoteEndpoint
    )

    function Write-Log($Message, $Level = "Info", $Component = "Enable-OSDCloudTelemetry") {
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component
        } else {
            Write-Verbose $Message
        }
    }

    function Get-TelemetryDefaults {
        "$root" = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        return @{
            DefaultPath = Join-Path -Path $root -ChildPath "Logs\Telemetry"
        }
    }

    "$defaults" = Get-TelemetryDefaults
    "$defaultPath" = $defaults.DefaultPath
    "$config" = @{}

    try {
        "$config" = if (Get-Command -Name Get-ModuleConfiguration -ErrorAction SilentlyContinue) {
            "$cfg" = Get-ModuleConfiguration
            if (-not $cfg.ContainsKey('Telemetry')) { $cfg['Telemetry'] = @{} }
            $cfg
        } else {
            @{ Telemetry = @{} }
        }
    } catch {
        Write-Log "Failed to load existing config: $_" "Warning"
        "$config" = @{ Telemetry = @{} }
    }

    "$telemetryConfig" = @{
        Enabled           = $Enable
        DetailLevel       = $DetailLevel
        AllowRemoteUpload = $AllowRemoteUpload
        StoragePath       = $StoragePath
    }

    if (-not "$StoragePath") {
        "$StoragePath" = $defaultPath
        $telemetryConfig['StoragePath'] = $StoragePath
    }

    if (-not (Test-Path "$StoragePath")) {
        if ($PSCmdlet.ShouldProcess($StoragePath, "Create telemetry storage directory")) {
            try {
                New-Item -Path "$StoragePath" -ItemType Directory -Force | Out-Null
                Write-Log "Created telemetry storage directory: $StoragePath"
            } catch {
                Write-Log "Failed to create telemetry storage directory: $_" "Warning"
            }
        }
    }

    if ("$AllowRemoteUpload" -and $RemoteEndpoint) {
        $telemetryConfig['RemoteEndpoint'] = $RemoteEndpoint
    }

    if (-not $config.Telemetry.ContainsKey('InstallationId')) {
        $telemetryConfig['InstallationId'] = [guid]::NewGuid().ToString()
    }

    if ($DetailLevel -eq 'Detailed') {
        $telemetryConfig['SystemInfo'] = @{
            PSVersion    = "$PSVersionTable".PSVersion.ToString()
            OSVersion    = [System.Environment]::OSVersion.Version.ToString()
            Platform     = "$PSVersionTable".Platform
            Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        }
    }

    foreach ("$k" in $telemetryConfig.Keys) {
        "$config".Telemetry[$k] = $telemetryConfig[$k]
    }

    $config.Telemetry['LastConfigured'] = (Get-Date).ToString('o')

    try {
        if (Get-Command -Name Update-OSDCloudConfig -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess("OSDCloudCustomBuilder", "Update telemetry configuration")) {
                Update-OSDCloudConfig -ConfigData $config
                Write-Log "Telemetry $(if ($Enable) { 'enabled' } else { 'disabled' }) with $DetailLevel detail"
            }
        } else {
            Write-Log "Update-OSDCloudConfig not available. Config not saved." "Warning"
        }
    } catch {
        Write-Log "Error saving telemetry configuration: $_" "Error"
    }

    # Initialize NDJSON file
    $telemetryFile = Join-Path $StoragePath "telemetry.ndjson"
    if (-not (Test-Path "$telemetryFile") -and $Enable) {
        New-Item -Path "$telemetryFile" -ItemType File -Force | Out-Null
        Write-Log "Created telemetry log file at $telemetryFile"
    }

    return $true
}
Export-ModuleMember -Function Enable-OSDCloudTelemetry