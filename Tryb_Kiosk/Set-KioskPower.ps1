#Requires -Version 5.1
<#
================================================================================
  Set-KioskPower.ps1
  Ustawia zasilanie kiosku na "ZAWSZE WLACZONY":
    - bez wygaszania ekranu, bez uspienia, bez hibernacji (AC i DC)
    - bez usypiania dyskow
    - zamkniecie pokrywy nie uspi maszyny (laptopy)
    - Wi-Fi w trybie maksymalnej wydajnosci (brak oszczedzania energii karty)
    - USB selective suspend wylaczone
    - karty sieciowe: zdjety "Zezwalaj komputerowi na wylaczanie tego urzadzenia"
  Dziala na Windows 11, w tym 25H2.

  Uruchomienie jako Administrator:
    powershell -ExecutionPolicy Bypass -File .\Set-KioskPower.ps1

  Zmiana ustawien kart sieciowych zaczyna w pelni obowiazywac po restarcie.
================================================================================
#>

$ErrorActionPreference = "Stop"
function Write-Step($n,$m){ Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-OK($m){ Write-Host "    OK  - $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    !   - $m" -ForegroundColor Yellow }

# --- Kontrola uprawnien -------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) { Write-Host "Uruchom ten skrypt jako Administrator." -ForegroundColor Red; exit 1 }

Write-Host "================ ZASILANIE KIOSKU: ZAWSZE WLACZONY ================" -ForegroundColor White

# 1) Plan wysokiej wydajnosci jako aktywny (best-effort; jak sie nie uda, modyfikujemy aktualny)
Write-Step 1 "Ustawianie planu zasilania"
$HighPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
powercfg /setactive $HighPerf 2>$null
if ($LASTEXITCODE -eq 0) { Write-OK "Aktywny plan: Wysoka wydajnosc." }
else { Write-Warn2 "Nie udalo sie wybrac planu Wysoka wydajnosc - modyfikuje aktualny plan." }

# 2) Wylaczenie wygaszania ekranu, uspienia, hibernacji i usypiania dyskow (AC i DC)
Write-Step 2 "Wylaczanie wygaszania / uspienia / hibernacji / usypiania dyskow"
powercfg /change monitor-timeout-ac   0
powercfg /change monitor-timeout-dc   0
powercfg /change standby-timeout-ac   0
powercfg /change standby-timeout-dc   0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /change disk-timeout-ac      0
powercfg /change disk-timeout-dc      0
Write-OK "Wszystkie limity czasu ustawione na 'nigdy'."

# 3) Calkowite wylaczenie hibernacji (i przy okazji szybkiego rozruchu)
Write-Step 3 "Wylaczanie hibernacji"
powercfg /hibernate off 2>$null
Write-OK "Hibernacja wylaczona."

# 4) Zamkniecie pokrywy = nic nie rob (dla laptopow/tabletow)
Write-Step 4 "Akcja zamkniecia pokrywy = brak"
$SUB_BUTTONS = "4f971e89-eebd-4455-a8de-9e59040e7347"
$LIDACTION   = "5ca83367-6e45-459f-a27b-476b1d01c936"
powercfg /setacvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0
Write-OK "Zamkniecie pokrywy nie uspi maszyny."

# 5) Wi-Fi: maksymalna wydajnosc + USB selective suspend wylaczone
Write-Step 5 "Wi-Fi i USB bez oszczedzania energii"
$SUB_WIFI    = "19cbb8fa-5279-450e-9fac-8a3d5fea2742"   # Wireless Adapter Settings
$WIFI_POWER  = "12bbebe6-58d6-4636-95bb-3217ef867c1a"   # Power Saving Mode (0 = Maximum Performance)
powercfg /setacvalueindex SCHEME_CURRENT $SUB_WIFI $WIFI_POWER 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_WIFI $WIFI_POWER 0
$SUB_USB     = "2a737441-1930-4402-8d77-b2bebba308a3"   # USB settings
$USB_SUSPEND = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"   # USB selective suspend (0 = Disabled)
powercfg /setacvalueindex SCHEME_CURRENT $SUB_USB $USB_SUSPEND 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_USB $USB_SUSPEND 0
Write-OK "Wi-Fi = maksymalna wydajnosc, USB selective suspend = wylaczone."

# 6) Karty sieciowe: zdejmij "Zezwalaj komputerowi na wylaczanie tego urzadzenia"
Write-Step 6 "Wylaczanie oszczedzania energii kart sieciowych"
$count = 0
try {
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $base -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d{4}$' } |
        ForEach-Object {
            $cfg = (Get-ItemProperty -Path $_.PSPath -Name 'NetCfgInstanceId' -ErrorAction SilentlyContinue).NetCfgInstanceId
            if ($cfg -and ($adapters.InterfaceGuid -contains $cfg)) {
                Set-ItemProperty -Path $_.PSPath -Name 'PnPCapabilities' -Value 24 -Type DWord
                $count++
            }
        }
} catch { }
if ($count -gt 0) { Write-OK "Wylaczono uspianie dla $count karty(kart) sieciowej(-ych) (efekt po restarcie)." }
else { Write-Warn2 "Nie zmieniono ustawien kart sieciowych - mozna pominac (Wi-Fi i tak ustawione na maks. wydajnosc)." }

# 7) Zastosowanie i weryfikacja
Write-Step 7 "Zastosowanie i weryfikacja"
powercfg /setactive SCHEME_CURRENT 2>$null

function Get-AcDcIndex($sub,$setting){
    # zwraca @(AC, DC) - bierze dwie OSTATNIE wartosci 0x z wyniku /query (sa to indeksy AC i DC),
    # niezaleznie od jezyka systemu
    $out = (powercfg /query SCHEME_CURRENT $sub $setting 2>$null) -join "`n"
    $m = [regex]::Matches($out, '0x[0-9a-fA-F]{8}')
    if ($m.Count -ge 2) {
        return @([Convert]::ToInt64($m[$m.Count-2].Value,16), [Convert]::ToInt64($m[$m.Count-1].Value,16))
    }
    return @($null,$null)
}

$mon = Get-AcDcIndex "SUB_VIDEO" "VIDEOIDLE"     # wygaszanie ekranu
$slp = Get-AcDcIndex "SUB_SLEEP" "STANDBYIDLE"   # uspienie
if ($mon[0] -eq 0 -and $mon[1] -eq 0) { Write-OK "Wygaszanie ekranu: nigdy (AC i DC)." } else { Write-Warn2 "Wygaszanie ekranu: AC=$($mon[0])s DC=$($mon[1])s" }
if ($slp[0] -eq 0 -and $slp[1] -eq 0) { Write-OK "Uspienie: nigdy (AC i DC)." } else { Write-Warn2 "Uspienie: AC=$($slp[0])s DC=$($slp[1])s" }

$active = (powercfg /getactivescheme) 2>$null
Write-Host "    i   - $active" -ForegroundColor Gray

Write-Host "`n================ GOTOWE ================" -ForegroundColor White
Write-Host "Schemat zasilania ustawiony na 'zawsze wlaczony'." -ForegroundColor White
Write-Host "Zmiana kart sieciowych zacznie w pelni obowiazywac po restarcie." -ForegroundColor White
