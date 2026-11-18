
# RAPORT SESJI BACKUPU - 16-18.11.2026
# Tylko odczyt - bez zmian w zadaniach Veeam

$Start = [datetime]'2026-11-16 00:00:00'
$End   = Get-Date

$Sessions = @(
    Get-VBRBackupSession | Where-Object {
        $_.CreationTime -ge $Start -and
        $_.CreationTime -le $End
    }

    Get-VBRComputerBackupJobSession | Where-Object {
        $_.CreationTime -ge $Start -and
        $_.CreationTime -le $End
    }
)

$Report = @(
    $Sessions | ForEach-Object {
        [PSCustomObject]@{
            Data        = $_.CreationTime.ToString('yyyy-MM-dd')
            Zadanie     = $_.JobName
            Rozpoczecie = $_.CreationTime
            Zakonczenie = $_.EndTime
            Wynik       = [string]$_.Result
            Stan        = [string]$_.State
            Typ         = [string]$_.JobType
        }
    }
)

Write-Host "`n=== PODSUMOWANIE DZIENNE ===" -ForegroundColor Cyan

$Report |
    Group-Object Data |
    Sort-Object Name |
    ForEach-Object {
        $group = $_.Group

        [PSCustomObject]@{
            Data       = $_.Name
            Uruchomionych = $group.Count
            Success    = @($group | Where-Object Wynik -eq 'Success').Count
            Warning    = @($group | Where-Object Wynik -eq 'Warning').Count
            Failed     = @($group | Where-Object Wynik -eq 'Failed').Count
            Inne       = @($group | Where-Object {
                $_.Wynik -notin @('Success','Warning','Failed')
            }).Count
        }
    } | Format-Table -AutoSize

Write-Host "`n=== SESJE WARNING / FAILED / INNE ===" -ForegroundColor Yellow

$Report |
    Where-Object { $_.Wynik -ne 'Success' } |
    Sort-Object Rozpoczecie |
    Format-Table Data,Zadanie,Wynik,Stan,Rozpoczecie -AutoSize

Write-Host "`n=== WSZYSTKIE SESJE ===" -ForegroundColor Cyan

$Report |
    Sort-Object Rozpoczecie |
    Format-Table Data,Zadanie,Wynik,Stan,Rozpoczecie -AutoSize
