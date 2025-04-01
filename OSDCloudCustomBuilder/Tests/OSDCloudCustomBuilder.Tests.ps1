# Patched
Set-StrictMode -Version Latest
Describe "OSDCloudCustomBuilder Module Tests" {
    BeforeAll {
        # Load the functions directly for testing
        . "$PSScriptRoot\..\Public\Add-CustomWimWithPwsh7.ps1"
        . "$PSScriptRoot\..\Public\New-CustomOSDCloudISO.ps1"
        . "$PSScriptRoot\..\Private\Test-WimFile.ps1"
        
        # Define the mocks for external commands
        function New-OSDCloudTemplate { return "$true" }
        function New-OSDCloudWorkspace { return "$true" }
        function New-OSDCloudISO { return "$true" }
        function Mount-WindowsImage { return "$true" }
        function Dismount-WindowsImage { return "$true" }
        function Get-WindowsImage { 
            return [PSCustomObject]@{
                ImageName = "Windows 10 Enterprise"
                ImageDescription = "Windows 10 Enterprise"
                ImageSize = 4GB
            }
        }
        function Invoke-WebRequest { return "$true" }
        
        # Mock all the private functions to avoid actual execution
        function Initialize-BuildEnvironment { param("$OutputPath") }
        function New-WorkspaceDirectory { param($OutputPath) return "C:\Temp\Workspace" }
        function Get-PowerShell7Package { param($PowerShell7Url, $TempPath) return "C:\Temp\Workspace\PowerShell-7.5.0-win-x64.zip" }
        function Initialize-OSDCloudTemplate { param($TempPath) return "C:\Temp\Workspace\OSDCloudWorkspace" }
        function Copy-CustomWimToWorkspace { param("$WimPath", $WorkspacePath) }
        function Copy-CustomizationScripts { param("$WorkspacePath", $ScriptPath) }
        function Update-WinPEWithPowerShell7 { param($TempPath, $WorkspacePath, $PowerShell7File) return "C:\bootWimPath" }
        function Optimize-ISOSize { param("$WorkspacePath") }
        function New-CustomISO { param("$WorkspacePath", $OutputPath, $ISOFileName, [switch]$IncludeWinRE) }
        function Remove-TempFiles { param("$TempPath") }
        function Show-Summary { param("$WimPath", $ISOPath, [switch]$IncludeWinRE) }
        
        # Mock Split-Path to avoid null path issues
        function Split-Path {
            param(
                [Parameter(ValueFromPipeline = "$true")]
                [string]"$Path",
                [switch]"$Parent",
                [switch]"$Leaf",
                [switch]"$LeafBase",
                [switch]"$Extension",
                [switch]"$Qualifier",
                [switch]"$NoQualifier",
                [switch]"$Resolve",
                [switch]$IsAbsolute
            )
            
            # Always return a consistent path for the test
            return "C:\ModulePath"
        }
    }
    
    Context "Module Functions" {
        It "Should be able to access the Add-CustomWimWithPwsh7 function" {
            { Get-Command Add-CustomWimWithPwsh7 -ErrorAction Stop } | Should -Not -Throw
        }
        
        It "Should be able to access the New-CustomOSDCloudISO function" {
            { Get-Command New-CustomOSDCloudISO -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context "Add-CustomWimWithPwsh7 Function" {
        It "Should run without errors with minimum parameters" {
            # Mock Test-WimFile directly to ensure it returns a valid result
            Mock Test-WimFile { 
                return [PSCustomObject]@{ 
                    ImageName = "Test Image"
                    ImageDescription = "Test Image Description"
                    ImageSize = 5GB
                }
            }
            
            { Add-CustomWimWithPwsh7 -WimPath "C:\Test\windows.wim" -OutputPath "C:\Output" -SkipAdminCheck } | Should -Not -Throw
        }
        
        It "Should run without errors with all parameters" {
            # Mock Test-WimFile directly to ensure it returns a valid result
            Mock Test-WimFile { 
                return [PSCustomObject]@{ 
                    ImageName = "Test Image"
                    ImageDescription = "Test Image Description"
                    ImageSize = 5GB
                }
            }
            
            { 
                Add-CustomWimWithPwsh7 -WimPath "C:\Test\windows.wim" `
                                     -OutputPath "C:\Output" `
                                     -ISOFileName "Custom.iso" `
                                     -PowerShell7Url "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip" `
                                     -IncludeWinRE `
                                     -SkipCleanup `
                                     -SkipAdminCheck
            } | Should -Not -Throw
        }
        
        It "Should call all required internal functions" {
            # Mock functions to verify they're called
            Mock Initialize-BuildEnvironment {}
            Mock Test-WimFile { 
                return [PSCustomObject]@{ 
                    ImageName = "Test Image"
                    ImageDescription = "Test Image Description"
                    ImageSize = 5GB
                }
            }
            Mock New-WorkspaceDirectory { return "C:\Temp\Workspace" }
            Mock Get-PowerShell7Package { return "C:\Temp\PowerShell.zip" }
            Mock Initialize-OSDCloudTemplate { return "C:\Temp\OSDWorkspace" }
            Mock Copy-CustomWimToWorkspace {}
            Mock Copy-CustomizationScripts {}
            Mock Update-WinPEWithPowerShell7 { return "C:\bootWimPath" }
            Mock Optimize-ISOSize {}
            Mock New-CustomISO {}
            Mock Remove-TempFiles {}
            Mock Show-Summary {}
            
            Add-CustomWimWithPwsh7 -WimPath "C:\Test\windows.wim" -OutputPath "C:\Output" -SkipAdminCheck
            
            Should -Invoke Initialize-BuildEnvironment -Times 1
            Should -Invoke Test-WimFile -Times 1
            Should -Invoke New-WorkspaceDirectory -Times 1
            Should -Invoke Get-PowerShell7Package -Times 1
            Should -Invoke Initialize-OSDCloudTemplate -Times 1
            Should -Invoke Copy-CustomWimToWorkspace -Times 1
            Should -Invoke Copy-CustomizationScripts -Times 1
            Should -Invoke Update-WinPEWithPowerShell7 -Times 1
            Should -Invoke Optimize-ISOSize -Times 1
            Should -Invoke New-CustomISO -Times 1
            Should -Invoke Remove-TempFiles -Times 1
            Should -Invoke Show-Summary -Times 1
        }
        
        It "Should not call Remove-TempFiles when SkipCleanup is specified" {
            # Mock functions to verify they're called
            Mock Initialize-BuildEnvironment {}
            Mock Test-WimFile { 
                return [PSCustomObject]@{ 
                    ImageName = "Test Image"
                    ImageDescription = "Test Image Description"
                    ImageSize = 5GB
                }
            }
            Mock New-WorkspaceDirectory { return "C:\Temp\Workspace" }
            Mock Get-PowerShell7Package { return "C:\Temp\PowerShell.zip" }
            Mock Initialize-OSDCloudTemplate { return "C:\Temp\OSDWorkspace" }
            Mock Copy-CustomWimToWorkspace {}
            Mock Copy-CustomizationScripts {}
            Mock Update-WinPEWithPowerShell7 { return "C:\bootWimPath" }
            Mock Optimize-ISOSize {}
            Mock New-CustomISO {}
            Mock Remove-TempFiles {}
            Mock Show-Summary {}
            
            Add-CustomWimWithPwsh7 -WimPath "C:\Test\windows.wim" -OutputPath "C:\Output" -SkipCleanup -SkipAdminCheck
            
            Should -Invoke Remove-TempFiles -Times 0
        }
    }
    
    Context "Copy-WimFileEfficiently Function" {
        BeforeAll {
            # Import the function directly
            . "$PSScriptRoot\..\Private\Copy-WimFileEfficiently.ps1"
            
            # Mock test paths to handle file existence check
            Mock Test-Path { $true } -ParameterFilter { $Path -like "C:\Dest\*" }
            
            # Mock Start-Process for robocopy
            Mock Start-Process { 
                return [PSCustomObject]@{
                    ExitCode = 1  # Success for robocopy
                }
            }
            
            # Mock filesystem operations
            Mock Rename-Item {}
            Mock Write-Verbose {}
            Mock Write-Error {}
        }
        
        It "Should handle successful file copy" {
            $result = Copy-WimFileEfficiently -SourcePath "C:\Source\file.wim" -DestinationPath "C:\Dest\file.wim"
            "$result" | Should -Be $true
            Should -Invoke Start-Process -Times 1
        }
        
        It "Should handle renaming copied files" {
            $result = Copy-WimFileEfficiently -SourcePath "C:\Source\file.wim" -DestinationPath "C:\Dest\file.wim" -NewName "newname.wim"
            "$result" | Should -Be $true
            Should -Invoke Start-Process -Times 1
            Should -Invoke Rename-Item -Times 1
        }
        
        It "Should report failure when robocopy fails" {
            Mock Start-Process { 
                return [PSCustomObject]@{
                    ExitCode = 8  # Failure for robocopy
                }
            }
            
            $result = Copy-WimFileEfficiently -SourcePath "C:\Source\file.wim" -DestinationPath "C:\Dest\file.wim"
            "$result" | Should -Be $false
        }
    }
}