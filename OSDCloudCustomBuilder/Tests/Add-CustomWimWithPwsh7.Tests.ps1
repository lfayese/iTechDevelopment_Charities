Describe "Add-CustomWimWithPwsh7" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Public\Add-CustomWimWithPwsh7.ps1"
        
        # Mock all the private functions to avoid actual execution
        function Initialize-BuildEnvironment { param($OutputPath) }
        function Test-WimFile { param($WimPath) return [PSCustomObject]@{ ImageName = "Test Image" } }
        function New-WorkspaceDirectory { param($OutputPath) return "C:\Temp\Workspace" }
        function Get-PowerShell7Package { param($PowerShell7Url, $TempPath) return "C:\Temp\Workspace\PowerShell-7.5.0-win-x64.zip" }
        function Initialize-OSDCloudTemplate { param($TempPath) return "C:\Temp\Workspace\OSDCloudWorkspace" }
        function Copy-CustomWimToWorkspace { param($WimPath, $WorkspacePath) }
        function Copy-CustomizationScripts { param($WorkspacePath, $ScriptPath) }
        function Customize-WinPEWithPowerShell7 { param($TempPath, $WorkspacePath, $PowerShell7File) return "C:\bootWimPath" }
        function Optimize-ISOSize { param($WorkspacePath) }
        function New-CustomISO { param($WorkspacePath, $OutputPath, $ISOFileName, [switch]$IncludeWinRE) }
        function Remove-TempFiles { param($TempPath) }
        function Show-Summary { param($WimPath, $ISOPath, [switch]$IncludeWinRE) }
        
        # Replace Split-Path with our own implementation to avoid null path errors
        function Split-Path {
            param(
                [Parameter(ValueFromPipeline = $true)]
                [string]$Path,
                [switch]$Parent,
                [switch]$Leaf,
                [switch]$LeafBase,
                [switch]$Extension,
                [switch]$Qualifier,
                [switch]$NoQualifier,
                [switch]$Resolve,
                [switch]$IsAbsolute
            )
            
            # Always return a consistent path for the test
            return "C:\ModulePath"
        }
        
        # Create parameter sets for testing
        $basicParams = @{
            WimPath = "C:\valid\file.wim"
            OutputPath = "C:\Output"
            SkipAdminCheck = $true  # Add this parameter to bypass admin check in tests
        }
        
        $advancedParams = @{
            WimPath = "C:\valid\file.wim"
            OutputPath = "C:\Output"
            ISOFileName = "Custom.iso"
            PowerShell7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip"
            IncludeWinRE = $true
            SkipCleanup = $true
            SkipAdminCheck = $true  # Add this parameter to bypass admin check in tests
        }
    }
    
    It "Calls all required functions with basic parameters" {
        # Mock all functions to verify they're called
        Mock Initialize-BuildEnvironment {}
        Mock Test-WimFile { return [PSCustomObject]@{ ImageName = "Test Image" } }
        Mock New-WorkspaceDirectory { return "C:\Temp\Workspace" }
        Mock Get-PowerShell7Package { return "C:\Temp\PowerShell.zip" }
        Mock Initialize-OSDCloudTemplate { return "C:\Temp\OSDWorkspace" }
        Mock Copy-CustomWimToWorkspace {}
        Mock Copy-CustomizationScripts {}
        Mock Customize-WinPEWithPowerShell7 { return "C:\bootWimPath" }
        Mock Optimize-ISOSize {}
        Mock New-CustomISO {}
        Mock Remove-TempFiles {}
        Mock Show-Summary {}
        
        # Call the function
        Add-CustomWimWithPwsh7 @basicParams
        
        # Verify all functions were called
        Should -Invoke Initialize-BuildEnvironment -Times 1
        Should -Invoke Test-WimFile -Times 1
        Should -Invoke New-WorkspaceDirectory -Times 1
        Should -Invoke Get-PowerShell7Package -Times 1
        Should -Invoke Initialize-OSDCloudTemplate -Times 1
        Should -Invoke Copy-CustomWimToWorkspace -Times 1
        Should -Invoke Copy-CustomizationScripts -Times 1
        Should -Invoke Customize-WinPEWithPowerShell7 -Times 1
        Should -Invoke Optimize-ISOSize -Times 1
        Should -Invoke New-CustomISO -Times 1
        Should -Invoke Remove-TempFiles -Times 1
        Should -Invoke Show-Summary -Times 1
    }
    
    It "Skips cleanup when SkipCleanup is specified" {
        # Mock all functions to verify they're called
        Mock Initialize-BuildEnvironment {}
        Mock Test-WimFile { return [PSCustomObject]@{ ImageName = "Test Image" } }
        Mock New-WorkspaceDirectory { return "C:\Temp\Workspace" }
        Mock Get-PowerShell7Package { return "C:\Temp\PowerShell.zip" }
        Mock Initialize-OSDCloudTemplate { return "C:\Temp\OSDWorkspace" }
        Mock Copy-CustomWimToWorkspace {}
        Mock Copy-CustomizationScripts {}
        Mock Customize-WinPEWithPowerShell7 { return "C:\bootWimPath" }
        Mock Optimize-ISOSize {}
        Mock New-CustomISO {}
        Mock Remove-TempFiles {}
        Mock Show-Summary {}
        
        # Call the function with SkipCleanup
        Add-CustomWimWithPwsh7 @advancedParams
        
        # Verify Remove-TempFiles was not called
        Should -Invoke Remove-TempFiles -Times 0
    }
    
    It "Passes IncludeWinRE parameter to New-CustomISO" {
        # Mock all functions to verify they're called
        Mock Initialize-BuildEnvironment {}
        Mock Test-WimFile { return [PSCustomObject]@{ ImageName = "Test Image" } }
        Mock New-WorkspaceDirectory { return "C:\Temp\Workspace" }
        Mock Get-PowerShell7Package { return "C:\Temp\PowerShell.zip" }
        Mock Initialize-OSDCloudTemplate { return "C:\Temp\OSDWorkspace" }
        Mock Copy-CustomWimToWorkspace {}
        Mock Copy-CustomizationScripts {}
        Mock Customize-WinPEWithPowerShell7 { return "C:\bootWimPath" }
        Mock Optimize-ISOSize {}
        Mock New-CustomISO {}
        Mock Remove-TempFiles {}
        Mock Show-Summary {}
        
        # Call the function with IncludeWinRE
        Add-CustomWimWithPwsh7 @advancedParams
        
        # Verify New-CustomISO was called with IncludeWinRE
        Should -Invoke New-CustomISO -Times 1 -ParameterFilter {
            $IncludeWinRE -eq $true
        }
    }
}