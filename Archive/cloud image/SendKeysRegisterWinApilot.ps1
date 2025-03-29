# Define the script folder path and the path for SendKeys script
$scriptFolderPath = "C:\OSDCloud\Scripts"
$ScriptPathSendKeys = Join-Path -Path $scriptFolderPath -ChildPath "SendKeys.ps1"

# Check if the script folder path exists, if not, create it
if (!(Test-Path -Path $scriptFolderPath -PathType Container)) {
    $null = New-Item -Path $scriptFolderPath -ItemType Directory -Force
}

# Define the script block for SendKeys script
$SendKeysScript = @"
`$Global:Transcript = "`$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-SendKeys.log"
Start-Transcript -Path (Join-Path `"$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD`" `$Global:Transcript) -ErrorAction Ignore

Write-Host -ForegroundColor DarkGray "Stop Debug-Mode (SHIFT + F10) with WscriptShell.SendKeys"
`$WscriptShell = New-Object -ComObject WScript.Shell

# ALT + TAB
Write-Host -ForegroundColor DarkGray "SendKeys: ALT + TAB"
`$WscriptShell.SendKeys("%({TAB})")

Start-Sleep -Seconds 1

# Shift + F10
Write-Host -ForegroundColor DarkGray "SendKeys: SHIFT + F10"
`$WscriptShell.SendKeys("+({F10})")

# Validate and execute remote script
try {
    $scriptContent = Invoke-RestMethod -Uri 'https://start-winautopilotreg.ps1' -ErrorAction Stop
    # Basic validation that content looks like PowerShell
    if ($scriptContent -match '^[# \t]*(?:function|param|begin|process|end|if|foreach|while|do|switch|try|catch)[ \t{]') {
        $tempPath = Join-Path $env:TEMP "WinAutopilotReg_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
        $scriptContent | Out-File -FilePath $tempPath -Encoding UTF8
        . $tempPath
        Remove-Item -Path $tempPath -Force
    } else {
        throw "Retrieved content does not appear to be a valid PowerShell script"
    }
} catch {
    Write-Error "Failed to execute remote script: $_"
    Stop-Transcript
    exit 1
}

Stop-Transcript -Verbose
"@

# Write the SendKeys script to the file
$SendKeysScript | Set-Content -Path $ScriptPathSendKeys -Encoding ascii

# Start a new PowerShell process and execute SendKeys script
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-File", `"$ScriptPathSendKeys`" -Wait
