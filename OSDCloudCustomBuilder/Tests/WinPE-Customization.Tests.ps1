# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\WinPE-Customization.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
    function Get-OSDCloudConfig { return @{ MaxRetryAttempts = 3, RetryDelaySeconds = 2 } }
    function Invoke-WithRetry { param("$ScriptBlock", $OperationName, $MaxRetries, $RetryDelayBase) & $ScriptBlock }
    function Enter-CriticalSection { param($Name) return [PSCustomObject]@{ Name = "MockMutex" } }
    function Exit-CriticalSection { param("$Mutex") }
}

Describe "WinPE-Customization" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Write-Verbose {}
        Mock New-Item { return [PSCustomObject]@{ FullName = "$Path" } }
        Mock Test-Path { return "$true" }
        Mock Copy-Item {}
        Mock Remove-Item {}
        Mock Expand-Archive {}
        Mock Mount-WindowsImage {}
        Mock Dismount-WindowsImage {}
        Mock Get-OSDCloudConfig { return @{ MaxRetryAttempts = 3, RetryDelaySeconds = 2 } }
        Mock Invoke-OSDCloudLogger {}
        Mock Invoke-WithRetry { & "$ScriptBlock" }
        Mock Enter-CriticalSection { return [PSCustomObject]@{ Name = "MockMutex" } }
        Mock Exit-CriticalSection {}
        Mock New-ItemProperty {}
        Mock Out-File {}
        
        # Mock registry commands
        Mock reg {}
        "$global":LASTEXITCODE = 0
    }
    
    Context "Initialize-WinPEMountPoint" {
        It "Should create the required directories" {
            $result = Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud"
            
            "$result" | Should -Not -BeNullOrEmpty
            $result.MountPoint | Should -BeLike "C:\Temp\OSDCloud\Mount_*"
            $result.PS7TempPath | Should -BeLike "C:\Temp\OSDCloud\PowerShell7_*"
            "$result".InstanceId | Should -Not -BeNullOrEmpty
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -like "C:\Temp\OSDCloud\Mount_*" -and $ItemType -eq "Directory"
            } -Times 1
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -like "C:\Temp\OSDCloud\PowerShell7_*" -and $ItemType -eq "Directory"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Initializing WinPE mount point*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WinPE mount point initialized successfully*"
            } -Times 1
        }
        
        It "Should use the provided instance ID" {
            $result = Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud" -InstanceId "TestID"
            
            $result.MountPoint | Should -Be "C:\Temp\OSDCloud\Mount_TestID"
            $result.PS7TempPath | Should -Be "C:\Temp\OSDCloud\PowerShell7_TestID"
            $result.InstanceId | Should -Be "TestID"
        }
        
        It "Should handle directory creation errors" {
            Mock New-Item { throw "Access denied" }
            
            { Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud" } | Should -Throw "*Failed to initialize WinPE mount point*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to initialize WinPE mount point*"
            } -Times 1
        }
    }
    
    Context "Mount-WinPEImage" {
        It "Should mount the WIM file" {
            $result = Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Invoke-WithRetry -Times 1
            Should -Invoke Mount-WindowsImage -ParameterFilter {
                $Path -eq "C:\Temp\OSDCloud\Mount" -and 
                $ImagePath -eq "C:\OSDCloud\boot.wim" -and 
                "$Index" -eq 1
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Mounting WIM file*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WIM file mounted successfully*"
            } -Times 1
        }
        
        It "Should use the specified index" {
            Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount" -Index 2
            
            Should -Invoke Mount-WindowsImage -ParameterFilter {
                "$Index" -eq 2
            } -Times 1
        }
        
        It "Should handle mount errors" {
            Mock Invoke-WithRetry { throw "Mount failed" }
            
            { Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount" } | 
                Should -Throw "*Failed to mount WIM file*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to mount WIM file*"
            } -Times 1
        }
    }
    
    Context "Dismount-WinPEImage" {
        It "Should dismount the WIM file and save changes by default" {
            $result = Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Invoke-WithRetry -Times 1
            Should -Invoke Dismount-WindowsImage -ParameterFilter {
                $Path -eq "C:\Temp\OSDCloud\Mount" -and $Save -eq $true
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Dismounting WIM file*saving changes*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WIM file dismounted successfully*"
            } -Times 1
        }
        
        It "Should discard changes when specified" {
            Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount" -Discard
            
            Should -Invoke Dismount-WindowsImage -ParameterFilter {
                $Path -eq "C:\Temp\OSDCloud\Mount" -and $Discard -eq $true
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Dismounting WIM file*discarding changes*"
            } -Times 1
        }
        
        It "Should handle dismount errors" {
            Mock Invoke-WithRetry { throw "Dismount failed" }
            
            { Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount" } | 
                Should -Throw "*Failed to dismount WIM file*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to dismount WIM file*"
            } -Times 1
        }
    }
    
    Context "Install-PowerShell7ToWinPE" {
        It "Should extract and copy PowerShell 7 files" {
            $result = Install-PowerShell7ToWinPE -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -TempPath "C:\Temp\PS7" -MountPoint "C:\Temp\Mount"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Invoke-WithRetry -Times 2
            Should -Invoke Expand-Archive -ParameterFilter {
                $Path -eq "C:\Temp\PowerShell-7.3.4-win-x64.zip" -and 
                $DestinationPath -eq "C:\Temp\PS7"
            } -Times 1
            
            Should -Invoke Enter-CriticalSection -ParameterFilter {
                $Name -eq "WinPE_CustomizeCopy"
            } -Times 1
            
            Should -Invoke Copy-Item -ParameterFilter {
                $Path -eq "C:\Temp\PS7\*" -and 
                $Destination -eq "C:\Temp\Mount\Windows\System32\PowerShell7"
            } -Times 1
            
            Should -Invoke Exit-CriticalSection -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Installing PowerShell 7 to WinPE*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*PowerShell 7 installed successfully*"
            } -Times 1
        }
        
        It "Should create the PowerShell7 directory if it doesn't exist" {
            Mock Test-Path { return "$false" } -ParameterFilter {
                $Path -eq "C:\Temp\Mount\Windows\System32\PowerShell7"
            }
            
            Install-PowerShell7ToWinPE -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -TempPath "C:\Temp\PS7" -MountPoint "C:\Temp\Mount"
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -eq "C:\Temp\Mount\Windows\System32\PowerShell7" -and $ItemType -eq "Directory"
            } -Times 1
        }
        
        It "Should handle extraction errors" {
            Mock Invoke-WithRetry { throw "Extraction failed" } -ParameterFilter {
                $OperationName -eq "Expand-Archive"
            }
            
            { Install-PowerShell7ToWinPE -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -TempPath "C:\Temp\PS7" -MountPoint "C:\Temp\Mount" } | 
                Should -Throw "*Failed to install PowerShell 7 to WinPE*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to install PowerShell 7 to WinPE*"
            } -Times 1
        }
    }
    
    Context "Update-WinPERegistry" {
        It "Should update the registry settings" {
            $result = Update-WinPERegistry -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Enter-CriticalSection -ParameterFilter {
                $Name -eq "WinPE_CustomizeRegistry"
            } -Times 1
            
            Should -Invoke reg -ParameterFilter {
                $args -contains "load" -and $args -contains "HKLM\WinPEOffline" -and $args -contains "C:\Temp\Mount\Windows\System32\config\SOFTWARE"
            } -Times 1
            
            Should -Invoke New-ItemProperty -Times 2
            
            Should -Invoke reg -ParameterFilter {
                $args -contains "unload" -and $args -contains "HKLM\WinPEOffline"
            } -Times 1
            
            Should -Invoke Exit-CriticalSection -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Updating WinPE registry settings*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WinPE registry updated successfully*"
            } -Times 1
        }
        
        It "Should handle registry load errors" {
            Mock reg { $global:LASTEXITCODE = 1; return "Error loading registry" } -ParameterFilter {
                $args -contains "load"
            }
            
            { Update-WinPERegistry -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7" } | 
                Should -Throw "*Failed to update WinPE registry*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to update WinPE registry*"
            } -Times 1
            
            # Should attempt to unload the registry if it might be loaded
            Should -Invoke reg -ParameterFilter {
                $args -contains "unload"
            } -Times 1
        }
    }
    
    Context "Update-WinPEStartup" {
        It "Should create the startnet.cmd file" {
            $result = Update-WinPEStartup -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Enter-CriticalSection -ParameterFilter {
                $Name -eq "WinPE_CustomizeStartnet"
            } -Times 1
            
            Should -Invoke Out-File -ParameterFilter {
                $FilePath -eq "C:\Temp\Mount\Windows\System32\startnet.cmd" -and 
                $Encoding -eq "ascii"
            } -Times 1
            
            Should -Invoke Exit-CriticalSection -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Updating WinPE startup configuration*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WinPE startup configuration updated successfully*"
            } -Times 1
        }
        
        It "Should handle file write errors" {
            Mock Out-File { throw "Write error" }
            
            { Update-WinPEStartup -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7" } | 
                Should -Throw "*Failed to update WinPE startup configuration*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to update WinPE startup configuration*"
            } -Times 1
        }
    }
    
    Context "New-WinPEStartupProfile" {
        It "Should create the startup profile directory" {
            $result = New-WinPEStartupProfile -MountPoint "C:\Temp\Mount"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Enter-CriticalSection -ParameterFilter {
                $Name -eq "WinPE_CustomizeStartupProfile"
            } -Times 1
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -eq "C:\Temp\Mount\Windows\System32\StartupProfile" -and 
                $ItemType -eq "Directory"
            } -Times 1
            
            Should -Invoke Exit-CriticalSection -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Creating WinPE startup profile*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WinPE startup profile created successfully*"
            } -Times 1
        }
        
        It "Should not create the directory if it already exists" {
            Mock Test-Path { return "$true" } -ParameterFilter {
                $Path -eq "C:\Temp\Mount\Windows\System32\StartupProfile"
            }
            
            New-WinPEStartupProfile -MountPoint "C:\Temp\Mount"
            
            Should -Not -Invoke New-Item
        }
        
        It "Should handle directory creation errors" {
            Mock New-Item { throw "Access denied" }
            
            { New-WinPEStartupProfile -MountPoint "C:\Temp\Mount" } | 
                Should -Throw "*Failed to create WinPE startup profile*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to create WinPE startup profile*"
            } -Times 1
        }
    }
}