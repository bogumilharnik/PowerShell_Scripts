<#
===============================================================================
    Collect-DefragDiagnostics.ps1
    Case 08168876 - Veeam Support

    Cel: zebranie pelnej informacji o zaplanowanej defragmentacji/optymalizacji
         wolumenow, ze szczegolnym uwzglednieniem wolumenu repozytorium ReFS,
         oraz skorelowanie zdarzen defragmentacji z datami wystapienia bledu
         FcRenameFile.

    ------------------------------------------------------------------------
    TRYB: WYLACZNIE DO ODCZYTU
    Skrypt uzywa wylacznie polecen odczytu:
      Get-ScheduledTask, Get-ScheduledTaskInfo, Get-WinEvent, Get-Volume,
      Get-ItemProperty, Get-Item, Get-CimInstance
    Skrypt NIE uruchamia defragmentacji, NIE wywoluje defrag.exe ani
    Optimize-Volume, NIE modyfikuje harmonogramu zadan.
    Jedyny zapis: plik raportu TXT (parametr -OutputFile).
    ------------------------------------------------------------------------

    Uruchomienie na serwerze repozytorium (WINSERV19-BKP2), jako administrator:
        powershell -ExecutionPolicy Bypass -File .\Collect-DefragDiagnostics.ps1
===============================================================================
#>

param(
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Defrag_Diagnostyka_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",

    # Wolumen repozytorium (do wyroznienia w raporcie)
    [string]$RepoDrive = "F",

    # Znane daty wystapienia bledu FcRenameFile - do korelacji
    [string[]]$ErrorDates = @(
        '2024-11-28',
        '2026-05-02','2026-05-04','2026-05-05','2026-05-06',
        '2026-07-05','2026-07-07','2026-07-08','2026-07-09',
        '2026-07-18','2026-07-19','2026-07-20','2026-07-21','2026-07-22','2026-07-24'
    )
)

$ErrorActionPreference = 'Continue'
$rep = New-Object System.Collections.Generic.List[string]

function Sec { param($t)
    $rep.Add(""); $rep.Add("="*100); $rep.Add("  $t"); $rep.Add("="*100); $rep.Add("")
    Write-Host "`n==> $t" -ForegroundColor Cyan }
function Txt { param($t) if($null -eq $t){$t=""}; $rep.Add($t.TrimEnd()) }

# ============================================================================
Sec "NAGLOWEK - DIAGNOSTYKA DEFRAGMENTACJI (TRYB TYLKO DO ODCZYTU)"
Txt ("Data wygenerowania : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt ("Serwer             : " + $env:COMPUTERNAME)
Txt ("Uzytkownik         : " + $env:USERDOMAIN + "\" + $env:USERNAME)
Txt ("Wolumen repo       : " + $RepoDrive + ":")
Txt ("Zgloszenie         : Case 08168876 (Veeam Support)")
Txt ""
Txt "Skrypt nie uruchamia defragmentacji i nie modyfikuje harmonogramu zadan."

# ============================================================================
Sec "1. ZADANIA HARMONOGRAMU - GALAZ \Microsoft\Windows\Defrag\"
try {
    $tasks = @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -ErrorAction Stop)
    Txt ("Liczba zadan: " + $tasks.Count)
    Txt ""
    foreach ($t in $tasks) {
        Txt ("--- ZADANIE: " + $t.TaskName + " ---")
        Txt ("Stan            : " + $t.State)
        Txt ("Opis            : " + $t.Description)
        Txt ("Autor           : " + $t.Author)
        try {
            $i = $t | Get-ScheduledTaskInfo -ErrorAction Stop
            Txt ("Ostatnie uruch. : " + $(if($i.LastRunTime){$i.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss')}else{'-'}))
            Txt ("Wynik ostatni   : " + $i.LastTaskResult + $(if($i.LastTaskResult -eq 0){"  (0 = sukces)"}else{""}))
            Txt ("Nastepne uruch. : " + $(if($i.NextRunTime){$i.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss')}else{'-'}))
            Txt ("Liczba brakow   : " + $i.NumberOfMissedRuns)
        } catch { Txt ("  (blad odczytu info: " + $_.Exception.Message + ")") }

        Txt ">> Wyzwalacze:"
        try {
            foreach ($tr in $t.Triggers) {
                Txt ("   " + $tr.CimClass.CimClassName + " | Enabled=" + $tr.Enabled +
                     " | Start=" + $tr.StartBoundary +
                     $(if($tr.DaysInterval){" | co "+$tr.DaysInterval+" dni"}else{""}) +
                     $(if($tr.WeeksInterval){" | co "+$tr.WeeksInterval+" tyg."}else{""}) +
                     $(if($tr.DaysOfWeek){" | dni: "+$tr.DaysOfWeek}else{""}))
            }
        } catch { Txt "   (brak danych o wyzwalaczach)" }

        Txt ">> Akcje:"
        try { foreach ($a in $t.Actions) { Txt ("   " + $a.Execute + " " + $a.Arguments) } }
        catch { Txt "   (brak danych o akcjach)" }
        Txt ""
    }
} catch { Txt ("Blad odczytu zadan: " + $_.Exception.Message) }

# ============================================================================
Sec "2. STATYSTYKI OPTYMALIZACJI PER WOLUMEN (rejestr - odczyt)"
Txt "Klucz: HKLM:\SOFTWARE\Microsoft\Dfrg\Statistics"
Txt "Pokazuje, ktore wolumeny sa objete zaplanowana optymalizacja i kiedy"
Txt "byly ostatnio przetwarzane."
Txt ""
try {
    $stats = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Dfrg\Statistics' -ErrorAction Stop)
    if ($stats.Count -eq 0) { Txt "Brak wpisow." }
    foreach ($s in $stats) {
        $p = Get-ItemProperty $s.PSPath -ErrorAction SilentlyContinue
        Txt ("--- Wolumen: " + $s.PSChildName + " ---")
        foreach ($n in ($p.PSObject.Properties.Name | Where-Object { $_ -notmatch '^PS' })) {
            $v = $p.$n
            # niektore wartosci to FILETIME w formie binarnej lub liczby
            Txt ("   " + $n.PadRight(28) + " : " + $v)
        }
        Txt ""
    }
} catch { Txt ("Blad odczytu rejestru: " + $_.Exception.Message) }

# ============================================================================
Sec "3. PELNA HISTORIA ZDARZEN DEFRAGMENTACJI (dziennik Application)"
Txt "Zrodlo: Microsoft-Windows-Defrag"
Txt ""
$defragEvents = @()
try {
    $defragEvents = @(Get-WinEvent -FilterHashtable @{
                        LogName='Application'; ProviderName='Microsoft-Windows-Defrag'
                      } -MaxEvents 1000 -ErrorAction Stop | Sort-Object TimeCreated)
    Txt ("Liczba zdarzen: " + $defragEvents.Count)
    if ($defragEvents.Count -gt 0) {
        Txt ("Zakres         : " + $defragEvents[0].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') +
             "  do  " + $defragEvents[-1].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
    }
    Txt ""
    foreach ($e in $defragEvents) {
        $msg = ($e.Message -split "`r?`n" | Where-Object { $_.Trim() }) -join ' | '
        Txt ("[" + $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') + "] ID=" + $e.Id +
             " " + $e.LevelDisplayName + " :: " + $msg)
    }
} catch { Txt ("Brak zdarzen lub blad odczytu: " + $_.Exception.Message) }

# ============================================================================
Sec "4. KORELACJA: ZDARZENIA DEFRAGMENTACJI vs DATY BLEDU FcRenameFile"
Txt "Zestawienie ma na celu sprawdzenie, czy defragmentacja uruchamiala sie"
Txt "w dniach, w ktorych wystapil blad FcRenameFile."
Txt ""
if ($defragEvents.Count -eq 0) {
    Txt "Brak zdarzen defragmentacji do korelacji."
} else {
    $byDay = $defragEvents | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') }
    $rows = foreach ($d in $ErrorDates) {
        $g = $byDay | Where-Object { $_.Name -eq $d }
        [pscustomobject]@{
            'Data bledu'       = $d
            'Defrag tego dnia' = if ($g) { 'TAK' } else { 'brak' }
            'Liczba zdarzen'   = if ($g) { $g.Count } else { 0 }
            'Godziny'          = if ($g) { ($g.Group | ForEach-Object { $_.TimeCreated.ToString('HH:mm') }) -join ', ' } else { '-' }
        }
    }
    Txt (($rows | Format-Table -AutoSize | Out-String))

    $hit = @($rows | Where-Object { $_.'Defrag tego dnia' -eq 'TAK' }).Count
    Txt ("Dni z bledem, w ktorych odnotowano defragmentacje: " + $hit + " z " + $ErrorDates.Count)
    Txt ""
    Txt "UWAGA INTERPRETACYJNA: dziennik zdarzen Defrag rejestruje przede wszystkim"
    Txt "zakonczenia operacji zaplanowanych. Brak wpisu w danym dniu nie wyklucza"
    Txt "aktywnosci uslugi defragsvc - operacje slabify/retrim na ReFS moga trwac"
    Txt "dlugo i przekraczac granice doby. Rozstrzygajace sa logi Process Monitor."
}

Txt ""
Txt ">> Wszystkie dni, w ktorych odnotowano zdarzenia defragmentacji:"
if ($defragEvents.Count -gt 0) {
    Txt (($defragEvents | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } |
          Select-Object @{n='Dzien';e={$_.Name}}, @{n='Zdarzen';e={$_.Count}},
                        @{n='Godziny';e={($_.Group | ForEach-Object { $_.TimeCreated.ToString('HH:mm') }) -join ', '}} |
          Sort-Object Dzien | Format-Table -AutoSize -Wrap | Out-String))
}

# ============================================================================
Sec "5. USLUGA DEFRAGSVC"
try {
    $svc = Get-Service -Name defragsvc -ErrorAction Stop
    Txt ("Nazwa       : " + $svc.Name)
    Txt ("Nazwa wysw. : " + $svc.DisplayName)
    Txt ("Stan        : " + $svc.Status)
    Txt ("Tryb startu : " + $svc.StartType)
} catch { Txt ("Blad odczytu uslugi: " + $_.Exception.Message) }

Txt ""
Txt ">> Proces svchost obslugujacy defragsvc (jesli aktywny):"
try {
    $p = Get-CimInstance Win32_Service -Filter "Name='defragsvc'" -ErrorAction Stop
    Txt ("   ProcessId : " + $p.ProcessId + $(if($p.ProcessId -eq 0){"  (usluga niedziala)"}else{""}))
    Txt ("   PathName  : " + $p.PathName)
    Txt ("   StartMode : " + $p.StartMode)
    Txt ("   State     : " + $p.State)
} catch { Txt ("   (brak danych: " + $_.Exception.Message + ")") }

# ============================================================================
Sec "6. WOLUMENY - STAN I SYSTEM PLIKOW"
try {
    Txt ((Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } |
          Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus, OperationalStatus,
              @{n='WolneGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
              @{n='CalkGB';e={[math]::Round($_.Size/1GB,1)}},
              @{n='Wolne%';e={ if($_.Size -gt 0){[math]::Round(100*$_.SizeRemaining/$_.Size,1)} else {0} }} |
          Format-Table -AutoSize | Out-String))
} catch { Txt ("Blad: " + $_.Exception.Message) }

Txt ">> Wolumen repozytorium - szczegoly:"
try {
    $v = Get-Volume -DriveLetter $RepoDrive -ErrorAction Stop
    Txt ("   Litera         : " + $v.DriveLetter)
    Txt ("   Etykieta       : " + $v.FileSystemLabel)
    Txt ("   System plikow  : " + $v.FileSystem)
    Txt ("   Typ systemu pl.: " + $v.FileSystemType)
    Txt ("   Stan           : " + $v.HealthStatus + " / " + $v.OperationalStatus)
    Txt ("   Rozmiar        : " + [math]::Round($v.Size/1GB,1) + " GB")
    Txt ("   Wolne          : " + [math]::Round($v.SizeRemaining/1GB,1) + " GB")
    Txt ("   Rozmiar alokacji: " + $v.AllocationUnitSize)
} catch { Txt ("   Blad: " + $_.Exception.Message) }

# ============================================================================
Sec "7. ZADANIA HARMONOGRAMU POWIAZANE ZE STORAGE (kontekst)"
Txt "Inne zadania systemowe mogace dotykac wolumenow w oknie backupowym."
Txt ""
try {
    $other = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskPath -match 'Defrag|Storage|Chkdsk|SpaceAgent|Data Integrity' -or
                       $_.TaskName -match 'Defrag|Optimize|Scrub|Integrity|SilentCleanup' })
    if ($other.Count -gt 0) {
        $rows2 = foreach ($t in $other) {
            $ti = $null
            try { $ti = $t | Get-ScheduledTaskInfo -ErrorAction Stop } catch {}
            [pscustomobject]@{
                Zadanie   = $t.TaskName
                Sciezka   = $t.TaskPath
                Stan      = $t.State
                Ostatnie  = if ($ti -and $ti.LastRunTime) { $ti.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }
                Nastepne  = if ($ti -and $ti.NextRunTime) { $ti.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }
            }
        }
        Txt (($rows2 | Sort-Object Sciezka, Zadanie | Format-Table -AutoSize -Wrap | Out-String))
    } else { Txt "Nie znaleziono dodatkowych zadan." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

# ============================================================================
Sec "8. ZDARZENIA SYSTEMOWE DYSK / iSCSI / NTFS (30 dni)"
try {
    $ev = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-30)} -ErrorAction Stop |
            Where-Object { $_.ProviderName -match 'disk|iScsiPrt|MSiSCSI|Ntfs|ReFS|volsnap|WHEA|Kernel-Power|mpio' -and
                           $_.LevelDisplayName -match 'Error|Warning|Critical' } |
            Sort-Object TimeCreated)
    Txt ("Liczba zdarzen: " + $ev.Count)
    if ($ev.Count -gt 0) {
        Txt (($ev | Select-Object @{n='Czas';e={$_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')}},
                    @{n='Zrodlo';e={$_.ProviderName}}, Id, LevelDisplayName,
                    @{n='Komunikat';e={($_.Message -split "`r?`n")[0]}} |
              Format-Table -AutoSize -Wrap | Out-String))
    }
} catch { Txt ("Blad: " + $_.Exception.Message) }

# ============================================================================
Sec "KONIEC RAPORTU"
Txt ("Zakonczono: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt "Potwierdzenie: skrypt nie uruchamial defragmentacji, nie modyfikowal"
Txt "harmonogramu zadan ani zadnych plikow w systemie."

try {
    $rep | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Host "`nZapisano raport:" -ForegroundColor Green
    Write-Host "    $OutputFile" -ForegroundColor Green
} catch { Write-Host ("BLAD zapisu: " + $_.Exception.Message) -ForegroundColor Red }
