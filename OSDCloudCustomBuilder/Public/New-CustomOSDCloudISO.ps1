<#
.SYNOPSIS
    Creates a custom OSDCloud ISO with PowerShell 7 support.
.DESCRIPTION
    This function creates a custom OSDCloud ISO with PowerShell 7 support and additional customizations.
    It handles the entire process from environment initialization to ISO generation.
    
    The function performs the following steps:
    1. Initializes the OSD environment
    2. Customizes the WinPE environment with PowerShell 7
    3. Injects custom scripts
    4. Builds the ISO file
    5. Optionally cleans up temporary files
.PARAMETER PwshVersion
    The PowerShell version to include in the ISO. Default is "7.5.0".
    Must be in the format "X.Y.Z" (e.g., "7.5.0").
.PARAMETER OutputPath
    The path where the ISO file will be created.
    If not specified, the default path from OSDCloudConfig will be used.
.PARAMETER SkipCleanup
    If specified, skips cleanup of temporary files after ISO creation.
    Useful for debugging or when you want to inspect the build artifacts.
.PARAMETER Force
    If specified, overwrites the output ISO file if it already exists.
    Without this parameter, the function will prompt for confirmation before overwriting.
.EXAMPLE
    New-CustomOSDCloudISO
    
    Creates a custom OSDCloud ISO with the default PowerShell 7.5.0 version.
.EXAMPLE
    New-CustomOSDCloudISO -PwshVersion "7.4.1" -OutputPath "C:\OSDCloud\Custom.iso"
    
    Creates a custom OSDCloud ISO with PowerShell 7.4.1 and saves it to the specified path.
.EXAMPLE
    New-CustomOSDCloudISO -SkipCleanup
    
    Creates a custom OSDCloud ISO and keeps the temporary files for inspection.
.NOTES
    Requires administrator privileges and Windows ADK installed.
    For detailed logging, set $VerbosePreference = "Continue" before running the function.
#>
function New-CustomOSDCloudISO {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(HelpMessage = "PowerShell version to include (format: X.Y.Z)")]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^(\d+\.\d+\.\d+)$')]
        [string]$PwshVersion = "7.5.0",
        
        [Parameter(HelpMessage = "Output path for the ISO file")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter(HelpMessage = "Skip cleanup of temporary files after ISO creation")]
        [switch]$SkipCleanup,
        
        [Parameter(HelpMessage = "Overwrite the output ISO file if it already exists")]
        [switch]$Force
    )
    
    begin {
        # Log operation start
        if ($script:LoggerExists) {
            Invoke-OSDCloudLogger -Message "Starting custom OSDCloud ISO build with PowerShell $PwshVersion" -Level Info -Component "New-CustomOSDCloudISO"
        }
        else {
            Write-Verbose "Starting custom OSDCloud ISO build with PowerShell $PwshVersion"
        }
        
        # Check for administrator privileges
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                $errorMessage = "This function requires administrator privileges to run properly."
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                }
                throw $errorMessage
            }
        }
        catch {
            $errorMessage = "Failed to check administrator privileges: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw "Administrator privilege check failed. Please run as administrator."
        }
        
        # Determine output path if not specified
        if (-not $OutputPath) {
            try {
                # Try to get from config
                $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
                if ($config -and $config.ISOOutputPath) {
                    $isoFileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"
                    $OutputPath = Join-Path -Path $config.ISOOutputPath -ChildPath $isoFileName
                    
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message "Using output path from config: $OutputPath" -Level Verbose -Component "New-CustomOSDCloudISO"
                    }
                }
                else {
                    # Default path
                    $isoFileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"
                    $OutputPath = Join-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath "Downloads") -ChildPath $isoFileName
                    
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message "Using default output path: $OutputPath" -Level Verbose -Component "New-CustomOSDCloudISO"
                    }
                }
            }
            catch {
                $errorMessage = "Failed to determine output path: $_"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "New-CustomOSDCloudISO" -Exception $_.Exception
                }
                else {
                    Write-Warning $errorMessage
                }
                
                # Fallback to default
                $isoFileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"
                $OutputPath = Join-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath "Downloads") -ChildPath $isoFileName
            }
        }
        
        # Create output directory if it doesn't exist
        $outputDirectory = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDirectory)) {
            try {
                if ($PSCmdlet.ShouldProcess($outputDirectory, "Create directory")) {
                    New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message "Created output directory: $outputDirectory" -Level Verbose -Component "New-CustomOSDCloudISO"
                    }
                }
            }
            catch {
                $errorMessage = "Failed to create output directory: $_"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO" -Exception $_.Exception
                }
                else {
                    Write-Error $errorMessage
                }
                throw
            }
        }
        
        # Check if output file already exists
        if (Test-Path -Path $OutputPath -PathType Leaf) {
            if (-not $Force -and -not $PSCmdlet.ShouldContinue("The file '$OutputPath' already exists. Do you want to overwrite it?", "File exists")) {
                $warningMessage = "Operation cancelled by user because the output file already exists."
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $warningMessage -Level Warning -Component "New-CustomOSDCloudISO"
                }
                else {
                    Write-Warning $warningMessage
                }
                return
            }
            
            # Log the overwrite
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Output file '$OutputPath' will be overwritten" -Level Warning -Component "New-CustomOSDCloudISO"
            }
        }
    }
    
    process {
        try {
            # Step 1: Initialize OSD environment
            if ($PSCmdlet.ShouldProcess("OSD Environment", "Initialize")) {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Initializing OSD environment" -Level Info -Component "New-CustomOSDCloudISO"
                }
                
                if (Get-Command -Name Initialize-OSDEnvironment -ErrorAction SilentlyContinue) {
                    Initialize-OSDEnvironment
                }
                else {
                    $errorMessage = "Required function Initialize-OSDEnvironment is not available"
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                    }
                    throw $errorMessage
                }
            }
            
            # Step 2: Customize WinPE with PowerShell 7
            if ($PSCmdlet.ShouldProcess("WinPE", "Add PowerShell $PwshVersion support")) {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Customizing WinPE with PowerShell $PwshVersion" -Level Info -Component "New-CustomOSDCloudISO"
                }
                
                if (Get-Command -Name Customize-WinPE -ErrorAction SilentlyContinue) {
                    Customize-WinPE -PwshVersion $PwshVersion
                }
                else {
                    $errorMessage = "Required function Customize-WinPE is not available"
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                    }
                    throw $errorMessage
                }
            }
            
            # Step 3: Inject custom scripts
            if ($PSCmdlet.ShouldProcess("WinPE", "Inject custom scripts")) {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Injecting custom scripts" -Level Info -Component "New-CustomOSDCloudISO"
                }
                
                if (Get-Command -Name Inject-Scripts -ErrorAction SilentlyContinue) {
                    Inject-Scripts
                }
                else {
                    $errorMessage = "Required function Inject-Scripts is not available"
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                    }
                    throw $errorMessage
                }
            }
            
            # Step 4: Build the ISO
            if ($PSCmdlet.ShouldProcess($OutputPath, "Build ISO file")) {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Building ISO file" -Level Info -Component "New-CustomOSDCloudISO"
                }
                
                if (Get-Command -Name Build-ISO -ErrorAction SilentlyContinue) {
                    # If Build-ISO supports an output path parameter, use it
                    $buildIsoCmd = Get-Command -Name Build-ISO
                    if ($buildIsoCmd.Parameters.ContainsKey('OutputPath')) {
                        Build-ISO -OutputPath $OutputPath
                    }
                    else {
                        # Otherwise, use the default behavior
                        Build-ISO
                        
                        # Try to move the ISO to the desired location if it's not already there
                        if (Get-Command -Name Get-OSDCloudConfig -ErrorAction SilentlyContinue) {
                            $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
                            if ($config -and $config.ISOOutputPath) {
                                $defaultIsoPath = Join-Path -Path $config.ISOOutputPath -ChildPath "OSDCloud.iso"
                                if (Test-Path -Path $defaultIsoPath -PathType Leaf) {
                                    if ($defaultIsoPath -ne $OutputPath) {
                                        Copy-Item -Path $defaultIsoPath -Destination $OutputPath -Force
                                        Remove-Item -Path $defaultIsoPath -Force
                                    }
                                }
                            }
                        }
                    }
                }
                else {
                    $errorMessage = "Required function Build-ISO is not available"
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                    }
                    throw $errorMessage
                }
            }
            
            # Step 5: Cleanup
            if (-not $SkipCleanup) {
                if ($PSCmdlet.ShouldProcess("Workspace", "Clean up temporary files")) {
                    if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                        Invoke-OSDCloudLogger -Message "Cleaning up workspace" -Level Info -Component "New-CustomOSDCloudISO"
                    }
                    
                    if (Get-Command -Name Cleanup-Workspace -ErrorAction SilentlyContinue) {
                        Cleanup-Workspace
                    }
                    else {
                        $warningMessage = "Cleanup-Workspace function is not available. Temporary files may remain."
                        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                            Invoke-OSDCloudLogger -Message $warningMessage -Level Warning -Component "New-CustomOSDCloudISO"
                        }
                        else {
                            Write-Warning $warningMessage
                        }
                    }
                }
            }
            else {
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Skipping cleanup as requested" -Level Info -Component "New-CustomOSDCloudISO"
                }
                else {
                    Write-Verbose "Skipping cleanup as requested"
                }
            }
            
            # Verify ISO exists
            if (Test-Path -Path $OutputPath -PathType Leaf) {
                $successMessage = "✅ ISO created successfully at: $OutputPath"
                Write-Host $successMessage -ForegroundColor Green
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "New-CustomOSDCloudISO"
                }
                
                # Return the output path for further processing
                return $OutputPath
            }
            else {
                $errorMessage = "ISO file was not found at the expected location: $OutputPath"
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO"
                }
                throw $errorMessage
            }
        }
        catch {
            $errorMessage = "Failed to create custom OSDCloud ISO: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-CustomOSDCloudISO" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}