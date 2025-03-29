Describe "Test-WimFile" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Test-WimFile.ps1"
        
        # Mock Test-Path to control function flow
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\valid\file.wim" }
        Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\invalid\file.wim" }
        
        # Mock Get-WindowsImage for success scenario
        Mock Get-WindowsImage {
            return [PSCustomObject]@{
                ImageName = "Windows 10 Enterprise"
                ImageDescription = "Windows 10 Enterprise"
                ImageSize = 5GB
            }
        } -ParameterFilter { $ImagePath -eq "C:\valid\file.wim" }
        
        # Mock Get-WindowsImage for failure scenario
        Mock Get-WindowsImage {
            throw "Invalid WIM file"
        } -ParameterFilter { $ImagePath -eq "C:\error\file.wim" }
        
        # Mock Write-Host and Write-Error to suppress output
        Mock Write-Host {}
        Mock Write-Error {}
    }
    
    It "Throws an error when the WIM file doesn't exist" {
        { Test-WimFile -WimPath "C:\invalid\file.wim" } | Should -Throw "The specified WIM file does not exist"
    }
    
    It "Returns WIM information for a valid WIM file" {
        $result = Test-WimFile -WimPath "C:\valid\file.wim"
        
        $result.ImageName | Should -Be "Windows 10 Enterprise"
        $result.ImageDescription | Should -Be "Windows 10 Enterprise"
        $result.ImageSize | Should -Be 5GB
    }
    
    It "Throws an error when the file is not a valid WIM" {
        # First mock Test-Path to return true for this test
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\error\file.wim" }
        
        { Test-WimFile -WimPath "C:\error\file.wim" } | Should -Throw "The specified file is not a valid Windows Image file"
    }
    
    It "Calls Get-WindowsImage with the correct parameters" {
        $result = Test-WimFile -WimPath "C:\valid\file.wim"
        
        Should -Invoke Get-WindowsImage -Times 1 -ParameterFilter {
            $ImagePath -eq "C:\valid\file.wim" -and
            $Index -eq 1 -and
            $ErrorAction -eq "Stop"
        }
    }
}