<#
===============================================================================
    Nazwa : Diagnose-FcRenameFile-SAFE.ps1
    Cel   : Diagnostyka bledu 'FcRenameFile - locked by 0 processes'.

    ZASADY BEZPIECZENSTWA (wersja poprawiona):
      * SKRYPT NIE ZAPISUJE ANI NIE USUWA NICZEGO W KATALOGACH REPOZYTORIUM.
      * Operacje repozytorium: WYLACZNIE ODCZYT (listowanie plikow, statystyki).
      * Testy zapisu/zmiany nazwy wykonywane sa w DEDYKOWANYM katalogu
        testowym poza repozytorium, ktory jest tworzony i kasowany przez skrypt.
      * Wbudowany bezpiecznik: skrypt przerwie prace, jesli katalog testowy
        znajduje sie wewnatrz sciezki repozytorium.
      * Brak usuwania z uzyciem wildcard - kasowany jest tylko wlasny katalog.

    URUCHOMIC NA SERWERZE REPOZYTORIUM (WINSERV19-BKP2),
    PowerShell "jako administrator".

        powershell -ExecutionPolicy Bypass -File .\Diagnose-FcRenameFile-SAFE.ps1
===============================================================================
#>

param(
    # Sciezki repozytoriow - TYLKO DO ODCZYTU (nigdy nie zapisujemy)
    [string[]]$RepoPaths = @("F:\RepositoryISCSI"),

    # Katalog testowy na TYM SAMYM wolumenie co repozytorium, ale POZA nim
    [string]$TestRootISCSI = "F:\_VeeamDiagTest",

    # Katalog testowy na dysku lokalnym - do porownania (inna warstwa storage)
    [string]$TestRootLocal = "C:\_VeeamDiagTest",

    [int]$RenameCycles = 50,
    [int]$BigFileMB    = 20,
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Diagnoza_FcRename_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
)

$ErrorActionPreference = 'Continue'
$rep = New-Object System.Collections.Generic.List[string]

function Sec { param($t)
    $rep.Add(""); $rep.Add("="*100); $rep.Add("  $t"); $rep.Add("="*100); $rep.Add("")
    Write-Host "`n==> $t" -ForegroundColor Cyan }
function Txt { param($t) if($null -eq $t){$t=""}; $rep.Add($t.TrimEnd()); Write-Host $t }

# ============================================================================
#  BEZPIECZNIK - katalog testowy NIE MOZE lezec wewnatrz repozytorium
# ============================================================================
function Assert-SafeTestPath {
    param([string]$TestPath, [string[]]$Forbidden)
    $tp = $TestPath.TrimEnd('\').ToLower()
    foreach ($f in $Forbidden) {
        $fp = $f.TrimEnd('\').ToLower()
        if ($tp -eq $fp -or $tp.StartsWith($fp + '\')) {
            throw "PRZERWANO: katalog testowy '$TestPath' znajduje sie wewnatrz repozytorium '$f'. Testy zapisu w repozytorium sa niedozwolone."
        }
    }
    return $true
}

Sec "NAGLOWEK"
Txt ("Data              : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt ("Serwer            : " + $env:COMPUTERNAME)
Txt ("Uzytkownik        : " + $env:USERDOMAIN + "\" + $env:USERNAME)
Txt ("Repozytoria (RO)  : " + ($RepoPaths -join '; '))
Txt ("Katalog testowy 1 : " + $TestRootISCSI + "  (ten sam wolumen co repozytorium, poza nim)")
Txt ("Katalog testowy 2 : " + $TestRootLocal + "  (dysk lokalny - porownanie)")
Txt ""
Txt "TRYB PRACY: w katalogach repozytorium wykonywany jest WYLACZNIE ODCZYT."

try {
    Assert-SafeTestPath -TestPath $TestRootISCSI -Forbidden $RepoPaths | Out-Null
    Assert-SafeTestPath -TestPath $TestRootLocal -Forbidden $RepoPaths | Out-Null
    Txt "Bezpiecznik sciezek: OK (katalogi testowe poza repozytorium)."
} catch {
    Txt ("BLAD BEZPIECZNIKA: " + $_.Exception.Message)
    $rep | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Host "`nPRZERWANO ZE WZGLEDOW BEZPIECZENSTWA." -ForegroundColor Red
    return
}

# ============================================================================
#  1. REPOZYTORIUM - TYLKO ODCZYT
# ============================================================================
Sec "1. ZALEGAJACE PLIKI TYMCZASOWE W REPOZYTORIUM (tylko odczyt)"
foreach ($rp in $RepoPaths) {
    Txt ("--- " + $rp + " ---")
    try {
        $tmp = @(Get-ChildItem -Path $rp -Recurse -File -Filter "*_tmp*" -ErrorAction Stop)
        Txt ("Znaleziono plikow tymczasowych: " + $tmp.Count)
        if ($tmp.Count -gt 0) {
            Txt (($tmp | Select-Object FullName,
                    @{n='Utworzony';e={$_.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')}},
                    @{n='Modyfikowany';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')}},
                    @{n='RozmiarKB';e={[math]::Round($_.Length/1KB,1)}} |
                Sort-Object Modyfikowany | Format-Table -AutoSize -Wrap | Out-String))
            Txt "UWAGA: plikow tych skrypt NIE usuwa. Decyzje o ich usunieciu"
            Txt "       nalezy podjac swiadomie, po weryfikacji stanu lancucha kopii."
        }
    } catch { Txt ("Blad odczytu: " + $_.Exception.Message) }
    Txt ""
}

# ============================================================================
#  2. STEROWNIKI FILTRUJACE (odczyt systemowy)
# ============================================================================
Sec "2. STEROWNIKI FILTRUJACE SYSTEMU PLIKOW (fltmc)"
Txt "Lista sterownikow przechwytujacych operacje plikowe (AV/EDR wystepuja tu"
Txt "jako minifiltry). Kluczowe dla ustalenia, czy operacje zmiany nazwy sa"
Txt "przechwytywane przez oprogramowanie ochronne."
Txt ""
try { Txt ((fltmc filters 2>&1 | Out-String)) } catch { Txt ("Blad fltmc: " + $_.Exception.Message) }

foreach ($rp in $RepoPaths) {
    $vol = Split-Path $rp -Qualifier
    Txt (">> Instancje filtrow na wolumenie " + $vol + ":")
    try { Txt ((fltmc instances -v $vol 2>&1 | Out-String)) } catch { Txt ("Blad: " + $_.Exception.Message) }
}
Txt ">> Instancje filtrow na wolumenie C: (porownanie):"
try { Txt ((fltmc instances -v C: 2>&1 | Out-String)) } catch { }

# ============================================================================
#  3. OPROGRAMOWANIE OCHRONNE (odczyt)
# ============================================================================
Sec "3. OPROGRAMOWANIE OCHRONNE I WYKLUCZENIA"
Txt ">> Uslugi ochronne (cortex/traps/cyvera/defender/sense):"
try {
    $svc = Get-Service | Where-Object { $_.Name -match 'cortex|traps|cyvera|defend|sense|WinDefend|cyserver' }
    if ($svc) { Txt (($svc | Select-Object Name, DisplayName, Status | Format-Table -AutoSize | Out-String)) }
    else { Txt "Nie wykryto uslug pasujacych do wzorca." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

Txt ">> Wykluczenia Windows Defender:"
try {
    $pref = Get-MpPreference -ErrorAction Stop
    Txt ("ExclusionPath      : " + ($pref.ExclusionPath -join '; '))
    Txt ("ExclusionExtension : " + ($pref.ExclusionExtension -join '; '))
    Txt ("ExclusionProcess   : " + ($pref.ExclusionProcess -join '; '))
    Txt ("RealTimeProtection : " + (-not $pref.DisableRealtimeMonitoring))
} catch { Txt ("Get-MpPreference niedostepny: " + $_.Exception.Message) }

Txt ""
Txt "UWAGA INTERPRETACYJNA: jesli katalog testowy nie jest objety wykluczeniami,"
Txt "a repozytorium jest - roznica wynikow testu ponizej wskaze wplyw skanowania."

# ============================================================================
#  4. TESTY ZMIANY NAZWY - KATALOGI TESTOWE (poza repozytorium)
# ============================================================================
function Invoke-RenameTest {
    param([string]$Root, [string]$Label, [int]$Cycles, [int]$BigMB)

    $created = $false
    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
        $created = $true
    }
    $work = Join-Path $Root ("run_" + (Get-Date -Format 'HHmmss'))
    New-Item -Path $work -ItemType Directory -Force | Out-Null

    $ok = 0; $fail = 0; $details = @()

    # Test A: male pliki, zmiana nazwy w petli
    for ($i = 1; $i -le $Cycles; $i++) {
        $src = Join-Path $work "t$i.dat_tmp"
        $dstName = "t$i.dat"
        try {
            "diag-$i" | Out-File -FilePath $src -Encoding ASCII -ErrorAction Stop
            Start-Sleep -Milliseconds 40
            Rename-Item -Path $src -NewName $dstName -ErrorAction Stop
            $ok++
        } catch {
            $fail++
            $details += ("  [maly plik] cykl " + $i + ": " + $_.Exception.Message)
        }
    }

    # Test B: duzy plik - zapis i natychmiastowa zmiana nazwy
    $bigOk = $null; $bigMsg = ""
    $bigSrc = Join-Path $work "big.dat_tmp"
    try {
        $buf = New-Object byte[] (1MB)
        (New-Object Random).NextBytes($buf)
        $fs = [System.IO.File]::Create($bigSrc)
        for ($k = 0; $k -lt $BigMB; $k++) { $fs.Write($buf, 0, $buf.Length) }
        $fs.Flush($true); $fs.Close(); $fs.Dispose()
        try {
            Rename-Item -Path $bigSrc -NewName "big.dat" -ErrorAction Stop
            $bigOk = $true
        } catch { $bigOk = $false; $bigMsg = $_.Exception.Message }
    } catch { $bigOk = $false; $bigMsg = "Blad zapisu: " + $_.Exception.Message }

    # Sprzatanie: kasujemy WYLACZNIE wlasny katalog roboczy
    try { Remove-Item -Path $work -Recurse -Force -ErrorAction Stop } catch { }
    if ($created) { try { Remove-Item -Path $Root -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

    return [pscustomobject]@{
        Lokalizacja = $Label
        Udane       = $ok
        Nieudane    = $fail
        DuzyPlikOK  = $bigOk
        DuzyPlikMsg = $bigMsg
        Szczegoly   = $details
    }
}

Sec "4. TEST ZMIANY NAZWY - WOLUMEN REPOZYTORIUM (katalog poza repozytorium)"
Txt ("Katalog: " + $TestRootISCSI + "   (wolumen iSCSI z macierzy MSA2)")
Txt ("Cykli: " + $RenameCycles + ", plik duzy: " + $BigFileMB + " MB")
Txt ""
$r1 = Invoke-RenameTest -Root $TestRootISCSI -Label "Wolumen iSCSI (F:)" -Cycles $RenameCycles -BigMB $BigFileMB
Txt ("Zmian nazwy udanych    : " + $r1.Udane)
Txt ("Zmian nazwy nieudanych : " + $r1.Nieudane)
Txt ("Duzy plik - zmiana OK  : " + $r1.DuzyPlikOK + " " + $r1.DuzyPlikMsg)
if ($r1.Szczegoly.Count -gt 0) { Txt ""; Txt "Szczegoly bledow:"; $r1.Szczegoly | ForEach-Object { Txt $_ } }

Sec "5. TEST PORORNAWCZY - DYSK LOKALNY (C:)"
Txt ("Katalog: " + $TestRootLocal + "   (dysk lokalny serwera, poza iSCSI)")
Txt ""
$r2 = Invoke-RenameTest -Root $TestRootLocal -Label "Dysk lokalny (C:)" -Cycles $RenameCycles -BigMB $BigFileMB
Txt ("Zmian nazwy udanych    : " + $r2.Udane)
Txt ("Zmian nazwy nieudanych : " + $r2.Nieudane)
Txt ("Duzy plik - zmiana OK  : " + $r2.DuzyPlikOK + " " + $r2.DuzyPlikMsg)
if ($r2.Szczegoly.Count -gt 0) { Txt ""; Txt "Szczegoly bledow:"; $r2.Szczegoly | ForEach-Object { Txt $_ } }

Sec "6. INTERPRETACJA WYNIKOW TESTOW"
$f1 = $r1.Nieudane -gt 0 -or $r1.DuzyPlikOK -eq $false
$f2 = $r2.Nieudane -gt 0 -or $r2.DuzyPlikOK -eq $false
if ($f1 -and $f2) {
    Txt "Bledy wystapily na OBU wolumenach (iSCSI oraz dysk lokalny)."
    Txt "=> Wskazuje to na czynnik dzialajacy globalnie w systemie operacyjnym,"
    Txt "   najczesciej sterownik filtrujacy (oprogramowanie AV/EDR)."
} elseif ($f1 -and -not $f2) {
    Txt "Bledy wystapily WYLACZNIE na wolumenie iSCSI (F:), dysk lokalny bez bledow."
    Txt "=> Wskazuje to na warstwe storage: polaczenie iSCSI, macierz MSA2"
    Txt "   lub polityke filtrowania przypisana do tego wolumenu."
} elseif (-not $f1 -and $f2) {
    Txt "Bledy wylacznie na dysku lokalnym - wynik nietypowy, wymaga powtorzenia testu."
} else {
    Txt "Nie odtworzono bledu w warunkach testowych (proste operacje plikowe)."
    Txt "=> Nie wyklucza to problemu: blad Veeam dotyczy pliku metadanych"
    Txt "   zapisywanego przez proces Veeam Data Mover, ktory moze byc traktowany"
    Txt "   inaczej przez sterowniki filtrujace. Kolejny krok: powtorzenie testu"
    Txt "   w trakcie pracy zadania backup'owego oraz weryfikacja polityki"
    Txt "   oprogramowania EDR dla sciezek repozytorium."
}

# ============================================================================
#  7. STAN WOLUMENU I ZDARZENIA SYSTEMOWE (odczyt)
# ============================================================================
Sec "7. STAN WOLUMENU REPOZYTORIUM"
foreach ($rp in $RepoPaths) {
    $q = (Split-Path $rp -Qualifier).TrimEnd(':')
    try {
        Txt ((Get-Volume -DriveLetter $q | Format-List DriveLetter, FileSystemLabel, FileSystem,
              HealthStatus, OperationalStatus, SizeRemaining, Size | Out-String))
    } catch { Txt ("Blad Get-Volume: " + $_.Exception.Message) }
}

Sec "8. ZDARZENIA SYSTEMOWE Z OSTATNICH 7 DNI (dysk / iSCSI / NTFS / zasilanie)"
try {
    $ev = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-7)} -ErrorAction Stop |
          Where-Object { $_.ProviderName -match 'disk|iScsiPrt|Ntfs|volsnap|WHEA|Kernel-Power|MSiSCSI' }
    if ($ev) {
        Txt (($ev | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName,
              @{n='Komunikat';e={($_.Message -split "`r?`n")[0]}} |
              Format-Table -AutoSize -Wrap | Out-String))
    } else { Txt "Brak zdarzen tego typu w ostatnich 7 dniach." }
} catch { Txt ("Blad odczytu dziennika: " + $_.Exception.Message) }

# ============================================================================
Sec "KONIEC RAPORTU"
Txt ("Zakonczono: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt "Przypomnienie: skrypt nie modyfikowal zadnych plikow w repozytorium."

try {
    $rep | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Host "`nZapisano raport:" -ForegroundColor Green
    Write-Host "    $OutputFile" -ForegroundColor Green
} catch { Write-Host ("BLAD zapisu: " + $_.Exception.Message) -ForegroundColor Red }
