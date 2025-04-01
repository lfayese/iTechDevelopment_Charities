function Optimize-ISOSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WorkspacePath
    )
    Write-Host "Cleaning up language directories to reduce ISO size..." -ForegroundColor Cyan
    $KeepTheseDirs = @('boot','efi','en-us','sources','fonts','resources','OSDCloud')
    # Define base Media folder path using Join-Path
    $MediaPath = Join-Path $WorkspacePath 'Media'
    # Clean Media folder using -Directory to only return directories.
    if (Test-Path $MediaPath) {
        Get-ChildItem -Path $MediaPath -Directory | 
            Where-Object { $KeepTheseDirs -notcontains $_.Name } | 
            Remove-Item -Recurse -Force
    }
    # Clean Boot folder
    $BootPath = Join-Path $MediaPath 'Boot'
    if (Test-Path $BootPath) {
        Get-ChildItem -Path $BootPath -Directory | 
            Where-Object { $KeepTheseDirs -notcontains $_.Name } | 
            Remove-Item -Recurse -Force
    }
    # Clean EFI Boot folder 
    $EFIBootPath = Join-Path $MediaPath 'EFI\Microsoft\Boot'
    if (Test-Path $EFIBootPath) {
        Get-ChildItem -Path $EFIBootPath -Directory | 
            Where-Object { $KeepTheseDirs -notcontains $_.Name } | 
            Remove-Item -Recurse -Force
    }
    Write-Host "Language cleanup complete" -ForegroundColor Green
}