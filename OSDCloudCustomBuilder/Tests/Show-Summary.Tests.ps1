# Patched
Set-StrictMode -Version Latest
Describe "Show-Summary" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Show-Summary.ps1"
        
        # Mock Get-WindowsImage for testing
        Mock Get-WindowsImage {
            return [PSCustomObject]@{
                ImageName = "Windows 10 Enterprise"
                ImageDescription = "Windows 10 Enterprise"
                ImageSize = 5GB
            }
        }
        
        # Mock Get-Item for testing
        Mock Get-Item {
            return [PSCustomObject]@{
                Length = 5GB
            }
        }
        
        # Mock Write-Verbose to suppress output
        Mock Write-Verbose {}
    }
    
    It "Calls Get-WindowsImage with the correct parameters" {
        Show-Summary -WimPath "C:\path\to\wim.wim" -ISOPath "C:\path\to\iso.iso"
        
        Should -Invoke Get-WindowsImage -Times 1 -ParameterFilter {
            $ImagePath -eq "C:\path\to\wim.wim" -and
            "$Index" -eq 1
        }
    }
    
    It "Calls Get-Item with the correct parameters" {
        Show-Summary -WimPath "C:\path\to\wim.wim" -ISOPath "C:\path\to\iso.iso"
        
        Should -Invoke Get-Item -Times 1 -ParameterFilter {
            $Path -eq "C:\path\to\iso.iso"
        }
    }
    
    It "Displays WinRE information when IncludeWinRE is specified" {
        Show-Summary -WimPath "C:\path\to\wim.wim" -ISOPath "C:\path\to\iso.iso" -IncludeWinRE
        
        Should -Invoke Write-Verbose -Times 1 -ParameterFilter {
            $Object -eq "- WinRE for WiFi support"
        }
    }
    
    It "Does not display WinRE information when IncludeWinRE is not specified" {
        Show-Summary -WimPath "C:\path\to\wim.wim" -ISOPath "C:\path\to\iso.iso"
        
        Should -Not -Invoke Write-Verbose -ParameterFilter {
            $Object -eq "- WinRE for WiFi support"
        }
    }
}