#Requires -RunAsAdministrator

function Initialize-Scan {
    param (
        $Configuration
    )

    $proc = Start-Process -FilePath $CONFIGURATION.AutorunsExe `
            -ArgumentList '-nobanner', '/accepteula', '-a *', '-c', '-s', '*'  `
            -RedirectStandardOut $CONFIGURATION.TemporaryCSVFile -WindowStyle hidden -Passthru
    $proc.WaitForExit()
    $autorunsArray = Import-Csv $CONFIGURATION.TemporaryCSVFile
    $autorunsArray | ConvertTo-Json -depth 100 | Set-Content $CONFIGURATION.StateFile
}

# Get Configuration items
$CONFIGURATION = Get-Content -Raw -Path "$PSScriptRoot\configuration.json" | out-string | ConvertFrom-Json

# Create Program Files directories
Write-Host "[*] Configuring Program Files"
$autorunsDir = $CONFIGURATION.InstallPath
If(!(test-path $autorunsDir)) {
  New-Item -ItemType Directory -Force -Path $autorunsDir >$null 2>&1
}

# Download Mark Russinovich's Autorunsc64.exe if it doesn't exist
Write-Host "[*] Configuring Autorunsc64.exe"
$autorunsPath = $CONFIGURATION.AutorunsExe
if(!(test-path $autorunsPath)) {
  # Requires TLS 1.2
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri "https://live.sysinternals.com/autorunsc64.exe" -OutFile "$autorunsPath"
}

# Install the BurntToast Module by Joshua King https://github.com/Windos/BurntToast
Write-Host "[*] Installing BurntToast PowerShell module"
Install-Module -Name BurntToast -Scope AllUsers 3>$null

# Put a copy of the scripts in the program files directory
Write-Host "[*] Copying scripts to Program Files directory"
Copy-Item "$PSScriptRoot\AutorunsAlert.ps1" "$autorunsDir\AutorunsAlert.ps1"
Copy-Item "$PSScriptRoot\AutorunsToast.ps1" "$autorunsDir\AutorunsToast.ps1"
Copy-Item "$PSScriptRoot\install.ps1" "$autorunsDir\install.ps1"
Copy-Item "$PSScriptRoot\uninstall.ps1" "$autorunsDir\uninstall.ps1"
Copy-Item "$PSScriptRoot\notificationicon.png" "$autorunsDir\notificationicon.png"
Copy-Item "$PSScriptRoot\configuration.json" "$autorunsDir\configuration.json"

# Configure the scheduled task for the worker process.
Get-ScheduledTask -TaskName "AutorunsAlert" -ErrorAction SilentlyContinue -OutVariable task >$null 2>&1
if (! $task) {
    Write-Host "[*] Configuring Scheduled Task for Autoruns Worker"
    $ST_A = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle hidden c:\PROGRA~1\AutorunsAlert\AutorunsAlert.ps1"
    $ST_ST = (Get-Date).addminutes(10) # Start checking in 10 minutes from now.
    $ST_T = New-ScheduledTaskTrigger -Once -At $ST_ST -RepetitionInterval (New-TimeSpan -Minutes $CONFIGURATION.FrequencyMinutes)
    $ST_P = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest -LogonType ServiceAccount
    Register-ScheduledTask -TaskName "AutorunsAlert" -Action $ST_A -Trigger $ST_T -Principal $ST_P >$null 2>&1
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -RestartCount 1 -StartWhenAvailable
    Set-ScheduledTask -TaskName "AutorunsAlert" -Settings $settings >$null 2>&1
}

# Configure the scheduled task for the toast process.
# This is used because we can't toast from SYSTEM to current user (easily or without additional packages)
Get-ScheduledTask -TaskName "AutorunsAlertToast" -ErrorAction SilentlyContinue -OutVariable task >$null 2>&1
if (! $task) {
    Write-Host "[*] Configuring Scheduled Task for Autoruns Toast Alerts"
    # We use cmd.exe to avoid the quick powershell flash you get even when choosing hide window.
    $ST_A = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c start /min "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File c:\PROGRA~1\AutorunsAlert\AutorunsToast.ps1'
    $ST_ST = (Get-Date).addminutes(15) # Start checking in 10 minutes from now.
    $ST_T = New-ScheduledTaskTrigger -Once -At $ST_ST -RepetitionInterval (New-TimeSpan -Minutes $CONFIGURATION.ToastCheckMinutes)
    $ST_USER = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $ST_P = New-ScheduledTaskPrincipal -UserId $ST_USER -RunLevel Highest
    Register-ScheduledTask -TaskName "AutorunsAlertToast" -Action $ST_A -Trigger $ST_T -Principal $ST_P >$null 2>&1
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -RestartCount 1 -StartWhenAvailable
    Set-ScheduledTask -TaskName "AutorunsAlertToast" -Settings $settings >$null 2>&1
}

# Configure the initial state file
Initialize-Scan -configuration $CONFIGURATION

# Configure the state flag for toast alerts. 
New-PSDrive HKU Registry HKEY_USERS >$null 2>&1
if (! (Test-Path "HKU:\.DEFAULT\SOFTWARE\AutorunsAlert")){
  New-Item –Path "HKU:\.DEFAULT\SOFTWARE" –Name AutorunsAlert >$null 2>&1
  New-ItemProperty -Path "HKU:\.DEFAULT\SOFTWARE\AutorunsAlert" -Name "Alert" -Value "0"  -PropertyType "DWORD" >$null 2>&1
  $acl = Get-Acl 'HKU:\.DEFAULT\SOFTWARE\AutorunsAlert'
  $loggedin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $person = [System.Security.Principal.NTAccount]"$loggedin"          
  $access = [System.Security.AccessControl.RegistryRights]"FullControl"
  $inheritance = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit,ObjectInherit"
  $propagation = [System.Security.AccessControl.PropagationFlags]"None"
  $type = [System.Security.AccessControl.AccessControlType]"Allow"
  $rule = New-Object System.Security.AccessControl.RegistryAccessRule($person,$access,$inheritance,$propagation,$type)
  $acl.AddAccessRule($rule)
  $acl |Set-Acl
}

# Done
Write-Host "[*] Setup is complete" -ForegroundColor Green
