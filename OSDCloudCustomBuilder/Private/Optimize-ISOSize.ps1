function Optimize-ISOSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WorkspacePath
    )
    
    Write-Host "Cleaning up language directories to reduce ISO size..." -ForeColor Cyan
    
    $KeepTheseDirs = @('boot','efi','en-us','sources','fonts','resources', 'OSDCloud')
    
    # Clean Media folder
    Get-ChildItem "$WorkspacePath\Media" | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force
    
    # Clean Boot folder
    Get-ChildItem "$WorkspacePath\Media\Boot" -ErrorAction SilentlyContinue | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force
    
    # Clean EFI Boot folder 
    Get-ChildItem "$WorkspacePath\Media\EFI\Microsoft\Boot" -ErrorAction SilentlyContinue | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force
    
    Write-Host "Language cleanup complete" -ForeColor Green
}