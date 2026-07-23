<#
===============================================================================
    Nazwa : Diagnose-FcRenameFile-READONLY.ps1
    Wersja: tylko do odczytu

    ------------------------------------------------------------------------
    GWARANCJA TRYBU PRACY
    ------------------------------------------------------------------------
    Skrypt wykonuje WYLACZNIE operacje odczytu.

    W calym skrypcie NIE WYSTEPUJA polecenia:
        New-Item, Remove-Item, Rename-Item, Move-Item, Copy-Item,
        Set-Content, Add-Content, Clear-Content, Set-ItemProperty,
        New-ItemProperty, Remove-ItemProperty, [System.IO.File]::Create,
        [System.IO.File]::Delete, [System.IO.File]::Move, mkdir, del, ren

    Jedyna operacja zapisu w calym skrypcie to zapisanie pliku raportu
    na pulpicie uzytkownika (parametr -OutputFile). Mozna ja calkowicie
    wylaczyc uruchamiajac skrypt z parametrem -NoFile - wtedy wynik
    pojawia sie wylacznie na ekranie i skrypt nie zapisuje NICZEGO.

    Uzyte polecenia: Get-ChildItem, Get-Item, Get-Service, Get-Volume,
    Get-Disk, Get-Partition, Get-MpPreference, Get-WinEvent, Get-Process,
    Get-CimInstance, Get-IscsiSession, Get-IscsiConnection, Get-IscsiTarget,
    fltmc (podpolecenia filters/instances - odczyt), fsutil fsinfo (odczyt),
    mpclaim -s (odczyt), openfiles /query (odczyt).

    Skrypt nie tworzy katalogow, nie kasuje plikow, nie zmienia nazw,
    nie modyfikuje ustawien systemu ani konfiguracji Veeam.
    ------------------------------------------------------------------------

    URUCHOMIENIE (na serwerze repozytorium, PowerShell jako administrator):
        powershell -ExecutionPolicy Bypass -File .\Diagnose-FcRenameFile-READONLY.ps1

    Wariant bez zapisu jakiegokolwiek pliku:
        powershell -ExecutionPolicy Bypass -File .\Diagnose-FcRenameFile-READONLY.ps1 -NoFile
===============================================================================
#>

param(
    # Sciezki repozytoriow - wylacznie do listowania zawartosci
    [string[]]$RepoPaths = @("F:\RepositoryISCSI", "D:\RepositoryLocal"),

    # Ile dni wstecz analizowac dziennik zdarzen
    [int]$EventDays = 14,

    # Sciezka raportu; ignorowana gdy podano -NoFile
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Diagnoza_ReadOnly_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",

    # Tryb bez zapisu jakiegokolwiek pliku - wynik tylko na ekranie
    [switch]$NoFile
)

$ErrorActionPreference = 'Continue'
$rep = New-Object System.Collections.Generic.List[string]

function Sec { param($t)
    $rep.Add(""); $rep.Add("="*100); $rep.Add("  $t"); $rep.Add("="*100); $rep.Add("")
    Write-Host "`n==> $t" -ForegroundColor Cyan }
function Txt { param($t) if($null -eq $t){$t=""}; $rep.Add($t.TrimEnd()); Write-Host $t }

Sec "NAGLOWEK - TRYB WYLACZNIE DO ODCZYTU"
Txt ("Data              : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt ("Serwer            : " + $env:COMPUTERNAME)
Txt ("Uzytkownik        : " + $env:USERDOMAIN + "\" + $env:USERNAME)
Txt ("Analizowane sciezki: " + ($RepoPaths -join '; '))
Txt ""
Txt "Skrypt nie tworzy, nie modyfikuje i nie usuwa zadnych plikow ani katalogow."
if ($NoFile) { Txt "Tryb -NoFile: raport nie zostanie zapisany na dysku." }
else { Txt ("Jedyny zapis: plik raportu -> " + $OutputFile) }

# ============================================================================
Sec "1. PLIKI TYMCZASOWE (*_tmp*) W REPOZYTORIACH"
Txt "Zalegajace pliki tymczasowe moga blokowac kolejne operacje zmiany nazwy."
Txt "Skrypt ich NIE usuwa - decyzja nalezy do administratora po weryfikacji lancucha."
Txt ""
foreach ($rp in $RepoPaths) {
    Txt ("--- " + $rp + " ---")
    if (-not (Test-Path $rp)) { Txt "Sciezka niedostepna na tym serwerze."; Txt ""; continue }
    try {
        $tmp = @(Get-ChildItem -Path $rp -Recurse -File -Filter "*_tmp*" -ErrorAction SilentlyContinue)
        Txt ("Znaleziono: " + $tmp.Count)
        if ($tmp.Count -gt 0) {
            Txt (($tmp | Select-Object @{n='Plik';e={$_.FullName}},
                    @{n='Utworzony';e={$_.CreationTime.ToString('yyyy-MM-dd HH:mm')}},
                    @{n='Modyfikowany';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                    @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
                Sort-Object Modyfikowany | Format-Table -AutoSize -Wrap | Out-String))
        }
    } catch { Txt ("Blad odczytu: " + $_.Exception.Message) }
    Txt ""
}

Txt ">> Najnowsze pliki .vbm w repozytoriach (kontrola dat metadanych):"
foreach ($rp in $RepoPaths) {
    if (-not (Test-Path $rp)) { continue }
    try {
        $vbm = @(Get-ChildItem -Path $rp -Recurse -File -Filter "*.vbm" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 15)
        if ($vbm) {
            Txt ("--- " + $rp + " ---")
            Txt (($vbm | Select-Object @{n='Plik';e={$_.Name}},
                    @{n='Modyfikowany';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                    @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
                Format-Table -AutoSize | Out-String))
        }
    } catch { }
}

# ============================================================================
Sec "2. STEROWNIKI FILTRUJACE SYSTEMU PLIKOW"
Txt "Sterowniki przechwytujace operacje plikowe. Oprogramowanie AV/EDR"
Txt "(Windows Defender, Cortex XDR) wystepuje tu jako minifiltr."
Txt "Kolumna 'Altitude' okresla kolejnosc przechwytywania operacji."
Txt ""
try { Txt ((fltmc filters 2>&1 | Out-String)) } catch { Txt ("Blad fltmc: " + $_.Exception.Message) }

$vols = @($RepoPaths | ForEach-Object { Split-Path $_ -Qualifier } | Select-Object -Unique)
$vols += "C:"
foreach ($v in ($vols | Select-Object -Unique)) {
    Txt (">> Instancje filtrow na wolumenie " + $v + ":")
    try { Txt ((fltmc instances -v $v 2>&1 | Out-String)) } catch { Txt ("Blad: " + $_.Exception.Message) }
}

# ============================================================================
Sec "3. OPROGRAMOWANIE OCHRONNE I WYKLUCZENIA"
Txt ">> Uslugi ochronne:"
try {
    $svc = Get-Service -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'cortex|traps|cyvera|cyserver|defend|sense|WinDefend|Palo' }
    if ($svc) { Txt (($svc | Select-Object Name, DisplayName, Status | Format-Table -AutoSize | Out-String)) }
    else { Txt "Nie wykryto uslug pasujacych do wzorca." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

Txt ">> Procesy oprogramowania ochronnego:"
try {
    $prc = Get-Process -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'cortex|traps|cyserver|cyvera|MsMpEng|NisSrv|SenseCE' }
    if ($prc) { Txt (($prc | Select-Object Name, Id, Path | Format-Table -AutoSize -Wrap | Out-String)) }
    else { Txt "Brak pasujacych procesow." }
} catch { }

Txt ">> Wykluczenia Windows Defender:"
try {
    $pref = Get-MpPreference -ErrorAction Stop
    Txt ("ExclusionPath      : " + ($pref.ExclusionPath -join '; '))
    Txt ("ExclusionExtension : " + ($pref.ExclusionExtension -join '; '))
    Txt ("ExclusionProcess   : " + ($pref.ExclusionProcess -join '; '))
    Txt ("RealTimeProtection : " + (-not $pref.DisableRealtimeMonitoring))
    Txt ("ScanNetworkFiles   : " + (-not $pref.DisableScanningNetworkFiles))
} catch { Txt ("Get-MpPreference niedostepny: " + $_.Exception.Message) }
Txt ""
Txt "UWAGA: wykluczenia Defendera nie obejmuja oprogramowania EDR innych"
Txt "producentow. Polityke wykluczen Cortex XDR nalezy zweryfikowac w jego konsoli."

# ============================================================================
Sec "4. WARSTWA iSCSI I SCIEZKI DO MACIERZY"
Txt ">> Sesje iSCSI:"
try {
    $ses = Get-IscsiSession -ErrorAction SilentlyContinue
    if ($ses) { Txt (($ses | Select-Object TargetNodeAddress, IsConnected, IsPersistent,
                      NumberOfConnections, SessionIdentifier | Format-List | Out-String)) }
    else { Txt "Brak sesji iSCSI lub modul niedostepny." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

Txt ">> Polaczenia iSCSI:"
try {
    $con = Get-IscsiConnection -ErrorAction SilentlyContinue
    if ($con) { Txt (($con | Select-Object ConnectionIdentifier, InitiatorAddress,
                      TargetAddress, TargetPortNumber | Format-Table -AutoSize | Out-String)) }
} catch { }

Txt ">> Cele iSCSI:"
try {
    $tgt = Get-IscsiTarget -ErrorAction SilentlyContinue
    if ($tgt) { Txt (($tgt | Select-Object NodeAddress, IsConnected | Format-Table -AutoSize | Out-String)) }
} catch { }

Txt ">> Konfiguracja MPIO (wielosciezkowosc):"
try { Txt ((mpclaim -s -d 2>&1 | Out-String)) } catch { Txt "mpclaim niedostepne (MPIO moze nie byc zainstalowane)." }

Txt ">> Parametry limitow czasowych inicjatora iSCSI (rejestr, odczyt):"
try {
    $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}"
    Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.MaxRequestHoldTime -or $p.LinkDownTime -or $p.SrbTimeoutDelta) {
            Txt ("  " + $_.PSChildName + " : MaxRequestHoldTime=" + $p.MaxRequestHoldTime +
                 ", LinkDownTime=" + $p.LinkDownTime + ", SrbTimeoutDelta=" + $p.SrbTimeoutDelta)
        }
    }
} catch { Txt ("Blad odczytu rejestru: " + $_.Exception.Message) }

# ============================================================================
Sec "5. STAN WOLUMENOW I DYSKOW"
try {
    Txt ((Get-Volume -ErrorAction SilentlyContinue |
          Where-Object { $_.DriveLetter } |
          Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus,
              OperationalStatus,
              @{n='WolneGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
              @{n='CalkGB';e={[math]::Round($_.Size/1GB,1)}},
              @{n='Wolne%';e={ if($_.Size -gt 0){[math]::Round(100*$_.SizeRemaining/$_.Size,1)} else {0} }} |
          Format-Table -AutoSize | Out-String))
} catch { Txt ("Blad Get-Volume: " + $_.Exception.Message) }

Txt ">> Dyski fizyczne / logiczne:"
try {
    Txt ((Get-Disk -ErrorAction SilentlyContinue |
          Select-Object Number, FriendlyName, BusType, HealthStatus, OperationalStatus,
              @{n='RozmiarGB';e={[math]::Round($_.Size/1GB,1)}} |
          Format-Table -AutoSize | Out-String))
} catch { }

foreach ($v in ($RepoPaths | ForEach-Object { Split-Path $_ -Qualifier } | Select-Object -Unique)) {
    Txt (">> Parametry NTFS wolumenu " + $v + ":")
    try { Txt ((fsutil fsinfo ntfsinfo $v 2>&1 | Out-String)) } catch { }
}

# ============================================================================
Sec ("6. ZDARZENIA SYSTEMOWE Z OSTATNICH " + $EventDays + " DNI")
Txt "Filtr: dysk, iSCSI, NTFS, migawki, sprzet (WHEA), zasilanie."
Txt ""
try {
    $ev = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-$EventDays)} -ErrorAction Stop |
          Where-Object { $_.ProviderName -match 'disk|iScsiPrt|MSiSCSI|Ntfs|volsnap|WHEA|Kernel-Power|mpio|storahci|EventLog' -and
                         $_.LevelDisplayName -match 'Error|Warning|Critical' }
    if ($ev) {
        Txt ("Liczba zdarzen: " + @($ev).Count)
        Txt (($ev | Select-Object @{n='Czas';e={$_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')}},
                  @{n='Zrodlo';e={$_.ProviderName}}, Id, LevelDisplayName,
                  @{n='Komunikat';e={ (($_.Message -split "`r?`n")[0]) }} |
              Format-Table -AutoSize -Wrap | Out-String))
    } else { Txt "Brak zdarzen tego typu w badanym okresie." }
} catch { Txt ("Blad odczytu dziennika: " + $_.Exception.Message) }

Txt ">> Dziennik aplikacji - wpisy Veeam z ostatnich 3 dni:"
try {
    $va = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-3)} -ErrorAction Stop |
          Where-Object { $_.ProviderName -match 'Veeam' -and $_.LevelDisplayName -match 'Error|Warning' } |
          Select-Object -First 40
    if ($va) {
        Txt (($va | Select-Object @{n='Czas';e={$_.TimeCreated.ToString('yyyy-MM-dd HH:mm')}},
                  Id, LevelDisplayName,
                  @{n='Komunikat';e={ (($_.Message -split "`r?`n")[0]) }} |
              Format-Table -AutoSize -Wrap | Out-String))
    } else { Txt "Brak wpisow." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

# ============================================================================
Sec "7. USLUGI VEEAM NA TYM SERWERZE"
try {
    $vs = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Veeam' }
    if ($vs) { Txt (($vs | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-String)) }
    else { Txt "Brak uslug Veeam na tym serwerze." }
} catch { }

Sec "8. OTWARTE PLIKI (openfiles - odczyt)"
Txt "Dziala tylko przy wlaczonej opcji 'openfiles /local on' (wymaga restartu)."
try {
    $of = openfiles /query /fo csv 2>&1
    if ($of -match 'ERROR|blad|nie jest') { Txt "Funkcja wylaczona lub niedostepna." }
    else { Txt (($of | Out-String)) }
} catch { Txt "openfiles niedostepne." }

# ============================================================================
Sec "KONIEC RAPORTU"
Txt ("Zakonczono: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt "Potwierdzenie: skrypt nie utworzyl, nie zmodyfikowal i nie usunal"
Txt "zadnego pliku ani katalogu w systemie."

if (-not $NoFile) {
    try {
        $rep | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
        Write-Host "`nZapisano raport:" -ForegroundColor Green
        Write-Host "    $OutputFile" -ForegroundColor Green
    } catch { Write-Host ("BLAD zapisu raportu: " + $_.Exception.Message) -ForegroundColor Red }
} else {
    Write-Host "`nTryb -NoFile: raport nie zostal zapisany (wynik wylacznie na ekranie)." -ForegroundColor Yellow
}
