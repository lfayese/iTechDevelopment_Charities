# Patched
Set-StrictMode -Version Latest
function New-CustomOSDCloudISO {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(HelpMessage = "PowerShell version to include (format: X.Y.Z)")]
        [ValidatePattern('^(\d+\.\d+\.\d+)$', ErrorMessage = "PowerShell version must be in format X.Y.Z with digits only")]
        [string]$PwshVersion = "7.5.0",

        [Parameter(HelpMessage = "Output path for the ISO file")]
        [string]$OutputPath,

        [switch]$SkipCleanup,
        [switch]$Force
    )

    begin {
        # Define local logger
        function Write-Log($Message, $Level = "Info", $Component = "New-CustomOSDCloudISO") {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $Message -Level $Level -Component $Component
            } else {
                Write-Verbose $Message
            }
        }

        Write-Log "Starting ISO build for PowerShell $PwshVersion"

        # Check admin privileges
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                throw "Administrator privileges required for ISO creation."
            }
        } catch {
            Write-Log "Admin privilege check failed: $_" "Error"
            throw "Administrator privileges required. Please run PowerShell as Administrator."
        }

        # Get configuration if available
        $config = $null
        if (Get-Command -Name Get-OSDCloudConfig -ErrorAction SilentlyContinue) {
            $config = Get-OSDCloudConfig
        }

        # Determine ISO output path
        if (-not $OutputPath) {
            $fileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"
            $basePath = if ($config?.ISOOutputPath) { $config.ISOOutputPath } else { "$env:USERPROFILE\Downloads" }
            $OutputPath = Join-Path -Path $basePath -ChildPath $fileName
            Write-Log "Using generated output path: $OutputPath" "Verbose"
        }

        # Validate path to prevent path traversal
        try {
            $normalizedPath = [System.IO.Path]::GetFullPath($OutputPath)
            if (-not $normalizedPath.StartsWith($basePath) -and -not $normalizedPath.StartsWith($env:USERPROFILE)) {
                throw "Path traversal attempt detected. Output path must be within allowed directories."
            }
            $OutputPath = $normalizedPath
        } catch {
            Write-Log "Path validation failed: $_" "Error"
            throw "Invalid output path specified: $OutputPath"
        }

        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDir)) {
            if ($PSCmdlet.ShouldProcess($outputDir, "Create output directory")) {
                New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
                Write-Log "Created output directory: $outputDir"
            }
        }

        # Check if file exists
        if ((Test-Path -Path $OutputPath -PathType Leaf) -and (-not $Force)) {
            if (-not $PSCmdlet.ShouldContinue("The file '$OutputPath' already exists. Overwrite?", "Confirm Overwrite")) {
                Write-Log "User canceled overwrite." "Warning"
                return
            }
        }
    }

    process {
        try {
            $steps = @(
                @{ Name = "Initialize-OSDEnvironment"; Desc = "Initialize OSD environment" },
                @{ Name = "Customize-WinPE"; Desc = "Customize WinPE with PowerShell $PwshVersion"; Params = @{ PwshVersion = $PwshVersion } },
                @{ Name = "Inject-Scripts"; Desc = "Inject custom scripts" },
                @{ Name = "Build-ISO"; Desc = "Build ISO"; Params = @{ OutputPath = $OutputPath } }
            )

            foreach ($step in $steps) {
                $fn = Get-Command -Name $step.Name -ErrorAction SilentlyContinue
                if ($null -eq $fn) {
                    throw "Required function $($step.Name) not found. Please ensure the OSDCloudCustomBuilder module is properly installed."
                }

                if ($PSCmdlet.ShouldProcess($step.Desc)) {
                    Write-Log $step.Desc
                    if ($step.Params) {
                        & $fn @step.Params
                    } else {
                        & $fn
                    }
                }
            }

            if (-not $SkipCleanup -and (Get-Command -Name Cleanup-Workspace -ErrorAction SilentlyContinue)) {
                Write-Log "Cleaning up temporary files"
                Cleanup-Workspace
            } elseif ($SkipCleanup) {
                Write-Log "Skipping cleanup as requested"
            }

            if (Test-Path -Path $OutputPath -PathType Leaf) {
                $fileInfo = Get-Item -Path $OutputPath
                if ($fileInfo.Length -gt 0) {
                    $successMsg = "✅ ISO created at: $OutputPath (Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB)"
                    Write-Log $successMsg "Info"
                    Write-Verbose $successMsg -ForegroundColor Green
                    return $OutputPath
                } else {
                    throw "ISO file was created but appears to be empty: $OutputPath"
                }
            } else {
                throw "ISO creation failed: File not found at expected location: $OutputPath"
            }
        } catch {
            Write-Log "ISO creation failed: $_" "Error" -Exception $_.Exception
            throw
        }
    }
}
Export-ModuleMember -Function New-CustomOSDCloudISO