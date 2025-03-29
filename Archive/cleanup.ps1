# === [ 10. Performance Optimizations ] ===
Write-Host "`nApplying performance optimizations..." -ForegroundColor Cyan

# 1. Clean up temporary files that may have been created during the process
$tempFolders = @(
    "$env:TEMP\OSDCloud*",
    "$env:SystemRoot\Temp\OSDCloud*",
    "$env:TEMP\WIM*"
)

foreach ($folder in $tempFolders) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "✅ Cleaned up temporary files at $folder" -ForegroundColor Green
        }
        catch {
            Write-Warning "⚠️ Could not clean up $folder: $($_.Exception.Message)"
        }
    }
}

# 2. Check and optimize ISO file if needed
$isoPath = "$workspace\OSDCloud.iso"
if (Test-Path $isoPath) {
    try {
        $isoInfo = Get-Item $isoPath
        $isoSizeMB = [math]::Round($isoInfo.Length / 1MB, 2)
        Write-Host "ISO Size: $isoSizeMB MB" -ForegroundColor Cyan

        # If ISO is larger than 1GB, show optimization tips
        if ($isoSizeMB -gt 1000) {
            Write-Host "💡 ISO file is quite large. Consider optimizing by:" -ForegroundColor Yellow
            Write-Host "   - Using fewer driver packs" -ForegroundColor Yellow
            Write-Host "   - Reducing custom content" -ForegroundColor Yellow
            Write-Host "   - Using WIM compression" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "⚠️ Could not analyze ISO file: $($_.Exception.Message)"
    }
}

# 3. Create a cleanup script that can be run later to free disk space
$cleanupScriptContent = @"
# OSDCloud Environment Cleanup Script
# Run this script to free up disk space after you're done with deployments

# Clean temp folders
Remove-Item -Path "$env:TEMP\OSDCloud*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\Temp\OSDCloud*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\WIM*" -Recurse -Force -ErrorAction SilentlyContinue

# Clean Windows update cache
if (Get-Command 'Clear-WindowsUpdateCache' -ErrorAction SilentlyContinue) {
    Clear-WindowsUpdateCache -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Windows Update cache cleanup command not available"
}

# Check and prompt for ISO/USB media deletion
`$workspacePath = "$workspace"
if (Test-Path "`$workspacePath\OSDCloud.iso") {
    if ((Read-Host -Prompt "Delete OSDCloud ISO file to free up space? (Y/N)").ToUpper() -eq 'Y') {
        Remove-Item -Path "`$workspacePath\OSDCloud.iso" -Force -ErrorAction SilentlyContinue
        Write-Host "ISO file deleted"
    }
}

if (Test-Path "`$workspacePath\OSDCloud_NoPrompt.iso") {
    if ((Read-Host -Prompt "Delete OSDCloud NoPrompt ISO file to free up space? (Y/N)").ToUpper() -eq 'Y') {
        Remove-Item -Path "`$workspacePath\OSDCloud_NoPrompt.iso" -Force -ErrorAction SilentlyContinue
        Write-Host "NoPrompt ISO file deleted"
    }
}

Write-Host "Cleanup completed"
"@

$cleanupScriptPath = "$workspace\OSDCloud-Cleanup.ps1"
Set-Content -Path $cleanupScriptPath -Value $cleanupScriptContent -Force
Write-Host "🧹 Created cleanup script at: $cleanupScriptPath" -ForegroundColor Green

# 4. Optimize future runs by caching external files
$cacheFolder = "$workspace\Cache"
New-Folder -Path $cacheFolder

# Add diagnostic functions that can help debug issues
$diagnosticScriptContent = @"
# OSDCloud Diagnostic Tool
# Run this to diagnose issues with OSDCloud deployments

function Test-OSDCloudEnvironment {
    `$results = @{
        "PowerShell Version" = `$PSVersionTable.PSVersion.ToString()
        "OSD Module Installed" = `$null
        "OSD Module Version" = `$null
        "Windows ADK Installed" = `$null
        "Deployment Tools Installed" = `$null
        "Windows PE Add-on Installed" = `$null
        "Available Disk Space" = `$null
        "Media Creation Status" = `$null
    }

    # Check OSD Module
    `$osdModule = Get-Module -Name OSD -ListAvailable
    `$results["OSD Module Installed"] = if (`$osdModule) { "Yes" } else { "No" }
    if (`$osdModule) {
        `$results["OSD Module Version"] = `$osdModule.Version.ToString()
    }

    # Check Windows ADK
    `$adkPath = "HKLM:\Software\Microsoft\Windows Kits\Installed Roots"
    `$results["Windows ADK Installed"] = if (Test-Path `$adkPath) { "Yes" } else { "No" }

    # Check for Deployment Tools
    `$deployToolsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools"
    `$results["Deployment Tools Installed"] = if (Test-Path `$deployToolsPath) { "Yes" } else { "No" }

    # Check for Windows PE Add-on
    `$winPEPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"
    `$results["Windows PE Add-on Installed"] = if (Test-Path `$winPEPath) { "Yes" } else { "No" }

    # Check available disk space
    `$systemDrive = Get-PSDrive C
    `$freeSpaceGB = [math]::Round(`$systemDrive.Free / 1GB, 2)
    `$results["Available Disk Space"] = "`$freeSpaceGB GB"

    # Check if media was created successfully
    `$workspace = "$workspace"
    `$mediaStatus = @()
    if (Test-Path "`$workspace\OSDCloud.iso") {
        `$mediaStatus += "ISO file exists"
    }
    if (Test-Path "`$workspace\OSDCloud_NoPrompt.iso") {
        `$mediaStatus += "NoPrompt ISO file exists"
    }
    `$usbDrive = Get-Volume | Where-Object { `$_.DriveType -eq 'Removable' -and `$_.FileSystemLabel -like 'OSDCloud*' }
    if (`$usbDrive) {
        `$mediaStatus += "USB drive detected"
    }

    if (`$mediaStatus.Count -gt 0) {
        `$results["Media Creation Status"] = [string]::Join(", ", `$mediaStatus)
    } else {
        `$results["Media Creation Status"] = "No media detected"
    }

    # Display results
    `$results.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize

    # Provide recommendations
    Write-Host "Recommendations:" -ForegroundColor Yellow
    if (-not `$osdModule) {
        Write-Host "- Install the OSD module: Install-Module OSD -Force" -ForegroundColor Red
    }
    if (`$freeSpaceGB -lt 10) {
        Write-Host "- Low disk space detected. Free up at least 10GB for optimal performance" -ForegroundColor Red
    }
    if (-not (Test-Path `$winPEPath)) {
        Write-Host "- Windows PE Add-on not detected. Install ADK and WinPE Add-on" -ForegroundColor Red
    }
}

# Run the diagnostic
Test-OSDCloudEnvironment
"@

$diagnosticScriptPath = "$workspace\OSDCloud-Diagnostic.ps1"
Set-Content -Path $diagnosticScriptPath -Value $diagnosticScriptContent -Force
Write-Host "🔍 Created diagnostic script at: $diagnosticScriptPath" -ForegroundColor Green

# 5. Create performance benchmark to measure deployment speed
$benchmarkScriptContent = @"
# OSDCloud Performance Benchmark
# This script measures the performance of key deployment tasks

function Measure-OSDCloudTask {
    param(
        [Parameter(Mandatory = `$true)]
        [string]`$Name,

        [Parameter(Mandatory = `$true)]
        [scriptblock]`$ScriptBlock
    )

    Write-Host "Starting task: `$Name" -ForegroundColor Cyan
    `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        & `$ScriptBlock
        `$stopwatch.Stop()
        `$elapsed = `$stopwatch.Elapsed
        Write-Host "✅ Task completed: `$Name - Time: `$(`$elapsed.Minutes)m `$(`$elapsed.Seconds)s" -ForegroundColor Green
        return @{
            Name = `$Name
            Success = `$true
            TimeSeconds = `$elapsed.TotalSeconds
            Error = `$null
        }
    }
    catch {
        `$stopwatch.Stop()
        `$elapsed = `$stopwatch.Elapsed
        Write-Host "❌ Task failed: `$Name - Time: `$(`$elapsed.Minutes)m `$(`$elapsed.Seconds)s" -ForegroundColor Red
        Write-Host "   Error: `$(`$_.Exception.Message)" -ForegroundColor Red
        return @{
            Name = `$Name
            Success = `$false
            TimeSeconds = `$elapsed.TotalSeconds
            Error = `$_.Exception.Message
        }
    }
}

# Array to store results
`$results = @()

# Test 1: Create a basic template
`$results += Measure-OSDCloudTask -Name "Create Basic Template" -ScriptBlock {
    New-OSDCloudTemplate -Name "BenchmarkTest" -WinRE
}

# Test 2: Create a basic workspace
`$results += Measure-OSDCloudTask -Name "Create Workspace" -ScriptBlock {
    New-OSDCloudWorkspace -WorkspacePath "C:\OSDCloud\Benchmark" -Template "BenchmarkTest"
}

# Test 3: Generate a small ISO
`$results += Measure-OSDCloudTask -Name "Generate ISO" -ScriptBlock {
    New-OSDCloudISO -WorkspacePath "C:\OSDCloud\Benchmark" -DestinationPath "C:\OSDCloud\Benchmark\Benchmark.iso"
}

# Display results table
`$results | Format-Table -Property Name, Success, @{Name="Time (seconds)"; Expression={`$_.TimeSeconds}}, Error -AutoSize

# Clean up benchmark files
Remove-Item -Path "C:\OSDCloud\Benchmark" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:ProgramData\OSDCloud\Templates\BenchmarkTest" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Benchmark completed. Use these results to optimize your deployment process."
"@

$benchmarkScriptPath = "$workspace\OSDCloud-Benchmark.ps1"
Set-Content -Path $benchmarkScriptPath -Value $benchmarkScriptContent -Force
Write-Host "⏱️ Created performance benchmark at: $benchmarkScriptPath" -ForegroundColor Green

# 6. Create optimization recommendations based on the current setup
$optimizationRecommendations = @()

# Check system specs for performance bottlenecks
$cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
$ram = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
$systemDrive = Get-PSDrive C
$freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)

# CPU check
if ($cpu.NumberOfCores -lt 4) {
    $optimizationRecommendations += "⚠️ Low CPU cores detected ($($cpu.NumberOfCores)). OSDCloud performs better with 4+ cores."
}

# RAM check
if ($ram -lt 8) {
    $optimizationRecommendations += "⚠️ Low RAM detected ($ram GB). OSDCloud performs better with 8+ GB of RAM."
}

# Disk space check
if ($freeSpaceGB -lt 20) {
    $optimizationRecommendations += "⚠️ Low disk space detected ($freeSpaceGB GB). Free up at least 20GB for optimal performance."
}

# Check if running on SSD
try {
    $diskDrive = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq 0 }
    if ($diskDrive.MediaType -ne "SSD") {
        $optimizationRecommendations += "⚠️ Running on non-SSD media. OSDCloud performs significantly better on SSDs."
    }
}
catch {
    # Silently continue if we can't determine disk type
}

# Check for Windows ADK and DISM versions
$dismVersion = $null
try {
    $dismInfo = (dism /English /? | Select-String -Pattern "Version: (\d+\.\d+\.\d+\.\d+)").Matches
    if ($dismInfo.Count -gt 0) {
        $dismVersion = $dismInfo[0].Groups[1].Value
        # Check if DISM version is outdated
        if ([Version]$dismVersion -lt [Version]"10.0.19041.0") {
            $optimizationRecommendations += "⚠️ DISM version ($dismVersion) is outdated. Update Windows ADK for better performance."
        }
    }
}
catch {
    # Silently continue if we can't determine DISM version
}

# Display optimization recommendations
if ($optimizationRecommendations.Count -gt 0) {
    Write-Host "`nPerformance Optimization Recommendations:" -ForegroundColor Yellow
    foreach ($recommendation in $optimizationRecommendations) {
        Write-Host $recommendation -ForegroundColor Yellow
    }

    # Add additional recommendations
    Write-Host "`nGeneral Performance Tips:" -ForegroundColor Cyan
    Write-Host "- Close other applications to free up memory when creating images" -ForegroundColor Cyan
    Write-Host "- Use smaller OS images when possible (Education/Pro instead of Enterprise)" -ForegroundColor Cyan
    Write-Host "- Run the cleanup script periodically to recover disk space" -ForegroundColor Cyan
    Write-Host "- Consider using PowerShell 7 for better performance" -ForegroundColor Cyan

    # Save recommendations to a file
    $recommendationsPath = "$workspace\OSDCloud-Recommendations.txt"
    $recommendationsContent = @"
# OSDCloud Performance Recommendations
# Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm")

## System Analysis
- CPU: $($cpu.Name) ($($cpu.NumberOfCores) cores)
- RAM: $ram GB
- Free Disk Space: $freeSpaceGB GB
- DISM Version: $dismVersion

## Specific Recommendations
$([string]::Join("`n", $optimizationRecommendations))

## General Performance Tips
- Close other applications to free up memory when creating images
- Use smaller OS images when possible (Education/Pro instead of Enterprise)
- Run the cleanup script periodically to recover disk space
- Consider using PowerShell 7 for better performance
- Set up a RAM disk for temporary files if you have 16+ GB of RAM
- For frequent deployments, consider setting up a dedicated OSDCloud server

## Advanced Optimizations
- Use 7-Zip maximum compression for WIM files to save space
- Pre-download driver packs and store them locally
- Create a minimal template without extra modules for faster boot times
- Consider network-based deployments for large environments
"@

    Set-Content -Path $recommendationsPath -Value $recommendationsContent -Force
    Write-Host "📋 Created performance recommendations at: $recommendationsPath" -ForegroundColor Green
}

Write-Host "`nPerformance optimizations and tools have been added!" -ForegroundColor Green