
# Diagnostyka ostrzeżeń - Strona i pokrewne
# Tylko odczyt

$Start = [datetime]'2026-11-16 00:00:00'
$End   = [datetime]'2026-11-19 00:00:00'

$WarnSessions = @(
    Get-VBRBackupSession | Where-Object {
        $_.JobName -eq 'Strona i pokrewne' -and
        $_.CreationTime -ge $Start -and
        $_.CreationTime -lt $End
    } | Sort-Object CreationTime
)

foreach ($s in $WarnSessions) {

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Zadanie: $($s.JobName)"
    Write-Host "Data:    $($s.CreationTime)"
    Write-Host "Koniec:  $($s.EndTime)"
    Write-Host "Wynik:   $($s.Result)"
    Write-Host "========================================"

    Get-VBRTaskSession -Session $s |
        Select-Object Name, Status, Reason |
        Format-Table -AutoSize -Wrap
}
