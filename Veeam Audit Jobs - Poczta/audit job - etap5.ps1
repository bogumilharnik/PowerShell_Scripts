
# POCZTA - ETAP 5
# READ-ONLY: punkty tylko jednego historycznego child backupu

$ErrorActionPreference = 'Stop'
Import-Module Veeam.Backup.PowerShell -DisableNameChecking

$parentId = 'fe0345eb-af67-468b-b0c9-58e8fc8b160a'
$childId  = 'a8b7b9fd-65c5-46f8-a862-8e61b9355121'

$parents = @(
    Get-VBRBackup -Name 'Poczta' |
    Where-Object {
        $_.Name -eq 'Poczta' -and
        "$($_.Id)" -eq $parentId
    }
)

if ($parents.Count -ne 1) {
    throw 'Nie znaleziono jednoznacznie kontenera Poczta.'
}

$children = @(
    $parents[0].FindChildBackups() |
    Where-Object { "$($_.Id)" -eq $childId }
)

if ($children.Count -ne 1) {
    throw 'Nie znaleziono jednoznacznie child backupu.'
}

$child = $children[0]
$points = @(
    Get-VBRRestorePoint -Backup $child -ErrorAction Stop |
    Sort-Object CreationTime
)

Write-Host "`n=== PUNKTY PRZYWRACANIA ==="

$points |
    Select-Object Name, Id, CreationTime, Type,
        VmId, ObjectId, IsConsistent |
    Format-Table -AutoSize

Write-Host "`n=== PODSUMOWANIE ==="

[PSCustomObject]@{
    BackupName  = $child.Name
    BackupId    = $child.Id
    JobId       = $child.JobId
    Points      = $points.Count
    OldestPoint = if ($points.Count) {
        $points[0].CreationTime
    } else { $null }
    NewestPoint = if ($points.Count) {
        $points[-1].CreationTime
    } else { $null }
} | Format-List
