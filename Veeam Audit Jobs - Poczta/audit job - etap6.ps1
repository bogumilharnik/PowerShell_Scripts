
# POCZTA - ETAP 6
# READ-ONLY: identyfikacja innych lancuchow tej samej VM
# Brak zmian w Veeam i repozytorium

$ErrorActionPreference = 'Stop'
Import-Module Veeam.Backup.PowerShell -DisableNameChecking

$targetName = 'Debian11-Poczta'

$results = @(
    foreach ($backup in @(Get-VBRBackup)) {

        if (-not $backup.IsTruePerVmContainer) {
            continue
        }

        try {
            $children = @($backup.FindChildBackups())
        }
        catch {
            Write-Warning "Nie odczytano struktury: $($backup.Name)"
            continue
        }

        foreach ($child in $children) {
            if (
                $child.Name -eq $targetName -or
                $child.Name -like "* - $targetName"
            ) {
                [PSCustomObject]@{
                    ParentName = $backup.Name
                    ParentId   = $backup.Id
                    ParentJobId = $backup.JobId
                    ChildName  = $child.Name
                    ChildId    = $child.Id
                    ChildJobId = $child.JobId
                }
            }
        }
    }
)

$results | Format-Table -AutoSize
Write-Host "Znalezione lancuchy: $($results.Count)"
