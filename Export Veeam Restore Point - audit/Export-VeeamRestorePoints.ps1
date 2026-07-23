<#
===============================================================================
    Nazwa      : Export-VeeamRestorePoints.ps1
    Cel        : Wyeksportowanie do pliku TXT:
                 1) KOMPLETNEJ listy punktow przywracania (kazda maszyna,
                    kazdy punkt: data, typ, zadanie),
                 2) WERYFIKACJI wskazanych par maszyna+data (lista Piotra)
                    - czy w danym dniu powstal punkt przywracania,
                 3) ANALIZY LUK - wszystkie odstepy > 30h miedzy kolejnymi
                    punktami danej maszyny w badanym okresie.

    Skrypt jest TYLKO DO ODCZYTU - nie zmienia zadnych ustawien.

    Uruchomienie (serwer Veeam B&R, Windows PowerShell 5.1 jako administrator):
        powershell -ExecutionPolicy Bypass -File .\Export-VeeamRestorePoints.ps1
===============================================================================
#>

param(
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Veeam_RestorePoints_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",
    # Poczatek okresu analizy luk (domyslnie od 1 marca 2026, by objac 1.04)
    [datetime]$AnalysisStart = (Get-Date '2026-03-01'),
    # Prog uznania odstepu za luke (godziny); dzienny backup => norma ~24h
    [int]$GapThresholdHours = 30
)

# --- LISTA DO WERYFIKACJI (maszyna + data wg maila Piotra) -------------------
# Format: @{ Vm = 'nazwa maszyny (jak w Veeam)'; Date = 'yyyy-MM-dd' }
$CheckList = @(
    @{ Vm = 'VMware vCenter Server';       Date = '2026-07-22' },
)

$ErrorActionPreference = 'Continue'
$report = New-Object System.Collections.Generic.List[string]

function Add-Section { param([string]$T)
    $report.Add(""); $report.Add(("=" * 100)); $report.Add("  $T")
    $report.Add(("=" * 100)); $report.Add("")
    Write-Host "==> $T" -ForegroundColor Cyan
}
function Add-Text { param([string]$T) if ($null -eq $T) {$T=""}; $report.Add($T.TrimEnd()) }

# --- NAGLOWEK ----------------------------------------------------------------
Add-Section "NAGLOWEK RAPORTU - PUNKTY PRZYWRACANIA"
Add-Text ("Data wygenerowania  : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Text ("Serwer              : " + $env:COMPUTERNAME)
Add-Text ("Uzytkownik          : " + $env:USERDOMAIN + "\" + $env:USERNAME)
Add-Text ("Okres analizy luk   : od " + $AnalysisStart.ToString('yyyy-MM-dd') + " do dzis")
Add-Text ("Prog luki           : > " + $GapThresholdHours + " godzin")

try { Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
      Add-Text "Modul PowerShell    : Veeam.Backup.PowerShell (zaladowany)" }
catch { try { Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
              Add-Text "Modul PowerShell    : VeeamPSSnapIn (snap-in)" }
        catch { Add-Text ("BLAD modulu Veeam: " + $_.Exception.Message) } }
try { Connect-VBRServer -Server localhost -ErrorAction Stop
      Add-Text "Polaczenie z VBR    : localhost (OK)" }
catch { Add-Text ("Polaczenie z VBR    : " + $_.Exception.Message) }

# --- POBRANIE WSZYSTKICH PUNKTOW ----------------------------------------------
Add-Section "POBIERANIE PUNKTOW PRZYWRACANIA (dyskowe, wszystkie zadania)"
$allPoints = @()
try {
    $backups = @(Get-VBRBackup -ErrorAction Stop)
    Add-Text ("Liczba obiektow backup (Get-VBRBackup): " + $backups.Count)
    foreach ($b in $backups) {
        try {
            $rps = @(Get-VBRRestorePoint -Backup $b -ErrorAction Stop)
            foreach ($rp in $rps) {
                $vmName = $rp.VmName
                if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = $rp.Name }
                $corrupted = $null
                try { $corrupted = $rp.IsCorrupted } catch { }
                $allPoints += [pscustomobject]@{
                    Maszyna      = $vmName
                    Zadanie      = $b.JobName
                    Data         = $rp.CreationTime
                    Typ          = $rp.Type
                    Uszkodzony   = $corrupted
                }
            }
        } catch {
            Add-Text ("  Blad odczytu punktow dla backupu '" + $b.Name + "': " + $_.Exception.Message)
        }
    }
    Add-Text ("Laczna liczba punktow przywracania: " + $allPoints.Count)
} catch {
    Add-Text ("Blad Get-VBRBackup: " + $_.Exception.Message)
}

# --- SEKCJA 1: PELNA LISTA PUNKTOW PER MASZYNA --------------------------------
Add-Section "1. KOMPLETNA LISTA PUNKTOW PRZYWRACANIA (per maszyna, chronologicznie)"
$byVm = $allPoints | Group-Object Maszyna | Sort-Object Name
foreach ($g in $byVm) {
    Add-Text ("-" * 100)
    Add-Text ("MASZYNA: " + $g.Name + "   (liczba punktow: " + $g.Count + ")")
    Add-Text (($g.Group | Sort-Object Data |
               Select-Object @{n='Data utworzenia';e={$_.Data.ToString('yyyy-MM-dd HH:mm:ss')}},
                             Typ, Zadanie, Uszkodzony |
               Format-Table -AutoSize | Out-String))
}

# --- SEKCJA 2: WERYFIKACJA LISTY (maszyna + data) ------------------------------
Add-Section "2. WERYFIKACJA WSKAZANYCH DNI (czy istnieje punkt przywracania z danego dnia)"
Add-Text ("Zweryfikowano par (maszyna, data): " + $CheckList.Count)
Add-Text ""
$verRows = foreach ($item in $CheckList) {
    $day      = [datetime]$item.Date
    $dayEnd   = $day.AddDays(1)
    $vmPoints = @($allPoints | Where-Object { $_.Maszyna -eq $item.Vm })
    $hit      = @($vmPoints | Where-Object { $_.Data -ge $day -and $_.Data -lt $dayEnd })
    $prev     = @($vmPoints | Where-Object { $_.Data -lt $day }    | Sort-Object Data -Descending | Select-Object -First 1)
    $next     = @($vmPoints | Where-Object { $_.Data -ge $dayEnd } | Sort-Object Data             | Select-Object -First 1)
    [pscustomobject]@{
        Maszyna          = $item.Vm
        Dzien            = $item.Date
        PunktTegoDnia    = if ($vmPoints.Count -eq 0) { 'BRAK MASZYNY W BACKUPACH' }
                           elseif ($hit.Count -gt 0)  { 'JEST (' + ($hit[0].Data.ToString('HH:mm')) + ')' }
                           else                       { 'BRAK' }
        PoprzedniPunkt   = if ($prev) { $prev[0].Data.ToString('yyyy-MM-dd HH:mm') } else { '-' }
        NastepnyPunkt    = if ($next) { $next[0].Data.ToString('yyyy-MM-dd HH:mm') } else { '-' }
        OdstepGodz       = if ($prev -and $next) { [math]::Round(($next[0].Data - $prev[0].Data).TotalHours,1) } else { $null }
    }
}
Add-Text (($verRows | Format-Table -AutoSize | Out-String))
$missing = @($verRows | Where-Object { $_.PunktTegoDnia -eq 'BRAK' })
$found   = @($verRows | Where-Object { $_.PunktTegoDnia -like 'JEST*' })
Add-Text ("PODSUMOWANIE WERYFIKACJI: BRAK punktu w danym dniu: " + $missing.Count + " przypadkow; punkt ISTNIEJE: " + $found.Count + " przypadkow.")

# --- SEKCJA 3: ANALIZA LUK > progu --------------------------------------------
Add-Section ("3. ANALIZA LUK - odstepy > " + $GapThresholdHours + "h miedzy kolejnymi punktami (od " + $AnalysisStart.ToString('yyyy-MM-dd') + ")")
$gapRows = @()
foreach ($g in $byVm) {
    $pts = @($g.Group | Where-Object { $_.Data -ge $AnalysisStart } | Sort-Object Data)
    for ($i = 1; $i -lt $pts.Count; $i++) {
        $delta = ($pts[$i].Data - $pts[$i-1].Data).TotalHours
        if ($delta -gt $GapThresholdHours) {
            $gapRows += [pscustomobject]@{
                Maszyna       = $g.Name
                PunktPrzed    = $pts[$i-1].Data.ToString('yyyy-MM-dd HH:mm')
                PunktPo       = $pts[$i].Data.ToString('yyyy-MM-dd HH:mm')
                OdstepGodz    = [math]::Round($delta,1)
                Zadanie       = $pts[$i].Zadanie
            }
        }
    }
}
if ($gapRows.Count -gt 0) {
    Add-Text ("Wykryte luki (" + $gapRows.Count + "):")
    Add-Text (($gapRows | Sort-Object Maszyna, PunktPrzed | Format-Table -AutoSize | Out-String))
} else {
    Add-Text "Nie wykryto luk powyzej progu w badanym okresie."
}
Add-Text ""
Add-Text "UWAGA interpretacyjna: luka moze wynikac takze z harmonogramu (zadania tygodniowe,"
Add-Text "maszyny dodane/usuniete z zadan, przerwy planowane) - kazda pozycje nalezy ocenic w kontekscie."

# --- ZAKONCZENIE ---------------------------------------------------------------
Add-Section "KONIEC RAPORTU"
Add-Text ("Raport wygenerowano: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

try {
    $report | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Host ""; Write-Host "Zapisano raport:" -ForegroundColor Green
    Write-Host "    $OutputFile" -ForegroundColor Green
} catch { Write-Host ("BLAD zapisu: " + $_.Exception.Message) -ForegroundColor Red }

try { Disconnect-VBRServer -ErrorAction SilentlyContinue } catch { }
