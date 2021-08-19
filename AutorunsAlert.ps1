Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $logfile
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    If($logfile) {
        Add-Content $logfile -Value $Line
    }
    Else {
        Write-Output $Line
    }
}

function Start-FullScan {
    param (
        $autorunsPath,
        $autorunsCsv
    )

    # Call autorunssc.exe and save output to temp csv.
    Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Starting autorunsc.exe process"
    $proc = Start-Process -FilePath $autorunsPath `
            -ArgumentList '-nobanner', '/accepteula', '-a *', '-c', '-s', '*'  -RedirectStandardOut $autorunsCsv -WindowStyle hidden -Passthru
    $proc.WaitForExit()
    Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Process autorunsc.exe is done."
    
    # import the temp csv as a powershell object and remove the temp csv. 
    $autorunsArray = Import-Csv $autorunsCsv
    Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Importing temp CSV file"
    Remove-Item -Path $autorunsCsv -Force
    Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Deleting temp .csv file"
    
    # return the current state of autoruns configuration as a powershell object. 
    return $autorunsArray | ConvertTo-Json | ConvertFrom-Json
}

function Compare-Autoruns {
    param (
        $CurrentAutoruns,
        $PreviousAutoruns
    )

    # comparisons. 
    $Comparison = Compare-Object -ReferenceObject $PreviousAutoruns -DifferenceObject $CurrentAutoruns -Property "Entry Location", "Entry" -PassThru
    
    return $Comparison
}

function Start-SortComparisonObject {
    param (
        $ComparisonObject,
        $CONFIGURATION
    )

    # comparisons. 
    $Comparison = Compare-Object -ReferenceObject $PreviousAutoruns -DifferenceObject $CurrentAutoruns -Property "Entry Location", "Entry" -PassThru
    
    $NewAustoruns = @()

    foreach ($item in $Comparison)
    {
        If ($item.SideIndicator -like "=>"){
            $ReportValue = $item | ConvertTo-Json
            Write-Log -Level WARN -logfile $CONFIGURATION.AuditLogFile -Message "NEW AUTORUN: "
            Add-Content $CONFIGURATION.AuditLogFile -Value $ReportValue
            $NewAustoruns += $item
        }

        If ($item.SideIndicator -like "<=") {
            $ReportValue = $item | ConvertTo-Json
            Write-Log -Level INFO -logfile $CONFIGURATION.AuditLogFile -Message "Removed persistence item. (Was in the previous autoruns scan, but no longer exists):"
            Add-Content $CONFIGURATION.AuditLogFile -Value $ReportValue
        }
    }

    return $NewAustoruns
}

function Update-StateFile {
    param (

    )
}

# Get Configuration items
$CONFIGURATION = Get-Content -Raw -Path "$PSScriptRoot\configuration.json" | out-string | ConvertFrom-Json
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Autoruns comparison starting."


# Run autorunsc.exe to gather current state. 
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Calling Start-FullScan"
$currentAutoruns = Start-FullScan -autorunsCsv $CONFIGURATION.TemporaryCSVFile -autorunsPath $CONFIGURATION.AutorunsExe

# Gather previous state from .json state file. 
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Reading previous scan results from .json file"
$previousAutoruns = Get-Content -Raw -Path $CONFIGURATION.StateFile | out-string | ConvertFrom-Json

# Compare.
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Comparing this scan with previous scan"
$ComparisonResult = Compare-Autoruns -CurrentAutoruns $currentAutoruns -PreviousAutoruns $previousAutoruns

# Identify the reportable conditions and return those. (Log all interesting conditions in the function even if not alertable) 
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Identifying differences"
$NewAutoruns = Start-SortComparisonObject -ComparisonObject $ComparisonResult -CONFIGURATION $CONFIGURATION

# Update the state file ahead of the next run
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Updating state file"
$currentAutoruns | ConvertTo-Json -depth 100 | Set-Content $CONFIGURATION.StateFile

# If no new alertable conditions are found we are done.
if ($null -eq $NewAutoruns){
    Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "No new autoruns entries identified. Exiting."
    exit
}

# Set the notification flag for the user mode process
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Setting notification flag."
Set-Itemproperty -path 'HKCU:\SOFTWARE\AutorunsAlert' -Name 'Alert' -value 1

# Done.
Write-Log -Level INFO -logfile $CONFIGURATION.ScriptLogFile -Message "Issues identified. Flag configured. Exiting."
exit








