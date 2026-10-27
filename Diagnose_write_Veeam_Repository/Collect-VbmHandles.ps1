<#
===============================================================================
    Collect-VbmHandles.ps1
    Case 08168876 - Veeam Support

    Cel: zbieranie informacji o uchwytach (handles) pliku metadanych .vbm
         w trakcie proby odtworzenia bledu FcRenameFile.

    TRYB: skrypt czyta stan systemu i zapisuje wynik do C:\temp.
          NIE modyfikuje plikow w repozytorium.

    Uruchomienie na serwerze repozytorium (WINSERV19-BKP2), jako administrator:
        powershell -ExecutionPolicy Bypass -File .\Collect-VbmHandles.ps1

    Zatrzymanie: Ctrl+C
===============================================================================
#>

param(
    # Nazwa bazowa pliku VBM - bez sciezki, handle.exe szuka po fragmencie nazwy.
    # Obejmie takze pliki tymczasowe (.vbm_1_tmp, .vbm_36_tmp itd.)
    [string]$VbmName = "VMware vCenter Server_1E664.vbm",

    # Sciezka do handle.exe
    [string]$HandleExe = "C:\temp\handle.exe",

    # Interwal probkowania w milisekundach.
    # 1000 ms (propozycja pierwotna) moze nie zlapac blokady trwajacej ulamek sekundy.
    [int]$IntervalMs = 200,

    [string]$OutFile = "C:\temp\handle_output_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
)

if (-not (Test-Path $HandleExe)) {
    Write-Host "BLAD: nie znaleziono $HandleExe" -ForegroundColor Red
    Write-Host "Pobierz Handle z https://learn.microsoft.com/en-us/sysinternals/downloads/handle"
    return
}

$hdr = @(
    "=" * 90
    " ZBIERANIE UCHWYTOW PLIKU VBM - Case 08168876"
    "=" * 90
    " Start        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
    " Serwer       : $env:COMPUTERNAME"
    " Szukany plik : $VbmName"
    " Interwal     : $IntervalMs ms"
    "=" * 90
    ""
)
$hdr | Out-File -FilePath $OutFile -Encoding UTF8
$hdr | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }

Write-Host "Zbieranie w toku. Uruchom teraz zadanie backup'owe." -ForegroundColor Yellow
Write-Host "Zatrzymanie: Ctrl+C`n" -ForegroundColor Yellow

$i = 0
$hits = 0
try {
    while ($true) {
        $i++
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'

        # -u pokazuje wlasciciela uchwytu (uzytkownika procesu)
        $res = & $HandleExe -nobanner -u $VbmName 2>&1

        $found = $res | Where-Object {
            $_ -match [regex]::Escape($VbmName) -or $_ -match 'pid:'
        }

        if ($found) {
            $hits++
            $block = @("", "[$ts] --- ZNALEZIONO UCHWYT (probka #$i) ---") + $found
            $block | Out-File -FilePath $OutFile -Append -Encoding UTF8
            Write-Host "[$ts] UCHWYT ZNALEZIONY (trafienie #$hits)" -ForegroundColor Green
            $found | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }
        }
        else {
            # zapisujemy tez brak trafienia - dowod, ze plik nie byl trzymany
            # przez zaden proces w przestrzeni uzytkownika
            "[$ts] probka #$i - brak uchwytow w przestrzeni uzytkownika" |
                Out-File -FilePath $OutFile -Append -Encoding UTF8
        }

        if ($i % 25 -eq 0) {
            Write-Host "[$ts] probek: $i, trafien: $hits" -ForegroundColor DarkGray
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}
finally {
    $ftr = @(
        ""
        "=" * 90
        " Koniec       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        " Probek       : $i"
        " Trafien      : $hits"
        "=" * 90
    )
    $ftr | Out-File -FilePath $OutFile -Append -Encoding UTF8
    Write-Host ""
    Write-Host "Zapisano: $OutFile" -ForegroundColor Green
    Write-Host "Probek: $i, trafien: $hits"
}
