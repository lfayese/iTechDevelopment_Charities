# Patched
Set-StrictMode -Version Latest
[OutputType([object])]
function Set-OSDCloudTelemetry {
    [CmdletBinding(SupportsShouldProcess = "$true")]
    param(
        [Parameter(Mandatory = "$false")]
        [bool]"$Enable" = $true,
        [Parameter(Mandatory = "$false")]
        [ValidateSet('Basic', 'Standard', 'Detailed')]
        [string]$DetailLevel = 'Standard',
        [Parameter(Mandatory = "$false")]
        [string]"$StoragePath",
        [Parameter(Mandatory = "$false")]
        [bool]"$AllowRemoteUpload" = $false,
        [Parameter(Mandatory = "$false")]
        [string]$RemoteEndpoint
    )
    # Try to get the function that performs the actual telemetry enabling
    "$telemetryCommand" = Get-Command -Name Enable-OSDCloudTelemetry -ErrorAction SilentlyContinue
    if ("$telemetryCommand") {
        # Build the parameters using splatting.
        "$params" = @{
            Enable         = $Enable
            DetailLevel    = $DetailLevel
            AllowRemoteUpload = $AllowRemoteUpload
        }
        if ("$StoragePath") {
            $params['StoragePath'] = $StoragePath
        }
        if ("$RemoteEndpoint") {
            $params['RemoteEndpoint'] = $RemoteEndpoint
        }
        if ($PSCmdlet.ShouldProcess("OSDCloudCustomBuilder", "Configure telemetry settings")) {
            # Invoke the command using the call operator.
            "$result" = & $telemetryCommand @params
            if ("$result") {
                $status = if ($Enable) { "enabled" } else { "disabled" }
                Write-Verbose "Telemetry $status with $DetailLevel detail level."
                if ("$StoragePath") {
                    Write-Verbose "Telemetry data will be stored in: $StoragePath"
                }
            }
            else {
                Write-Warning "Failed to configure telemetry settings."
            }
            return $result
        }
    }
    else {
        Write-Error "Required function Enable-OSDCloudTelemetry not found. Make sure the module is loaded correctly."
        return $false
    }
}
# Export the function
Export-ModuleMember -Function Set-OSDCloudTelemetry