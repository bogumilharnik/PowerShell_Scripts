#requires -Version 5.1
<#
.SYNOPSIS
  Audyt konfiguracji zadan typu Backup w Veeam B&R 12.3.2.3617.
.DESCRIPTION
  Tylko dwa polecenia odczytowe Veeam: Get-VBRJob i Get-VBRJobObject.
  Nie pobiera restore points, nie rozwija kontenerow, nie uruchamia backupow,
  nie zmienia konfiguracji, nie odpytuje zawartosci repozytoriow.
  Zapisuje lokalnie CSV: Jobs, JobObjects, Summary, Errors (jesli bledy).
  Przy jakimkolwiek bledzie odczytu oznacza eksport jako PARTIAL.
.NOTES
  Uruchamiac na WINSERV19-VEEAM w Windows PowerShell 5.1 x64.
  Najpierw przejrzec caly kod. Pliki CSV moga zawierac nazwy infrastruktury.
#>

$ErrorActionPreference = 'Stop'
$ExpectedBackupJobs = 21
$OutputRoot = 'C:\VeeamAudit\Exports'

# Fail closed: komendy musza pochodzic z modulu Veeam.
foreach ($commandName in @('Get-VBRJob', 'Get-VBRJobObject')) {
    $command = Get-Command -Name $commandName -ErrorAction Stop
    if ($command.Source -ne 'Veeam.Backup.PowerShell') {
        throw "Nieoczekiwane zrodlo komendy $commandName : $($command.Source)"
    }
}

Write-Host 'Pobieranie listy zadan Veeam (metadane)...'
# Veeam 12.3 moze pokazac ostrzezenie dotyczace zadan agentowych.
$allJobs = @(Get-VBRJob -ErrorAction Stop)
$backupJobs = @($allJobs | Where-Object { [string]$_.JobType -eq 'Backup' } | Sort-Object Name)

Write-Host ('Zadania ogolem: {0}; typ Backup: {1}' -f $allJobs.Count, $backupJobs.Count)
if ($backupJobs.Count -ne $ExpectedBackupJobs) {
    throw ('Oczekiwano {0} zadan typu Backup, otrzymano {1}. Bez eksportu; sprawdz aktualny stan.' -f $ExpectedBackupJobs, $backupJobs.Count)
}

$jobsReport = New-Object 'System.Collections.Generic.List[object]'
$objectsReport = New-Object 'System.Collections.Generic.List[object]'
$errorsReport = New-Object 'System.Collections.Generic.List[object]'
$summaryReport = New-Object 'System.Collections.Generic.List[object]'
$started = Get-Date

foreach ($job in $backupJobs) {
    $jobName = [string]$job.Name
    $jobId = [string]$job.Id
    $jobsReport.Add([PSCustomObject]@{
        JobName           = $jobName
        JobId             = $jobId
        JobType           = [string]$job.JobType
        IsScheduleEnabled = [string]$job.IsScheduleEnabled
    })

    Write-Host ('Odczyt: {0}' -f $jobName)
    $jobObjects = @()
    $jobHasError = $false
    try {
        $jobObjects = @(Get-VBRJobObject -Job $job -ErrorAction Stop)
    }
    catch {
        $jobHasError = $true
        $errorsReport.Add([PSCustomObject]@{
            JobName = $jobName
            ObjectName = ''
            Stage = 'Get-VBRJobObject'
            Error = $_.Exception.Message
        })
        Write-Warning ('Nie udalo sie pobrac obiektow zadania {0}' -f $jobName)
    }

    $jobRows = 0
    foreach ($item in $jobObjects) {
        try {
            # Odczyt tylko wlasciwosci obiektow juz zwroconych przez Get-VBRJobObject.
            $source = $item.Object
            $sourceClass = ''
            $sourceId = ''
            $sourceObjectId = ''
            $sourceObjectRef = ''
            $sourceHostId = ''
            $sourceUuid = ''
            $sourceViType = ''

            if ($null -ne $source) {
                $sourceClass = $source.GetType().FullName
                $sourceId = [string]$source.Id
                $sourceObjectId = [string]$source.ObjectId
                $sourceObjectRef = [string]$source.ObjectRef
                $sourceHostId = [string]$source.HostId
                $sourceUuid = [string]$source.Uuid
                $sourceViType = [string]$source.ViType
            }

            $objectsReport.Add([PSCustomObject]@{
                JobName            = $jobName
                JobId              = $jobId
                EntryName          = [string]$item.Name
                EntryType          = [string]$item.Type
                TypeDisplayName    = [string]$item.TypeDisplayName
                SourceObjType      = [string]$item.SourceObjType
                IsIncluded         = [string]$item.IsIncluded
                IsExcluded         = [string]$item.IsExcluded
                IsFolder           = [string]$item.IsFolder
                IsVssChild         = [string]$item.IsVssChild
                IsExcludeDisksChild = [string]$item.IsExcludeDisksChild
                Location           = [string]$item.Location
                EntryObjectId      = [string]$item.ObjectId
                SourceClass        = $sourceClass
                SourceId           = $sourceId
                SourceObjectId     = $sourceObjectId
                SourceObjectRef    = $sourceObjectRef
                SourceHostId       = $sourceHostId
                SourceUuid         = $sourceUuid
                SourceViType       = $sourceViType
            })
            $jobRows++
        }
        catch {
            $jobHasError = $true
            $errorsReport.Add([PSCustomObject]@{
                JobName = $jobName
                ObjectName = [string]$item.Name
                Stage = 'ExtractProperties'
                Error = $_.Exception.Message
            })
            Write-Warning ('Blad przetwarzania obiektu w zadaniu {0}' -f $jobName)
        }
    }

    $jobStatus = 'OK'
    if ($jobHasError) { $jobStatus = 'ERROR' }
    $summaryReport.Add([PSCustomObject]@{
        JobName = $jobName
        JobId = $jobId
        ReturnedObjects = $jobObjects.Count
        ExportedObjects = $jobRows
        Status = $jobStatus
    })
}

# Lokalne pliki powstaja dopiero po ukonczeniu odczytu wszystkich zadan.
$exportStatus = if ($errorsReport.Count -gt 0) { 'PARTIAL' } else { 'COMPLETE' }
$runFolderName = 'Veeam_Backup_Jobs_{0}_{1}_{2}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)), $exportStatus
$runFolder = Join-Path $OutputRoot $runFolderName
New-Item -Path $runFolder -ItemType Directory -ErrorAction Stop | Out-Null

function Write-AuditCsv {
    param([object[]]$Rows, [string]$Filename)
    $path = Join-Path $runFolder $Filename
    if ($Rows.Count -gt 0) {
        $Rows | Export-Csv -LiteralPath $path -Delimiter ';' -Encoding UTF8 -NoTypeInformation -ErrorAction Stop
        $readBack = @(Import-Csv -LiteralPath $path -Delimiter ';' -ErrorAction Stop)
        if ($readBack.Count -ne $Rows.Count) {
            throw ('Niezgodna liczba wierszy w {0}: {1} != {2}' -f $Filename, $readBack.Count, $Rows.Count)
        }
    }
    else {
        Write-Host ('Brak rekordow - nie tworzono: {0}' -f $Filename)
    }
}

Write-AuditCsv -Rows $jobsReport.ToArray() -Filename 'Veeam_Backup_Jobs.csv'
Write-AuditCsv -Rows $objectsReport.ToArray() -Filename 'Veeam_Backup_JobObjects.csv'
Write-AuditCsv -Rows $summaryReport.ToArray() -Filename 'Veeam_Backup_JobSummary.csv'
Write-AuditCsv -Rows $errorsReport.ToArray() -Filename 'Veeam_Backup_JobErrors.csv'

Write-Host ''
Write-Host ('STATUS EKSPORTU: {0}' -f $exportStatus)
Write-Host ('Zadania Backup: {0}, rekordy obiektow: {1}, bledy: {2}' -f $backupJobs.Count, $objectsReport.Count, $errorsReport.Count)
Write-Host ('Czas: {0}' -f ((Get-Date) - $started))
Write-Host ('Folder: {0}' -f $runFolder)
if ($errorsReport.Count -gt 0) {
    Write-Warning 'Eksport NIEKOMPLETNY. Nie wykorzystuj go do oceny ochrony VM przed wyjasnieniem bledow.'
}
