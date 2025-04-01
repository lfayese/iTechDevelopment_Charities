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
        # Cache command/function availability to avoid repeated Get-Command calls  
        $logger = Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue  
        $initFunction = Get-Command -Name Initialize-OSDEnvironment -ErrorAction SilentlyContinue  
        $customizeFunction = Get-Command -Name Customize-WinPE -ErrorAction SilentlyContinue  
        $injectFunction = Get-Command -Name Inject-Scripts -ErrorAction SilentlyContinue  
        $buildIsoFunction = Get-Command -Name Build-ISO -ErrorAction SilentlyContinue  
        $cleanupFunction = Get-Command -Name Cleanup-Workspace -ErrorAction SilentlyContinue  
        $getConfigFunction = Get-Command -Name Get-OSDCloudConfig -ErrorAction SilentlyContinue
        # Cache configuration (if available) to use later  
        if ($getConfigFunction) {  
            $cachedConfig = Get-OSDCloudConfig -ErrorAction SilentlyContinue  
        }  
        else {  
            $cachedConfig = $null  
        }
        # Helper function for logging  
        function Write-Log($Message, $Level = "Info", $Component = "New-CustomOSDCloudISO", $Exception = $null) {  
            if ($logger) {  
                Invoke-OSDCloudLogger -Message $Message -Level $Level -Component $Component -Exception $Exception  
            }  
            else {  
                Write-Verbose $Message  
            }  
        }  
        Write-Log "Starting custom OSDCloud ISO build with PowerShell $PwshVersion" "Info"  
        # Check for administrator privileges  
        try {  
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(  
                [Security.Principal.WindowsBuiltInRole]::Administrator)  
            if (-not $isAdmin) {  
                $errorMessage = "This function requires administrator privileges to run properly."  
                Write-Log $errorMessage "Error"  
                throw $errorMessage  
            }  
        }  
        catch {  
            $errorMessage = "Failed to check administrator privileges: $_"  
            Write-Log $errorMessage "Error" -Exception $_.Exception  
            throw "Administrator privilege check failed. Please run as administrator."  
        }  
        # Determine output path if not specified  
        if (-not $OutputPath) {  
            $isoFileName = "OSDCloud_PS$($PwshVersion -replace '\.', '_').iso"  
            if ($cachedConfig -and $cachedConfig.ISOOutputPath) {  
                $OutputPath = Join-Path -Path $cachedConfig.ISOOutputPath -ChildPath $isoFileName  
                Write-Log "Using output path from config: $OutputPath" "Verbose"  
            }  
            else {  
                $OutputPath = Join-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath "Downloads") -ChildPath $isoFileName  
                Write-Log "Using default output path: $OutputPath" "Verbose"  
            }  
        }  
        # Create output directory if it doesn't exist  
        $outputDirectory = Split-Path -Path $OutputPath -Parent  
        if (-not (Test-Path -Path $outputDirectory)) {  
            try {  
                if ($PSCmdlet.ShouldProcess($outputDirectory, "Create directory")) {  
                    New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null  
                    Write-Log "Created output directory: $outputDirectory" "Verbose"  
                }  
            }  
            catch {  
                $errorMessage = "Failed to create output directory: $_"  
                Write-Log $errorMessage "Error" -Exception $_.Exception  
                throw  
            }  
        }  
        # Check if output file already exists  
        if (Test-Path -Path $OutputPath -PathType Leaf) {  
            if (-not $Force -and -not $PSCmdlet.ShouldContinue("The file '$OutputPath' already exists. Do you want to overwrite it?", "File exists")) {  
                $warningMessage = "Operation cancelled by user because the output file already exists."  
                Write-Log $warningMessage "Warning"  
                return  
            }  
            Write-Log "Output file '$OutputPath' will be overwritten" "Warning"  
        }  
    }  
    process {  
        try {  
            # Step 1: Initialize OSD environment  
            if ($PSCmdlet.ShouldProcess("OSD Environment", "Initialize")) {  
                Write-Log "Initializing OSD environment" "Info"  
                if ($initFunction) {  
                    Initialize-OSDEnvironment  
                }  
                else {  
                    $errorMessage = "Required function Initialize-OSDEnvironment is not available"  
                    Write-Log $errorMessage "Error"  
                    throw $errorMessage  
                }  
            }  
            # Step 2: Customize WinPE with PowerShell 7  
            if ($PSCmdlet.ShouldProcess("WinPE", "Add PowerShell $PwshVersion support")) {  
                Write-Log "Customizing WinPE with PowerShell $PwshVersion" "Info"  
                if ($customizeFunction) {  
                    Customize-WinPE -PwshVersion $PwshVersion  
                }  
                else {  
                    $errorMessage = "Required function Customize-WinPE is not available"  
                    Write-Log $errorMessage "Error"  
                    throw $errorMessage  
                }  
            }  
            # Step 3: Inject custom scripts  
            if ($PSCmdlet.ShouldProcess("WinPE", "Inject custom scripts")) {  
                Write-Log "Injecting custom scripts" "Info"  
                if ($injectFunction) {  
                    Inject-Scripts  
                }  
                else {  
                    $errorMessage = "Required function Inject-Scripts is not available"  
                    Write-Log $errorMessage "Error"  
                    throw $errorMessage  
                }  
            }  
            # Step 4: Build the ISO  
            if ($PSCmdlet.ShouldProcess($OutputPath, "Build ISO file")) {  
                Write-Log "Building ISO file" "Info"  
                if ($buildIsoFunction) {  
                    # If Build-ISO supports an output path parameter, use it  
                    if ($buildIsoFunction.Parameters.ContainsKey('OutputPath')) {  
                        Build-ISO -OutputPath $OutputPath  
                    }  
                    else {  
                        Build-ISO  
                        # Try to move the ISO to the desired location if it's not already there  
                        $defaultIsoPath = $null  
                        if ($cachedConfig -and $cachedConfig.ISOOutputPath) {  
                            $defaultIsoPath = Join-Path -Path $cachedConfig.ISOOutputPath -ChildPath "OSDCloud.iso"  
                        }  
                        if ($defaultIsoPath -and (Test-Path -Path $defaultIsoPath -PathType Leaf)) {  
                            if ($defaultIsoPath -ne $OutputPath) {  
                                Copy-Item -Path $defaultIsoPath -Destination $OutputPath -Force  
                                Remove-Item -Path $defaultIsoPath -Force  
                            }  
                        }  
                    }  
                }  
                else {  
                    $errorMessage = "Required function Build-ISO is not available"  
                    Write-Log $errorMessage "Error"  
                    throw $errorMessage  
                }  
            }  
            # Step 5: Cleanup  
            if (-not $SkipCleanup) {  
                if ($PSCmdlet.ShouldProcess("Workspace", "Clean up temporary files")) {  
                    Write-Log "Cleaning up workspace" "Info"  
                    if ($cleanupFunction) {  
                        Cleanup-Workspace  
                    }  
                    else {  
                        $warningMessage = "Cleanup-Workspace function is not available. Temporary files may remain."  
                        Write-Log $warningMessage "Warning"  
                    }  
                }  
            }  
            else {  
                Write-Log "Skipping cleanup as requested" "Info"  
            }  
            # Verify ISO exists  
            if (Test-Path -Path $OutputPath -PathType Leaf) {  
                $successMessage = "✅ ISO created successfully at: $OutputPath"  
                Write-Host $successMessage -ForegroundColor Green  
                Write-Log $successMessage "Info"  
                return $OutputPath  
            }  
            else {  
                $errorMessage = "ISO file was not found at the expected location: $OutputPath"  
                Write-Log $errorMessage "Error"  
                throw $errorMessage  
            }  
        }  
        catch {  
            $errorMessage = "Failed to create custom OSDCloud ISO: $_"  
            Write-Log $errorMessage "Error" -Exception $_.Exception  
            throw  
        }  
    }  
}