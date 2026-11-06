
# AUDYT POCZTA - ETAP 1
# READ-ONLY: brak zmian w Veeam i repozytorium

$ErrorActionPreference = 'Stop'

Import-Module Veeam.Backup.PowerShell -ErrorAction Stop

$names = @('Poczta', 'Poczta_imported')

foreach ($name in $names) {
    Write-Host "`n=== BACKUP: $name ==="

    $backups = @(Get-VBRBackup -Name $name |
        Where-Object { $_.Name -eq $name })

    if ($backups.Count -eq 0) {
        Write-Host "BRAK OBIEKTU O TEJ NAZWIE"
        continue
    }

    foreach ($backup in $backups) {
        [PSCustomObject]@{
            Name                 = $backup.Name
            Id                   = $backup.Id
            JobId                = $backup.JobId
            JobType              = $backup.JobType
            IsTruePerVmContainer = $backup.IsTruePerVmContainer
            Repository           = try {
                $backup.GetRepository().Name
            } catch { 'Nieustalone' }
        } | Format-List
    }
}

Write-Host "`n=== DEFINICJA ZADANIA POCZTA ==="

$jobs = @(Get-VBRJob -Name 'Poczta' |
    Where-Object { $_.Name -eq 'Poczta' })

if ($jobs.Count -eq 0) {
    Write-Host 'Brak aktualnego zadania o nazwie Poczta.'
} else {
    $jobs | Select-Object Name, Id, JobType,
        IsScheduleEnabled, IsRunning |
        Format-List
}
