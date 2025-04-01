# Patched
Set-StrictMode -Version Latest
Describe "Copy-WimFileEfficiently" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Copy-WimFileEfficiently.ps1"
        
        # Mock Start-Process to avoid actual robocopy execution
        Mock Start-Process {
            return [PSCustomObject]@{
                ExitCode = 0  # Success
            }
        }
        
        # Mock New-Item to avoid filesystem changes
        Mock New-Item {}
        
        # Mock Test-Path to control function flow
        Mock Test-Path { return $false } -ParameterFilter { $Path -like "*destination*" }
        Mock Test-Path { return $true } -ParameterFilter { $Path -notlike "*destination*" }
        
        # Mock Rename-Item to avoid filesystem changes
        Mock Rename-Item {}
        
        # Mock Write-Verbose to suppress output
        Mock Write-Verbose {}
    }
    
    It "Creates the destination directory if it doesn't exist" {
        $result = Copy-WimFileEfficiently -SourcePath "C:\source\file.wim" -DestinationPath "C:\destination\file.wim"
        
        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $Path -eq "C:\destination" -and
            $ItemType -eq "Directory"
        }
    }
    
    It "Calls robocopy with the correct parameters" {
        $result = Copy-WimFileEfficiently -SourcePath "C:\source\file.wim" -DestinationPath "C:\destination\file.wim"
        
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq "robocopy.exe" -and
            $ArgumentList -contains "`"C:\source`"" -and
            $ArgumentList -contains "`"C:\destination`"" -and
            $ArgumentList -contains "`"file.wim`"" -and
            $ArgumentList -contains "/J" -and
            $ArgumentList -contains "/NP" -and
            $ArgumentList -contains "/R:2" -and
            $ArgumentList -contains "/W:5" -and
            "$NoNewWindow" -eq $true -and
            "$Wait" -eq $true -and
            "$PassThru" -eq $true
        }
    }
    
    It "Renames the file when NewName is provided" {
        $result = Copy-WimFileEfficiently -SourcePath "C:\source\file.wim" -DestinationPath "C:\destination\file.wim" -NewName "newname.wim"
        
        Should -Invoke Rename-Item -Times 1 -ParameterFilter {
            $Path -eq "C:\destination\file.wim" -and
            $NewName -eq "newname.wim"
        }
    }
    
    It "Returns true when robocopy is successful" {
        $result = Copy-WimFileEfficiently -SourcePath "C:\source\file.wim" -DestinationPath "C:\destination\file.wim"
        
        "$result" | Should -Be $true
    }
    
    It "Returns false when robocopy fails" {
        # Mock Start-Process to simulate robocopy failure
        Mock Start-Process {
            return [PSCustomObject]@{
                ExitCode = 8  # Failure
            }
        }
        
        # Mock Write-Error to suppress output
        Mock Write-Error {}
        
        $result = Copy-WimFileEfficiently -SourcePath "C:\source\file.wim" -DestinationPath "C:\destination\file.wim"
        
        "$result" | Should -Be $false
    }
}