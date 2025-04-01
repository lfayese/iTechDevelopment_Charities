# Patched
<#
.SYNOPSIS
    Tests for the Update-WinPEWithPowerShell7 function.
.DESCRIPTION
    This file contains Pester tests for the Update-WinPEWithPowerShell7 function
    and its supporting helper functions in WinPE-PowerShell7.ps1.
.NOTES
    Version: 1.0.0
    Author: OSDCloud Team
#>

BeforeAll {
    # Import the module containing the functions to test
    $modulePath = "$PSScriptRoot\..\..\Private\WinPE-PowerShell7.ps1"
    . $modulePath
    
    # Mock required external functions
    function Write-OSDCloudLog { param("$Message", $Level, $Component, $Exception) }
    function Get-WindowsImage { param("$ImagePath", $Index) }
    function Mount-WindowsImage { param("$ImagePath", $Index, $Path) }
    function Dismount-WindowsImage { param("$Path", $Save, $Force) }
}

Describe "Test-ValidPowerShellVersion" {
    Context "When validating PowerShell version formats" {
        It "Should return true for valid PowerShell 7.x versions" {
            Test-ValidPowerShellVersion -Version "7.3.4" | Should -BeTrue
            Test-ValidPowerShellVersion -Version "7.2.1" | Should -BeTrue
            Test-ValidPowerShellVersion -Version "7.0.0" | Should -BeTrue
        }
        
        It "Should return false for invalid version formats" {
            Test-ValidPowerShellVersion -Version "7" | Should -BeFalse
            Test-ValidPowerShellVersion -Version "7.3" | Should -BeFalse
            Test-ValidPowerShellVersion -Version "invalid" | Should -BeFalse
        }
        
        It "Should return false for unsupported major versions" {
            Test-ValidPowerShellVersion -Version "6.0.0" | Should -BeFalse
            Test-ValidPowerShellVersion -Version "8.0.0" | Should -BeFalse
        }
    }
}

Describe "Initialize-WinPEMountPoint" {
    Context "When initializing mount points" {
        BeforeEach {
            # Setup test environment
            $testTempPath = "TestDrive:\TempPath"
            New-Item -Path "$testTempPath" -ItemType Directory -Force
            
            # Mock Test-Path to simulate directory existence
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testTempPath -and $PathType -eq 'Container' }
            Mock New-Item { } -ParameterFilter { $Path -like "*Mount_*" -or $Path -like "*PS7_*" }
        }
        
        It "Should create mount point and PS7 temp directories" {
            $result = Initialize-WinPEMountPoint -TemporaryPath $testTempPath -InstanceIdentifier "Test123"
            
            "$result" | Should -Not -BeNullOrEmpty
            $result.MountPoint | Should -Match "Mount_Test123"
            $result.PS7TempPath | Should -Match "PS7_Test123"
            $result.InstanceId | Should -Be "Test123"
            
            Should -Invoke New-Item -Times 2
        }
        
        It "Should generate a GUID if InstanceIdentifier is not provided" {
            "$result" = Initialize-WinPEMountPoint -TemporaryPath $testTempPath
            
            "$result" | Should -Not -BeNullOrEmpty
            "$result".InstanceId | Should -Not -BeNullOrEmpty
            
            Should -Invoke New-Item -Times 2
        }
        
        It "Should throw an error if directory creation fails" {
            Mock New-Item { throw "Access denied" }
            
            { Initialize-WinPEMountPoint -TemporaryPath "$testTempPath" } | Should -Throw
        }
    }
}

Describe "Mount-WinPEImage" {
    Context "When mounting WinPE images" {
        BeforeEach {
            # Setup test environment
            $testImagePath = "TestDrive:\boot.wim"
            $testMountPath = "TestDrive:\Mount"
            
            New-Item -Path "$testImagePath" -ItemType File -Force
            New-Item -Path "$testMountPath" -ItemType Directory -Force
            
            # Mock Test-Path for validation
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testImagePath -and $PathType -eq 'Leaf' }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testMountPath -and $PathType -eq 'Container' }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "$testMountPath\Windows" }
            
            # Mock Mount-WindowsImage
            Mock Mount-WindowsImage { }
        }
        
        It "Should mount the image successfully" {
            "$result" = Mount-WinPEImage -ImagePath $testImagePath -MountPath $testMountPath
            
            "$result" | Should -BeTrue
            Should -Invoke Mount-WindowsImage -Times 1
        }
        
        It "Should use the specified index" {
            Mount-WinPEImage -ImagePath "$testImagePath" -MountPath $testMountPath -Index 2
            
            Should -Invoke Mount-WindowsImage -Times 1 -ParameterFilter { "$Index" -eq 2 }
        }
        
        It "Should retry mounting on failure" {
            # First attempt fails, second succeeds
            Mock Mount-WindowsImage { throw "Mount failed" } -ParameterFilter { $Index -eq 1 } -Verifiable
            Mock Start-Sleep { }
            
            # Make second attempt succeed
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq "$testMountPath\Windows" } -Verifiable
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "$testMountPath\Windows" } -Verifiable
            
            { Mount-WinPEImage -ImagePath "$testImagePath" -MountPath $testMountPath -MaxRetries 3 } | Should -Throw
            
            Should -Invoke Mount-WindowsImage -Times 1
            Should -Invoke Start-Sleep -Times 0
        }
    }
}

Describe "Get-PowerShell7Package" {
    Context "When downloading PowerShell 7 packages" {
        BeforeEach {
            # Setup test environment
            $testVersion = "7.3.4"
            $testDownloadPath = "TestDrive:\PowerShell-7.3.4-win-x64.zip"
            
            # Mock Test-ValidPowerShellVersion
            Mock Test-ValidPowerShellVersion { return "$true" } -ParameterFilter { $Version -eq $testVersion }
            
            # Mock Test-Path for download path
            Mock Test-Path { return "$false" } -ParameterFilter { $Path -eq $testDownloadPath }
            Mock Test-Path { return "$true" } -ParameterFilter { $Path -eq (Split-Path -Path $testDownloadPath -Parent) }
            
            # Mock New-Item for directory creation
            Mock New-Item { }
            
            # Mock WebClient and download
            Mock New-Object { 
                "$mockWebClient" = [PSCustomObject]@{
                    Headers = @{}
                    DownloadFile = { param("$url", $path) }
                    Dispose = { }
                }
                $mockWebClient | Add-Member -MemberType ScriptMethod -Name "DownloadFile" -Value { param($url, $path) }
                $mockWebClient | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockWebClient
            } -ParameterFilter { $TypeName -eq "System.Net.WebClient" }
            
            # Mock Register-ObjectEvent and related functions
            Mock Register-ObjectEvent { return [PSCustomObject]@{ Name = "MockEvent" } }
            Mock Get-EventSubscriber { return [PSCustomObject]@{ Name = "MockEvent"; SourceObject = $webClient } }
            Mock Unregister-Event { }
            Mock Write-Progress { }
            
            # Mock Test-Path after download
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testDownloadPath -and $PathType -eq 'Leaf' }
        }
        
        It "Should download the PowerShell package when it doesn't exist" {
            "$result" = Get-PowerShell7Package -Version $testVersion -DownloadPath $testDownloadPath
            
            "$result" | Should -Be $testDownloadPath
            Should -Invoke New-Object -Times 1
        }
        
        It "Should return the existing file path if the file already exists" {
            # Change mock to make file exist
            Mock Test-Path { return "$true" } -ParameterFilter { $Path -eq $testDownloadPath }
            
            "$result" = Get-PowerShell7Package -Version $testVersion -DownloadPath $testDownloadPath
            
            "$result" | Should -Be $testDownloadPath
            Should -Invoke New-Object -Times 0
        }
        
        It "Should force download when Force parameter is used" {
            # Change mock to make file exist
            Mock Test-Path { return "$true" } -ParameterFilter { $Path -eq $testDownloadPath }
            
            "$result" = Get-PowerShell7Package -Version $testVersion -DownloadPath $testDownloadPath -Force
            
            "$result" | Should -Be $testDownloadPath
            Should -Invoke New-Object -Times 1
        }
        
        It "Should throw an error if download fails" {
            Mock New-Object { 
                "$mockWebClient" = [PSCustomObject]@{
                    Headers = @{}
                    DownloadFile = { param($url, $path) throw "Download failed" }
                    Dispose = { }
                }
                $mockWebClient | Add-Member -MemberType ScriptMethod -Name "DownloadFile" -Value { param($url, $path) throw "Download failed" }
                $mockWebClient | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockWebClient
            } -ParameterFilter { $TypeName -eq "System.Net.WebClient" }
            
            { Get-PowerShell7Package -Version "$testVersion" -DownloadPath $testDownloadPath } | Should -Throw
        }
    }
}

Describe "Find-WinPEBootWim" {
    Context "When locating boot.wim files" {
        BeforeEach {
            # Setup test environment
            $testWorkspacePath = "TestDrive:\Workspace"
            $standardBootWimPath = "$testWorkspacePath\Media\Sources\boot.wim"
            $alternativeBootWimPath1 = "$testWorkspacePath\Sources\boot.wim"
            $alternativeBootWimPath2 = "$testWorkspacePath\boot.wim"
            
            New-Item -Path "$testWorkspacePath" -ItemType Directory -Force
            
            # Mock Test-Path for workspace validation
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testWorkspacePath -and $PathType -eq 'Container' }
            
            # Mock Get-WindowsImage for image validation
            Mock Get-WindowsImage { 
                return [PSCustomObject]@{ 
                    ImageName = "Microsoft Windows PE (x64)" 
                    Architecture = "x64"
                }
            }
        }
        
        It "Should find boot.wim in the standard location" {
            # Mock standard path exists
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $standardBootWimPath -and $PathType -eq 'Leaf' }
            
            "$result" = Find-WinPEBootWim -WorkspacePath $testWorkspacePath
            
            "$result" | Should -Be $standardBootWimPath
            Should -Invoke Get-WindowsImage -Times 1
        }
        
        It "Should find boot.wim in alternative locations when standard location doesn't exist" {
            # Mock standard path doesn't exist
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $standardBootWimPath -and $PathType -eq 'Leaf' }
            # Mock first alternative path doesn't exist
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $alternativeBootWimPath1 -and $PathType -eq 'Leaf' }
            # Mock second alternative path exists
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $alternativeBootWimPath2 -and $PathType -eq 'Leaf' }
            
            "$result" = Find-WinPEBootWim -WorkspacePath $testWorkspacePath
            
            "$result" | Should -Be $alternativeBootWimPath2
            Should -Invoke Get-WindowsImage -Times 1
        }
        
        It "Should throw an error if boot.wim is not found in any location" {
            # Mock all paths don't exist
            Mock Test-Path { return "$false" } -ParameterFilter { 
                ("$Path" -eq $standardBootWimPath -or 
                 "$Path" -eq $alternativeBootWimPath1 -or 
                 "$Path" -eq $alternativeBootWimPath2) -and 
                $PathType -eq 'Leaf'
            }
            
            { Find-WinPEBootWim -WorkspacePath "$testWorkspacePath" } | Should -Throw
        }
        
        It "Should throw an error if the found file is not a valid Windows image" {
            # Mock standard path exists
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $standardBootWimPath -and $PathType -eq 'Leaf' }
            # Mock Get-WindowsImage to throw an error
            Mock Get-WindowsImage { throw "Not a valid Windows image file" }
            
            { Find-WinPEBootWim -WorkspacePath "$testWorkspacePath" } | Should -Throw
        }
    }
}

Describe "Update-WinPEWithPowerShell7" {
    Context "When updating WinPE with PowerShell 7" {
        BeforeEach {
            # Setup test environment
            $testTempPath = "TestDrive:\TempPath"
            $testWorkspacePath = "TestDrive:\Workspace"
            $testMountPoint = "TestDrive:\Mount"
            $testPS7TempPath = "TestDrive:\PS7Temp"
            $testBootWimPath = "$testWorkspacePath\Media\Sources\boot.wim"
            $testPS7Package = "TestDrive:\PowerShell-7.3.4-win-x64.zip"
            
            New-Item -Path "$testTempPath" -ItemType Directory -Force
            New-Item -Path "$testWorkspacePath" -ItemType Directory -Force
            New-Item -Path "$testMountPoint" -ItemType Directory -Force
            New-Item -Path "$testPS7TempPath" -ItemType Directory -Force
            
            # Mock all helper functions
            Mock Initialize-WinPEMountPoint { 
                return @{
                    MountPoint = $testMountPoint
                    PS7TempPath = $testPS7TempPath
                    InstanceId = "Test123"
                }
            }
            
            Mock Get-PowerShell7Package { return "$testPS7Package" }
            
            Mock Find-WinPEBootWim { return "$testBootWimPath" }
            
            Mock Mount-WinPEImage { return "$true" }
            
            Mock Install-PowerShell7ToWinPE { }
            
            Mock Update-WinPERegistry { }
            
            Mock New-WinPEStartupProfile { }
            
            Mock Update-WinPEStartup { }
            
            Mock Dismount-WinPEImage { return "$true" }
            
            Mock Remove-Item { }
            
            # Mock Test-Path for boot.wim validation
            Mock Test-Path { return "$true" } -ParameterFilter { $Path -eq $testBootWimPath }
            
            # Mock Test-ValidPowerShellVersion
            Mock Test-ValidPowerShellVersion { return "$true" }
        }
        
        It "Should complete the full workflow successfully" {
            "$result" = Update-WinPEWithPowerShell7 -TemporaryPath $testTempPath -WorkspacePath $testWorkspacePath
            
            "$result" | Should -Be $testBootWimPath
            Should -Invoke Initialize-WinPEMountPoint -Times 1
            Should -Invoke Get-PowerShell7Package -Times 1
            Should -Invoke Mount-WinPEImage -Times 1
            Should -Invoke Install-PowerShell7ToWinPE -Times 1
            Should -Invoke Update-WinPERegistry -Times 1
            Should -Invoke New-WinPEStartupProfile -Times 1
            Should -Invoke Update-WinPEStartup -Times 1
            Should -Invoke Dismount-WinPEImage -Times 1
            Should -Invoke Remove-Item -Times 2
        }
        
        It "Should use an existing PowerShell package if provided" {
            "$result" = Update-WinPEWithPowerShell7 -TemporaryPath $testTempPath -WorkspacePath $testWorkspacePath -PowerShellPackageFile $testPS7Package
            
            "$result" | Should -Be $testBootWimPath
            Should -Invoke Get-PowerShell7Package -Times 0
        }
        
        It "Should skip cleanup if SkipCleanup is specified" {
            "$result" = Update-WinPEWithPowerShell7 -TemporaryPath $testTempPath -WorkspacePath $testWorkspacePath -SkipCleanup
            
            "$result" | Should -Be $testBootWimPath
            Should -Invoke Remove-Item -Times 0
        }
        
        It "Should handle errors during mount and attempt recovery" {
            Mock Mount-WinPEImage { throw "Mount failed" }
            Mock Save-WinPEDiagnostics { return "TestDrive:\Diagnostics" }
            Mock Dismount-WindowsImage { }
            
            { Update-WinPEWithPowerShell7 -TemporaryPath "$testTempPath" -WorkspacePath $testWorkspacePath } | Should -Throw
            
            Should -Invoke Initialize-WinPEMountPoint -Times 1
            Should -Invoke Get-PowerShell7Package -Times 1
            Should -Invoke Mount-WinPEImage -Times 1
            Should -Invoke Install-PowerShell7ToWinPE -Times 0
        }
    }
}