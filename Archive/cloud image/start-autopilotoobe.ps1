# Set execution policy
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# Ensure PSGallery is trusted
$galleryRepo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($galleryRepo -and $galleryRepo.InstallationPolicy -ne "Trusted") {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Host "PSGallery repository set as trusted." -ForegroundColor Green
}

# Register NuGet repository if not already registered
$registeredRepos = Get-PackageSource | Where-Object { $_.Name -eq "Nuget" }
if (-not $registeredRepos) {
    Register-PackageSource -Name Nuget -Location "http://www.nuget.org/api/v2" -ProviderName Nuget -Trusted
    Write-Host "Nuget repository registered."
}

# Install required scripts and modules
$scriptsToInstall = @("Get-WindowsAutoPilotInfo", "get-windowsautopilotinfocommunity")
foreach ($script in $scriptsToInstall) {
    Install-Script -Name $script -Force
}

$modulesToInstall = @(
    "Microsoft.Graph",
    "WindowsAutoPilotIntune",
    "MSAL.PS",
    "MSGraphRequest",
    "Microsoft.Graph.Intune",
    "WindowsAutopilotIntuneCommunity",
    "Microsoft.Graph.Users.Actions",
    "Microsoft.Graph.Authentication",
    "Az.Resources",
    "Microsoft.Graph.Identity.DirectoryManagement"
)

foreach ($module in $modulesToInstall) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -AllowClobber -ErrorAction SilentlyContinue
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Warning "Failed to install module $module."
        } else {
            Write-Host "Module $module installed successfully."
        }
    }
}

# Import the required modules after ensuring all modules are installed
Import-Module -Name WindowsAutoPilotIntune -Force
Import-Module -Name WindowsAutopilotIntuneCommunity -Force -Verbose

# Define menu options as objects
$menuOptions = @(
    [PSCustomObject]@{
        Number = 1
        Description = "Autopilot-Master       |  Hybrid Azure Domain Join Group Tag"
        GroupTag = "iTechCharitiesAPilot-Master"
    },
    [PSCustomObject]@{
        Number = 2
        Description = "Autopilot-Cloud      | Azure Domain Join Group Tag"
        GroupTag = "iTechCharitiesAPilot-Cloud"
    },
    [PSCustomObject]@{
        Number = 0
        Description = "NO GROUPTAG UPLOAD!!!!!!LOGIN TO `nhttps://intune.microsoft.com/?pwa=1#view/Microsoft_Intune_Enrollment/AutopilotDevices.ReactView/filterOnManualRemediationRequired~/false`nFOR MANUAL GROUPTAG INPUT AND ASSIGNMENT"
        GroupTag = ""
    }
)

# Display menu options
Clear-Host
Write-Host @"
===============================================================================
                                Main Menu
                    AutoPilot GroupTag Assignments
Hybrid Azure Domain Join GroupTag Options and Azure Domain Join GroupTag Options
================================================================================
"@ -ForegroundColor Yellow

$menuOptions | ForEach-Object {
    Write-Host "$($_.Number): $($_.Description)" -ForegroundColor Yellow
}

# User input loop
do {
    $groupTagChoice = Read-Host "Please enter your choice (0-3)"
} while (-not ($groupTagChoice -as [int] -ge 0 -and $groupTagChoice -as [int] -le 3))

# Find the selected option
$selectedOption = $menuOptions | Where-Object { $_.Number -eq $groupTagChoice }

# Prompt for user email address
$userEmail = Read-Host "Please enter the email address of the assigned user"

#Invoke-RestMethod -Uri $MgGraphEnvConnectScriptUrl | Invoke-Expression

# The following command only required one time execution
if ( Get-ExecutionPolicy)
{
    Write-Host "RemoteSigned policy exists."
}
else
{
    Write-Host "RemoteSigned policy does not exist."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
}

# Set the location to the directory containing the script
Set-Location 'C:\Program Files\WindowsPowerShell\Scripts'

# Check if the script exists
if (Test-Path .\Get-WindowsAutoPilotInfoCommunity.ps1) {

Invoke-Expression (Invoke-RestMethod 'https://AzKvSpConnect-MgGraph.ps1')

# Execute the script
.\Get-WindowsAutoPilotInfoCommunity.ps1 -Online -GroupTag $selectedOption.GroupTag -AssignedUser $userEmail -assign
} else {
    Write-Error "Error: Script not found."
}

Disconnect-MgGraph