<#
===============================================================================
    Nazwa : Analyze-RepoFolders-READONLY.ps1

    ------------------------------------------------------------------------
    TRYB: WYLACZNIE ODCZYT
    Skrypt uzywa tylko: Get-ChildItem, Get-Item, Get-HotFix, Measure-Object.
    NIE tworzy, NIE modyfikuje i NIE usuwa zadnych plikow ani katalogow.
    Jedyny mozliwy zapis to plik raportu (-OutputFile); parametr -NoFile
    calkowicie go wylacza.
    ------------------------------------------------------------------------

    Cel: ustalenie, dlaczego blad FcRenameFile dotyka wybranych zadan.
         Analizuje katalogi zadan pod katem: liczby plikow, liczby punktow,
         zalegajacych plikow tymczasowych oraz dat modyfikacji sterownikow.

    Uruchomienie (serwer repozytorium, PowerShell jako administrator):
        powershell -ExecutionPolicy Bypass -File .\Analyze-RepoFolders-READONLY.ps1 -NoFile
===============================================================================
#>

param(
    [string[]]$RepoPaths = @("F:\RepositoryISCSI", "D:\RepositoryLocal"),
    [datetime]$ChangeWindowStart = (Get-Date '2026-07-10'),
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Analiza_Katalogow_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt",
    [switch]$NoFile
)

$ErrorActionPreference = 'Continue'
$rep = New-Object System.Collections.Generic.List[string]
function Sec { param($t) $rep.Add(""); $rep.Add("="*100); $rep.Add("  $t"); $rep.Add("="*100); $rep.Add("")
    Write-Host "`n==> $t" -ForegroundColor Cyan }
function Txt { param($t) if($null -eq $t){$t=""}; $rep.Add($t.TrimEnd()); Write-Host $t }

Sec "ANALIZA KATALOGOW ZADAN - TRYB TYLKO DO ODCZYTU"
Txt ("Data   : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt ("Serwer : " + $env:COMPUTERNAME)
Txt ""
Txt "Skrypt nie modyfikuje zadnych danych."

# --- 1. STATYSTYKA KATALOGOW ZADAN ------------------------------------------
Sec "1. STATYSTYKA KATALOGOW ZADAN (liczba plikow, rozmiar, sieroty)"
$rows = @()
foreach ($rp in $RepoPaths) {
    if (-not (Test-Path $rp)) { continue }
    try {
        $dirs = @(Get-ChildItem -Path $rp -Directory -ErrorAction SilentlyContinue)
        foreach ($d in $dirs) {
            $files = @(Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
            $vbk = @($files | Where-Object { $_.Extension -eq '.vbk' })
            $vib = @($files | Where-Object { $_.Extension -eq '.vib' })
            $vbm = @($files | Where-Object { $_.Extension -eq '.vbm' })
            $tmp = @($files | Where-Object { $_.Name -like '*_tmp*' })
            $rows += [pscustomobject]@{
                Repozytorium = Split-Path $rp -Leaf
                Zadanie      = $d.Name
                PlikowRazem  = $files.Count
                VBK          = $vbk.Count
                VIB          = $vib.Count
                VBM          = $vbm.Count
                SierotyTMP   = $tmp.Count
                RozmiarGB    = [math]::Round((($files | Measure-Object Length -Sum).Sum)/1GB,1)
                OstatniZapis = if ($files) { (($files | Sort-Object LastWriteTime -Descending)[0]).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '-' }
            }
        }
    } catch { Txt ("Blad: " + $_.Exception.Message) }
}
Txt (($rows | Sort-Object PlikowRazem -Descending | Format-Table -AutoSize | Out-String))
Txt "INTERPRETACJA: katalogi o najwiekszej liczbie plikow sa najbardziej narazone"
Txt "               na problemy z operacjami na metadanych (szczegolnie na ReFS)."

# --- 2. SZCZEGOLY SIEROT ----------------------------------------------------
Sec "2. ZALEGAJACE PLIKI TYMCZASOWE - SZCZEGOLY"
$anyTmp = $false
foreach ($rp in $RepoPaths) {
    if (-not (Test-Path $rp)) { continue }
    $tmp = @(Get-ChildItem -Path $rp -Recurse -File -Filter "*_tmp*" -ErrorAction SilentlyContinue)
    if ($tmp.Count -gt 0) {
        $anyTmp = $true
        Txt (($tmp | Select-Object @{n='Zadanie';e={Split-Path (Split-Path $_.FullName -Parent) -Leaf}},
                    @{n='Plik';e={$_.Name}},
                    @{n='Utworzony';e={$_.CreationTime.ToString('yyyy-MM-dd HH:mm')}},
                    @{n='Modyfikowany';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                    @{n='WiekDni';e={[math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays,0)}},
                    @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
              Sort-Object WiekDni | Format-Table -AutoSize -Wrap | Out-String))
    }
}
if (-not $anyTmp) { Txt "Nie znaleziono zalegajacych plikow tymczasowych." }
Txt ""
Txt "UWAGA: skrypt tych plikow NIE usuwa. Przed ewentualnym usunieciem nalezy"
Txt "       zweryfikowac spojnosc lancucha kopii dla danej maszyny w konsoli Veeam."

# --- 3. AKTYWNOSC W KATALOGACH W OKRESIE ZMIANY -----------------------------
Sec ("3. AKTYWNOSC PLIKOW OD " + $ChangeWindowStart.ToString('yyyy-MM-dd'))
Txt "Rozklad zapisu plikow wg dni - pomaga skorelowac zmiane zachowania systemu."
Txt ""
foreach ($rp in $RepoPaths) {
    if (-not (Test-Path $rp)) { continue }
    try {
        $recent = @(Get-ChildItem -Path $rp -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $ChangeWindowStart })
        if ($recent) {
            Txt ("--- " + $rp + " ---")
            Txt (($recent | Group-Object { $_.LastWriteTime.ToString('yyyy-MM-dd') } |
                  Select-Object @{n='Dzien';e={$_.Name}}, @{n='Plikow';e={$_.Count}} |
                  Sort-Object Dzien | Format-Table -AutoSize | Out-String))
        }
    } catch { }
}

# --- 4. STEROWNIKI - DATY I WERSJE ------------------------------------------
Sec "4. STEROWNIKI FILTRUJACE - DATY MODYFIKACJI I WERSJE"
Txt "Zmiana daty sterownika w okolicach zmiany zachowania systemu jest silna przeslanka."
Txt ""
$drv = @(
    "C:\Windows\System32\drivers\tedrdrv.sys",
    "C:\Windows\System32\drivers\cyvrfsfd.sys",
    "C:\Windows\System32\drivers\WdFilter.sys",
    "C:\Windows\System32\drivers\refs.sys",
    "C:\Windows\System32\drivers\refsv1.sys",
    "C:\Windows\System32\drivers\msiscsi.sys",
    "C:\Windows\System32\drivers\mpio.sys"
)
foreach ($f in $drv) {
    try {
        if (Test-Path $f) {
            $i = Get-Item $f -ErrorAction Stop
            Txt ("{0,-20} {1,-20} {2}" -f $i.Name, $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $i.VersionInfo.FileVersion)
        }
    } catch { }
}

Sec "5. AKTUALIZACJE SYSTEMU (ostatnie 60 dni)"
try {
    $hf = Get-HotFix -ErrorAction SilentlyContinue |
          Where-Object { $_.InstalledOn -and $_.InstalledOn -ge (Get-Date).AddDays(-60) }
    if ($hf) { Txt (($hf | Select-Object HotFixID, Description,
                     @{n='Zainstalowano';e={$_.InstalledOn.ToString('yyyy-MM-dd')}} |
                   Sort-Object Zainstalowano | Format-Table -AutoSize | Out-String)) }
    else { Txt "Brak aktualizacji w tym okresie lub dane niedostepne." }
} catch { Txt ("Blad: " + $_.Exception.Message) }

Sec "6. PLIKI PROGRAMOWE CORTEX XDR - DATY (wskaznik aktualizacji agenta)"
foreach ($p in @("C:\Program Files\Palo Alto Networks", "C:\Program Files (x86)\Palo Alto Networks")) {
    if (Test-Path $p) {
        try {
            Txt ("--- " + $p + " ---")
            Txt ((Get-ChildItem -Path $p -Recurse -File -Include *.sys,*.exe,*.dll -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 15 |
                  Select-Object Name, @{n='Modyfikowany';e={$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')}},
                      @{n='Wersja';e={$_.VersionInfo.FileVersion}} |
                  Format-Table -AutoSize | Out-String))
        } catch { Txt ("Brak dostepu do katalogu: " + $_.Exception.Message) }
    }
}

Sec "KONIEC"
Txt ("Zakonczono: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Txt "Potwierdzenie: nie zmodyfikowano zadnych danych."

if (-not $NoFile) {
    try { $rep | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
          Write-Host "`nZapisano: $OutputFile" -ForegroundColor Green }
    catch { Write-Host ("BLAD zapisu: " + $_.Exception.Message) -ForegroundColor Red }
} else { Write-Host "`nTryb -NoFile: nie zapisano raportu." -ForegroundColor Yellow }
