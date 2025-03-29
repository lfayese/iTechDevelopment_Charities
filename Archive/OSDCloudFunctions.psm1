# OSDCloudFunctions.psm1
# Shared functions for OSDCloud scripts
# Created: 2025-03-15

# Function to copy OSDCloud scripts to WinPE image
function Copy-OSDCloudScriptsToWinPE {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MountPath,
        
        [Parameter(Mandatory = $false)]
        [string]$SourceRoot = "$PSScriptRoot\..\..",
        
        [Parameter(Mandatory = $false)]
        [string]$DestinationRoot = "$MountPath\OSDCloud",
        
        [Parameter(Mandatory = $false)]
        [string[]]$FoldersToCopy = @(
            "Deploy",
            "Shared",
            "Modules",
            "Config"
        )
    )
    
    Write-Host "Copying OSDCloud scripts to WinPE image..." -ForegroundColor Cyan
    
    foreach ($folder in $FoldersToCopy) {
        $sourcePath = Join-Path $SourceRoot $folder
        $destinationPath = Join-Path $DestinationRoot $folder
        
        if (Test-Path $sourcePath) {
            if (!(Test-Path $destinationPath)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }
            
            Write-Host "  Copying $folder to $destinationPath" -ForegroundColor Yellow
            Copy-Item -Path "$sourcePath\*" -Destination $destinationPath -Recurse -Force
        }
        else {
            Write-Warning "Source folder not found: $sourcePath"
        }
    }
    
    # Create a verification file
    $verificationFile = Join-Path $DestinationRoot "scripts_included.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = "OSDCloud scripts copied at: $timestamp`r`n`r`nFolders included:`r`n"
    
    foreach ($folder in $FoldersToCopy) {
        $destinationPath = Join-Path $DestinationRoot $folder
        if (Test-Path $destinationPath) {
            $content += "- $folder`r`n"
            $files = Get-ChildItem -Path $destinationPath -Recurse -File | Select-Object -ExpandProperty FullName
            foreach ($file in $files) {
                $relativePath = $file.Replace($DestinationRoot, "").TrimStart("\")
                $content += "  - $relativePath`r`n"
            }
        }
    }
    
    Set-Content -Path $verificationFile -Value $content -Force
    Write-Host "Verification file created: $verificationFile" -ForegroundColor Green
    
    return $true
}

# Function to validate OSDCloud workspace
function Test-OSDCloudWorkspace {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$WorkspacePath = ".",
        
        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )
    
    $requiredFolders = @(
        "Deploy",
        "Shared",
        "Modules",
        "Config"
    )
    
    $missingFolders = @()
    $validationPassed = $true
    
    Write-Host "Validating OSDCloud workspace at: $WorkspacePath" -ForegroundColor Cyan
    
    foreach ($folder in $requiredFolders) {
        $folderPath = Join-Path $WorkspacePath $folder
        if (!(Test-Path $folderPath)) {
            $missingFolders += $folder
            $validationPassed = $false
            Write-Warning "Missing required folder: $folder"
        }
        else {
            Write-Host "  Found required folder: $folder" -ForegroundColor Green
        }
    }
    
    if ($Detailed) {
        # Check for key files
        $keyFiles = @{
            "Config\Tools\Initialize-OSDCloud.ps1" = "Initialize-OSDCloud script"
            "Config\Tools\itec-osdcloudbuild.ps1" = "OSDCloud build script"
            "Modules\WorkspaceValidator.ps1" = "Workspace validator"
            "Deploy\Drivers\OSDCloudDrivers.ps1" = "OSDCloud drivers script"
        }
        
        foreach ($keyFile in $keyFiles.Keys) {
            $filePath = Join-Path $WorkspacePath $keyFile
            if (!(Test-Path $filePath)) {
                $validationPassed = $false
                Write-Warning "Missing key file: $keyFile - $($keyFiles[$keyFile])"
            }
            else {
                Write-Host "  Found key file: $keyFile" -ForegroundColor Green
            }
        }
    }
    
    # Return results
    if ($validationPassed) {
        Write-Host "OSDCloud workspace validation passed!" -ForegroundColor Green
    }
    else {
        Write-Warning "OSDCloud workspace validation failed!"
    }
    
    return $validationPassed
}

# Function to configure WinPE for OSDCloud
function Set-OSDCloudWinPEConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MountPath
    )
    
    Write-Host "Configuring WinPE for OSDCloud..." -ForegroundColor Cyan
    
    # Configure WinPE settings
    try {
        # Set PowerShell execution policy
        $winpeExecutionPolicyPath = "$MountPath\Windows\System32\WindowsPowerShell\v1.0\profile.ps1"
        $executionPolicyContent = "Set-ExecutionPolicy -ExecutionPolicy Bypass -Force"
        
        if (!(Test-Path $winpeExecutionPolicyPath)) {
            New-Item -Path $winpeExecutionPolicyPath -ItemType File -Force | Out-Null
        }
        
        Set-Content -Path $winpeExecutionPolicyPath -Value $executionPolicyContent -Force
        Write-Host "  Set PowerShell execution policy to Bypass" -ForegroundColor Green
        
        # Configure PowerShell profile
        $winpeProfilePath = "$MountPath\Windows\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1"
        $profileContent = @"
# OSDCloud PowerShell Profile
Write-Host "Loading OSDCloud PowerShell Profile..." -ForegroundColor Cyan

# Set console properties
`$Host.UI.RawUI.WindowTitle = "OSDCloud WinPE"
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "Cyan"
Clear-Host

# Import OSDCloud modules
if (Test-Path X:\OSDCloud\Modules) {
    Get-ChildItem -Path X:\OSDCloud\Modules -Filter *.psm1 -Recurse | ForEach-Object {
        Import-Module `$_.FullName -Force
    }
}

# Start OSDCloud automatically if requested
if (Test-Path X:\OSDCloud\Config\autostart.txt) {
    Write-Host "Autostart enabled, launching OSDCloud..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    & X:\OSDCloud\Config\Tools\Initialize-OSDCloud.ps1
}

Write-Host "OSDCloud WinPE environment ready!" -ForegroundColor Green
"@
        
        if (!(Test-Path $winpeProfilePath)) {
            New-Item -Path $winpeProfilePath -ItemType File -Force | Out-Null
        }
        
        Set-Content -Path $winpeProfilePath -Value $profileContent -Force
        Write-Host "  Configured PowerShell profile" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error "Failed to configure WinPE: $_"
        return $false
    }
}

# Function to verify WinPE image
function Test-OSDCloudWinPEImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MountPath
    )
    
    Write-Host "Verifying OSDCloud WinPE image..." -ForegroundColor Cyan
    
    $requiredPaths = @(
        "$MountPath\OSDCloud",
        "$MountPath\OSDCloud\Deploy",
        "$MountPath\OSDCloud\Shared",
        "$MountPath\OSDCloud\Modules",
        "$MountPath\OSDCloud\Config",
        "$MountPath\OSDCloud\scripts_included.txt"
    )
    
    $missingPaths = @()
    $validationPassed = $true
    
    foreach ($path in $requiredPaths) {
        if (!(Test-Path $path)) {
            $missingPaths += $path
            $validationPassed = $false
            Write-Warning "Missing required path in WinPE image: $path"
        }
        else {
            Write-Host "  Found required path: $path" -ForegroundColor Green
        }
    }
    
    # Check if key scripts are included
    $keyScripts = @(
        "$MountPath\OSDCloud\Config\Tools\Initialize-OSDCloud.ps1",
        "$MountPath\OSDCloud\Deploy\Drivers\OSDCloudDrivers.ps1",
        "$MountPath\OSDCloud\Modules\SharedFunctions\OSDCloudFunctions.psm1"
    )
    
    foreach ($script in $keyScripts) {
        if (!(Test-Path $script)) {
            $validationPassed = $false
            Write-Warning "Missing key script in WinPE image: $script"
        }
        else {
            Write-Host "  Found key script: $script" -ForegroundColor Green
        }
    }
    
    # Return results
    if ($validationPassed) {
        Write-Host "OSDCloud WinPE image validation passed!" -ForegroundColor Green
    }
    else {
        Write-Warning "OSDCloud WinPE image validation failed!"
    }
    
    return $validationPassed
}

# Export functions
Export-ModuleMember -Function Copy-OSDCloudScriptsToWinPE
Export-ModuleMember -Function Test-OSDCloudWorkspace
Export-ModuleMember -Function Set-OSDCloudWinPEConfig
Export-ModuleMember -Function Test-OSDCloudWinPEImage