
# POCZTA - ETAP 4
# READ-ONLY: bez zmian zadan, backupow i repozytorium

$ErrorActionPreference = 'Stop'
Import-Module Veeam.Backup.PowerShell -DisableNameChecking

$parentId = 'fe0345eb-af67-468b-b0c9-58e8fc8b160a'
$childId  = 'a8b7b9fd-65c5-46f8-a862-8e61b9355121'
$jobId    = 'c18e80d1-795b-45d4-bb0e-c4457e3142ff'

$parents = @(Get-VBRBackup -Name 'Poczta' |
    Where-Object { "$($_.Id)" -eq $parentId })

if ($parents.Count -ne 1) {
    throw 'Nie mozna jednoznacznie zidentyfikowac parent backupu.'
}

$children = @($parents[0].FindChildBackups() |
    Where-Object { "$($_.Id)" -eq $childId })

if ($children.Count -ne 1) {
    throw 'Nie mozna jednoznacznie zidentyfikowac child backupu.'
}

$child = $children[0]

Write-Host "`n=== BACKUP CHILD ==="
$child | Select-Object Name, Id, JobId, JobType |
    Format-List

Write-Host "`n=== PLIKI - RZECZYWISTE WLASCIWOSCI ==="
$files = @(Get-VBRBackupFile -Backup $child -ErrorAction Stop)

Write-Host "Liczba wpisow: $($files.Count)"

if ($files.Count -gt 0) {
    $files[0] | Format-List *
}

Write-Host "`n=== AKTUALNE ZADANIE ==="
$jobs = @(Get-VBRJob -Name 'Poczta' |
    Where-Object { "$($_.Id)" -eq $jobId })

if ($jobs.Count -ne 1) {
    throw 'Nie mozna jednoznacznie zidentyfikowac zadania.'
}

$job = $jobs[0]

$job | Select-Object Name, Id, JobType,
    IsScheduleEnabled, IsRunning | Format-List

Write-Host "`n=== OBIEKTY ZADANIA ==="
Get-VBRJobObject -Job $job |
    Select-Object Name, ObjectId, Type |
    Format-Table -AutoSize

Write-Host "`n=== KONIEC ODCZYTU ==="
