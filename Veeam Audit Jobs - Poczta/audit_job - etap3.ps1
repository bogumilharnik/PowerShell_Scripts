
# POCZTA - ETAP 3
# READ-ONLY: odczyt jednego kontenera i jego plikow
# Bez zmian konfiguracji, backupow i repozytorium

$ErrorActionPreference = 'Stop'

Import-Module Veeam.Backup.PowerShell -DisableNameChecking

$expectedId = 'fe0345eb-af67-468b-b0c9-58e8fc8b160a'

$parents = @(
    Get-VBRBackup -Name 'Poczta' |
        Where-Object {
            $_.Name -eq 'Poczta' -and
            $_.Id.ToString() -eq $expectedId
        }
)

if ($parents.Count -ne 1) {
    throw "Nie znaleziono jednoznacznie kontenera Poczta."
}

$parent = $parents[0]
$children = @($parent.FindChildBackups())

Write-Host "`n=== KONTENER ==="

[PSCustomObject]@{
    ParentName = $parent.Name
    ParentId   = $parent.Id
    JobId      = $parent.JobId
    ChildCount = $children.Count
} | Format-List

Write-Host "`n=== CHILD BACKUPS ==="

$children |
    Select-Object Name, Id, JobId, JobType |
    Format-Table -AutoSize

Write-Host "`n=== PLIKI W KATALOGU VEEAM ==="

foreach ($child in $children) {

    Write-Host "`nCHILD: $($child.Name)"
    Write-Host "ID: $($child.Id)"

    try {
        $files = @(Get-VBRBackupFile -Backup $child -ErrorAction Stop)

        Write-Host "Liczba wpisow: $($files.Count)"

        foreach ($file in $files) {
            [PSCustomObject]@{
                ChildName = $child.Name
                FileName  = $file.Name
                FilePath  = $file.Path
                FileType  = $file.BackupFileType
            }
        }
    }
    catch {
        Write-Warning "Nie udalo sie odczytac listy plikow: $($_.Exception.Message)"
    }
}
