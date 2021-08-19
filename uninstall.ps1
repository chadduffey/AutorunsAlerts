#Requires -RunAsAdministrator

# Get Configuration items
$CONFIGURATION = Get-Content -Raw -Path "$PSScriptRoot\configuration.json" | out-string | ConvertFrom-Json

# Remove the scheduled tasks
Write-Host "[*] Removing scheduled tasks"
Get-ScheduledTask -TaskName "AutorunsAlertToast" -ErrorAction SilentlyContinue -OutVariable task >$null 2>&1
if ($task) { Unregister-ScheduledTask -TaskName AutorunsAlertToast -Confirm:$false }
Get-ScheduledTask -TaskName "AutorunsAlert" -ErrorAction SilentlyContinue -OutVariable task >$null 2>&1
if ($task) { Unregister-ScheduledTask -TaskName AutorunsAlert -Confirm:$false }

# Remove the program scripts and directory
Write-Host "[*] Removing Program Directory"
if( $CONFIGURATION.InstallPath ) { # Testing that we didnt have an issue reading config before going bananas on a delete.
    if (Test-Path -Path $CONFIGURATION.InstallPath ) { Remove-Item -LiteralPath $CONFIGURATION.InstallPath -Force -Recurse }
}

# Remove the registry key and values
Write-Host "[*] Removing Registry Key"
New-PSDrive HKU Registry HKEY_USERS >$null 2>&1
if ((Test-Path "HKU:\.DEFAULT\SOFTWARE\AutorunsAlert")) { Remove-Item -Path "HKU:\.DEFAULT\SOFTWARE\AutorunsAlert" -Force }

# done
Write-Host "[*] Uninstall complete." -ForegroundColor Green
