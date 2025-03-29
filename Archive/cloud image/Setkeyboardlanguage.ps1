$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Set-KeyboardLanguage.log"
Start-Transcript -Path (Join-Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" $Global:Transcript) -ErrorAction Stop

try {
    Write-Host "Starting keyboard language configuration..."
    
    # Get current language list
    $LanguageList = Get-WinUserLanguageList
    Write-Host "Current languages: $($LanguageList.LanguageTag -join ', ')"
    
    # Check if en-US is already present
    if ($LanguageList.LanguageTag -contains "en-US") {
        Write-Host "en-US is already in the language list"
    } else {
        Write-Host "Adding en-US to language list"
        $LanguageList.Add("en-US")
    }
    
    # Set en-US as the primary language
    $enUS = $LanguageList | Where-Object LanguageTag -eq "en-US"
    if ($enUS) {
        Write-Host "Setting en-US as primary language"
        # Move en-US to the first position
        $LanguageList.Remove($enUS)
        $LanguageList.Insert(0, $enUS)
    }
    
    # Apply changes
    Set-WinUserLanguageList $LanguageList -Force
    Write-Host "Language settings applied successfully"
    
    # Verify changes
    $NewLanguageList = Get-WinUserLanguageList
    if ($NewLanguageList[0].LanguageTag -eq "en-US") {
        Write-Host "Verified: en-US is set as primary language"
    } else {
        Write-Warning "Verification failed: Primary language is $($NewLanguageList[0].LanguageTag)"
    }
    
    # Set keyboard layout
    Write-Host "Setting keyboard layout..."
    $enUS.InputMethodTips.Clear()
    $enUS.InputMethodTips.Add('0409:00000409') # US keyboard layout
    Set-WinUserLanguageList $NewLanguageList -Force
    
} catch {
    Write-Error "Failed to configure keyboard language: $_"
    exit 1
} finally {
    Stop-Transcript
}