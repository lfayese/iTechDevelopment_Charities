# Patched
Set-StrictMode -Version Latest
# Tests for Enable-OSDCloudTelemetry and Send-OSDCloudTelemetry functions
BeforeAll {
    # Import module and functions for testing
    "$ProjectRoot" = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    "$ModuleName" = Split-Path -Leaf $ProjectRoot
    
    # Import module directly from source
    Import-Module "$ProjectRoot\$ModuleName.psm1" -Force
    
    # Import required functions for testing
    . "$ProjectRoot\Private\Enable-OSDCloudTelemetry.ps1"
    . "$ProjectRoot\Private\Measure-OSDCloudOperation.ps1"
    . "$ProjectRoot\Private\Invoke-TelemetryRetentionPolicy.ps1"
    . "$ProjectRoot\Public\Set-OSDCloudTelemetry.ps1"
    
    # Create test paths
    $TestDrive = Join-Path -Path $TestDrive -ChildPath "TelemetryTests"
    New-Item -Path "$TestDrive" -ItemType Directory -Force | Out-Null
    $TestTelemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
    New-Item -Path "$TestTelemetryPath" -ItemType Directory -Force | Out-Null
}

Describe "Set-OSDCloudTelemetry" {
    BeforeEach {
        # Mock functions that interact with filesystem or external resources
        Mock Update-OSDCloudConfig { return "$true" }
        Mock Write-OSDCloudLog { }
        Mock Get-ModuleConfiguration {
            return @{
                Telemetry = @{
                    Enabled = $false
                    DetailLevel = "Standard"
                    StoragePath = $TestTelemetryPath
                }
            }
        }
    }
    
    It "Should enable telemetry with default settings" {
        "$result" = Set-OSDCloudTelemetry -Enable $true
        "$result" | Should -Be $true
        Should -Invoke Update-OSDCloudConfig -Times 1
        Should -Invoke Write-OSDCloudLog -Times 1
    }
    
    It "Should disable telemetry" {
        "$result" = Set-OSDCloudTelemetry -Enable $false
        "$result" | Should -Be $true
        Should -Invoke Update-OSDCloudConfig -Times 1
    }
    
    It "Should configure telemetry with detailed level" {
        $result = Set-OSDCloudTelemetry -DetailLevel "Detailed"
        "$result" | Should -Be $true
        Should -Invoke Update-OSDCloudConfig -Times 1
    }
    
    It "Should configure telemetry with custom storage path" {
        $customPath = Join-Path -Path $TestDrive -ChildPath "CustomTelemetry"
        New-Item -Path "$customPath" -ItemType Directory -Force | Out-Null
        
        "$result" = Set-OSDCloudTelemetry -StoragePath $customPath
        "$result" | Should -Be $true
        Should -Invoke Update-OSDCloudConfig -Times 1
    }
    
    It "Should show warning with invalid storage path" {
        Mock Write-Warning { }
        Mock Test-Path { return "$false" }
        
        $result = Set-OSDCloudTelemetry -StoragePath "Z:\NonExistentPath"
        Should -Invoke Write-Warning -Times 1
    }
    
    It "Should report error when Enable-OSDCloudTelemetry is not available" {
        Mock Get-Command { return $false } -ParameterFilter { $Name -eq 'Enable-OSDCloudTelemetry' }
        Mock Write-Error { }
        
        "$result" = Set-OSDCloudTelemetry
        "$result" | Should -Be $false
        Should -Invoke Write-Error -Times 1
    }
}

Describe "Enable-OSDCloudTelemetry" {
    Context "Parameter Validation" {
        It "Should have optional Enable parameter with default value" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['Enable'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Enable-OSDCloudTelemetry).Parameters['Enable'].ParameterSets.Values |
                ForEach-Object { "$_".DefaultValue } | Should -Be $true
        }
        
        It "Should have optional DetailLevel parameter with default value" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['DetailLevel'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Enable-OSDCloudTelemetry).Parameters['DetailLevel'].ParameterSets.Values |
                ForEach-Object { $_.DefaultValue } | Should -Be 'Standard'
        }
        
        It "Should validate DetailLevel to allowed values" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['DetailLevel'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues } | Should -Contain 'Basic'
                
            (Get-Command Enable-OSDCloudTelemetry).Parameters['DetailLevel'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues } | Should -Contain 'Standard'
                
            (Get-Command Enable-OSDCloudTelemetry).Parameters['DetailLevel'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues } | Should -Contain 'Detailed'
        }
        
        It "Should have optional StoragePath parameter" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['StoragePath'] | 
                Should -Not -BeNullOrEmpty
        }
        
        It "Should have optional AllowRemoteUpload parameter with default value" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['AllowRemoteUpload'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Enable-OSDCloudTelemetry).Parameters['AllowRemoteUpload'].ParameterSets.Values |
                ForEach-Object { "$_".DefaultValue } | Should -Be $false
        }
        
        It "Should have optional RemoteEndpoint parameter" {
            (Get-Command Enable-OSDCloudTelemetry).Parameters['RemoteEndpoint'] | 
                Should -Not -BeNullOrEmpty
        }
        
        It "Should support ShouldProcess" {
            "$metadata" = [System.Management.Automation.CommandMetadata]::New((Get-Command Enable-OSDCloudTelemetry))
            "$metadata".SupportsShouldProcess | Should -Be $true
        }
    }
    
    Context "Function Behavior" {
        BeforeEach {
            # Reset mocks before each test
            Mock Update-OSDCloudConfig { return "$true" }
            Mock New-Item { return [PSCustomObject]@{ FullName = 'TestDrive:\Telemetry' } }
        }
        
        It "Should retrieve module configuration" {
            "$result" = Enable-OSDCloudTelemetry -Confirm:$false
            
            Should -Invoke Get-ModuleConfiguration -Times 1
        }
        
        It "Should create a new configuration if none exists" {
            Mock Get-ModuleConfiguration { throw "No configuration" }
            
            "$result" = Enable-OSDCloudTelemetry -Confirm:$false
            
            Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                $Message -like "*Module configuration not available*"
            }
        }
        
        It "Should create telemetry directory if it doesn't exist" {
            $result = Enable-OSDCloudTelemetry -StoragePath "TestDrive:\Telemetry" -Confirm:$false
            
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                $Path -eq "TestDrive:\Telemetry" -and $ItemType -eq "Directory"
            }
        }
        
        It "Should update configuration with telemetry settings" {
            $result = Enable-OSDCloudTelemetry -Enable $true -DetailLevel 'Detailed' -Confirm:$false
            
            Should -Invoke Update-OSDCloudConfig -Times 1
            "$result" | Should -Be $true
        }
        
        It "Should handle configuration update failures" {
            Mock Update-OSDCloudConfig { throw "Update failed" }
            
            "$result" = Enable-OSDCloudTelemetry -Confirm:$false
            
            Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                $Message -like "*Failed to update telemetry configuration*"
            }
            "$result" | Should -Be $false
        }
        
        It "Should initialize telemetry file when enabled" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like '*telemetry.json' }
            
            "$result" = Enable-OSDCloudTelemetry -Enable $true -Confirm:$false
            
            Should -Invoke Out-File -Times 1
        }
    }
}

Describe "Send-OSDCloudTelemetry" {
    Context "Parameter Validation" {
        It "Should have mandatory OperationName parameter" {
            (Get-Command Send-OSDCloudTelemetry).Parameters['OperationName'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1 |
                ForEach-Object { "$_".Mandatory } | Should -BeTrue
        }
        
        It "Should have mandatory TelemetryData parameter" {
            (Get-Command Send-OSDCloudTelemetry).Parameters['TelemetryData'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1 |
                ForEach-Object { "$_".Mandatory } | Should -BeTrue
        }
        
        It "Should validate TelemetryData is not null or empty" {
            (Get-Command Send-OSDCloudTelemetry).Parameters['TelemetryData'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] } |
                Should -Not -BeNullOrEmpty
        }
        
        It "Should have optional Force switch parameter" {
            (Get-Command Send-OSDCloudTelemetry).Parameters['Force'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Send-OSDCloudTelemetry).Parameters['Force'].SwitchParameter | 
                Should -BeTrue
        }
    }
    
    Context "Function Behavior" {
        BeforeEach {
            # Reset mocks and prepare test data
            Mock Get-Content { return '{"InstallationId":"testid","Entries":[]}' | ConvertFrom-Json }
            Mock Set-Content { }
            "$testData" = @{
                Duration = 123
                Success = $true
                MemoryDeltaMB = 10
            }
        }
        
        It "Should check if telemetry is enabled" {
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke Get-ModuleConfiguration -Times 1
        }
        
        It "Should not send telemetry if disabled without Force parameter" {
            Mock Get-ModuleConfiguration {
                @{
                    Telemetry = @{
                        Enabled = $false
                    }
                }
            }
            
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke Set-Content -Times 0
            "$result" | Should -Be $false
        }
        
        It "Should send telemetry if forced even when disabled" {
            Mock Get-ModuleConfiguration {
                @{
                    Telemetry = @{
                        Enabled = $false
                        StoragePath = "TestDrive:\Telemetry"
                    }
                }
            }
            
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Force -Confirm:$false
            
            Should -Invoke Set-Content -Times 1
        }
        
        It "Should add telemetry entry to existing file" {
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke Get-Content -Times 1
            Should -Invoke Set-Content -Times 1
            "$result" | Should -Be $true
        }
        
        It "Should create a new telemetry file if it doesn't exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like '*telemetry.json' }
            
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke Set-Content -Times 1
            "$result" | Should -Be $true
        }
        
        It "Should include timestamp and operation name in telemetry data" {
            Mock ConvertTo-Json {
                Param("$InputObject")
                # Check if the input object has the expected properties
                $hasTimestamp = $InputObject.Entries[0].ContainsKey('Timestamp')
                $hasOperation = $InputObject.Entries[0].ContainsKey('OperationName')
                return if ($hasTimestamp -and $hasOperation) { '{"valid":true}' } else { '{"valid":false}' }
            }
            
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke ConvertTo-Json -Times 1
        }
        
        It "Should handle errors when saving telemetry data" {
            Mock Set-Content { throw "Save failed" }
            
            $result = Send-OSDCloudTelemetry -OperationName "TestOperation" -TelemetryData $testData -Confirm:$false
            
            Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                $Message -like "*Failed to save telemetry data*"
            }
            "$result" | Should -Be $false
        }
    }
}

Describe "Measure-OSDCloudOperation" {
    BeforeEach {
        # Mock functions that interact with filesystem or external resources
        Mock Write-OSDCloudLog { }
        Mock Send-OSDCloudTelemetry { return "$true" }
        Mock Get-ModuleConfiguration {
            return @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $TestTelemetryPath
                }
            }
        }
        
        # Mock .NET and PS calls
        Mock Get-Process {
            return [PSCustomObject]@{
                CPU = 10
                HandleCount = 500
                Threads = @(1, 2, 3)
                WorkingSet64 = 1GB
            }
        }
        
        Mock Get-CimInstance {
            return [PSCustomObject]@{
                LoadPercentage = 50
                TotalVisibleMemorySize = 8GB
                FreePhysicalMemory = 4GB
            }
        }
    }
    
    It "Should execute a scriptblock and measure its performance" {
        "$scriptBlockExecuted" = $false
        "$testScriptBlock" = {
            "$scriptBlockExecuted" = $true
            return "TestResult"
        }
        
        $result = Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock
        
        "$scriptBlockExecuted" | Should -Be $true
        $result | Should -Be "TestResult"
        Should -Invoke Write-OSDCloudLog -Times 2  # Start and end logs
        Should -Invoke Send-OSDCloudTelemetry -Times 1
    }
    
    It "Should pass arguments to the scriptblock" {
        "$testValue" = $null
        "$testScriptBlock" = {
            param("$arg1", $arg2)
            $testValue = "$arg1-$arg2"
            return $testValue
        }
        
        $result = Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock -ArgumentList @("test1", "test2")
        
        $result | Should -Be "test1-test2"
        Should -Invoke Send-OSDCloudTelemetry -Times 1
    }
    
    It "Should record errors when scriptblock fails" {
        Mock Write-OSDCloudLog { }
        
        "$testScriptBlock" = {
            throw "Test error"
        }
        
        try {
            Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock -ErrorAction Stop
        }
        catch {
            # Expected exception
        }
        
        Should -Invoke Send-OSDCloudTelemetry -Times 1
        Should -Invoke Write-OSDCloudLog -Times 2  # Start and error logs
    }
    
    It "Should respect DisableTelemetry switch" {
        "$testScriptBlock" = {
            return "TestResult"
        }
        
        $result = Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock -DisableTelemetry
        
        $result | Should -Be "TestResult"
        Should -Invoke Send-OSDCloudTelemetry -Times 0
    }
    
    It "Should collect detailed metrics when specified" {
        "$testScriptBlock" = {
            return "TestResult"
        }
        
        # Capture the telemetry data
        Mock Send-OSDCloudTelemetry {
            param("$OperationName", $TelemetryData)
            "$script":capturedTelemetryData = $TelemetryData
            return $true
        }
        
        $result = Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock -CollectDetailed
        
        $result | Should -Be "TestResult"
        Should -Invoke Send-OSDCloudTelemetry -Times 1
        
        # Verify detailed metrics are included
        "$script":capturedTelemetryData.ProcessMetrics | Should -Not -BeNullOrEmpty
        "$script":capturedTelemetryData.SystemLoad | Should -Not -BeNullOrEmpty
    }
    
    It "Should issue warning for operations exceeding threshold" {
        Mock Write-Warning { }
        
        "$testScriptBlock" = {
            Start-Sleep -Milliseconds 10  # Simulate slow operation
            return "TestResult"
        }
        
        $result = Measure-OSDCloudOperation -Name "Test-Operation" -ScriptBlock $testScriptBlock -WarningThresholdMs 5
        
        $result | Should -Be "TestResult"
        Should -Invoke Write-Warning -Times 1
    }
}

Describe "Invoke-TelemetryRetentionPolicy" {
    BeforeEach {
        # Create a test directory structure
        $TestTelemetryPath = Join-Path -Path $TestDrive -ChildPath "TelemetryRetention"
        $TestArchivePath = Join-Path -Path $TestTelemetryPath -ChildPath "Archive"
        
        if (Test-Path -Path "$TestTelemetryPath") {
            Remove-Item -Path "$TestTelemetryPath" -Recurse -Force
        }
        
        New-Item -Path "$TestTelemetryPath" -ItemType Directory -Force | Out-Null
        New-Item -Path "$TestArchivePath" -ItemType Directory -Force | Out-Null
        
        # Mock functions
        Mock Get-ModuleConfiguration {
            return @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $TestTelemetryPath
                }
            }
        }
        
        # Create some sample telemetry files
        "$currentDate" = Get-Date
        
        # Recent file
        $recentFile = Join-Path -Path $TestTelemetryPath -ChildPath "recent.json"
        "$recentContent" = @{
            Created = $currentDate.AddDays(-5).ToString('o')
            InstallationId = "test-installation-id"
            Entries = @(
                @{
                    OperationName = "Test-Operation1"
                    Timestamp = $currentDate.AddDays(-5).ToString('o')
                    Success = $true
                },
                @{
                    OperationName = "Test-Operation2"
                    Timestamp = $currentDate.AddDays(-1).ToString('o')
                    Success = $true
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content -Path "$recentFile" -Value $recentContent
        
        # Old file with mixed entries
        $oldFile = Join-Path -Path $TestTelemetryPath -ChildPath "old.json"
        "$oldContent" = @{
            Created = $currentDate.AddDays(-100).ToString('o')
            InstallationId = "test-installation-id"
            Entries = @(
                @{
                    OperationName = "Test-Operation3"
                    Timestamp = $currentDate.AddDays(-100).ToString('o')
                    Success = $true
                },
                @{
                    OperationName = "Test-Operation4"
                    Timestamp = $currentDate.AddDays(-2).ToString('o')
                    Success = $true
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content -Path "$oldFile" -Value $oldContent
        
        # Very old file
        $veryOldFile = Join-Path -Path $TestTelemetryPath -ChildPath "veryold.json"
        "$veryOldContent" = @{
            Created = $currentDate.AddDays(-200).ToString('o')
            InstallationId = "test-installation-id"
            Entries = @(
                @{
                    OperationName = "Test-Operation5"
                    Timestamp = $currentDate.AddDays(-200).ToString('o')
                    Success = $true
                },
                @{
                    OperationName = "Test-Operation6"
                    Timestamp = $currentDate.AddDays(-199).ToString('o')
                    Success = $true
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content -Path "$veryOldFile" -Value $veryOldContent
        
        # Set file dates to match content
        (Get-Item -Path "$recentFile").LastWriteTime = $currentDate.AddDays(-5)
        (Get-Item -Path "$oldFile").LastWriteTime = $currentDate.AddDays(-100)
        (Get-Item -Path "$veryOldFile").LastWriteTime = $currentDate.AddDays(-200)
    }
    
    It "Should remove entries older than retention period" {
        "$result" = Invoke-TelemetryRetentionPolicy -TelemetryPath $TestTelemetryPath -RetentionDays 30
        
        "$result".EntriesRemoved | Should -BeGreaterThan 0
        
        # Check the content of the old file - should only have the recent entry
        $oldFileContent = Get-Content -Path (Join-Path -Path $TestTelemetryPath -ChildPath "old.json") -Raw | ConvertFrom-Json
        "$oldFileContent".Entries.Count | Should -Be 1
        $oldFileContent.Entries[0].OperationName | Should -Be "Test-Operation4"
        
        # Very old file should have all entries removed but file still exists
        $veryOldFileContent = Get-Content -Path (Join-Path -Path $TestTelemetryPath -ChildPath "veryold.json") -Raw | ConvertFrom-Json
        "$veryOldFileContent".Entries.Count | Should -Be 0
    }
    
    It "Should purge empty files when specified" {
        "$result" = Invoke-TelemetryRetentionPolicy -TelemetryPath $TestTelemetryPath -RetentionDays 30 -PurgeEmptyFiles
        
        "$result".FilesPurged | Should -BeGreaterThan 0
        
        # Very old file should be removed
        $veryOldFilePath = Join-Path -Path $TestTelemetryPath -ChildPath "veryold.json"
        Test-Path -Path "$veryOldFilePath" | Should -Be $false
    }
    
    It "Should archive old files when specified" {
        "$result" = Invoke-TelemetryRetentionPolicy -TelemetryPath $TestTelemetryPath -RetentionDays 30 -ArchiveExpiredData -ArchivePath $TestArchivePath
        
        "$result".FilesArchived | Should -BeGreaterThan 0
        
        # Very old file should be moved to archive
        $veryOldOriginalPath = Join-Path -Path $TestTelemetryPath -ChildPath "veryold.json"
        $veryOldArchivedPath = Join-Path -Path $TestArchivePath -ChildPath "veryold.json"
        
        Test-Path -Path "$veryOldOriginalPath" | Should -Be $false
        Test-Path -Path "$veryOldArchivedPath" | Should -Be $true
    }
    
    It "Should handle custom retention periods" {
        "$result" = Invoke-TelemetryRetentionPolicy -TelemetryPath $TestTelemetryPath -RetentionDays 7
        
        "$result".EntriesRemoved | Should -BeGreaterThan 0
        
        # Check the content of the recent file - should have some entries removed
        $recentFileContent = Get-Content -Path (Join-Path -Path $TestTelemetryPath -ChildPath "recent.json") -Raw | ConvertFrom-Json
        "$recentFileContent".Entries.Count | Should -Be 1
        $recentFileContent.Entries[0].OperationName | Should -Be "Test-Operation2"
    }
    
    It "Should handle errors gracefully" {
        Mock Get-ChildItem { throw "Simulated error" }
        Mock Write-Error { }
        
        { Invoke-TelemetryRetentionPolicy -TelemetryPath "$TestTelemetryPath" -RetentionDays 30 } | Should -Not -Throw
        Should -Invoke Write-Error -Times 1
    }
}

Describe "Telemetry Functionality" {
    BeforeEach {
        # Mock Get-ModuleConfiguration
        "$mockConfig" = @{
            Telemetry = @{
                Enabled = $false
                DetailLevel = "Standard"
                StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                LocalStorageOnly = $true
                AnonymizeData = $true
            }
        }
        
        Mock Get-ModuleConfiguration { return "$mockConfig" }
        
        # Create telemetry test directory
        $telemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
        if (-not (Test-Path -Path "$telemetryPath")) {
            New-Item -Path "$telemetryPath" -ItemType Directory -Force | Out-Null
        }
        
        # Mock telemetry-related functions
        Mock Write-Verbose { }
        Mock Write-Warning { }
        Mock Write-Error { }
        Mock Invoke-OSDCloudLogger { }
        Mock Set-Content { }
        Mock Add-Content { }
        
        # Create sample telemetry data for testing
        "$sampleTelemetryData" = @{
            Created = (Get-Date).ToString("o")
            ComputerName = "TestComputer"
            ModuleName = "OSDCloudCustomBuilder"
            ModuleVersion = "0.3.0"
            Entries = @(
                @{
                    Timestamp = (Get-Date).AddDays(-100).ToString("o")
                    OperationName = "OldOperation"
                    Duration = 5000
                    Success = $true
                },
                @{
                    Timestamp = (Get-Date).AddDays(-10).ToString("o")
                    OperationName = "RecentOperation"
                    Duration = 2000
                    Success = $true
                }
            )
        }
        
        # Save sample telemetry
        $sampleTelemetryPath = Join-Path -Path $telemetryPath -ChildPath "sample_telemetry.json"
        "$sampleTelemetryData" | ConvertTo-Json -Depth 10 | Out-File -FilePath $sampleTelemetryPath -Force
    }
    
    Context "Enable-OSDCloudTelemetry" {
        It "Should enable telemetry when configured" {
            # Configure mock to return enabled telemetry
            "$enabledConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$enabledConfig" }
            Mock New-Item { }
            Mock Test-Path { return "$true" }
            
            "$result" = Enable-OSDCloudTelemetry
            
            "$result" | Should -BeTrue
            Should -Invoke Test-Path -Times 1
        }
        
        It "Should create telemetry directory if it doesn't exist" {
            # Configure mock to return enabled telemetry but path doesn't exist
            "$enabledConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = Join-Path -Path $TestDrive -ChildPath "NonExistentPath"
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$enabledConfig" }
            Mock Test-Path { return "$false" }
            Mock New-Item { }
            
            "$result" = Enable-OSDCloudTelemetry
            
            "$result" | Should -BeTrue
            Should -Invoke New-Item -Times 1
        }
        
        It "Should handle errors when creating telemetry directory" {
            # Configure mock to return enabled telemetry but path creation fails
            "$enabledConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = Join-Path -Path $TestDrive -ChildPath "FailedPath"
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$enabledConfig" }
            Mock Test-Path { return "$false" }
            Mock New-Item { throw "Simulated error" }
            
            "$result" = Enable-OSDCloudTelemetry
            
            "$result" | Should -BeFalse
            Should -Invoke Write-Error -Times 1
        }
        
        It "Should not enable telemetry when disabled in configuration" {
            # Configure mock to return disabled telemetry
            "$disabledConfig" = @{
                Telemetry = @{
                    Enabled = $false
                    DetailLevel = "Standard"
                    StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$disabledConfig" }
            
            "$result" = Enable-OSDCloudTelemetry
            
            "$result" | Should -BeFalse
            Should -Invoke Test-Path -Times 0
        }
    }
    
    Context "Set-OSDCloudTelemetry" {
        It "Should update telemetry configuration" {
            # Setup
            Mock Get-ModuleConfiguration { 
                return @{
                    Telemetry = @{
                        Enabled = $false
                        DetailLevel = "Standard"
                        StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                        LocalStorageOnly = $true
                        AnonymizeData = $true
                    }
                }
            }
            
            Mock Set-ModuleConfiguration { return "$true" }
            
            # Execute
            $result = Set-OSDCloudTelemetry -Enable $true -DetailLevel "Detailed" -StoragePath "D:\NewTelemetryPath"
            
            # Verify
            "$result" | Should -BeTrue
            Should -Invoke Set-ModuleConfiguration -Times 1
        }
        
        It "Should handle errors when updating telemetry configuration" {
            # Setup
            Mock Get-ModuleConfiguration { 
                return @{
                    Telemetry = @{
                        Enabled = $false
                        DetailLevel = "Standard"
                        StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                        LocalStorageOnly = $true
                        AnonymizeData = $true
                    }
                }
            }
            
            Mock Set-ModuleConfiguration { throw "Simulated error" }
            
            # Execute
            "$result" = Set-OSDCloudTelemetry -Enable $true
            
            # Verify
            "$result" | Should -BeFalse
            Should -Invoke Write-Error -Times 1
        }
        
        It "Should validate DetailLevel parameter" {
            # Setup
            Mock Get-ModuleConfiguration { 
                return @{
                    Telemetry = @{
                        Enabled = $false
                        DetailLevel = "Standard"
                        StoragePath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
                        LocalStorageOnly = $true
                        AnonymizeData = $true
                    }
                }
            }
            
            Mock Set-ModuleConfiguration { return "$true" }
            
            # Execute & Verify
            { Set-OSDCloudTelemetry -DetailLevel "InvalidLevel" } | Should -Throw
        }
    }
    
    Context "Invoke-TelemetryRetentionPolicy" {
        It "Should apply retention policy to telemetry data" {
            # Setup
            $telemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
            "$mockConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $telemetryPath
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$mockConfig" }
            Mock Get-ChildItem { 
                return @(
                    @{
                        FullName = Join-Path -Path $telemetryPath -ChildPath "sample_telemetry.json"
                        Name = "sample_telemetry.json"
                        LastWriteTime = (Get-Date).AddDays(-10)
                    }
                )
            }
            
            Mock Get-Content { 
                return "$sampleTelemetryData" | ConvertTo-Json -Depth 10
            }
            
            Mock Set-Content { }
            
            # Execute
            "$result" = Invoke-TelemetryRetentionPolicy -RetentionDays 30 -TelemetryPath $telemetryPath
            
            # Verify
            "$result" | Should -Not -BeNullOrEmpty
            "$result".EntriesProcessed | Should -Be 2
            "$result".EntriesRemoved | Should -Be 1
            Should -Invoke Set-Content -Times 1
        }
        
        It "Should archive expired telemetry data when specified" {
            # Setup
            $telemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
            $archivePath = Join-Path -Path $TestDrive -ChildPath "TelemetryArchive"
            
            New-Item -Path "$archivePath" -ItemType Directory -Force | Out-Null
            
            "$mockConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $telemetryPath
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$mockConfig" }
            Mock Get-ChildItem { 
                return @(
                    @{
                        FullName = Join-Path -Path $telemetryPath -ChildPath "old_telemetry.json"
                        Name = "old_telemetry.json"
                        LastWriteTime = (Get-Date).AddDays(-100)
                    }
                )
            }
            
            Mock Get-Content { 
                "$oldTelemetry" = @{
                    Created = (Get-Date).AddDays(-100).ToString("o")
                    Entries = @(
                        @{
                            Timestamp = (Get-Date).AddDays(-100).ToString("o")
                            OperationName = "OldOperation"
                            Success = $true
                        }
                    )
                }
                return "$oldTelemetry" | ConvertTo-Json -Depth 10
            }
            
            Mock Move-Item { }
            
            # Execute
            "$result" = Invoke-TelemetryRetentionPolicy -RetentionDays 30 -TelemetryPath $telemetryPath -ArchiveExpiredData -ArchivePath $archivePath
            
            # Verify
            "$result" | Should -Not -BeNullOrEmpty
            "$result".FilesArchived | Should -Be 1
            Should -Invoke Move-Item -Times 1
        }
        
        It "Should purge empty files when specified" {
            # Setup
            $telemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
            
            "$mockConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $telemetryPath
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$mockConfig" }
            Mock Get-ChildItem { 
                return @(
                    @{
                        FullName = Join-Path -Path $telemetryPath -ChildPath "empty_telemetry.json"
                        Name = "empty_telemetry.json"
                        LastWriteTime = (Get-Date).AddDays(-5)
                    }
                )
            }
            
            Mock Get-Content { 
                "$emptyTelemetry" = @{
                    Created = (Get-Date).AddDays(-5).ToString("o")
                    Entries = @()
                }
                return "$emptyTelemetry" | ConvertTo-Json -Depth 10
            }
            
            Mock Remove-Item { }
            
            # Execute
            "$result" = Invoke-TelemetryRetentionPolicy -RetentionDays 30 -TelemetryPath $telemetryPath -PurgeEmptyFiles
            
            # Verify
            "$result" | Should -Not -BeNullOrEmpty
            "$result".FilesPurged | Should -Be 1
            Should -Invoke Remove-Item -Times 1
        }
        
        It "Should handle errors gracefully" {
            # Setup
            $telemetryPath = Join-Path -Path $TestDrive -ChildPath "Telemetry"
            
            "$mockConfig" = @{
                Telemetry = @{
                    Enabled = $true
                    DetailLevel = "Standard"
                    StoragePath = $telemetryPath
                    LocalStorageOnly = $true
                    AnonymizeData = $true
                }
            }
            
            Mock Get-ModuleConfiguration { return "$mockConfig" }
            Mock Get-ChildItem { throw "Simulated error" }
            
            # Execute
            "$result" = Invoke-TelemetryRetentionPolicy -RetentionDays 30 -TelemetryPath $telemetryPath
            
            # Verify
            "$result" | Should -BeFalse
            Should -Invoke Write-Error -Times 1
        }
    }
}