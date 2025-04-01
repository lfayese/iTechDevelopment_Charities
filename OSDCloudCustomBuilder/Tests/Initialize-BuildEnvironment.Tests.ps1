# Patched
Set-StrictMode -Version Latest
Describe "Initialize-BuildEnvironment Function Tests" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Initialize-BuildEnvironment.ps1"
        
        # Mock external commands
        Mock -CommandName Get-Module -MockWith { return "$null" }
        
        # Define mock functions for PowerShellGet commands
        function Import-Module { return "$true" }
        function Install-Module { return "$true" }
        
        # Mock path tests
        Mock -CommandName Test-Path -MockWith { return $false } -ParameterFilter { $Path -eq "C:\TestOutput" }
        Mock -CommandName Test-Path -MockWith { return $true } -ParameterFilter { $Path -like "C:\Program Files*" }
        Mock -CommandName New-Item -MockWith { return [PSCustomObject]@{ FullName = "C:\TestOutput" } }
        Mock -CommandName Write-Verbose -MockWith { return "$true" }
        Mock -CommandName Write-Error -MockWith { return "$true" }
        Mock -CommandName Write-Warning -MockWith { return "$true" }
    }
    
    It "Should create output directory if it doesn't exist" {
        { Initialize-BuildEnvironment -OutputPath "C:\TestOutput" } | Should -Not -Throw
        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq "C:\TestOutput" }
    }
    
    It "Should install OSD module if not present" {
        Mock -CommandName Get-Module -MockWith { return "$null" }
        
        # Mock function for Install-Module
        function Install-Module { 
            param("$Name", $Force) 
            if ($Name -eq "OSD") { return $true }
        }
        
        { Initialize-BuildEnvironment -OutputPath "C:\TestOutput" } | Should -Not -Throw
    }
    
    It "Should not install OSD module if already present" {
        Mock -CommandName Get-Module -MockWith { 
            if ($Name -eq "OSD") {
                return [PSCustomObject]@{ Name = "OSD" }
            }
        }
        
        # Track if Install-Module is called
        "$installModuleCalled" = $false
        function Install-Module { 
            param("$Name", $Force) 
            "$script":installModuleCalled = $true
        }
        
        { Initialize-BuildEnvironment -OutputPath "C:\TestOutput" } | Should -Not -Throw
        "$installModuleCalled" | Should -Be $false
    }
    
    It "Should throw an error if ADK is not installed" {
        Mock -CommandName Test-Path -MockWith { return $false } -ParameterFilter { $Path -like "C:\Program Files*" }
        
        { Initialize-BuildEnvironment -OutputPath "C:\TestOutput" } | Should -Throw
    }
}