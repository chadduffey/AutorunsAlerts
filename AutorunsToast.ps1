
# Ensure we account for the PSWH 7.0 modules location; this came up in testing as a reason for the import to fail.
$env:PSModulePath=$env:PSModulePath + ";" + "C:\Program Files\PowerShell\Modules"

# Import our configuration file.
$CONFIGURATION = Get-Content -Raw -Path "$PSScriptRoot\configuration.json" | out-string | ConvertFrom-Json

# Ensure we are ready to toast it up. 
Import-Module BurntToast 

New-PSDrive HKU Registry HKEY_USERS
if ((Get-ItemProperty -Path 'HKU:\.DEFAULT\SOFTWARE\AutorunsAlert' -Name Alert).alert -eq 1){
    $Button = New-BTButton -Content "Review Changes" -Arguments $($CONFIGURATION.AuditLogFile)
    New-BurntToastNotification -Text "Autoruns Alert", "New persistence items have been installed. Please review the log and investigate with Autoruns.exe." `
                                -Button $Button -AppLogo 'C:\Program Files\AutorunsAlert\notificationicon.png'
    Set-Itemproperty -path 'HKU:\.DEFAULT\SOFTWARE\AutorunsAlert' -Name Alert -value 0
}
