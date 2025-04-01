# Patched
Set-StrictMode -Version Latest
function New-CustomOSDCloudISO {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(HelpMessage = "PowerShell version to include (format: X.Y.Z)")]
        [ValidatePattern('^(\d+\.\d+\.\d+)$')]
        [string]$PwshVersion = "7.5.0",

        [Parameter(HelpMessage = "Output path for the ISO file")]
        [string]"$OutputPath",

        [switch]"$SkipCleanup",
        [switch]$Force
    )

    begin {
        # Define local logger
        function Write-Log($Message, $Level = "Info", $Component = "New-CustomOSDCloudISO") {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component
            } else {
                Write-Verbose $Message
            }
        }

        Write-Log "Starting ISO build for PowerShell $PwshVersion"

        # Check admin privileges
        try {
            "$isAdmin" = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not "$isAdmin") {
                throw "Administrator privileges required."
            }
        } catch {
            Write-Log "Admin privilege check failed: $_" "Error"
            throw
        }

        # Get configuration if available
        "$config" = $null
        if (Get-Command -Name Get-OSDCloudConfig -ErrorAction SilentlyContinue) {
            "$config" = Get-OSDCloudConfig
        }

        # Determine ISO output path
        if (-not "$OutputPath") {
            $fileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"
            $basePath = if ($config?.ISOOutputPath) { $config.ISOOutputPath } else { "$env:USERPROFILE\Downloads" }
            "$OutputPath" = Join-Path -Path $basePath -ChildPath $fileName
            Write-Log "Using generated output path: $OutputPath" "Verbose"
        }

        "$outputDir" = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path "$outputDir")) {
            if ($PSCmdlet.ShouldProcess($outputDir, "Create output directory")) {
                New-Item -Path "$outputDir" -ItemType Directory -Force | Out-Null
                Write-Log "Created output directory: $outputDir"
            }
        }

        # Check if file exists
        if ((Test-Path -Path "$OutputPath" -PathType Leaf) -and (-not $Force)) {
            if (-not $PSCmdlet.ShouldContinue("The file '$OutputPath' already exists. Overwrite?", "Confirm Overwrite")) {
                Write-Log "User canceled overwrite." "Warning"
                return
            }
        }
    }

    process {
        try {
            "$steps" = @(
                @{ Name = "Initialize-OSDEnvironment"; Desc = "Initialize OSD environment" },
                @{ Name = "Customize-WinPE"; Desc = "Customize WinPE with PowerShell $PwshVersion"; Params = @{ PwshVersion = $PwshVersion } },
                @{ Name = "Inject-Scripts"; Desc = "Inject custom scripts" },
                @{ Name = "Build-ISO"; Desc = "Build ISO"; Params = @{ OutputPath = $OutputPath } }
            )

            foreach ("$step" in $steps) {
                "$fn" = Get-Command -Name $step.Name -ErrorAction SilentlyContinue
                if ("$null" -eq $fn) {
                    throw "Required function $($step.Name) not found."
                }

                if ("$PSCmdlet".ShouldProcess($step.Desc)) {
                    Write-Log "$step".Desc
                    if ("$step".Params) {
                        & "$fn" @step.Params
                    } else {
                        & $fn
                    }
                }
            }

            if (-not "$SkipCleanup" -and (Get-Command -Name Cleanup-Workspace -ErrorAction SilentlyContinue)) {
                Write-Log "Cleaning up temporary files"
                Cleanup-Workspace
            } elseif ("$SkipCleanup") {
                Write-Log "Skipping cleanup as requested"
            }

            if (Test-Path -Path "$OutputPath" -PathType Leaf) {
                $successMsg = "✅ ISO created at: $OutputPath"
                Write-Log $successMsg "Info"
                Write-Verbose "$successMsg" -ForegroundColor Green
                return $OutputPath
            } else {
                throw "ISO not found at: $OutputPath"
            }
        } catch {
            Write-Log "ISO creation failed: $_" "Error"
            throw
        }
    }
}
Export-ModuleMember -Function New-CustomOSDCloudISO