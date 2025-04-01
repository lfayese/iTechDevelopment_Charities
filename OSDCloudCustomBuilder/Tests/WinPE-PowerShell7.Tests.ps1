# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\WinPE-PowerShell7.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Write-OSDCloudLog {}
    function Test-ValidPowerShellVersion { param("$Version") return $true }
    function Get-PowerShell7Package { param($Version, $DownloadPath) return "C:\TestPath\PowerShell-7.3.4-win-x64.zip" }
}

Describe "WinPE PowerShell 7 Functions" {
    BeforeEach {
        # Setup common mocks for each test
        Mock Mount-WindowsImage { return "$true" }
        Mock Dismount-WindowsImage { return "$true" }
        Mock Expand-Archive { return "$true" }
        Mock Copy-Item { return "$true" }
        Mock New-Item { return [PSCustomObject]@{ FullName = "$Path" } }
        Mock Test-Path { return "$true" }
        Mock Write-OSDCloudLog {}
        Mock reg { return "$true" }
        Mock New-ItemProperty { return [PSCustomObject]@{ Property = "Value" } }
        Mock [System.IO.File]::WriteAllText {}
    }
    
    Context "Initialize-WinPEMountPoint" {
        It "Should create a mount point directory" {
            $result = Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud"
            
            "$result" | Should -Not -BeNullOrEmpty
            $result.MountPoint | Should -BeLike "C:\Temp\OSDCloud\Mount_*"
            $result.PS7TempPath | Should -BeLike "C:\Temp\OSDCloud\PS7_*"
            "$result".InstanceId | Should -Not -BeNullOrEmpty
            
            Should -Invoke New-Item -Times 2
        }
        
        It "Should use the provided instance ID" {
            $result = Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud" -InstanceId "TestID"
            
            $result.MountPoint | Should -Be "C:\Temp\OSDCloud\Mount_TestID"
            $result.PS7TempPath | Should -Be "C:\Temp\OSDCloud\PS7_TestID"
            $result.InstanceId | Should -Be "TestID"
        }
    }
    
    Context "Get-PowerShell7Package" {
        It "Should return the path of an existing package" {
            $result = Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp"
            
            $result | Should -Be "C:\TestPath\PowerShell-7.3.4-win-x64.zip"
        }
    }
    
    Context "Mount-WinPEImage" {
        It "Should mount a WIM file successfully" {
            $result = Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount"
            
            "$result" | Should -BeTrue
            Should -Invoke Mount-WindowsImage -Times 1
        }
        
        It "Should use the specified index" {
            Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount" -Index 2
            
            Should -Invoke Mount-WindowsImage -ParameterFilter { "$Index" -eq 2 } -Times 1
        }
    }
    
    Context "Install-PowerShell7ToWinPE" {
        It "Should extract PowerShell 7 to the WinPE image" {
            $result = Install-PowerShell7ToWinPE -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" `
                                               -TempPath "C:\Temp\PS7" `
                                               -MountPoint "C:\Temp\Mount"
            
            Should -Invoke Expand-Archive -Times 1
            Should -Invoke Test-Path -Times 1
        }
    }
    
    Context "Update-WinPERegistry" {
        It "Should update registry settings" {
            $result = Update-WinPERegistry -MountPoint "C:\Temp\Mount"
            
            Should -Invoke reg -Times 2
            Should -Invoke New-ItemProperty -Times 2
        }
    }
    
    Context "Update-WinPEStartup" {
        It "Should create a startup script in the WinPE image" {
            $result = Update-WinPEStartup -MountPoint "C:\Temp\Mount"
            
            "$result" | Should -BeTrue
            Should -Invoke Test-Path -Times 1
        }
    }
    
    Context "Dismount-WinPEImage" {
        It "Should save changes when dismounting" {
            $result = Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount"
            
            "$result" | Should -BeTrue
            Should -Invoke Dismount-WindowsImage -ParameterFilter { "$Save" -eq $true } -Times 1
        }
        
        It "Should discard changes when specified" {
            Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount" -Discard
            
            Should -Invoke Dismount-WindowsImage -ParameterFilter { "$Discard" -eq $true } -Times 1
        }
    }
    
    Context "Update-WinPEWithPowerShell7" {
        It "Should perform the complete customization process" {
            Mock Initialize-WinPEMountPoint { 
                return @{
                    MountPoint = "C:\Temp\OSDCloud\Mount_TestID"
                    PS7TempPath = "C:\Temp\OSDCloud\PS7_TestID"
                    InstanceId = "TestID"
                }
            }
            Mock Get-PowerShell7Package { return "C:\Temp\PowerShell-7.3.4-win-x64.zip" }
            Mock Install-PowerShell7ToWinPE { return "$true" }
            Mock Update-WinPERegistry { return "$true" }
            Mock Update-WinPEStartup { return "$true" }
            Mock New-WinPEStartupProfile { return "$true" }
            Mock Dismount-WinPEImage { return "$true" }
            
            $result = Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud"
            
            $result | Should -Be "C:\OSDCloud\Media\Sources\boot.wim"
            Should -Invoke Initialize-WinPEMountPoint -Times 1
            Should -Invoke Mount-WinPEImage -Times 1
            Should -Invoke Install-PowerShell7ToWinPE -Times 1
            Should -Invoke Update-WinPERegistry -Times 1
            Should -Invoke Update-WinPEStartup -Times 1
            Should -Invoke New-WinPEStartupProfile -Times 1
            Should -Invoke Dismount-WinPEImage -Times 1
        }
        
        It "Should accept a provided PowerShell 7 package" {
            Mock Initialize-WinPEMountPoint { 
                return @{
                    MountPoint = "C:\Temp\OSDCloud\Mount_TestID"
                    PS7TempPath = "C:\Temp\OSDCloud\PS7_TestID"
                    InstanceId = "TestID"
                }
            }
            
            $result = Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" `
                                             -WorkspacePath "C:\OSDCloud" `
                                             -PowerShell7File "C:\Custom\PowerShell-7.3.4-win-x64.zip"
            
            Should -Not -Invoke Get-PowerShell7Package
            Should -Invoke Install-PowerShell7ToWinPE -ParameterFilter { 
                $PowerShell7File -eq "C:\Custom\PowerShell-7.3.4-win-x64.zip" 
            } -Times 1
        }
        
        It "Should properly handle alias for backward compatibility" {
            # Test alias usage
            Mock Update-WinPEWithPowerShell7 { return "C:\TestPath\boot.wim" }
            
            # This should call Update-WinPEWithPowerShell7 via the alias
            $result = Customize-WinPEWithPowerShell7 -TempPath "C:\Temp" -WorkspacePath "C:\Workspace"
            
            $result | Should -Be "C:\TestPath\boot.wim"
            Should -Invoke Update-WinPEWithPowerShell7 -Times 1
        }
    }
}