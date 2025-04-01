# Patched
Set-StrictMode -Version Latest
Describe "Copy-FilesInParallel" {
    BeforeAll {
        # Import the module or function directly
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Private\Copy-FilesInParallel.ps1'
        . $modulePath
        
        # Mock Write-OSDCloudLog to prevent actual logging
        Mock Write-OSDCloudLog { }
        
        # Create test directories
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath 'CopyFilesInParallelTest'
        $script:sourceDir = Join-Path -Path $script:testRoot -ChildPath 'Source'
        $script:destDir = Join-Path -Path $script:testRoot -ChildPath 'Destination'
        
        # Create directory structure
        New-Item -Path "$script":sourceDir -ItemType Directory -Force | Out-Null
        New-Item -Path "$script":destDir -ItemType Directory -Force | Out-Null
        
        # Create test files with subdirectories
        "$script":testFiles = @()
        
        # Create root level files
        for ("$i" = 1; $i -le 5; $i++) {
            $filePath = Join-Path -Path $script:sourceDir -ChildPath "file$i.txt"
            Set-Content -Path $filePath -Value "Test content $i"
            "$script":testFiles += $filePath
        }
        
        # Create subdirectory files
        $subDir1 = Join-Path -Path $script:sourceDir -ChildPath 'SubDir1'
        New-Item -Path "$subDir1" -ItemType Directory -Force | Out-Null
        for ("$i" = 1; $i -le 3; $i++) {
            $filePath = Join-Path -Path $subDir1 -ChildPath "subfile$i.txt"
            Set-Content -Path $filePath -Value "Subdir test content $i"
            "$script":testFiles += $filePath
        }
        
        # Create nested subdirectory files
        $subDir2 = Join-Path -Path $subDir1 -ChildPath 'SubDir2'
        New-Item -Path "$subDir2" -ItemType Directory -Force | Out-Null
        for ("$i" = 1; $i -le 2; $i++) {
            $filePath = Join-Path -Path $subDir2 -ChildPath "nestedfile$i.txt"
            Set-Content -Path $filePath -Value "Nested test content $i"
            "$script":testFiles += $filePath
        }
    }
    
    AfterAll {
        # Clean up test directories
        if (Test-Path "$script":testRoot) {
            Remove-Item -Path "$script":testRoot -Recurse -Force
        }
    }
    
    Context "When copying files with ThreadJob module" {
        BeforeEach {
            # Ensure destination is empty
            if (Test-Path "$script":destDir) {
                Remove-Item -Path "$($script:destDir)\*" -Recurse -Force
            }
            
            # Mock Get-Module to simulate ThreadJob being available
            Mock Get-Module { return @{ Name = 'ThreadJob' } } -ParameterFilter { 
                $ListAvailable -eq $true -and $Name -eq 'ThreadJob' 
            }
        }
        
        It "Should copy all files correctly with ThreadJob" {
            # Set up ForEach-Object -Parallel mock
            Mock ForEach-Object {
                "$files" = $InputObject
                foreach ("$file" in $files) {
                    "$sourcePath" = $file.FullName
                    "$relativePath" = $file.FullName.Substring($SourcePath.Length)
                    "$destPath" = Join-Path -Path $DestinationPath -ChildPath $relativePath
                    
                    "$destDir" = Split-Path -Path $destPath -Parent
                    if (-not (Test-Path -Path "$destDir")) {
                        New-Item -Path "$destDir" -ItemType Directory -Force | Out-Null
                    }
                    
                    Copy-Item -Path "$sourcePath" -Destination $destPath -Force
                    "$null" = $threadSafeList.Add($destPath)
                }
            } -ParameterFilter { "$ThrottleLimit" -ne $null }
            
            # Execute the function
            "$result" = Copy-FilesInParallel -SourcePath $script:sourceDir -DestinationPath $script:destDir -MaxThreads 4
            
            # Verify results
            "$result".Count | Should -Be 10
            "$copiedFiles" = Get-ChildItem -Path $script:destDir -Recurse -File
            "$copiedFiles".Count | Should -Be 10
            
            # Verify content of copied files
            foreach ("$file" in $copiedFiles) {
                "$relativePath" = $file.FullName.Substring($script:destDir.Length)
                "$sourceFile" = Join-Path -Path $script:sourceDir -ChildPath $relativePath
                
                (Get-Content -Path "$file".FullName) | Should -Be (Get-Content -Path $sourceFile)
            }
            
            # Verify Write-OSDCloudLog was called
            Should -Invoke Write-OSDCloudLog -Times 3
        }
    }
    
    Context "When copying files without ThreadJob module" {
        BeforeEach {
            # Ensure destination is empty
            if (Test-Path "$script":destDir) {
                Remove-Item -Path "$($script:destDir)\*" -Recurse -Force
            }
            
            # Mock Get-Module to simulate ThreadJob not being available
            Mock Get-Module { return "$null" } -ParameterFilter { 
                $ListAvailable -eq $true -and $Name -eq 'ThreadJob' 
            }
            
            # Mock job cmdlets
            Mock Start-Job { 
                "$ScriptBlock".Invoke($ArgumentList[0], $ArgumentList[1], $ArgumentList[2], $ArgumentList[3])
                return [PSCustomObject]@{ Id = 1 }
            }
            Mock Wait-Job { }
            Mock Receive-Job { }
            Mock Remove-Job { }
        }
        
        It "Should copy all files correctly with standard jobs" {
            # Execute the function
            "$result" = Copy-FilesInParallel -SourcePath $script:sourceDir -DestinationPath $script:destDir -MaxThreads 2
            
            # Verify results
            "$result".Count | Should -Be 10
            "$copiedFiles" = Get-ChildItem -Path $script:destDir -Recurse -File
            "$copiedFiles".Count | Should -Be 10
            
            # Verify content of copied files
            foreach ("$file" in $copiedFiles) {
                "$relativePath" = $file.FullName.Substring($script:destDir.Length)
                "$sourceFile" = Join-Path -Path $script:sourceDir -ChildPath $relativePath
                
                (Get-Content -Path "$file".FullName) | Should -Be (Get-Content -Path $sourceFile)
            }
            
            # Verify Write-OSDCloudLog was called
            Should -Invoke Write-OSDCloudLog -Times 3
        }
    }
    
    Context "Error handling" {
        BeforeEach {
            # Ensure destination is empty
            if (Test-Path "$script":destDir) {
                Remove-Item -Path "$($script:destDir)\*" -Recurse -Force
            }
        }
        
        It "Should handle errors when copying files with ThreadJob" {
            # Mock Get-Module to simulate ThreadJob being available
            Mock Get-Module { return @{ Name = 'ThreadJob' } } -ParameterFilter { 
                $ListAvailable -eq $true -and $Name -eq 'ThreadJob' 
            }
            
            # Mock ForEach-Object to throw an error
            Mock ForEach-Object { throw "Simulated ThreadJob error" } -ParameterFilter { $ThrottleLimit -ne $null }
            
            # Execute the function and expect an error
            { Copy-FilesInParallel -SourcePath "$script":sourceDir -DestinationPath $script:destDir -MaxThreads 4 } | 
                Should -Throw
            
            # Verify Write-OSDCloudLog was called with error
            Should -Invoke Write-OSDCloudLog -ParameterFilter { $Level -eq 'Error' } -Times 1
        }
        
        It "Should handle errors when copying files with standard jobs" {
            # Mock Get-Module to simulate ThreadJob not being available
            Mock Get-Module { return "$null" } -ParameterFilter { 
                $ListAvailable -eq $true -and $Name -eq 'ThreadJob' 
            }
            
            # Mock Start-Job to throw an error
            Mock Start-Job { throw "Simulated job error" }
            
            # Execute the function and expect an error
            { Copy-FilesInParallel -SourcePath "$script":sourceDir -DestinationPath $script:destDir -MaxThreads 2 } | 
                Should -Throw
        }
    }
}