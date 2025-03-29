<#
.DESCRIPTION
Script to Run Cloud Image
Created: 03/01/2024 by Laolu Fayese
#>

#================================================
#   PreOS
#   Install and Import OSD Module
#================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
Install-Module -Name OSD -Scope AllUsers
Update-Module -Name OSD -Scope AllUsers
Install-Module -Name OSDProgress -Scope AllUsers

Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force  


Invoke-Expression (Invoke-RestMethod -Uri 'https:///OSDCloudStartNetV2.ps1')

function Get-HyperVName {
    [CmdletBinding()]
    param ()
    if ($WindowsPhase -eq 'WinPE'){
        Write-host "Unable to get HyperV Name in WinPE"
    }
    else{
        if (((Get-CimInstance Win32_ComputerSystem).Model -eq "Virtual Machine") -and ((Get-CimInstance Win32_ComputerSystem).Manufacturer -eq "Microsoft Corporation")){
            $HyperVName = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters' -Name "VirtualMachineName" -ErrorAction SilentlyContinue
        }
    return $HyperVName
    Set-DisRes 1600
    }
}
#Start the Transcript
$Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-OSDCloud.log"
$null = Start-Transcript -Path (Join-Path "$env:SystemRoot\Temp" $Transcript) -ErrorAction Ignore

$Manufacturer = (Get-CimInstance -Class:Win32_ComputerSystem).Manufacturer
$Model = (Get-CimInstance -Class:Win32_ComputerSystem).Model
$HPTPM = $false
$HPBIOS = $false
$HPIADrivers = $false

if ($Manufacturer -match "HP" -or $Manufacturer -match "Hewlett-Packard"){
    $Manufacturer = "HP"
    if ($InternetConnection){
        $HPEnterprise = Test-HPIASupport
    }
}
if ($HPEnterprise){
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1')
    osdcloud-InstallModuleHPCMSL
    $TPM = osdcloud-HPTPMDetermine
    $BIOS = osdcloud-HPBIOSDetermine
    $HPIADrivers = $true
    if ($TPM){
    write-host "HP Update TPM Firmware: $TPM - Requires Interaction" -ForegroundColor Yellow
        $HPTPM = $true
    }
    Else {
        $HPTPM = $false
    }

    if ($BIOS -eq $false){
        $CurrentVer = Get-HPBIOSVersion
        write-host "HP System Firmware already Current: $CurrentVer" -ForegroundColor Green
        $HPBIOS = $false
    }
    else
        {
        $LatestVer = (Get-HPBIOSUpdates -Latest).ver
        $CurrentVer = Get-HPBIOSVersion
        write-host "HP Update System Firmwware from $CurrentVer to $LatestVer" -ForegroundColor Yellow
        $HPBIOS = $true
    }
}
$Global:OSDCloud = [ordered]@{
        DevMode = [bool]$false
        WindowsDefenderUpdate = [bool]$True
        NetFx3 = [bool]$True
        SetTimeZone = [bool]$True
        HPIADrivers = [bool]$HPIADrivers
        Bitlocker = [bool]$True
        ClearDiskConfirm = [bool]$false
        OSDCloudUnattend = [bool]$True
        restart = [bool]$True
        HPTPMUpdate = [bool]$HPTPM
        HPBIOSUpdate = [bool]$HPBIOS
    }
    
#Determine the proper Windows environment
if ($env:SystemDrive -eq 'X:') {$WindowsPhase = 'WinPE'}
else {
    $ImageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Ignore).ImageState
    if ($env:UserName -eq 'defaultuser0') {$WindowsPhase = 'OOBE'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE') {$WindowsPhase = 'Specialize'}
    elseif ($ImageState -eq 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_AUDIT') {$WindowsPhase = 'AuditMode'}
    else {$WindowsPhase = 'Windows'}
}

#Finish initialization
Write-Host -ForegroundColor DarkGray "$ScriptName $ScriptVersion $WindowsPhase"

#Load OSDCloud Functions
Invoke-Expression (Invoke-RestMethod -Uri 'functions.osdcloud.com')
Invoke-Expression (Invoke-RestMethod -Uri 'https://gist.githubusercontent.com/oshrc-support/ee3a1ec2cca163075dd4f16726026727/raw/functionsbkup.oshrc.gov.ps1')
Invoke-Expression (Invoke-RestMethod -Uri 'https://gist.githubusercontent.com/oshrc-support/43aa90966394912acb5d16bc8736487a/raw/functions.oshrc.gov.ps1')
Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/eq-winpe.psm1')

#endregion
#=================================================
#region WinPE
if ($WindowsPhase -eq 'WinPE') {

#Process OSDCloud startup and load Azure KeyVault dependencies
osdcloud-StartWinPE -OSDCloud -KeyVault

#Stop the startup Transcript.  OSDCloud will create its own
$null = Stop-Transcript -ErrorAction Ignore
    
#================================================
#   [OS] Start-OSDCloud with Params
#================================================
# Start OSDCloud and pass all the parameters except the Language to allow for prompting
$separator = "========================================================="
$scriptTitle = "Cloud Image Deployment Script"

Write-Host $separator -ForegroundColor Cyan
Write-Host "========== $scriptTitle ==========" -ForegroundColor Cyan
Write-Host "============== Start OSDCloud Imaging ZTI ===============" -ForegroundColor Cyan
Write-Host "============= Edition - 23H2 Build - 22631 ==============" -ForegroundColor Cyan
Write-Host $separator -ForegroundColor Cyan

Start-Sleep -Seconds 5

# Define URLs
$Pro23H2_URL = "https:///Windows11/Pro23H2.wim"
$Pro4w23H2_URL = "https:///Windows11/Pro4w23H2.wim"

# Select Deployment Method
$actionChoices = @("&0. FindImageFile", "&1. Win 11 Pro URL", "&2. Win 11 Pro4W URL", "&3. Win 11 Pro ESD", "&4. Win 11 Enterprise ESD", "&5. OSDCloudGUI")
$action = $Host.UI.PromptForChoice("Deployment Method", "Select a Deployment method to perform imaging", $actionChoices, 0)

# Perform Actions Based on Choice
switch ($action) {
    '0' {
        $selectedAction = "Start-OSDCloud -FindImageFile -Verbose -ZTI"
    }
    '1' {
        $selectedAction = "Start-OSDCloud -ImageFileUrl $Pro23H2_URL -ImageIndex 1 -ZTI"
    }
    '2' {
        $selectedAction = "Start-OSDCloud -ImageFileUrl $Pro4w23H2_URL -ImageIndex 1 -ZTI"
    }
    '3' {
        $selectedAction = "Start-OSDCloud -OSLanguage 'en-us' -OSVersion 'Windows 11' -OSBuild '23H2' -OSEdition 'Pro' -OSLicense 'Volume' -ZTI"
    }
    '4' {
        $selectedAction = "Start-OSDCloud -OSLanguage 'en-us' -OSVersion 'Windows 11' -OSBuild '23H2' -OSEdition 'Enterprise' -OSLicense 'Volume' -ZTI"
    }
    '5' {
        $selectedAction = "Write-Host 'Start-OSDCloudGUI Windows 11 Deployment' -ForegroundColor Cyan"
    }
    Default {
        Write-Host "Invalid choice. Please select a valid option." -ForegroundColor Red
        exit
    }
}

# Execute Selected Action
Invoke-Expression $selectedAction
#endregion
#=================================================================================
#   PostOS
#   Installing driver and update Microsoft patches
#   during specialize phase
#=================================================================================
if ($WindowsPhase -eq 'Specialize') {
function Set-OSDCloudUnattendSpecialize {
    [CmdletBinding()]
    param ()
$UnattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
        <settings pass="generalize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotCleanTaskBar>true</DoNotCleanTaskBar>
        </component>
        <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotCleanUpNonPresentDevices>true</DoNotCleanUpNonPresentDevices>
            <PersistAllDeviceInstalls>true</PersistAllDeviceInstalls>
        </component>
        <component name="Microsoft-Windows-TerminalServices-LocalSessionManager" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <fDenyTSConnections>false</fDenyTSConnections>
        </component>
        <component name="Microsoft-Windows-TerminalServices-RDP-WinStationExtensions" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UserAuthentication>0</UserAuthentication>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <TimeZone>Eastern Standard Time</TimeZone>
            <RegisteredOrganization>OSHRC</RegisteredOrganization>
            <RegisteredOwner>OSHRC</RegisteredOwner>
        </component>
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
           <InputLocale>0409:00000409</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
             <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>OSDCloud Specialize</Description>
                    <Path>Powershell -ExecutionPolicy Bypass -Command Invoke-OSDSpecialize -Verbose</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>cmd /c PowerCfg.exe /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c</Path>
                    <Description>Set Windows power plan to High Performance....</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand>
                    <Order>3</Order>
                    <Path>powershell -ExecutionPolicy Bypass -Command iex (irm https://Install-EmbeddedProductKey.ps1)</Path>
                    <Description>Execute Install-EmbeddedProductKey Script...</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand>
                    <Order>4</Order>
                    <Path>powershell -ExecutionPolicy Bypass -Command iex (irm https:///raw//DeployTools.ps1)</Path>
                    <Description>Execute DeployTools Script...</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand>
                    <Order>5</Order>
                    <Path>powershell -ExecutionPolicy Bypass -Command iex (irm https:///WUpdate.ps1)</Path>
                    <Description>Execute Windows Update Script...</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand>
                    <Order>6</Order>
                    <Path>powershell -ExecutionPolicy Bypass -Command iex (irm https:///tpmAttestation.ps1)</Path>
                    <Description>Test Autopilot Attestation Script...</Description>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
        <component name="Microsoft-Windows-TPM-Tasks" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
            xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ClearTpm>1</ClearTpm>
        </component>
        <component name="Microsoft-Windows-Security-SPP-UX" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SkipAutoActivation>false</SkipAutoActivation>
        </component>
        <component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <CEIPEnabled>0</CEIPEnabled>
        </component>
        <component name="Networking-MPSSVC-Svc" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <FirewallGroups>
                <FirewallGroup wcm:action="add" wcm:keyValue="RemoteDesktop">
                    <Active>true</Active>
                    <Profile>all</Profile>
                    <Group>@FirewallAPI.dll,-28752</Group>
                </FirewallGroup>
            </FirewallGroups>
		</component>
		</settings>
		<settings pass="oobeSystem">
		<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
		 <OOBE>
		 <HideEULAPage>true</HideEULAPage>
         <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
         <HideOnlineAccountScreens>false</HideOnlineAccountScreens>
         <HideLocalAccountScreen>true</HideLocalAccountScreen>
         <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
         <ProtectYourPC>3</ProtectYourPC>
         <UnattendEnableRetailDemo>false</UnattendEnableRetailDemo>
         </OOBE>
	</component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <Reseal>
            <Mode>Audit</Mode>
            </Reseal>
        </component>
    </settings>
    <settings pass="auditUser">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                <Order>1</Order>
                <Description>Set ExecutionPolicy RemoteSigned</Description>
                <Path>PowerShell -WindowStyle Hidden -Command "Set-ExecutionPolicy RemoteSigned -Force"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                <Order>2</Order>
                <Description>WaitWebConnection</Description>
                <Path>PowerShell -Command "Wait-WebConnection powershellgallery.com -Verbose"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                <Order>3</Order>
                <Description>Save Get-WindowsAutopilotInfo</Description>
                <Path>PowerShell -Command "Install-Script -Name Get-WindowsAutopilotInfo -Verbose -Force"</Path>
                </RunSynchronousCommand>		
				<RunSynchronousCommand wcm:action="add">
                <Order>4</Order>
                <Description>Check Windows Autopilot Pre-req</Description>
                <Path>powershell -Command  iex (irm https:///check-autopilotprereq.ps1)</Path>
                </RunSynchronousCommand>
				<RunSynchronousCommand wcm:action="add">
                <Order>5</Order>
                <Description>Execute BootOOBE to stop Loop</Description>
                <Path>PowerShell -Command iex (irm https:///oobetasks.ps1)</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
</unattend>
'@
#================================================================================================
#   Set Unattend.xml
#================================================================================================
$PantherUnattendPath = 'C:\Windows\Panther'
if (-NOT (Test-Path $PantherUnattendPath)) {
    New-Item -Path $PantherUnattendPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
$Panther = 'C:\Windows\Panther'
$UnattendPath = "$Panther\Invoke-OSDSpecialize.xml"

Write-Verbose "Setting $UnattendPath"
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Width 2000 -Force

Write-Verbose "Setting Unattend in Offline Registry"
Invoke-Exe reg load HKLM\TempSYSTEM "C:\Windows\System32\Config\SYSTEM"
Invoke-Exe reg add HKLM\TempSYSTEM\Setup /v UnattendFile /d "C:\Windows\Panther\Invoke-OSDSpecialize.xml" /f
Invoke-Exe reg unload HKLM\TempSYSTEM
}
}
Set-OSDCloudUnattendSpecialize
#endregion
#=================================================================================
#   WinPE PostOS
#   Restart Computer
#=================================================================================

#region Windows
if ($WindowsPhase -eq 'Windows') {

    #Load OSD and Azure stuff

    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/eq-oobe.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/_anywhere.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/eq-oobe-startup.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/deviceshp.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/autopilot.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/defender.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https:///ne-winpe.psm1')
    Invoke-Expression (Invoke-RestMethod -Uri 'https:///Invoke-HPDriverUpdate.ps1')
     
    osdcloud-SetExecutionPolicy
    osdcloud-InstallPackageManagement
    osdcloud-InstallModuleKeyVault
    osdcloud-InstallModuleOSD
    osdcloud-InstallModuleAzureAD   
    osdcloud-UpdateDefenderStack
    osdcloud-InstallModulePester
    osdcloud-InstallPwsh
    osdcloud-InstallWinGet
    #osdcloud-RenamePC
	
	Write-Host -ForegroundColor DarkGray "Apply HP DriverPack OSD"
	Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/oshrc-support/OSDCloudScripts/main/HP/GaryBlok/ApplyHPDriverPackOSD.ps1') -Wait
	
	
	Write-Host -ForegroundColor DarkGray "Running Windows Autopilot Registration"
	Invoke-Expression (Invoke-RestMethod -Uri 'https:///start-winautopilotreg.ps1') -Wait
	
	Write-Host -ForegroundColor DarkGray "Running OOBE Tasks"
	Invoke-Expression (Invoke-RestMethod -Uri 'https://BootOOBE.ps1') -Wait
	
	Set-Volume -DriveLetter C -NewFileSystemLabel "Local Disk"
 
    $null = Stop-Transcript -ErrorAction Ignore
}
wpeutil reboot