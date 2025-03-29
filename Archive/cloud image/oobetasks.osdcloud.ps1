# oobetasks.osdcloud.ch
$scriptFolderPath = "$env:windir\Temp\OSDCloud\Scripts"
$ScriptPathOOBE = $(Join-Path -Path $scriptFolderPath -ChildPath "OOBE.ps1")
$ScriptPathSendKeys = $(Join-Path -Path $scriptFolderPath -ChildPath "SendKeys.ps1")
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"

If(!(Test-Path -Path $scriptFolderPath)) {
    New-Item -Path $scriptFolderPath -ItemType Directory -Force | Out-Null
}

If(!(Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-TaskLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path "$LogPath\OSDCloud-Tasks.log" -Value $logMessage
    switch($Level) {
        'Info' { Write-Host -ForegroundColor DarkGray $Message }
        'Warning' { Write-Host -ForegroundColor Yellow $Message }
        'Error' { Write-Host -ForegroundColor Red $Message }
    }
}

$OOBEScript =@"
`$Global:Transcript = "`$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-OOBEScripts.log"
Start-Transcript -Path (Join-Path "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" `$Global:Transcript) -ErrorAction Ignore | Out-Null

# OOBE Tasks Configuration Script
[CmdletBinding()]
param(
    [Parameter()]
    [string]`$AutopilotProfilePath = "C:\Windows\Provisioning\Autopilot\AutopilotConfigurationFile.json",

    [Parameter()]
    [switch]`$SkipAutopilot
)

# Function to install required modules for Autopilot
function Install-AutopilotModules {
    Write-Host "Installing required modules for Autopilot..." -ForegroundColor Cyan

    `$RequiredModules = @(
        "WindowsAutopilotIntune",
        "Microsoft.Graph.Intune"
    )

    foreach (`$Module in `$RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name `$Module)) {
            Install-Module -Name `$Module -Force -AllowClobber
        }
        Import-Module -Name `$Module -Force
    }
}

# Function to configure Windows settings during OOBE
function Set-OOBEConfiguration {
    Write-Host "Configuring OOBE settings..." -ForegroundColor Cyan

    # Set time zone
    Set-TimeZone -Id "Eastern Standard Time"

    # Configure power settings
    powercfg /change monitor-timeout-ac 15
    powercfg /change standby-timeout-ac 0

    # Enable Remote Desktop
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
}

# Function to register device with Autopilot
function Register-DeviceAutopilot {
    if (-not `$SkipAutopilot) {
        Write-Host "Checking for existing Autopilot registration..." -ForegroundColor Cyan

        # Get hardware hash
        `$hwid = (Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData

        if (`$hwid) {
            Write-Host "Hardware hash found: `$hwid" -ForegroundColor Green

            # Check for existing Autopilot profile
            if (Test-Path `$AutopilotProfilePath) {
                Write-Host "Applying existing Autopilot profile..." -ForegroundColor Cyan
                Install-AutopilotModules

                # Apply profile
                `$Profile = Get-Content `$AutopilotProfilePath | ConvertFrom-Json
                Set-AutopilotProfile -ConfigurationJson `$Profile
            }
            else {
                Write-Host "No Autopilot profile found. Device will need to be registered manually." -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "Could not retrieve hardware hash. Autopilot registration may fail."
        }
    }
}

# Function to configure Windows Update
function Initialize-WindowsUpdates {
    Write-Host "Initializing Windows Updates..." -ForegroundColor Cyan

    # Install PSWindowsUpdate if not present
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Force
    }

    # Import module and configure updates
    Import-Module PSWindowsUpdate
    Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -Confirm:`$false

    # Install all available updates
    Write-Host "Installing Windows Updates..." -ForegroundColor Cyan
    Install-WindowsUpdate -AcceptAll -AutoReboot:`$false
}

# Post-deployment task management
$Global:TaskStates = @{}

function Initialize-PostDeployment {
    param(
        [switch]$SkipAutopilot,
        [switch]$SkipWindowsUpdates
    )

    $Config = Get-OSDCloudConfiguration
    $tasks = @(
        @{
            Name = "ConfigureOOBE"
            Enabled = $true
            Action = { Set-OOBEConfiguration }
        },
        @{
            Name = "RegisterAutopilot"
            Enabled = -not $SkipAutopilot
            Action = { Register-DeviceAutopilot }
        },
        @{
            Name = "WindowsUpdates"
            Enabled = -not $SkipWindowsUpdates
            Action = { Initialize-WindowsUpdates }
        }
    )

    foreach ($task in $tasks) {
        if ($task.Enabled) {
            try {
                Write-Host "Executing $($task.Name)..." -ForegroundColor Cyan
                & $task.Action
                $Global:TaskStates[$task.Name] = "Completed"
            }
            catch {
                $Global:TaskStates[$task.Name] = "Failed"
                Write-Error "Task $($task.Name) failed: $_"
                # Continue with other tasks instead of failing completely
            }
        }
        else {
            $Global:TaskStates[$task.Name] = "Skipped"
        }
    }

    # Write final status
    $statusLog = Join-Path $Config.Paths.Logs "PostDeploymentStatus.json"
    $Global:TaskStates | ConvertTo-Json | Out-File $statusLog
}

try {
    Write-Host "Starting OOBE configuration tasks..." -ForegroundColor Cyan

    # Run configuration tasks
    Set-OOBEConfiguration
    Register-DeviceAutopilot
    Initialize-WindowsUpdates

    Write-Host "OOBE configuration completed successfully!" -ForegroundColor Green

    # Prompt for restart if needed
    if (Test-PendingReboot) {
        Write-Host "A restart is required to complete configuration. System will restart in 2 minutes..." -ForegroundColor Yellow
        Start-Sleep -Seconds 120
        Restart-Computer -Force
    }
}
catch {
    Write-Error "An error occurred during OOBE configuration: `$_"
    exit 1
}

Stop-Transcript -Verbose | Out-File
"@

Out-File -FilePath $ScriptPathOOBE -InputObject $OOBEScript -Encoding ascii

$SendKeysScript = @"
`$Global:Transcript = "`$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-SendKeys.log"
Start-Transcript -Path (Join-Path "`$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" `$Global:Transcript) -ErrorAction Ignore | Out-Null

Write-Host -ForegroundColor DarkGray "Stop Debug-Mode (SHIFT + F10) with WscriptShell.SendKeys"
`$WscriptShell = New-Object -com Wscript.Shell

# ALT + TAB
Write-Host -ForegroundColor DarkGray "SendKeys: ALT + TAB"
`$WscriptShell.SendKeys("%({TAB})")

Start-Sleep -Seconds 1

# Shift + F10
Write-Host -ForegroundColor DarkGray "SendKeys: SHIFT + F10"
`$WscriptShell.SendKeys("+({F10})")

Stop-Transcript -Verbose | Out-File
"@

Out-File -FilePath $ScriptPathSendKeys -InputObject $SendKeysScript -Encoding ascii

# Copy ServiceUI.exe from USB instead of downloading
Write-Host -ForegroundColor Gray "Copying ServiceUI.exe from USB..."
Copy-Item -Path "X:\OSDCloud\Scripts\ServiceUI64.exe" -Destination "C:\Windows\Temp\OSDCloud\ServiceUI.exe" -Force

#Create Scheduled Task for SendKeys with 15 seconds delay
$TaskName = "Scheduled Task for SendKeys"

$ShedService = New-Object -comobject 'Schedule.Service'
$ShedService.Connect()

$Task = $ShedService.NewTask(0)
$Task.RegistrationInfo.Description = $taskName
$Task.Settings.Enabled = $true
$Task.Settings.AllowDemandStart = $true

# https://msdn.microsoft.com/en-us/library/windows/desktop/aa383987(v=vs.85).aspx
$trigger = $task.triggers.Create(9) # 0 EventTrigger, 1 TimeTrigger, 2 DailyTrigger, 3 WeeklyTrigger, 4 MonthlyTrigger, 5 MonthlyDOWTrigger, 6 IdleTrigger, 7 RegistrationTrigger, 8 BootTrigger, 9 LogonTrigger
$trigger.Delay = 'PT15S'
$trigger.Enabled = $true

$action = $Task.Actions.Create(0)
$action.Path = 'C:\Windows\Temp\OSDCloud\ServiceUI.exe'
$action.Arguments = '-process:RuntimeBroker.exe C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe ' + $ScriptPathSendKeys + ' -NoExit'

$taskFolder = $ShedService.GetFolder("\")
# https://msdn.microsoft.com/en-us/library/windows/desktop/aa382577(v=vs.85).aspx
$taskFolder.RegisterTaskDefinition($TaskName, $Task , 6, "SYSTEM", $NULL, 5)

# Create Scheduled Task for OSDCloud post installation with 20 seconds delay
$TaskName = "Scheduled Task for OSDCloud post installation"

$ShedService = New-Object -comobject 'Schedule.Service'
$ShedService.Connect()

$Task = $ShedService.NewTask(0)
$Task.RegistrationInfo.Description = $taskName
$Task.Settings.Enabled = $true
$Task.Settings.AllowDemandStart = $true

# https://msdn.microsoft.com/en-us/library/windows/desktop/aa383987(v=vs.85).aspx
$trigger = $task.triggers.Create(9) # 0 EventTrigger, 1 TimeTrigger, 2 DailyTrigger, 3 WeeklyTrigger, 4 MonthlyTrigger, 5 MonthlyDOWTrigger, 6 IdleTrigger, 7 RegistrationTrigger, 8 BootTrigger, 9 LogonTrigger
$trigger.Delay = 'PT20S'
$trigger.Enabled = $true

$action = $Task.Actions.Create(0)
$action.Path = 'C:\Windows\Temp\OSDCloud\ServiceUI.exe'
$action.Arguments = '-process:RuntimeBroker.exe C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe ' + $ScriptPathOOBE + ' -NoExit'

$taskFolder = $ShedService.GetFolder("\")
# https://msdn.microsoft.com/en-us/library/windows/desktop/aa382577(v=vs.85).aspx
$taskFolder.RegisterTaskDefinition($TaskName, $Task , 6, "SYSTEM", $NULL, 5)

# Cleanup scheduled Tasks
Write-Host -ForegroundColor DarkGray "Unregistering Scheduled Tasks"
$tasksToRemove = @(
    "Scheduled Task for SendKeys",
    "Scheduled Task for OSDCloud post installation"
)
foreach ($taskName in $tasksToRemove) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Successfully removed task: $taskName"
    } else {
        Write-Host "Task not found: $taskName"
    }
}

Write-Host -ForegroundColor DarkGray "Restarting Computer"
Start-Process PowerShell -ArgumentList "-NoL -C Restart-Computer -Force" -Wait

Stop-Transcript -Verbose | Out-File